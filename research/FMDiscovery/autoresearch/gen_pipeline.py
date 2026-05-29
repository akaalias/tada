#!/usr/bin/env python3
"""Generate a structured pipeline spec for one experiment, so the dashboard can
draw a consistent process diagram. Maps the experiment's program.md entry + note
into a fixed stage vocabulary via the Anthropic API. Best-effort: prints a
warning and exits 0 on any failure so it never breaks the autoresearch loop.

Usage: gen_pipeline.py <label>   (writes results/pipelines/<label>.json)
"""
import os, sys, json, re, pathlib, urllib.request

PKG = pathlib.Path(__file__).resolve().parent.parent
OUT = PKG / "results" / "pipelines"

# The fixed visual vocabulary. Keep in sync with the dashboard renderer.
KINDS = ["input", "retrieve", "generate", "expand", "select", "critique", "ensemble", "post", "output"]

TOOL = {
    "name": "pipeline_spec",
    "description": "Record the experiment's on-device pipeline as an ordered list of stages.",
    "input_schema": {
        "type": "object",
        "properties": {
            "summary": {"type": "string", "description": "<=10 words naming the core idea of this experiment."},
            "stages": {
                "type": "array",
                "description": "Ordered left-to-right stages of the on-device pipeline (NOT the eval/judge).",
                "items": {
                    "type": "object",
                    "properties": {
                        "kind": {"type": "string", "enum": KINDS, "description":
                            "input=the user one-liner; retrieve=RAG fetch of exemplars; generate=an on-device FM call that drafts questions/unknowns; expand=one FM call that over-produces N candidates; select=deterministic Swift ranking/pick of top-K; critique=a second FM pass that audits/edits/revises a draft (reflexion); ensemble=best-of-N variants then pick; post=deterministic Swift post-processing (dedup/coverage-check/atomicity-repair); output=the final 7 questions."},
                        "text": {"type": "string", "description": "<=8 words: what this stage does for THIS experiment."},
                        "knobs": {"type": "object", "description": "Optional knob values shown as chips, e.g. {\"temp\":\"0.7\",\"sampling\":\"greedy\",\"k\":\"2\",\"n\":\"4\"}. Omit if none."}
                    },
                    "required": ["kind", "text"]
                }
            }
        },
        "required": ["summary", "stages"]
    }
}

SYSTEM = (
    "You convert a one-line description of an on-device LLM pipeline experiment into a structured "
    "stage list, using ONLY the fixed stage vocabulary in the tool. The point is a consistent visual "
    "language: the SAME building block must always get the SAME kind, so similar experiments look "
    "similar and different ones look different. Always start with an 'input' stage and end with an "
    "'output' stage. Describe ONLY the generation pipeline that runs on-device — never the eval, gold, "
    "or judge. Put decoding/retrieval/count settings in knobs. Be terse."
)


def fail(msg):
    print(f"[gen_pipeline] {msg}", file=sys.stderr)
    sys.exit(0)  # never break the loop


def main():
    if len(sys.argv) < 2:
        fail("usage: gen_pipeline.py <label>")
    label = sys.argv[1]
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        fail("ANTHROPIC_API_KEY not set")

    prog = (PKG / "program.md").read_text(encoding="utf-8") if (PKG / "program.md").exists() else ""
    entry = ""
    for line in prog.splitlines():
        if line.lstrip().startswith("-") and re.search(r"\b" + re.escape(label) + r"\b", line):
            entry = line.strip()
            break
    note = ""
    runs = PKG / "results" / "runs.jsonl"
    if runs.exists():
        for l in runs.read_text(encoding="utf-8").splitlines():
            try:
                r = json.loads(l)
                if r.get("label") == label:
                    note = r.get("note", "")
            except Exception:
                pass
    if not entry and not note:
        fail(f"no description found for {label}")

    user = f"Experiment label: {label}\nShort note: {note}\nFull log entry: {entry}\n\nProduce the pipeline_spec."
    body = json.dumps({
        "model": "claude-sonnet-4-6",
        "max_tokens": 900,
        "system": SYSTEM,
        "tools": [TOOL],
        "tool_choice": {"type": "tool", "name": "pipeline_spec"},
        "messages": [{"role": "user", "content": user}],
    }).encode()

    req = urllib.request.Request("https://api.anthropic.com/v1/messages", data=body, method="POST")
    req.add_header("x-api-key", key)
    req.add_header("anthropic-version", "2023-06-01")
    req.add_header("content-type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read())
    except Exception as e:
        fail(f"API call failed for {label}: {e}")

    spec = None
    for block in data.get("content", []):
        if block.get("type") == "tool_use":
            spec = block.get("input")
    if not spec:
        fail(f"no tool_use in response for {label}")
    spec["label"] = label

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"{label}.json").write_text(json.dumps(spec, indent=2), encoding="utf-8")
    print(f"[gen_pipeline] wrote results/pipelines/{label}.json")


if __name__ == "__main__":
    main()
