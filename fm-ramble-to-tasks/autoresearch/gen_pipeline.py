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

# The fixed visual vocabulary. Keep in sync with the dashboard renderer (util.js).
KINDS = ["input", "retrieve", "generate", "expand", "select", "critique", "ensemble", "post", "output"]

TOOL = {
    "name": "pipeline_spec",
    "description": "Record the experiment's on-device pipeline as an ordered list of stages.",
    "input_schema": {
        "type": "object",
        "properties": {
            "summary": {"type": "string", "description": "<=10 words naming the core idea of this experiment."},
            "hypothesis": {"type": "string", "description": "1-2 plain sentences for a human skimming the dashboard: the BELIEF this experiment tests — what we expected to improve and WHY. Frame as a testable bet, e.g. 'Forcing the model to decide hasActionableTasks before listing should stop it inventing tasks on venting.' Do NOT describe the mechanism here (that's 'technique')."},
            "technique": {"type": "string", "description": "1-2 plain sentences: the concrete METHOD used to test the hypothesis — the actual change/mechanism in plain language, naming the lever (decoding, retrieval/RAG, multi-call pipeline, guided-schema design, deterministic post-processing, LoRA adapter, etc.). e.g. 'A single greedy on-device call with a reasoning-first @Generable schema that gates the task list on a boolean.'"},
            "result": {"type": "string", "description": "1-2 plain sentences: what ACTUALLY happened when this ran. You MUST use the EXACT metrics given in the user message (quality score, win/tie/loss vs Sonnet, the rubric, kept-or-discarded) — do not invent numbers. State the headline quality and how it compared to the prior best/baseline, what the judge/rubric revealed, and the takeaway (hypothesis confirmed or falsified)."},
            "stages": {
                "type": "array",
                "description": "Ordered left-to-right stages of the on-device pipeline (NOT the eval/judge).",
                "items": {
                    "type": "object",
                    "properties": {
                        "kind": {"type": "string", "enum": KINDS, "description":
                            "input=the user's free-form ramble; retrieve=RAG fetch of exemplars; generate=an on-device FM call that extracts tasks (or drafts/segments); expand=one FM call that over-produces N candidate tasks; select=deterministic Swift ranking/pick; critique=a second FM pass that audits/edits a draft (drop non-actionable/retracted/duplicate); ensemble=best-of-N variants then pick; post=deterministic Swift post-processing (dedup/filter); output=the final 0..N tasks."},
                        "text": {"type": "string", "description": "<=8 words: what this stage does for THIS experiment."},
                        "knobs": {"type": "object", "description": "Optional knob values shown as chips, e.g. {\"temp\":\"0.7\",\"sampling\":\"greedy\",\"k\":\"2\",\"n\":\"4\"}. Omit if none."},
                        "call_labels": {"type": "array", "items": {"type": "string"}, "description": "REQUIRED when this stage makes more than one model call (n>1 for an ensemble, or calls>1 for a model-based select/tournament/loop): one concise description per call (<=7 words), in order, length equal to the call count. NEVER leave multiple calls as bare numbers."},
                        "prompt": {"type": "string", "description": "FM calls (generate/expand/critique/ensemble) ONLY: the VERBATIM prompt for this call — the system/instructions text AND the user-message template — copied EXACTLY from the provided Swift source (Prompts.swift + the topology function). Do NOT paraphrase, summarize, or invent. Omit entirely for deterministic stages (input/output/retrieve/select/post)."}
                    },
                    "required": ["kind", "text"]
                }
            }
        },
        "required": ["summary", "hypothesis", "technique", "result", "stages"]
    }
}

