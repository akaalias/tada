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
            "hypothesis": {"type": "string", "description": "1-2 plain sentences for a human skimming the dashboard: the BELIEF this experiment tests — what we expected to improve and WHY we thought it would. Frame as a testable bet, e.g. 'Distilling Sonnet's question-style into the weights should beat any in-context prompt, because the gap is per-call judgment, not instructions.' Do NOT describe the mechanism here (that's 'technique')."},
            "technique": {"type": "string", "description": "1-2 plain sentences: the concrete METHOD used to test the hypothesis — the actual change/mechanism in plain language, naming the lever (decoding, retrieval/RAG, multi-call pipeline, guided-schema design, deterministic post-processing, LoRA adapter, etc.). e.g. 'A single greedy on-device call using a LoRA adapter fine-tuned on 558 Sonnet task->questions pairs.'"},
            "stages": {
                "type": "array",
                "description": "Ordered left-to-right stages of the on-device pipeline (NOT the eval/judge).",
                "items": {
                    "type": "object",
                    "properties": {
                        "kind": {"type": "string", "enum": KINDS, "description":
                            "input=the user one-liner; retrieve=RAG fetch of exemplars; generate=an on-device FM call that drafts questions/unknowns; expand=one FM call that over-produces N candidates; select=deterministic Swift ranking/pick of top-K; critique=a second FM pass that audits/edits/revises a draft (reflexion); ensemble=best-of-N variants then pick; post=deterministic Swift post-processing (dedup/coverage-check/atomicity-repair); output=the final 7 questions."},
                        "text": {"type": "string", "description": "<=8 words: what this stage does for THIS experiment."},
                        "knobs": {"type": "object", "description": "Optional knob values shown as chips, e.g. {\"temp\":\"0.7\",\"sampling\":\"greedy\",\"k\":\"2\",\"n\":\"4\"}. Omit if none."},
                        "call_labels": {"type": "array", "items": {"type": "string"}, "description": "REQUIRED when this stage makes more than one model call (n>1 for an ensemble, or calls>1 for a model-based select/tournament/loop): one concise human-readable description per call (<=7 words), in order, with length equal to the call count. Describe what EACH call actually does. e.g. ensemble: [\"draft at temp 0.3\", \"draft at temp 0.6\", ...]; pairwise tournament: [\"semifinal: draft A vs B\", \"same pair, order swapped\", \"final: the two winners\", ...]. NEVER leave multiple calls as bare numbers."}
                    },
                    "required": ["kind", "text"]
                }
            }
        },
        "required": ["summary", "hypothesis", "technique", "stages"]
    }
}

SYSTEM = """You convert a one-line description of an on-device LLM pipeline experiment into a structured stage list, using ONLY the fixed stage vocabulary in the tool. Goal: a consistent visual language — the SAME building block always gets the SAME kind, so similar experiments look similar.

You ALSO write two short human-readable fields for the dashboard: 'hypothesis' (the testable bet — what we expected to improve and why) and 'technique' (the concrete method/lever used to test it). Ground both in the log entry and note; if the description is sparse, infer the most reasonable bet and method from the technique named. Keep each to 1-2 plain sentences, no jargon dumps. The hypothesis is the WHY/what-we-believe; the technique is the HOW/what-we-did — keep them distinct.
CRITICAL FACTUAL GUARD: 'full-30', 'dev-10', 'full-30 greedy', 'dev' etc. refer to the EVALUATION subset — the 30 or 10 frozen HELD-OUT eval cases the run is scored on — NOT the training-set size. NEVER state or imply a training-set/corpus size unless an explicit number appears in the log entry (e.g. '558 train pairs', 'corpus 619'). If the training size is not given, do not mention it. Do not confuse eval-subset size with training-set size.

Rules:
- Always start with 'input' and end with 'output'. Describe ONLY the on-device generation pipeline — never the eval, gold, or judge.
- Map building blocks to kinds:
  - a single on-device model call that drafts the questions -> generate (an FM call)
  - retrieval / RAG / few-shot exemplar lookup -> retrieve
  - one FM call that OVER-produces many candidates (e.g. 12) -> expand
  - deterministic Swift ranking/selection of top-K, no model -> select
  - a SECOND model pass that audits/edits/revises a draft (reflexion/editor/critique) -> critique
  - best-of-N / multiple variants (e.g. N temperatures) then pick -> ensemble
  - deterministic Swift post-processing (dedup, coverage check, atomicity repair) -> post
- DO NOT invent stages. A plain single-shot pipeline is EXACTLY: input -> generate -> output. Only add retrieve/expand/select/critique/ensemble/post if the description explicitly implies them.
- generate/critique/ensemble are model (FM) calls; select/post are deterministic code. Put decoding/retrieval/count settings in knobs (temp, sampling, k, n). Keep text fields <=8 words.
- If a model call uses a fine-tuned / LoRA / adapter model instead of the stock base 3B, set that stage's knobs.model to the adapter name (e.g. "adapter-v1"). Omit model for the stock base model.
- A select/post stage that uses the MODEL (pairwise LLM comparisons, a tournament, an LLM-as-judge) is real model work: set its knobs.calls to the number of model calls it makes (e.g. a single-elimination pairwise tournament over 4 candidates with a two-order vote ≈ 6). Pure deterministic select/post (sorting, embedding clustering, dedup, regex repair) must OMIT calls.
- For ANY stage with multiple model calls (parallel ensemble OR a sequential model-based select/tournament/loop), you MUST fill call_labels with one short human-readable description per call, in order — describe what each call does; never leave them as bare numbers.

Examples (description -> stage kinds):
- "single-shot (EXP-000 port)" -> input, generate, output
- "over-generate 12 scored, top-7 in Swift" -> input, expand, select, output
- "brainstorm then select+phrase" (two FM calls) -> input, generate, generate, output
- "RAG few-shot: nearest gold exemplars injected" -> input, retrieve, generate, output
- "reflexion editor on RAG draft" -> input, retrieve, generate, critique, output
- "best-of-N(4 temps) RAG sets, select by Swift coverage scorer" -> input, retrieve, ensemble, select, output"""


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
    # Match the bullet whose HEADING is this label (after optional markdown **),
    # not just any line that mentions the label (e.g. a PIVOT note).
    head = re.compile(r"^\s*-\s*\*{0,2}" + re.escape(label) + r"\b")
    for line in prog.splitlines():
        if head.match(line):
            entry = line.strip()
            break
    # Fallback: many runs (esp. the adapter track) have no bullet HEADED by their
    # exact label — their context lives in a milestone bullet that mentions the
    # label inline. Grab the first such bullet so hypothesis/technique are grounded.
    if not entry:
        mention = re.compile(r"\b" + re.escape(label) + r"\b")
        for line in prog.splitlines():
            if line.lstrip().startswith("-") and mention.search(line):
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
