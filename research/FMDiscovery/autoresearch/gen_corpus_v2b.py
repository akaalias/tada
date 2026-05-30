#!/usr/bin/env python3
"""v2b reasoning-distillation: regenerate the gold for the EXISTING corpus inputs
with a COVERAGE-FORCING prompt. Sonnet must first reason about the distinct
decision-relevant unknowns of the task (the "which unknowns matter & why" step),
then write exactly ONE atomic question per axis. This holds the input set + data
size constant vs the v1 corpus, so it's a clean A/B on TARGET quality — directly
attacking the rubric dimension that stays stuck at 3 (coverage).

The reasoning is captured in each case file for transparency, but training only
uses title + 7 questions, so the production contract is unchanged.

Reads research/FMDiscovery/corpus/*.json (inputs), writes corpus_v2b/*.json.
Resumable: skips inputs already regenerated. Requires ANTHROPIC_API_KEY.
"""
import os, sys, json, pathlib, urllib.request

PKG = pathlib.Path(__file__).resolve().parent.parent
SRC = PKG / "corpus"
DST = PKG / "corpus_v2b"
KEY = os.environ.get("ANTHROPIC_API_KEY")
MODEL = "claude-sonnet-4-6"

# Same coach contract as the eval gold, plus an explicit coverage step. The seven
# axes are a checklist, not a straitjacket: span the ones that actually matter for
# THIS task, one atomic question each.
DISCOVERY_PROMPT = """You are a personal task coach. The user just shared a task they want to accomplish.

Before planning, you must UNDERSTAND what they mean. First, think about which UNKNOWNS most determine how this task should be done — the questions whose answers would most change the plan. Span DISTINCT decision axes; do not cluster several questions on the same axis. Useful axes to consider (use the ones that matter for THIS task):
- scope / what specifically is included or excluded
- people / who it is for or who is involved
- context / where and when it happens
- constraints / budget, time, resources, hard limits
- preferences / style, tone, priorities, what to emphasise
- success criteria / what "done well" looks like
- logistics / format, tools, the immediate next action

Then turn the most decision-relevant unknowns into questions.

TASK TITLE: restate the user's goal as a short, specific title (4-9 words) in their own terms. NEVER a generic label like "Clarifying Questions".
DESCRIPTION: summarise the task in one plain sentence.
QUESTIONS:
- Each subTask "title" IS the complete question the user sees, ~5-10 words, natural.
- ONE QUESTION PER ITEM. NEVER combine with "and"/"or". If tempted, split.
- Each question must cover a DIFFERENT axis from the others — maximise coverage of the distinct unknowns, minimise overlap.
- "coversAxis": name the single axis this question addresses (one of the axes above, or a more specific one).
- Be specific to THIS task; no generic filler. Do NOT use emojis.
Generate EXACTLY 7 focused questions, each atomic, each on a distinct axis."""

TASK_TOOL = {
    "name": "create_task_plan",
    "description": "Create a structured task plan after reasoning about the key unknowns.",
    "input_schema": {
        "type": "object",
        "properties": {
            "keyUnknowns": {
                "type": "array",
                "description": "The distinct decision-relevant unknowns, each with why it matters. Reason here FIRST.",
                "items": {
                    "type": "object",
                    "properties": {
                        "axis": {"type": "string"},
                        "whyItMatters": {"type": "string"},
                    },
                    "required": ["axis", "whyItMatters"],
                },
            },
            "title": {"type": "string"},
            "description": {"type": "string"},
            "subTasks": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "title": {"type": "string"},
                        "description": {"type": "string"},
                        "coversAxis": {"type": "string"},
                        "requiresExternalAction": {"type": "boolean"},
                    },
                    "required": ["title", "description", "coversAxis", "requiresExternalAction"],
                },
            },
        },
        "required": ["keyUnknowns", "title", "description", "subTasks"],
    },
}


def tool_call(system, user, max_tokens=2560):
    body = json.dumps({
        "model": MODEL, "max_tokens": max_tokens, "system": system,
        "tools": [TASK_TOOL], "tool_choice": {"type": "tool", "name": TASK_TOOL["name"]},
        "messages": [{"role": "user", "content": user}],
    }).encode()
    req = urllib.request.Request("https://api.anthropic.com/v1/messages", data=body, method="POST")
    req.add_header("x-api-key", KEY)
    req.add_header("anthropic-version", "2023-06-01")
    req.add_header("content-type", "application/json")
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read())
    for b in data.get("content", []):
        if b.get("type") == "tool_use":
            return b["input"]
    raise RuntimeError("no tool_use in response")


def main():
    if not KEY:
        print("[v2b] ANTHROPIC_API_KEY not set", file=sys.stderr); sys.exit(1)
    DST.mkdir(parents=True, exist_ok=True)
    inputs = sorted(SRC.glob("*.json"))
    print(f"[v2b] regenerating coverage-forced gold for {len(inputs)} corpus inputs -> corpus_v2b/")
    written = skipped = failed = 0
    for f in inputs:
        case = json.loads(f.read_text())
        out = DST / f.name
        if out.exists():
            skipped += 1; continue
        task = case["input"]
        try:
            plan = tool_call(DISCOVERY_PROMPT, f'Task the user entered: "{task}"\n\nReason about the key unknowns, then generate EXACTLY 7 clarifying questions, one axis each.')
        except Exception as e:
            print(f"[v2b] skip '{task}': {e}", file=sys.stderr); failed += 1; continue
        qs = [{"title": q["title"], "description": q.get("description", ""),
               "coversAxis": q.get("coversAxis", ""),
               "requiresExternalAction": q.get("requiresExternalAction", False)}
              for q in plan.get("subTasks", [])[:7]]
        out.write_text(json.dumps({
            "id": case["id"], "input": task,
            "keyUnknowns": plan.get("keyUnknowns", []),
            "gold": {"taskTitle": plan["title"], "taskDescription": plan["description"], "questions": qs},
        }, indent=2))
        written += 1
        if written % 25 == 0:
            print(f"  ... {written} written ({skipped} skipped, {failed} failed)")
    total = len(list(DST.glob("*.json")))
    print(f"[v2b] done: {written} written, {skipped} skipped, {failed} failed ({total} total in corpus_v2b/)")


if __name__ == "__main__":
    main()
