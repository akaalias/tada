#!/usr/bin/env python3
"""GAD discriminator (round 0) — the reward model for adversarial distillation.

Trains a semantic embedding-MLP D to separate TEACHER (Sonnet gold) question-sets
from STUDENT (the on-device model's own drafts), then scores each student draft by
how TEACHER-like D judges it. That score is the GAD reward: the policy is then pushed
(via the existing GRPO group-relative policy gradient) toward its own drafts that most
fool D. Unlike GRPO's judge-rubric reward — which was flat on coverage because all of
the student's drafts miss the same unknown — D contrasts against the TEACHER, whose
drafts contain it, so the reward can in principle reward teacher-like coverage.

Representation: MiniLM (all-MiniLM-L6-v2) embeds the task and each of the 7 questions;
the set is [task_emb | mean(question_emb) | max(question_emb)] (1152-d) — task context,
central topics, and coverage spread. MLP -> teacher/student logit, BCE. Split is BY TASK
(a task's gold + its drafts share a split) so D can't separate on task identity.

Output: results/gad_rewards.jsonl in the score_rollouts schema (id, group, input, title,
description, questions, reward) so build_grpo_data.py / train_adapter_grpo.py consume it
unchanged. reward = sigmoid(D logit) = P(teacher-like) in [0,1].

Run in the venv (sentence-transformers + torch):
    python gad_discriminator.py --out results/gad_rewards.jsonl [--epochs 60] [--seed 0]
"""
import argparse, json, glob, pathlib
import numpy as np
import torch
import torch.nn as nn
from sentence_transformers import SentenceTransformer

PKG = pathlib.Path(__file__).resolve().parent.parent
CORPUS = PKG / "corpus"
RES = PKG / "results"


def set_texts(qs):
    return [str(q.get("title", "")).strip() for q in qs if q.get("title")]


def load_data():
    """student drafts (from cached rollouts) + matched teacher gold, keyed by task id."""
    students = []          # list of dicts: full draft record (for re-emission) + texts
    seen = set()
    for f in sorted(glob.glob(str(RES / "grpo_roll_k*.jsonl"))):
        for line in pathlib.Path(f).read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            d = json.loads(line)
            t = set_texts(d.get("questions", []))
            if len(t) == 7:
                d["_texts"] = t
                students.append(d)
                seen.add(d["id"])
    teachers = []
    for cid in sorted(seen):
        cf = CORPUS / f"{cid}.json"
        if not cf.exists():
            continue
        g = json.loads(cf.read_text())["gold"]
        t = set_texts(g["questions"])
        if len(t) == 7:
            teachers.append({"id": cid, "input": json.loads(cf.read_text())["input"], "_texts": t})
    return teachers, students


def auc(scores, y):
    order = np.argsort(scores); ranks = np.empty(len(scores)); ranks[order] = np.arange(1, len(scores) + 1)
    npos, nneg = y.sum(), len(y) - y.sum()
    return float("nan") if npos == 0 or nneg == 0 else (ranks[y == 1].sum() - npos * (npos + 1) / 2) / (npos * nneg)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(RES / "gad_rewards.jsonl"))
    ap.add_argument("--epochs", type=int, default=60)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    torch.manual_seed(args.seed); rng = np.random.RandomState(args.seed)

    teachers, students = load_data()
    print(f"teacher gold sets: {len(teachers)}   student draft sets: {len(students)}")

    enc = SentenceTransformer("all-MiniLM-L6-v2")

    def featurize(records):
        tasks = enc.encode([r["input"] for r in records], batch_size=64, show_progress_bar=False)
        feats = []
        for r, te in zip(records, tasks):
            qe = enc.encode(r["_texts"], batch_size=16, show_progress_bar=False)
            feats.append(np.concatenate([te, qe.mean(0), qe.max(0)]))
        return np.array(feats, dtype=np.float32)

    Xt, Xs = featurize(teachers), featurize(students)
    X = np.vstack([Xt, Xs]); y = np.array([1] * len(Xt) + [0] * len(Xs), dtype=np.float32)
    ids = [r["id"] for r in teachers] + [r["id"] for r in students]

    # split BY TASK so a task's gold + drafts never straddle train/val
    uniq = sorted(set(ids)); rng.shuffle(uniq)
    val_ids = set(uniq[: max(1, len(uniq) // 5)])
    val_mask = np.array([i in val_ids for i in ids])

    mu, sd = X[~val_mask].mean(0), X[~val_mask].std(0) + 1e-6
    Xn = (X - mu) / sd
    Xtr = torch.tensor(Xn[~val_mask]); ytr = torch.tensor(y[~val_mask])
    Xva = torch.tensor(Xn[val_mask]); yva = y[val_mask]

    D = nn.Sequential(nn.Linear(X.shape[1], 256), nn.ReLU(), nn.Dropout(0.3),
                      nn.Linear(256, 64), nn.ReLU(), nn.Dropout(0.3), nn.Linear(64, 1))
    opt = torch.optim.Adam(D.parameters(), lr=1e-3, weight_decay=1e-4)
    lossf = nn.BCEWithLogitsLoss(pos_weight=torch.tensor([(y[~val_mask] == 0).sum() / max(1, (y[~val_mask] == 1).sum())]))
    best_auc, best_state = -1, None
    for ep in range(args.epochs):
        D.train(); opt.zero_grad()
        loss = lossf(D(Xtr).squeeze(1), ytr); loss.backward(); opt.step()
        D.eval()
        with torch.no_grad():
            va = auc(D(Xva).squeeze(1).numpy(), yva)
        if va == va and va > best_auc:
            best_auc, best_state = va, {k: v.clone() for k, v in D.state_dict().items()}
    if best_state:
        D.load_state_dict(best_state)
    print(f"discriminator best val AUC (teacher vs student): {best_auc:.3f}  "
          f"({'usable signal' if best_auc > 0.6 else 'weak/no signal'})")

    # reward every student draft = P(teacher-like)
    D.eval()
    with torch.no_grad():
        s = torch.sigmoid(D(torch.tensor((Xs - mu) / sd)).squeeze(1)).numpy()
    out = []
    for r, rew in zip(students, s):
        out.append({"id": r["id"], "group": r["id"], "input": r["input"],
                    "title": r["title"], "description": r.get("description", ""),
                    "questions": r["questions"], "reward": float(rew)})
    pathlib.Path(args.out).write_text("\n".join(json.dumps(o, ensure_ascii=False) for o in out))
    print(f"wrote {len(out)} GAD-scored drafts to {args.out}  "
          f"(reward mean {s.mean():.3f}, std {s.std():.3f}, min {s.min():.3f}, max {s.max():.3f})")
    # within-task reward spread = the gradient GAD has to work with (GRPO had ~0 on coverage)
    from collections import defaultdict
    g = defaultdict(list)
    for o in out:
        g[o["group"]].append(o["reward"])
    spreads = [np.std(v) for v in g.values() if len(v) > 1]
    print(f"mean within-task reward std: {np.mean(spreads):.3f}  "
          f"(higher = more group-relative gradient for the policy than GRPO's flat-coverage signal)")


if __name__ == "__main__":
    main()
