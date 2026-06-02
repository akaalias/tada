#!/usr/bin/env python3
"""GAD go/no-go diagnostic — can a discriminator separate TEACHER (Sonnet gold)
question-sets from STUDENT (the on-device model's own drafts), and is the separating
signal CONTENT (coverage/topic) or STYLE (length/phrasing/vocabulary)?

GAD only helps if the teacher/student boundary is about WHAT is asked (coverage),
not HOW it is phrased. Post-SFT the student already matches the teacher's style, so
if a discriminator still separates them on CONTENT, that residual is the coverage/
quality signal GAD could climb toward. If it separates them on STYLE, GAD would just
re-learn style (which SFT already gave us) — a confirmed dead end.

Method (pure numpy, no API, no sklearn):
  teacher sets = corpus gold; student sets = cached rollouts (results/grpo_roll_k*.jsonl).
  For each SET (its 7 question texts):
    STYLE features   — #q, words/q, char/word, %wh-initial, %2nd-person, ?-count, TTR, commas
    CONTENT features — TF-IDF bag-of-words over the set text (stopwords dropped)
  Train logistic regression (numpy GD, L2) teacher-vs-student on a train split; report
  held-out AUC for STYLE-only, CONTENT-only, and BOTH; list the most teacher-vs-student
  discriminative content words. Compare:
    CONTENT AUC high & STYLE AUC ~0.5  -> separation is semantic -> GAD well-posed.
    STYLE AUC high (~CONTENT)          -> separation is style    -> GAD would re-learn style.
    neither separates                  -> no usable signal       -> GAD cannot help.
    python gad_discriminator_probe.py
"""
import json, pathlib, re
import numpy as np

PKG = pathlib.Path(__file__).resolve().parent.parent
CORPUS = PKG / "corpus"
RES = PKG / "results"
STOP = set("a an the to of for in on at and or but with your you i my me we our is are do "
           "does did will would should can could what which who whom when where why how "
           "be been being have has had this that these those it its as by from".split())
WH = ("what", "which", "who", "whom", "whose", "when", "where", "why", "how", "do", "does",
      "did", "are", "is", "have", "has", "will", "would", "should", "can", "could")


def set_texts(questions):
    return [str(q.get("title", "")).strip() for q in questions if q.get("title")]


def load_sets():
    """Return (texts_list, label) — label 1 = teacher (gold), 0 = student (draft).
    Matched on the 150 rollout task ids so the only systematic difference is the model."""
    teacher, student = [], []
    # student drafts from the cached rollouts
    seen_ids = set()
    for f in sorted(RES.glob("grpo_roll_k*.jsonl")):
        for line in f.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            d = json.loads(line)
            qs = set_texts(d.get("questions", []))
            if len(qs) == 7:
                student.append(qs)
                seen_ids.add(d["id"])
    # teacher gold for those same tasks
    for cid in sorted(seen_ids):
        cf = CORPUS / f"{cid}.json"
        if cf.exists():
            g = json.loads(cf.read_text())["gold"]
            qs = set_texts(g["questions"])
            if len(qs) == 7:
                teacher.append(qs)
    return teacher, student


def style_features(qset):
    words = [q.split() for q in qset]
    wl = [len(w) for w in words]
    allw = [w.lower() for q in words for w in q]
    chars = [len(w) for w in allw]
    wh = sum(1 for q in qset if q.split() and q.split()[0].lower().strip("?,.").lower() in WH)
    second = sum(1 for w in allw if w.strip("?,.'s") in ("you", "your", "you're", "yours"))
    qmarks = sum(q.count("?") for q in qset)
    commas = sum(q.count(",") for q in qset)
    ttr = len(set(allw)) / max(1, len(allw))
    return [len(qset), np.mean(wl), np.std(wl), np.mean(chars) if chars else 0,
            wh / max(1, len(qset)), second / max(1, len(allw)), qmarks, commas, ttr]


def tokenize(qset):
    toks = re.findall(r"[a-z]+", " ".join(qset).lower())
    return [t for t in toks if t not in STOP and len(t) > 2]


def build_tfidf(sets, min_df=5, max_feats=400):
    from collections import Counter
    df = Counter()
    docs = [tokenize(s) for s in sets]
    for d in docs:
        for t in set(d):
            df[t] += 1
    vocab = [t for t, c in df.most_common() if c >= min_df][:max_feats]
    vidx = {t: i for i, t in enumerate(vocab)}
    idf = np.array([np.log(len(sets) / (1 + df[t])) for t in vocab])
    X = np.zeros((len(sets), len(vocab)))
    for i, d in enumerate(docs):
        c = Counter(t for t in d if t in vidx)
        for t, n in c.items():
            X[i, vidx[t]] = n
    X = X / np.clip(X.sum(1, keepdims=True), 1, None) * idf  # tf-idf
    return X, vocab


