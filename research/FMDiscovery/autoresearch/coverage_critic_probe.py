#!/usr/bin/env python3
"""Gate-1 diagnostic for the on-device coverage CRITIC (#6) — can a small model
RECOGNISE coverage well enough to pick the best draft from a pool?

The bet behind a shipped critic is the generation-discrimination gap: the 3B can't
reliably GENERATE the pivotal-unknown question, but a critic only has to RECOGNISE
which of several drafts covers it. A critic helps only if (Gate 1) it can score
coverage and (Gate 2) the over-generation pool actually contains higher-coverage
drafts to pick. Gate 2 is already measured: within the 6 same-adapter samples per
task, an ORACLE best-of-6 reaches mean coverage 3.31 vs 2.94 for a random draw.

This script measures Gate 1 operationally, with NO task leakage:
  - TRAIN a MiniLM-embedding critic to predict the judge's coverage score from a
    question-set, on 1552 candidates over the 30 EVAL tasks.
  - TEST on the disjoint 145 CORPUS rollout pools (6 samples/task): the critic picks
    the 1 draft of 6 with the highest predicted coverage; record its ACTUAL coverage.
  - Compare critic-selected mean coverage against random (2.94) and oracle (3.31).
If critic-selection lands near the oracle, a shipped best-of-N + critic could lift
coverage; if it lands near random, the critic can't recognise coverage and #6 won't help.

Run in the venv (sentence-transformers + torch):
    python coverage_critic_probe.py
"""
import json, pathlib
import numpy as np
import torch, torch.nn as nn
from sentence_transformers import SentenceTransformer
from collections import defaultdict

P = pathlib.Path(__file__).resolve().parent.parent
SKIP = {"costs.json", "operators.json", "types.json", "adapter_provenance.json",
        "runs.jsonl", "gad_rewards.jsonl", "grpo_rewards.jsonl"}


def qtexts(qs):
    return [str(q.get("title", "")).strip() for q in qs if q.get("title")]


def load_train():
    """(task_input, set_texts, coverage) over the 30 eval tasks, from all result files."""
    rows = []
    for f in sorted(P.glob("results/*.json")):
        if f.name in SKIP:
            continue
        try:
            data = json.loads(f.read_text())
        except Exception:
            continue
        if not isinstance(data, list):
            continue
        for c in data:
            if not isinstance(c, dict):
                continue
            cov = (c.get("verdict") or {}).get("rubric", {}).get("coverage")
            cand = (c.get("candidate") or {}).get("questions")
            if cov is None or not cand:
                continue
            t = qtexts(cand)
            if len(t) == 7:
                rows.append((c.get("input", ""), t, int(cov)))
    return rows


def load_pools():
    """corpus rollout pools: task -> list of (set_texts, coverage). 6 samples/task."""
    pools = defaultdict(list)
    for r in (json.loads(l) for l in (P / "results/grpo_rewards.jsonl").read_text().splitlines() if l.strip()):
        cov = r.get("rubric", {}).get("coverage")
        t = qtexts(r.get("questions", []))
        if cov is not None and len(t) == 7:
            pools[r["group"]].append((r["input"], t, int(cov)))
    return pools


def main():
    enc = SentenceTransformer("all-MiniLM-L6-v2")

    def feat(input_text, texts):
        te = enc.encode([input_text], show_progress_bar=False)[0]
        qe = enc.encode(texts, show_progress_bar=False)
        return np.concatenate([te, qe.mean(0), qe.max(0)]).astype(np.float32)

    train = load_train()
    print(f"training rows (eval-task candidates): {len(train)}")
    Xtr = np.array([feat(i, t) for i, t, _ in train])
    ytr = np.array([c for _, _, c in train], dtype=np.float32)

    mu, sd = Xtr.mean(0), Xtr.std(0) + 1e-6
    Xn = torch.tensor((Xtr - mu) / sd)
    yb = torch.tensor((ytr >= 4).astype(np.float32))           # critic target: is this a high-coverage set?

    torch.manual_seed(0)
    net = nn.Sequential(nn.Linear(Xtr.shape[1], 256), nn.ReLU(), nn.Dropout(0.3),
                        nn.Linear(256, 64), nn.ReLU(), nn.Dropout(0.3), nn.Linear(64, 1))
    opt = torch.optim.Adam(net.parameters(), lr=1e-3, weight_decay=1e-4)
    posw = torch.tensor([(yb == 0).sum() / max(1, (yb == 1).sum())])
    lossf = nn.BCEWithLogitsLoss(pos_weight=posw)
    for _ in range(120):
        net.train(); opt.zero_grad()
        loss = lossf(net(Xn).squeeze(1), yb); loss.backward(); opt.step()

    # in-sample recognition AUC (sanity; the real test is the disjoint pool selection)
    net.eval()
    with torch.no_grad():
        s = net(Xn).squeeze(1).numpy()
    order = np.argsort(s); ranks = np.empty(len(s)); ranks[order] = np.arange(1, len(s) + 1)
    npos = (yb.numpy() == 1).sum(); nneg = len(s) - npos
    auc_in = (ranks[yb.numpy() == 1].sum() - npos * (npos + 1) / 2) / (npos * nneg)
    print(f"critic in-sample AUC (cov>=4 vs <4): {auc_in:.3f}")

    # the decisive test: pick 1-of-6 on the DISJOINT corpus rollout pools
    pools = load_pools()
    rand_cov, crit_cov, oracle_cov = [], [], []
    rng = np.random.RandomState(0)
    for task, items in pools.items():
        if len(items) < 2:
            continue
        covs = np.array([c for _, _, c in items])
        feats = np.array([feat(i, t) for i, t, _ in items])
        with torch.no_grad():
            pred = net(torch.tensor((feats - mu) / sd)).squeeze(1).numpy()
        crit_cov.append(covs[int(np.argmax(pred))])       # critic's pick
        oracle_cov.append(covs.max())                     # perfect pick
        rand_cov.append(covs[rng.randint(len(covs))])     # random draw
    rand_cov, crit_cov, oracle_cov = map(np.array, (rand_cov, crit_cov, oracle_cov))
    print(f"\nbest-of-6 selection on {len(crit_cov)} disjoint corpus tasks:")
    print(f"  RANDOM draw   mean coverage: {rand_cov.mean():.3f}")
    print(f"  CRITIC pick   mean coverage: {crit_cov.mean():.3f}")
    print(f"  ORACLE pick   mean coverage: {oracle_cov.mean():.3f}")
    gap = oracle_cov.mean() - rand_cov.mean()
    captured = (crit_cov.mean() - rand_cov.mean()) / gap if gap > 1e-9 else 0.0
    print(f"  critic captures {captured*100:.0f}% of the oracle's coverage headroom over random")

    print("\n── read ──")
    if crit_cov.mean() - rand_cov.mean() > 0.10 and captured > 0.4:
        print("  The critic recognises coverage well enough to SELECT for it (beats random,")
        print("  captures a real share of the oracle headroom). Gate 1 PASSES → an on-device")
        print("  best-of-N + coverage critic is worth building. Ceiling is the oracle ~3.3,")
        print("  so expect a modest coverage lift (~+0.2-0.3), not 3->4.")
    else:
        print("  The critic barely beats a random draw — it cannot reliably recognise which")
        print("  draft covers the pivotal unknown (discrimination is ~as hard as generation here).")
        print("  Gate 1 FAILS → a shipped coverage critic would not lift coverage. The recognition")
        print("  itself needs more capacity, same wall as generation.")


if __name__ == "__main__":
    main()
