#!/usr/bin/env python3
"""Build ON-POLICY ORPO preference pairs — the fix for the failed style-vs-style run.

The first ORPO attempt paired chosen=v2b gold vs rejected=v1 gold (two Sonnet
styles), so the model learned v2b's surface tics, not coverage judgment. Here the
contrast is good-answer vs the model's OWN draft for the SAME task:
  chosen   = corpus gold (standard Sonnet — the high-coverage target)
  rejected = the on-device model's own questions (drafts_*.jsonl from `fmresearch
             generate`), which carry the coverage-3 weakness by construction
The only systematic difference is the model's actual quality gap — a proper
on-policy negative (the DPO/ORPO best practice: negatives drawn from the policy).

Both sides are emitted in the SAME assistant schema (title/summary/7×{question,
detail,requiresExternalAction}), so the odds-ratio term can't latch onto a format
or detail-length confound.

Usage: gen_orpo_pairs_onpolicy.py [drafts_file]   (default: results/drafts_v2a_e1.jsonl)
Output: adapter/data_orpo_onpolicy/{train,valid}.jsonl
"""
import json, sys, pathlib, random

PKG = pathlib.Path(__file__).resolve().parent.parent
CORPUS = PKG / "corpus"
DRAFTS = PKG / "results" / (sys.argv[1] if len(sys.argv) > 1 else "drafts_v2a_e1.jsonl")
OUT = PKG / "adapter" / "data_orpo_onpolicy"

# Byte-identical contract to format_training_data.py / gen_orpo_pairs.py.
DEFAULT = "A conversation between a user and a helpful assistant. "
INSTR = ("Taking the role of a personal task coach. Given a task the user wants to accomplish, "
         "generate clarifying questions that uncover what they specifically want, the context "
         "(who/what/when/where/why), constraints and preferences, and key execution details. "
         "Restate the user's goal as a short specific title (4-9 words), never a generic label. "
         "Summarise the task in one sentence. Each question is complete, 5-10 words, asks ONE "
         "thing (never combine with \"and\"/\"or\"), specific to THIS task, addressed to the user, "
         "no emojis. Produce exactly 7 questions.")


def gold_json(case):
    g = case["gold"]
    return json.dumps({
        "title": g["taskTitle"], "summary": g["taskDescription"],
        "questions": [{"question": q["title"], "detail": q.get("description", ""),
                       "requiresExternalAction": q.get("requiresExternalAction", False)}
                      for q in g["questions"]],
    }, ensure_ascii=False)


def draft_json(d):
    return json.dumps({
        "title": d["title"], "summary": d.get("description", ""),
        "questions": [{"question": q["title"], "detail": q.get("description", ""),
                       "requiresExternalAction": q.get("requiresExternalAction", False)}
                      for q in d["questions"]],
    }, ensure_ascii=False)


def titles(qs, key):
    return [q[key].strip().lower() for q in qs]


def main():
    pairs, skipped = [], 0
    for line in DRAFTS.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        d = json.loads(line)
        cf = CORPUS / f"{d['id']}.json"
        if not cf.exists():
            skipped += 1; continue
        case = json.loads(cf.read_text())
        # spec sanity + genuine signal: draft must have 7 questions and differ from gold
        if len(d.get("questions", [])) != 7 or len(case["gold"]["questions"]) != 7:
            skipped += 1; continue
        if titles(d["questions"], "title") == titles(case["gold"]["questions"], "title"):
            skipped += 1; continue   # identical → no preference signal
        pairs.append({
            "prompt": [
                {"role": "system", "content": DEFAULT + INSTR},
                {"role": "user", "content": f'Task the user entered: "{case["input"]}"'},
            ],
            "chosen": gold_json(case),
            "rejected": draft_json(d),
        })
    random.seed(0)
    random.shuffle(pairs)
    n = max(1, int(len(pairs) * 0.1))
    valid, train = pairs[:n], pairs[n:]
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "train.jsonl").write_text("\n".join(json.dumps(p, ensure_ascii=False) for p in train), encoding="utf-8")
    (OUT / "valid.jsonl").write_text("\n".join(json.dumps(p, ensure_ascii=False) for p in valid), encoding="utf-8")
    print(f"wrote {len(train)} train / {len(valid)} valid on-policy ORPO pairs to adapter/data_orpo_onpolicy/ "
          f"({skipped} skipped)")


if __name__ == "__main__":
    main()
