#!/usr/bin/env python3
"""Build results/samples.json — the data behind dashboard/samples.html (the sample
index). Each sample = a user ramble (input) + its frozen Sonnet gold task list,
grouped by category (the `kind` field). Category lives only in RambleInputs.swift;
the input + tasks come from the frozen gold/ files (the source of truth).

Read-only over gold/ and the Swift source; writes only results/samples.json.
Run from anywhere: paths are resolved relative to the package root.
"""
import json, os, re, sys

PKG = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
INPUTS = os.path.join(PKG, "Sources", "EvalBench", "RambleInputs.swift")
GOLD = os.path.join(PKG, "gold")
OUT = os.path.join(PKG, "results", "samples.json")

# Category display order + a one-line description of what each stresses.
CATS = [
    ("zero",        "Zero-task",   "Nothing actionable — venting, chit-chat. The correct answer is an empty list."),
    ("bait",        "Bait",        "Wishes and someday-musings that sound like tasks but aren't. Don't invent a task."),
    ("single",      "Single",      "Exactly one task as stated — don't over-decompose."),
    ("multi",       "Multiple",    "Several distinct tasks in one ramble."),
    ("interleaved", "Interleaved", "Tasks split across the ramble, returned to and refined later."),
    ("dedup",       "Dedup",       "The same intention said twice — collapse to one task."),
    ("noisy",       "Noisy",       "Dictation with self-correction, retraction, filler."),
    ("mixed",       "Mixed",       "One real task buried in non-actionable rambling."),
    ("long",        "Long",        "~1-2 min rambles: tasks scattered through tangents and someday-asides."),
]

def parse_inputs():
    """id -> (kind, heldOutReal) from the Swift source."""
    src = open(INPUTS, encoding="utf-8").read()
    out = {}
    for m in re.finditer(
        r'RambleInput\(id:\s*"([^"]+)",\s*kind:\s*"([^"]+)",\s*heldOutReal:\s*(true|false)',
        src,
    ):
        out[m.group(1)] = (m.group(2), m.group(3) == "true")
    return out

def main():
    meta = parse_inputs()
    by_kind = {}
    for fn in sorted(os.listdir(GOLD)):
        if not fn.endswith(".json"):
            continue
        g = json.load(open(os.path.join(GOLD, fn), encoding="utf-8"))
        gid = g.get("id", fn[:-5])
        kind, held = meta.get(gid, ("other", False))
        by_kind.setdefault(kind, []).append({
            "id": gid,
            "input": g.get("input", ""),
            "tasks": (g.get("gold") or {}).get("tasks", []),
            "heldOut": held,
        })

    cats = []
    for kind, label, desc in CATS:
        items = sorted(by_kind.pop(kind, []), key=lambda x: x["id"])
        if items:
            cats.append({"kind": kind, "label": label, "desc": desc, "items": items})
    # Any category not in CATS (defensive) goes last, alphabetically.
    for kind in sorted(by_kind):
        cats.append({"kind": kind, "label": kind.title(), "desc": "", "items": by_kind[kind]})

    total = sum(len(c["items"]) for c in cats)
    json.dump({"total": total, "categories": cats}, open(OUT, "w", encoding="utf-8"), indent=2)
    print(f"wrote {OUT} ({total} samples in {len(cats)} categories)")

if __name__ == "__main__":
    main()