def auc(scores, y):
    order = np.argsort(scores)
    ranks = np.empty_like(order, dtype=float)
    ranks[order] = np.arange(1, len(scores) + 1)
    npos = y.sum(); nneg = len(y) - npos
    if npos == 0 or nneg == 0:
        return float("nan")
    return (ranks[y == 1].sum() - npos * (npos + 1) / 2) / (npos * nneg)


def _sigmoid(z):
    return 1.0 / (1.0 + np.exp(-np.clip(z, -30, 30)))


def train_lr(X, y, l2=1.0, iters=1500, lr=0.1):
    mu, sd = X.mean(0), X.std(0); sd[sd == 0] = 1
    Xs = np.clip(np.nan_to_num((X - mu) / sd), -10, 10)
    w = np.zeros(Xs.shape[1]); b = 0.0
    for _ in range(iters):
        p = _sigmoid(Xs @ w + b)
        g = p - y
        w -= lr * (Xs.T @ g / len(y) + l2 * w / len(y))
        b -= lr * g.mean()
    return w, b, mu, sd


def evaluate(Xtr, ytr, Xte, yte, l2=1.0):
    w, b, mu, sd = train_lr(Xtr, ytr, l2=l2)
    s = np.clip(np.nan_to_num((Xte - mu) / sd), -10, 10) @ w + b
    return auc(s, yte), (w, mu, sd)


def main():
    np.seterr(over="ignore", divide="ignore", invalid="ignore")  # AUC is rank-based; saturated logits are harmless
    teacher, student = load_sets()
    rng = np.random.RandomState(0)
    # balance: sample equal #student as teacher for a clean base rate
    student = [student[i] for i in rng.permutation(len(student))[:len(teacher) * 2]]
    sets = teacher + student
    y = np.array([1] * len(teacher) + [0] * len(student), dtype=float)
    print(f"teacher (gold) sets: {len(teacher)}   student (draft) sets: {len(student)}   (base rate {y.mean():.2f})")

    Xstyle = np.array([style_features(s) for s in sets])
    Xcontent, vocab = build_tfidf(sets)
    print(f"style features: {Xstyle.shape[1]}   content vocab: {Xcontent.shape[1]}")

    idx = rng.permutation(len(sets))
    cut = int(len(sets) * 0.7)
    tr, te = idx[:cut], idx[cut:]
    yt, ye = y[tr], y[te]

    auc_style, _ = evaluate(Xstyle[tr], yt, Xstyle[te], ye)
    auc_content, (wc, muc, sdc) = evaluate(Xcontent[tr], yt, Xcontent[te], ye)
    auc_both, _ = evaluate(np.hstack([Xstyle, Xcontent])[tr], yt,
                           np.hstack([Xstyle, Xcontent])[te], ye)
    print(f"\nheld-out AUC (1.0 = perfectly separable, 0.5 = indistinguishable):")
    print(f"  STYLE-only    : {auc_style:.3f}")
    print(f"  CONTENT-only  : {auc_content:.3f}")
    print(f"  BOTH          : {auc_both:.3f}")

    # most teacher-vs-student discriminative content words (LR weight on standardized tf-idf)
    order = np.argsort(wc)
    print("\nmost TEACHER-like content words:", ", ".join(vocab[i] for i in order[::-1][:12]))
    print("most STUDENT-like content words:", ", ".join(vocab[i] for i in order[:12]))

    print("\n── read ──")
    if auc_content < 0.6 and auc_style < 0.6:
        print("  Neither content nor style separates teacher from student (AUC ~0.5).")
        print("  No usable discriminator signal — GAD has nothing to climb. STRONG no-go.")
    elif auc_style >= auc_content - 0.03:
        print(f"  STYLE separates as well as content (style {auc_style:.2f} ≈ content {auc_content:.2f}).")
        print("  The teacher/student boundary is largely STYLE — GAD would re-learn phrasing")
        print("  SFT already gave us, not coverage. Weak case for GAD.")
    else:
        print(f"  CONTENT separates ({auc_content:.2f}) well ABOVE style ({auc_style:.2f}).")
        print("  The residual teacher/student difference is SEMANTIC (what is asked), exactly the")
        print("  signal GAD could climb. Inspect the discriminative words above: if they are TOPIC")
        print("  words (budget, location, experience, timeline...) the coverage signal is real and")
        print("  GAD is well-posed; if they are function/style words, treat as style.")


if __name__ == "__main__":
    main()
