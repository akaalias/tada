#!/usr/bin/env python3
"""Format training data for the pointwise COVERAGE CRITIC adapter (#1).

The critic reads a task + the 7 clarifying questions and emits a single coverage
score (1-5) — the judge's own coverage rubric, learned as a narrow recognition task.
The bet (generation-discrimination gap): an FM with a critic-adapter might RECOGNISE
coverage on unseen tasks where the shallow MiniLM probe could not (it captured only
18% of the oracle best-of-N headroom).

Training examples are mined from every result file (results/*.json): each judged case
gives (input, candidate question-set, judge coverage). The classes are imbalanced
(mostly 3s), so we CAP the dominant class to force the critic to discriminate rather
than predict the mode. Chat schema is byte-identical to format_training_data.py so the
toolkit SFT trainer consumes it unchanged; the assistant content is just the digit.

NOTE: these candidates are over the 30 EVAL tasks. The oracle-gap gate (critic_gate.py)
tests on the DISJOINT 145 corpus rollout pools, so there is no task leakage between
critic training and the gate.

    python format_critic_data.py [--cap3 300]
Output: adapter/data_critic/{train,valid}.jsonl
"""
import argparse, json, pathlib, random
from collections import defaultdict

PKG = pathlib.Path(__file__).resolve().parent.parent
RES = PKG / "results"
OUT = PKG / "adapter" / "data_critic"
SKIP = {"costs.json", "operators.json", "types.json", "adapter_provenance.json",
        "runs.jsonl", "gad_rewards.jsonl", "grpo_rewards.jsonl"}

SYSTEM = ("A conversation between a user and a helpful assistant. You are a strict evaluator "
          "of the clarifying questions a task-planning assistant asks before planning. Judge "
          "COVERAGE on a 1-5 scale: do the seven questions together cover the most decision-"
          "critical unknowns needed to plan THIS task well — the unknowns whose answers would "
          "most change the resulting plan? 5 = every pivotal unknown is covered; 3 = the obvious "
          "ones are covered but a decision-critical one is missing; 1 = misses the unknowns that "
          "matter. Reply with only the integer.")


def numbered(qs):
    return "\n".join(f"{i+1}. {q.get('title','').strip()}" for i, q in enumerate(qs))


def user_msg(task_input, questions):
    return (f'Task the user entered: "{task_input}"\n\n'
            f"The seven clarifying questions:\n{numbered(questions)}\n\n"
            "Coverage score (1-5):")


def mine():
    rows = []
    for f in sorted(RES.glob("*.json")):
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
            if cov is None or not cand or len(cand) != 7:
                continue
            rows.append((c.get("input", ""), cand, int(cov)))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cap3", type=int, default=300, help="cap on the dominant coverage-3 class")
    args = ap.parse_args()

    rows = mine()
    byc = defaultdict(list)
    for r in rows:
        byc[r[2]].append(r)
    random.seed(0)
    balanced = []
    for cov, items in byc.items():
        random.shuffle(items)
        cap = args.cap3 if cov == 3 else len(items)
        balanced.extend(items[:cap])
    random.shuffle(balanced)

    pairs = [[
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": user_msg(inp, qs)},
        {"role": "assistant", "content": str(cov)},
    ] for inp, qs, cov in balanced]

    n = max(1, int(len(pairs) * 0.1))
    valid, train = pairs[:n], pairs[n:]
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "train.jsonl").write_text("\n".join(json.dumps(p, ensure_ascii=False) for p in train), encoding="utf-8")
    (OUT / "valid.jsonl").write_text("\n".join(json.dumps(p, ensure_ascii=False) for p in valid), encoding="utf-8")
    dist = {c: min(len(v), args.cap3 if c == 3 else len(v)) for c, v in sorted(byc.items())}
    print(f"wrote {len(train)} train / {len(valid)} valid critic examples to adapter/data_critic/")
    print(f"balanced coverage distribution: {dist}")


if __name__ == "__main__":
    main()
