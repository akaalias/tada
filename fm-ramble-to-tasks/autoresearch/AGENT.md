# AUTORESEARCH_RULES — standing instructions for the autonomous coding agent

You are an autonomous ML-systems research agent. Your job: improve an on-device
Apple Foundation Model that splits a free-form user ramble into 0..N atomic,
actionable tasks, until it matches Anthropic Sonnet on the quality metric. You run
**exactly ONE experiment per invocation**, fully autonomously, then stop. Speed of
the on-device model does not matter.

## The task
Input: free-form, often dictated, stream-of-consciousness text. It may contain zero,
one, or several distinct intentions, sometimes interleaved or buried in
non-actionable rambling. Output: 0..N short, actionable task one-liners. An EMPTY
list is the correct, expected answer when nothing in the input is actionable.

## The artifact and the metric
- The MUTABLE artifact you improve: `fm-ramble-to-tasks/Sources/SplitAgent/**` ONLY.
- Headline metric: `quality` (0-1) = mean set-match **F1** over the full gold set,
  with zero-task cases scored binary (correctly empty = 1, else 0). The Sonnet judge
  does the paraphrase-aware matching AND a 1-5 diagnostic rubric (faithfulness /
  atomicity / actionability / coverage / nonRedundancy). Higher is better. Gate on
  the FULL set.
- Decoding: prefer GREEDY (`sampling: .greedy`, temp 0) for the final generation
  unless the technique inherently needs diverse samples (best-of-N / self-consistency),
  in which case the aggregation must supply stability. With ~15 gold cases one case is
  ~0.067, so a delta ≤ ~0.05 is noise, not a win.

## Current best to BUILD ON
`baseline` — singleShot, greedy, stock FM — **quality 0.727** (full set). The gap is
concentrated and specific:
1. **ZERO-TASK (the #1 lever):** all 4 venting/bait cases score 0.000 — the stock FM
   INVENTS tasks on non-actionable input ("Take a break" from venting, "journal more"
   from idle musing). Teaching it to return `[]` when nothing is actionable is the
   single biggest win available.
2. **RETRACTION in long rambles:** `long_portugal` kept "Renew passport" after the
   user said "scratch that" — a faithfulness miss.
Faithfulness and coverage are the load-bearing rubric dims for this task.

The harness JUDGES and LOGS automatically when you run the eval command. You do not
implement judging or scoring.

## HARD RULES (never violate — violations are auto-reverted)
- Edit ONLY files under `fm-ramble-to-tasks/Sources/SplitAgent/`. You may also append
  to `fm-ramble-to-tasks/program.md`, and you may create
  `fm-ramble-to-tasks/autoresearch/REQUEST.md` (the training-track flag — see below;
  the ONLY permitted write under `autoresearch/`).
- NEVER modify `Sources/EvalBench`, `Sources/Contract`, `Sources/fmramble`, `gold/`,
  `results/`, `Package.swift`, or anything else under `autoresearch/`. These are the ruler.
- NEVER hand-edit `results/runs.jsonl` or `results/*.json`. The eval writes them.
- NEVER change the gold, the judge, the metric, or the spec gate. Do not make the
  metric easier. Improve the agent, not the ruler.
- GOLD-LEAK BAN: never copy, template, or paraphrase a gold task list into your output.
  The agent must always GENERATE tasks from the input. If you add retrieval/few-shot,
  demonstrations must be OTHER tasks — never the eval case's own gold.
- Every experiment MUST end with a GREEN build and exactly one NEW logged run.
- Keep all previous configs intact; each experiment ADDS a new named config (`expNNN`).

## One iteration — do all of this, then STOP
1. **Review.** Read `fm-ramble-to-tasks/program.md` (the log + current best). Read the
   most recent `results/*.json` and study the judge's per-case `notes` and per-case F1
   — these are the concrete failure modes to attack.
2. **Ideate ONE hypothesis** grounded in those notes. The dominant gap is ZERO-TASK
   (don't invent tasks on non-actionable input). The real lever space:
   - **prompt** (`Prompts.swift`): strengthen the "return empty when nothing is
     actionable" contract; add a worked zero-task / retraction contrast.
   - **guided schema** (`Generated.swift`, the `@Generable FMRambleSplit`): a richer
     schema is a real lever — e.g. a pre-field that first decides "is there any
     actionable task here?", or in-schema reasoning before the list.
   - **topology** (`ConfiguredAgent.swift`): multi-call pipelines. Promising untried
     ones: SEGMENT→EXTRACT (chunk the ramble, extract per chunk, dedup),
     OVER-GENERATE→FILTER (generate candidates, drop non-actionable/duplicate in a
     second pass), EXTRACT→CRITIQUE (a scoped self-check: "is each item actually
     actionable and actually stated/not-retracted by the user?" → drop the failures;
     directly attacks both zero-task and retraction), best-of-N / self-consistency.
   - **decoding** (`SplitConfig`): per-stage temperature / sampling.
   - **deterministic Swift post-processing**: dedup near-duplicate tasks. Prefer the
     model learning the behavior over brittle heuristics.
   - **adapter**: NOT yet available (Phase 3, trained on RunPod). If your best idea
     genuinely needs a fine-tuned adapter, REQUEST it (below) and still run an
     inference experiment this iteration.
   Build on the current best; periodically try a bold, different idea.
3. **Code it** as a NEW named config in `Configs.swift`. Choose a UNIQUE label: scan
   `results/runs.jsonl` AND `Configs.swift` for the highest existing `expNNN` and use
   the next integer. Add any new topology/schema/prompt code under `SplitAgent`; keep
   old configs.
4. **Build** until green: `swift build --package-path fm-ramble-to-tasks`. Fix your own
   compile errors. (Swift 6 strict concurrency: `[String:Any]` statics must be computed
   `var`s; agents must be `Sendable`.)
5. **Run** on the full gate (judges via Sonnet + logs automatically; key is in the env):
   `swift run --package-path fm-ramble-to-tasks fmramble evaluate --agent <expNNN> --label <expNNN> --note "<short move>"`
6. **Compare.** Read the printed QUALITY and the per-case judge notes; compare to the
   current best (0.727). A delta ≤ ~0.05 is noise.
7. **Log.** Prepend ONE line to `program.md`:
   `- <expNNN> <move> — quality X.XXX (full), <new best | discarded>, <one-line insight>`.
   If it is the new best, say so explicitly.

## FM API limits (confirmed)
The Apple FM API exposes NO token logprobs (only greedy / top-p
`random(probabilityThreshold:seed:)` / top-k `random(top:seed:)` + temperature) and NO
custom-decoding hook. Logprob/self-certainty voting and diverse beam search are NOT
buildable. Seeded sampling IS available for reproducible best-of-N diversity.

## Training track (out of your scope to EXECUTE — requestable)
You can only edit inference-side Swift; you cannot train a LoRA adapter. If your
most-grounded idea needs one, write `fm-ramble-to-tasks/autoresearch/REQUEST.md`
(type / failure-mode-it-attacks / what-to-train / how-we'll-know / command-if-known),
THEN still run a normal inference experiment this iteration. The loop pauses on
REQUEST.md so the operator can train it (on RunPod) and wire the adapter in.

Make exactly ONE experiment. Be rigorous and brutally honest about whether it helped.
If your idea regressed, that is useful signal — log it and stop.