SYSTEM = """You convert a one-line description of an on-device LLM pipeline experiment into a structured stage list, using ONLY the fixed stage vocabulary in the tool. The task is RAMBLE-SPLITTING: turn a free-form user brain-dump into 0..N atomic, actionable tasks (an empty list when nothing is actionable). Goal: a consistent visual language — the SAME building block always gets the SAME kind, so similar experiments look similar.

You ALSO write three short human-readable fields for the dashboard: 'hypothesis' (the testable bet — what we expected to improve and why), 'technique' (the concrete method/lever used to test it), and 'result' (what actually happened). Ground hypothesis/technique in the log entry and note; if the description is sparse, infer the most reasonable bet and method from the technique named. Keep each to 1-2 plain sentences. The hypothesis is the WHY/what-we-believe; the technique is the HOW/what-we-did; the result is the WHAT-HAPPENED — keep them distinct. For 'result', you MUST use the exact metrics provided in the user message (quality, win/tie/loss, rubric, kept/discarded) and never invent numbers.
CRITICAL FACTUAL GUARD: 'dev', 'test', 'full' and their counts (e.g. dev-11) refer to the EVALUATION subset — the frozen HELD-OUT eval cases the run is scored on — NOT the training-set size. NEVER state or imply a training-set/corpus size unless an explicit number appears in the log entry.

Rules:
- Always start with 'input' and end with 'output'. Describe ONLY the on-device generation pipeline — never the eval, gold, or judge.
- Map building blocks to kinds:
  - a single on-device model call that extracts the tasks -> generate (an FM call)
  - retrieval / RAG / few-shot exemplar lookup -> retrieve
  - one FM call that OVER-produces many candidate tasks -> expand
  - deterministic Swift ranking/selection, no model -> select
  - a SECOND model pass that audits/edits/revises a draft (reflexion/critique/filter) -> critique
  - best-of-N / multiple variants then pick -> ensemble
  - deterministic Swift post-processing (dedup, filter non-actionable) -> post
- DO NOT invent stages. A plain single-shot pipeline is EXACTLY: input -> generate -> output. Only add retrieve/expand/select/critique/ensemble/post if the description explicitly implies them.
- generate/critique/ensemble are model (FM) calls; select/post are deterministic code. Put decoding/retrieval/count settings in knobs (temp, sampling, k, n). Keep text fields <=8 words.
- If a model call uses a fine-tuned / LoRA / adapter model instead of the stock base, set that stage's knobs.model to the adapter name. Omit model for the stock base model.
- For ANY stage with multiple model calls, you MUST fill call_labels with one short description per call, in order.

Examples (description -> stage kinds):
- "single-shot extract (baseline)" -> input, generate, output
- "reasoning-first gated schema" -> input, generate, output
- "segment the ramble then extract per chunk, dedup" -> input, generate, generate, post, output
- "over-generate candidates then filter non-actionable" -> input, expand, post, output
- "extract then a scoped self-critique drops retracted/duplicate" -> input, generate, critique, output"""


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
    head = re.compile(r"^\s*-\s*\*{0,2}" + re.escape(label) + r"\b")
    for line in prog.splitlines():
        if head.match(line):
            entry = line.strip()
            break
    if not entry:
        mention = re.compile(r"\b" + re.escape(label) + r"\b")
        for line in prog.splitlines():
            if line.lstrip().startswith("-") and mention.search(line):
                entry = line.strip()
                break
    note = ""
    metrics = ""
    runs = PKG / "results" / "runs.jsonl"
    if runs.exists():
        for l in runs.read_text(encoding="utf-8").splitlines():
            try:
                r = json.loads(l)
                if r.get("label") == label:
                    note = r.get("note", "")
                    metrics = (
                        f"quality={r.get('quality'):.3f} on {r.get('subset','full')}-{r.get('n','')} "
                        f"(W/T/L vs Sonnet = {r.get('wins')}/{r.get('ties')}/{r.get('losses')}), "
                        f"specPass={round(r.get('specPass',0)*100)}%, "
                        f"rubric faith={r.get('faithfulness')} atom={r.get('atomicity')} "
                        f"action={r.get('actionability')} cover={r.get('coverage')} nonRed={r.get('nonRedundancy')}, "
                        f"{'KEPT (new best)' if r.get('kept') else 'discarded'}"
                    )
            except Exception:
                pass
    if not entry and not note:
        fail(f"no description found for {label}")

    # Source so the model can attach the VERBATIM prompt to each FM stage.
    def _read(rel):
        f = PKG / rel
        return f.read_text(encoding="utf-8") if f.exists() else ""
    prompts_src = _read("Sources/SplitAgent/Prompts.swift")
    agent_src = _read("Sources/SplitAgent/ConfiguredAgent.swift")
    cfgtext = _read("Sources/SplitAgent/Configs.swift")
    mt = re.search(r'"' + re.escape(label) + r'":\s*SplitConfig\(\s*topology:\s*\.(\w+)', cfgtext)
    topo = mt.group(1) if mt else ""

    user = (f"Experiment label: {label}\nShort note: {note}\nFull log entry: {entry}\n"
            f"Measured metrics (use these EXACT numbers for 'result'): {metrics or 'none recorded'}\n"
            f"This config's topology is `.{topo}`.\n\n"
            f"For each FM stage (generate/expand/critique/ensemble), set its `prompt` to the EXACT "
            f"system instructions + user-message template that the `.{topo}` topology uses, copied "
            f"VERBATIM from the source below (do not paraphrase). The agent source:\n"
            f"=== Prompts.swift ===\n{prompts_src}\n=== ConfiguredAgent.swift ===\n{agent_src}\n\n"
            f"Produce the pipeline_spec.")
    body = json.dumps({
        "model": "claude-sonnet-4-6",
        "max_tokens": 2500,
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

    # Sonnet occasionally serializes the stages array as a JSON STRING; coerce to a list.
    if isinstance(spec.get("stages"), str):
        try:
            spec["stages"] = json.loads(spec["stages"])
        except Exception:
            spec["stages"] = []
    if not isinstance(spec.get("stages"), list):
        spec["stages"] = []

    # DETERMINISTIC adapter knob: the ground truth of which adapter a config uses is
    # its `adapter:` path in Configs.swift. Stamp it onto the first on-device model
    # stage so the LoRA node renders correctly.
    cfg = (PKG / "Sources" / "SplitAgent" / "Configs.swift")
    if cfg.exists():
        m = re.search(r'"' + re.escape(label) + r'":\s*SplitConfig\((.*?)\)',
                      cfg.read_text(), re.DOTALL)
        ad = re.search(r'adapter:\s*"([^"]+)"', m.group(1)) if m else None
        if ad:
            name = pathlib.Path(ad.group(1)).stem
            fmk = {"generate", "expand", "critique", "ensemble"}
            for st in spec.get("stages", []):
                if st.get("kind") in fmk:
                    st.setdefault("knobs", {})["model"] = name
                    break

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"{label}.json").write_text(json.dumps(spec, indent=2), encoding="utf-8")
    print(f"[gen_pipeline] wrote results/pipelines/{label}.json")


if __name__ == "__main__":
    main()
