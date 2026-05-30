#!/usr/bin/env python3
"""Build ORPO preference pairs for judgment-transfer training.

Each pair shares ONE task input; the only systematic difference is COVERAGE:
  chosen   = corpus_v2b gold (coverage-forced: one atomic question per distinct
             decision axis — 7 distinct axes by construction)
  rejected = corpus (v1) gold (standard Sonnet — fluent and on-task, but more
             likely to repeat axes / miss the pivotal unknown)
Both sides are real Sonnet output in the SAME format, so the odds-ratio term in
ORPO points at the COVERAGE difference, not at fluency/format. Zero API cost —
both sides already on disk, paired by slug.

Output: adapter/data_orpo/pairs.jsonl  — one JSON object per line:
  {"prompt":[{system},{user}], "chosen":"<assistant json>", "rejected":"<assistant json>"}
matching format_training_data.py's system/user/assistant contract exactly.
"""
import json, os, pathlib, random

PKG = pathlib.Path(__file__).resolve().parent.parent
V1 = PKG / "corpus"
V2B = PKG / "corpus_v2b"
OUT = PKG / "adapter" / "data_orpo"

# Byte-identical to format_training_data.py so ORPO continues from the same contract.
DEFAULT = "A conversation between a user and a helpful assistant. "
INSTR = ("Taking the role of a personal task coach. Given a task the user wants to accomplish, "
         "generate clarifying questions that uncover what they specifically want, the context "
         "(who/what/when/where/why), constraints and preferences, and key execution details. "
         "Restate the user's goal as a short specific title (4-9 words), never a generic label. "
         "Summarise the task in one sentence. Each question is complete, 5-10 words, asks ONE "
         "thing (never combine with \"and\"/\"or\"), specific to THIS task, addressed to the user, "
         "no emojis. Produce exactly 7 questions.")


def assistant_json(case):
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
    return json.dumps(resp, ensure_ascii=False)


def main():
    pairs = []
    for f in sorted(V2B.glob("*.json")):
        v1f = V1 / f.name
        if not v1f.exists():
            continue
        chosen_case = json.loads(f.read_text())
        rejected_case = json.loads(v1f.read_text())
        if chosen_case["input"] != rejected_case["input"]:
            continue
        pairs.append({
            "prompt": [
                {"role": "system", "content": DEFAULT + INSTR},
                {"role": "user", "content": f'Task the user entered: "{chosen_case["input"]}"'},
            ],
            "chosen": assistant_json(chosen_case),
            "rejected": assistant_json(rejected_case),
        })
    random.seed(0)
    random.shuffle(pairs)
    n = max(1, int(len(pairs) * 0.1))
    valid, train = pairs[:n], pairs[n:]
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "train.jsonl").write_text("\n".join(json.dumps(p, ensure_ascii=False) for p in train), encoding="utf-8")
    (OUT / "valid.jsonl").write_text("\n".join(json.dumps(p, ensure_ascii=False) for p in valid), encoding="utf-8")
    print(f"wrote {len(train)} train / {len(valid)} valid ORPO pairs to adapter/data_orpo/")


if __name__ == "__main__":
    main()
