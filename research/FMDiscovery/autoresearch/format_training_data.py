#!/usr/bin/env python3
"""Format the demonstration corpus into Apple adapter-toolkit training data
(chat JSONL: lists of {"role","content"} pairs). Trains ONLY on corpus/ (which
is disjoint from the frozen eval gold/), so the adapter never sees eval cases.
90/10 train/valid split. Output: adapter/data/{train,valid}.jsonl
"""
import json, pathlib, random

PKG = pathlib.Path(__file__).resolve().parent.parent
CORPUS = PKG / "corpus"
OUT = PKG / "adapter" / "data"

# Mirrors the canonical single-shot discovery instruction the on-device agent uses,
# so training matches inference. The assistant target is the structured plan JSON
# (FMDiscoveryPlan shape: title / summary / questions[{question,detail,requiresExternalAction}]).
INSTR = """You are a personal task coach. The user shared a task they want to accomplish. Generate clarifying questions that uncover what they specifically want, the context (who/what/when/where/why), constraints and preferences, and key execution details.
Restate the user's goal as a short specific title (4-9 words), never a generic label. Summarise the task in one sentence. Each question is complete, 5-10 words, asks ONE thing (never combine with "and"/"or"), specific to THIS task, addressed to the user, no emojis. Output a JSON object: {"title","summary","questions":[7 x {"question","detail","requiresExternalAction"}]}."""


def to_pair(case):
    g = case["gold"]
    user = INSTR + f'\n\nTask the user entered: "{case["input"]}"\n\nGenerate exactly 7 clarifying questions, one thing each.'
    resp = {
        "title": g["taskTitle"],
        "summary": g["taskDescription"],
        "questions": [
            {"question": q["title"], "detail": q.get("description", ""),
             "requiresExternalAction": q.get("requiresExternalAction", False)}
            for q in g["questions"]
        ],
    }
    return [{"role": "user", "content": user},
            {"role": "assistant", "content": json.dumps(resp, ensure_ascii=False)}]


def main():
    cases = [json.loads(f.read_text()) for f in sorted(CORPUS.glob("*.json"))]
    if not cases:
        print("no corpus cases; run gen_corpus.py first"); return
    pairs = [to_pair(c) for c in cases]
    random.seed(0); random.shuffle(pairs)
    n = max(1, int(len(pairs) * 0.1))
    valid, train = pairs[:n], pairs[n:]
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "train.jsonl").write_text("\n".join(json.dumps(p, ensure_ascii=False) for p in train), encoding="utf-8")
    (OUT / "valid.jsonl").write_text("\n".join(json.dumps(p, ensure_ascii=False) for p in valid), encoding="utf-8")
    print(f"wrote {len(train)} train / {len(valid)} valid pairs to adapter/data/")


if __name__ == "__main__":
    main()
