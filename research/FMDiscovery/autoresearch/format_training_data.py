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

# Schema-free guided generation (toolkit docs/schema.md): one fixed output format,
# so we DON'T embed a JSON schema — just consistent input/output pairs. Instructions
# go in a `system` role, prepended with the toolkit's recommended default for quality.
# Assistant content is the plan as stringified JSON via json.dumps (default separators
# give exactly one space after each comma/colon, which the toolkit requires).
DEFAULT = "A conversation between a user and a helpful assistant. "
INSTR = ("Taking the role of a personal task coach. Given a task the user wants to accomplish, "
         "generate clarifying questions that uncover what they specifically want, the context "
         "(who/what/when/where/why), constraints and preferences, and key execution details. "
         "Restate the user's goal as a short specific title (4-9 words), never a generic label. "
         "Summarise the task in one sentence. Each question is complete, 5-10 words, asks ONE "
         "thing (never combine with \"and\"/\"or\"), specific to THIS task, addressed to the user, "
         "no emojis. Produce exactly 7 questions.")


def to_pair(case):
    g = case["gold"]
    resp = {
        "title": g["taskTitle"],
        "summary": g["taskDescription"],
        "questions": [
            {"question": q["title"], "detail": q.get("description", ""),
             "requiresExternalAction": q.get("requiresExternalAction", False)}
            for q in g["questions"]
        ],
    }
    return [
        {"role": "system", "content": DEFAULT + INSTR},
        {"role": "user", "content": f'Task the user entered: "{case["input"]}"'},
        {"role": "assistant", "content": json.dumps(resp, ensure_ascii=False)},
    ]


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
