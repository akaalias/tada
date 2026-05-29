#!/usr/bin/env python3
"""Grow the demonstration / training corpus: generate NEW, diverse task
one-liners (deduped against the frozen eval set) and their Sonnet gold, into
research/FMDiscovery/corpus/. Feeds the RAG demonstration bank AND adapter
training data. Does NOT touch the eval gold/ (the ruler).

Usage: gen_corpus.py [count]      (default 24)
Requires ANTHROPIC_API_KEY.
"""
import os, sys, json, re, pathlib, urllib.request

PKG = pathlib.Path(__file__).resolve().parent.parent
CORPUS = PKG / "corpus"
GOLD = PKG / "gold"
KEY = os.environ.get("ANTHROPIC_API_KEY")
MODEL = "claude-sonnet-4-6"

# Canonical discovery prompt + tool, mirrored from Sources/EvalBench/GoldGenerator.swift
# so corpus gold matches the eval gold's style/contract.
DISCOVERY_PROMPT = """You are a personal task coach. The user just shared a task they want to accomplish.

Before making any plans, you need to UNDERSTAND what they actually mean. Generate clarifying questions that will help you understand: what specifically they want; the context (who, what, when, where, why); constraints or preferences; and KEY DETAILS needed for execution.

TASK TITLE: restate the user's goal as a short, specific title (4-9 words) in their own terms. NEVER use generic labels like "Clarifying Questions" or "Task Discovery".
DESCRIPTION: summarise the task itself in one plain sentence.
QUESTIONS:
- Each subTask "title" IS the complete question the user sees, ~5-10 words, natural.
- ONE QUESTION PER ITEM. NEVER combine with "and" or "or". If tempted, split.
- Be specific to THIS task; no generic filler.
Do NOT use emojis. Generate EXACTLY 7 focused questions, each atomic."""

TASK_TOOL = {
    "name": "create_task_plan",
    "description": "Create a structured task plan",
    "input_schema": {
        "type": "object",
        "properties": {
            "title": {"type": "string"},
            "description": {"type": "string"},
            "subTasks": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "title": {"type": "string"},
                        "description": {"type": "string"},
                        "requiresExternalAction": {"type": "boolean"},
                    },
                    "required": ["title", "description", "requiresExternalAction"],
                },
            },
        },
        "required": ["title", "description", "subTasks"],
    },
}

GEN_TOOL = {
    "name": "tasks",
    "description": "Return the list of new task one-liners.",
    "input_schema": {
        "type": "object",
        "properties": {"tasks": {"type": "array", "items": {"type": "string"}}},
        "required": ["tasks"],
    },
}


def tool_call(system, user, tool, max_tokens=2048):
    body = json.dumps({
        "model": MODEL, "max_tokens": max_tokens, "system": system,
        "tools": [tool], "tool_choice": {"type": "tool", "name": tool["name"]},
        "messages": [{"role": "user", "content": user}],
    }).encode()
    req = urllib.request.Request("https://api.anthropic.com/v1/messages", data=body, method="POST")
    req.add_header("x-api-key", KEY)
    req.add_header("anthropic-version", "2023-06-01")
    req.add_header("content-type", "application/json")
    with urllib.request.urlopen(req, timeout=90) as resp:
        data = json.loads(resp.read())
    for b in data.get("content", []):
        if b.get("type") == "tool_use":
            return b["input"]
    raise RuntimeError("no tool_use in response")


def slug(s):
    return re.sub(r"_+", "_", re.sub(r"[^a-z0-9]+", "_", s.lower())).strip("_")[:48]


def existing_inputs():
    seen = []
    for d in (GOLD, CORPUS):
        if d.exists():
            for f in d.glob("*.json"):
                try:
                    seen.append(json.loads(f.read_text())["input"])
                except Exception:
                    pass
    return seen


def main():
    if not KEY:
        print("[gen_corpus] ANTHROPIC_API_KEY not set", file=sys.stderr); sys.exit(1)
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 24
    CORPUS.mkdir(parents=True, exist_ok=True)
    avoid = existing_inputs()

    gen = tool_call(
        "You generate realistic, diverse everyday to-do one-liners someone would type into a task app.",
        f"Generate {count} diverse task one-liners spanning home, health, travel, career, finance, social, "
        f"learning, creative, admin, family, and hobbies. Each 3-9 words. They must be CLEARLY DIFFERENT from "
        f"these existing tasks (different domains/intent, not rephrasings):\n" + "\n".join(f"- {t}" for t in avoid),
        GEN_TOOL, max_tokens=1500,
    )
    tasks = [t.strip() for t in gen.get("tasks", []) if t.strip()]
    print(f"[gen_corpus] generating gold for {len(tasks)} new tasks")

    written = 0
    for task in tasks:
        sid = slug(task)
        out = CORPUS / f"{sid}.json"
        if out.exists():
            continue
        try:
            plan = tool_call(DISCOVERY_PROMPT, f'Task the user entered: "{task}"\n\nGenerate EXACTLY 7 clarifying questions, one thing each.', TASK_TOOL)
        except Exception as e:
            print(f"[gen_corpus] skip '{task}': {e}", file=sys.stderr); continue
        qs = [{"title": q["title"], "description": q.get("description", ""),
               "requiresExternalAction": q.get("requiresExternalAction", False)}
              for q in plan.get("subTasks", [])[:7]]
        out.write_text(json.dumps({
            "id": sid, "input": task,
            "gold": {"taskTitle": plan["title"], "taskDescription": plan["description"], "questions": qs},
        }, indent=2))
        written += 1
        print(f"  + {sid}: {task}")
    print(f"[gen_corpus] wrote {written} corpus cases ({len(list(CORPUS.glob('*.json')))} total)")


if __name__ == "__main__":
    main()
