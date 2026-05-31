#!/usr/bin/env python3
"""Coverage-blind re-judge of stored candidates — ANALYSIS, not the official metric.

Re-judges each candidate's ALREADY-GENERATED questions (from results/<label>.json) with
the EXACT official judge prompt, in two modes:
  control = all 5 rubric dims + "which set is better overall"   (should reproduce logged quality)
  blind   = 4 dims (coverage removed) + "better overall IGNORING coverage"
quality = 0.5*(rubricMean-1)/4 + 0.5*pairwise, mean over answered cases.

No regeneration, no Swift/ruler changes. The control mode validates the replication, so the
blind-vs-control DELTA is robust to any prompt drift (it affects both modes equally).

Usage: rejudge_coverage_blind.py <label> [<label> ...]
"""
import os, sys, json, time, pathlib, urllib.request
from collections import Counter

PKG = pathlib.Path(__file__).resolve().parent.parent
KEY = os.environ.get("ANTHROPIC_API_KEY")
MODEL = "claude-sonnet-4-6"
PAIR = {"A": 0.0, "tie": 0.5, "B": 1.0}          # goldBetter / tie / fmBetter
DIMS5 = ["atomicity", "specificity", "coverage", "naturalness", "nonRedundancy"]
DIMS4 = ["atomicity", "specificity", "naturalness", "nonRedundancy"]

DIM_DESC = {
    "atomicity": 'each question asks exactly ONE thing; never combines two asks with "and"/"or".',
    "specificity": 'questions are concrete to THIS task, not generic filler like "any other preferences?".',
    "coverage": "the 7 questions together cover the important unknowns needed to plan the task well.",
    "naturalness": "phrasing reads like a thoughtful human coach — concise, clear, not robotic.",
    "nonRedundancy": "questions do not overlap or repeat each other.",
}
TOOL_DESC = {
    "atomicity": "one ask per question, no and/or", "specificity": "concrete to this task, not generic",
    "coverage": "the 7 cover the important unknowns", "naturalness": "reads like a thoughtful human coach",
    "nonRedundancy": "questions do not overlap",
}


def system(dims):
    lines = "\n".join(f"- {d}: {DIM_DESC[d]}" for d in dims)
    word = "five" if len(dims) == 5 else "four"
    extra = "" if "coverage" in dims else (" Do NOT consider coverage or completeness of the unknowns "
                                           "at all — judge ONLY the dimensions listed above, and weigh the "
                                           "overall A-vs-B verdict on those alone.")
    return ("You are a strict, impartial evaluator of clarifying questions a task-planning assistant asks a user. "
            f"Rate SET B (the candidate) on {word} dimensions, each 1 (poor) to 5 (excellent):\n{lines}\n"
            'Then pick which SET (A or B) is better overall for planning this task, or "tie" if genuinely equal. '
            "Be willing to say B is better when it is — do not favour A by default. Judge only what is written." + extra)


def user(inp, gt, gqs, ct, cqs, dims):
    n = lambda qs: "\n".join(f"{i+1}. {q}" for i, q in enumerate(qs))
    crit = ("each rubric dimension (1-5), then decide which set is better overall" if "coverage" in dims
            else "each rubric dimension (1-5) IGNORING coverage, then decide which set is better overall IGNORING coverage")
    return (f'A user entered this task: "{inp}"\n\n'
            "Two assistants each produced a title and 7 clarifying questions to ask the user before planning. Judge impartially.\n\n"
            f"SET A (reference):\ntitle: {gt}\n{n(gqs)}\n\n"
            f"SET B (candidate):\ntitle: {ct}\n{n(cqs)}\n\n"
            f"Score SET B on {crit} for helping plan this specific task.")


def tool(dims):
    props = {"better": {"type": "string", "enum": ["A", "B", "tie"], "description": "Which set is better overall, or tie"}}
    for d in dims:
        props[d] = {"type": "integer", "minimum": 1, "maximum": 5, "description": TOOL_DESC[d]}
    props["notes"] = {"type": "string", "description": "One or two sentences on the candidate's main weakness."}
    return {"name": "judge_discovery", "description": "Record the pairwise verdict and rubric scores",
            "input_schema": {"type": "object", "properties": props, "required": ["better"] + dims + ["notes"]}}


def call(sys_s, user_s, tl):
    body = json.dumps({"model": MODEL, "max_tokens": 1024, "system": sys_s, "tools": [tl],
                       "tool_choice": {"type": "tool", "name": "judge_discovery"},
                       "messages": [{"role": "user", "content": user_s}]}).encode()
    req = urllib.request.Request("https://api.anthropic.com/v1/messages", data=body, method="POST")
    req.add_header("x-api-key", KEY); req.add_header("anthropic-version", "2023-06-01"); req.add_header("content-type", "application/json")
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                obj = json.load(r)
            for b in obj.get("content", []):
                if b.get("type") == "tool_use":
                    return b["input"]
        except Exception as e:
            if attempt == 3:
                raise
            time.sleep(2 * (attempt + 1))
    raise RuntimeError("no tool_use block")


def quality(v, dims):
    mean = sum(v[d] for d in dims) / len(dims)
    return 0.5 * ((mean - 1) / 4) + 0.5 * PAIR.get(v["better"], 0.5)


def run(label):
    cases = json.load(open(PKG / "results" / f"{label}.json"))
    out = {"control": [], "blind": []}
    pws = {"control": [], "blind": []}
    for c in cases:
        if c.get("error"):
            continue
        sp = c.get("spec", {})
        passed = sp.get("passed", True) if isinstance(sp, dict) else bool(sp)
        cand = c["candidate"]; cqs = [q["title"] for q in cand["questions"]]
        gold = json.load(open(PKG / "gold" / f"{c['id']}.json"))["gold"]
        gqs = [q["title"] for q in gold["questions"]]
        for mode, dims in (("control", DIMS5), ("blind", DIMS4)):
            if not passed:
                out[mode].append(0.0); continue
            v = call(system(dims), user(c["input"], gold["taskTitle"], gqs, cand["taskTitle"], cqs, dims), tool(dims))
            out[mode].append(quality(v, dims)); pws[mode].append(v["better"])
        print(f"  [{label}] judged {c['id']}", file=sys.stderr)
    agg = lambda xs: sum(xs) / len(xs) if xs else 0.0
    wtl = lambda ps: (Counter(ps).get("B", 0), Counter(ps).get("tie", 0), Counter(ps).get("A", 0))
    return {"n": len(out["control"]), "control": agg(out["control"]), "blind": agg(out["blind"]),
            "pw_control": wtl(pws["control"]), "pw_blind": wtl(pws["blind"])}


def main():
    if not KEY:
        print("ANTHROPIC_API_KEY not set", file=sys.stderr); sys.exit(1)
    runs = {json.loads(l)["label"]: json.loads(l) for l in open(PKG / "results" / "runs.jsonl")}
    print(f"{'label':<20} {'logged':>7} {'control':>8} {'blind':>7} {'Δblind':>7}   pw(control)  pw(blind)")
    for label in sys.argv[1:]:
        r = run(label)
        logged = runs.get(label, {}).get("quality", float("nan"))
        print(f"{label:<20} {logged:7.3f} {r['control']:8.3f} {r['blind']:7.3f} {r['blind']-r['control']:+7.3f}   "
              f"{r['pw_control'][0]}/{r['pw_control'][1]}/{r['pw_control'][2]}      {r['pw_blind'][0]}/{r['pw_blind'][1]}/{r['pw_blind'][2]}")


if __name__ == "__main__":
    main()
