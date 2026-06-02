#!/usr/bin/env python3
"""Training data for the PAIRWISE coverage critic (#2).

Relative judgment ("which of these two sets covers the task better?") is usually
stronger than absolute scoring, and the 3B was historically better at pairwise than
at absolute rubric scores. The pointwise critic captured 32% of the oracle headroom;
this tests whether a pairwise critic recognises coverage better.

For each of the 30 eval tasks we form pairs of candidate sets with DIFFERENT judge
coverage and label the higher-coverage one as the winner. Order is randomised and the
winner is balanced ~50/50 across "A"/"B" so the critic can't shortcut on position.
Chat schema matches the toolkit trainer; the assistant content is just "A" or "B".

NOTE: pairs are built only over the 30 EVAL tasks; the gate runs on the disjoint 145
corpus rollout pools — no task leakage.

    python format_critic_pairwise_data.py [--max-pairs-per-task 80]
Output: adapter/data_critic_pw/{train,valid}.jsonl
"""
import argparse, json, pathlib, random
from collections import defaultdict
from itertools import combinations

PKG = pathlib.Path(__file__).resolve().parent.parent
RES = PKG / "results"
OUT = PKG / "adapter" / "data_critic_pw"
SKIP = {"costs.json", "operators.json", "types.json", "adapter_provenance.json",
        "runs.jsonl", "gad_rewards.jsonl", "grpo_rewards.jsonl"}

SYSTEM = ("A conversation between a user and a helpful assistant. You compare two sets of "
          "clarifying questions a task-planning assistant could ask before planning, and decide "
          "which set has better COVERAGE — which one's seven questions better cover the most "
          "decision-critical unknowns needed to plan THIS task, the unknowns whose answers would "
          "most change the resulting plan. Reply with only the letter A or B.")


def numbered(qs):
    return "\n".join(f"{i+1}. {q.get('title','').strip()}" for i, q in enumerate(qs))


def user_msg(task_input, qa, qb):
    return (f'Task the user entered: "{task_input}"\n\n'
            f"SET A:\n{numbered(qa)}\n\nSET B:\n{numbered(qb)}\n\n"
            "Which set has better coverage, A or B?")


def mine_by_task():
    bytask = defaultdict(list)
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
            bytask[c.get("id", c.get("input", ""))].append((c.get("input", ""), cand, int(cov)))
    return bytask


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-pairs-per-task", type=int, default=80)
    args = ap.parse_args()
    rng = random.Random(0)

    bytask = mine_by_task()
    pairs = []
    for tid, items in bytask.items():
        diff = [(a, b) for a, b in combinations(items, 2) if a[2] != b[2]]
        rng.shuffle(diff)
        for a, b in diff[: args.max_pairs_per_task]:
            hi, lo = (a, b) if a[2] > b[2] else (b, a)        # winner = higher coverage
            inp = hi[0]
            if rng.random() < 0.5:                            # randomise which slot the winner takes
                qa, qb, ans = hi[1], lo[1], "A"
            else:
                qa, qb, ans = lo[1], hi[1], "B"
            pairs.append([
                {"role": "system", "content": SYSTEM},
                {"role": "user", "content": user_msg(inp, qa, qb)},
                {"role": "assistant", "content": ans},
            ])
    rng.shuffle(pairs)
    n = max(1, int(len(pairs) * 0.1))
    valid, train = pairs[:n], pairs[n:]
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "train.jsonl").write_text("\n".join(json.dumps(p, ensure_ascii=False) for p in train), encoding="utf-8")
    (OUT / "valid.jsonl").write_text("\n".join(json.dumps(p, ensure_ascii=False) for p in valid), encoding="utf-8")
    na = sum(1 for p in pairs if p[2]["content"] == "A")
    print(f"wrote {len(train)} train / {len(valid)} valid pairwise examples to adapter/data_critic_pw/  "
          f"(winner A: {na}/{len(pairs)} = {na/len(pairs)*100:.0f}%)")


if __name__ == "__main__":
    main()
