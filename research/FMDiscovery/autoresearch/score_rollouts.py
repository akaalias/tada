#!/usr/bin/env python3
"""Reward step for GRPO — score each on-policy draft with the SAME Sonnet rubric the
frozen ruler uses, and turn it into a scalar reward.

Per the project decision, the reward is the RUBRIC-MEAN (pairwise dropped): we send
the byte-identical judge prompt from `Sources/EvalBench/AnthropicJudge.swift` (system +
SET A=corpus gold / SET B=draft + the `judge_discovery` forced tool) and read only the
five 1-5 rubric dimensions, then

    reward = (mean(atomicity,specificity,coverage,naturalness,nonRedundancy) - 1) / 4

which matches `Rubric.normalized` in the harness (so the reward sits on the exact scale
of the rubric half of the headline metric). The drafts are over CORPUS tasks (disjoint
from the frozen 30 eval gold) — never the eval set — so this is not a leak; the trained
adapter is still validated on the frozen ruler with greedy decoding.

No SDK dependency: replicates AnthropicClient.toolCall over stdlib urllib (forced
tool_choice, anthropic-version 2023-06-01), so it runs in any venv with just the key.

Usage:
    ANTHROPIC_API_KEY=... python score_rollouts.py \
        --drafts results/grpo_roll_k1.jsonl [results/grpo_roll_k2.jsonl ...] \
        --out results/grpo_rewards.jsonl [--model claude-sonnet-4-6] [--workers 8]
Each input line: {id, input, title, description, questions:[{title,description,...}]}.
Each output line: the same record + {"reward": float, "rubric": {...}, "group": id}.
"""
import argparse, json, os, sys, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

PKG = Path(__file__).resolve().parent.parent
CORPUS = PKG / "corpus"

# --- byte-identical to AnthropicJudge.swift (system + tool) ---------------------------
SYSTEM = (
    "You are a strict, impartial evaluator of clarifying questions a task-planning "
    "assistant asks a user. Rate SET B (the candidate) on five dimensions, each 1 (poor) "
    "to 5 (excellent):\n"
    "- atomicity: each question asks exactly ONE thing; never combines two asks with "
    "\"and\"/\"or\".\n"
    "- specificity: questions are concrete to THIS task, not generic filler like \"any "
    "other preferences?\".\n"
    "- coverage: the 7 questions together cover the important unknowns needed to plan the "
    "task well.\n"
    "- naturalness: phrasing reads like a thoughtful human coach — concise, clear, not "
    "robotic.\n"
    "- nonRedundancy: questions do not overlap or repeat each other.\n"
    "Then pick which SET (A or B) is better overall for planning this task, or \"tie\" if "
    "genuinely equal. Be willing to say B is better when it is — do not favour A by "
    "default. Judge only what is written."
)
TOOL = {
    "name": "judge_discovery",
    "description": "Record the pairwise verdict and rubric scores",
    "input_schema": {
        "type": "object",
        "properties": {
            "better": {"type": "string", "enum": ["A", "B", "tie"], "description": "Which set is better overall, or tie"},
            "atomicity": {"type": "integer", "minimum": 1, "maximum": 5, "description": "one ask per question, no and/or"},
            "specificity": {"type": "integer", "minimum": 1, "maximum": 5, "description": "concrete to this task, not generic"},
            "coverage": {"type": "integer", "minimum": 1, "maximum": 5, "description": "the 7 cover the important unknowns"},
            "naturalness": {"type": "integer", "minimum": 1, "maximum": 5, "description": "reads like a thoughtful human coach"},
            "nonRedundancy": {"type": "integer", "minimum": 1, "maximum": 5, "description": "questions do not overlap"},
            "notes": {"type": "string", "description": "One or two sentences: the candidate's main weakness vs the reference, to guide iteration."},
        },
        "required": ["better", "atomicity", "specificity", "coverage", "naturalness", "nonRedundancy", "notes"],
    },
}
DIMS = ["atomicity", "specificity", "coverage", "naturalness", "nonRedundancy"]


def numbered(qs):
    return "\n".join(f"{i + 1}. {q['title']}" for i, q in enumerate(qs))


def user_prompt(task_input, gold, draft):
    return (
        f'A user entered this task: "{task_input}"\n\n'
        "Two assistants each produced a title and 7 clarifying questions to ask the user "
        "before planning. Judge impartially.\n\n"
        f"SET A (reference):\ntitle: {gold['taskTitle']}\n{numbered(gold['questions'])}\n\n"
        f"SET B (candidate):\ntitle: {draft['title']}\n{numbered(draft['questions'])}\n\n"
        "Score SET B on each rubric dimension (1-5), then decide which set is better "
        "overall for helping plan this specific task."
    )


def call_judge(api_key, model, system, user, max_tokens=1024, retries=5):
    body = json.dumps({
        "model": model, "max_tokens": max_tokens, "system": system,
        "messages": [{"role": "user", "content": user}],
        "tools": [TOOL], "tool_choice": {"type": "tool", "name": TOOL["name"]},
    }).encode()
    for attempt in range(retries):
        req = urllib.request.Request(
            "https://api.anthropic.com/v1/messages", data=body, method="POST",
            headers={"x-api-key": api_key, "anthropic-version": "2023-06-01",
                     "content-type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=90) as resp:
                payload = json.loads(resp.read())
            for block in payload.get("content", []):
                if block.get("type") == "tool_use":
                    return block["input"]
            raise RuntimeError(f"no tool_use in response: {payload}")
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as e:
            code = getattr(e, "code", None)
            if attempt == retries - 1 or (code and 400 <= code < 500 and code not in (429,)):
                raise
            time.sleep(2 ** attempt)


def reward_from_rubric(out):
    mean = sum(int(out[d]) for d in DIMS) / len(DIMS)
    return (mean - 1.0) / 4.0


def load_gold(draft_id):
    cf = CORPUS / f"{draft_id}.json"
    if not cf.exists():
        return None
    return json.loads(cf.read_text())["gold"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--drafts", nargs="+", required=True, help="one or more group draft jsonl files")
    ap.add_argument("--out", required=True)
    ap.add_argument("--model", default="claude-sonnet-4-6")
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        sys.exit("ANTHROPIC_API_KEY not set")

    records = []
    for f in args.drafts:
        for line in Path(f).read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line:
                records.append(json.loads(line))

    def score(rec):
        gold = load_gold(rec["id"])
        if gold is None or len(rec.get("questions", [])) != 7:
            return None
        out = call_judge(api_key, args.model, SYSTEM, user_prompt(rec["input"], gold, rec))
        rec = dict(rec)
        rec["group"] = rec["id"]
        rec["rubric"] = {d: int(out[d]) for d in DIMS}
        rec["reward"] = reward_from_rubric(out)
        return rec

    scored, done, total = [], 0, len(records)
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for r in ex.map(score, records):
            done += 1
            if r is not None:
                scored.append(r)
            if done % 25 == 0 or done == total:
                sys.stderr.write(f"[score] {done}/{total} judged ({len(scored)} kept)\n")

    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in scored), encoding="utf-8")
    rewards = [r["reward"] for r in scored]
    mean = sum(rewards) / len(rewards) if rewards else 0.0
    print(f"wrote {len(scored)} scored drafts to {args.out}  (mean reward {mean:.3f}, "
          f"min {min(rewards, default=0):.3f}, max {max(rewards, default=0):.3f})")


if __name__ == "__main__":
    main()
