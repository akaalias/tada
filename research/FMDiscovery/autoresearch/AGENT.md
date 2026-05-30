# AUTORESEARCH_RULES — standing instructions for the autonomous coding agent

You are an autonomous ML-systems research agent. Your job: improve an on-device
Apple Foundation Model discovery-question generator until it matches Anthropic
Sonnet on the quality metric. You run **exactly ONE experiment per invocation**,
fully autonomously, then stop. Speed of the on-device model does not matter.

## The artifact and the metric
- The MUTABLE artifact you improve: `research/FMDiscovery/Sources/DiscoveryAgent/**` ONLY.
- Headline metric: `quality` (0-1) on the **full-30 gate with GREEDY (deterministic)
  decoding**, judged by Sonnet (pairwise vs gold + a 1-5 rubric on atomicity/
  specificity/coverage/naturalness/non-redundancy). Higher is better.
- **GATE ON full-30 + greedy, NOT dev-10.** Hard-won lesson: the 10-case dev proxy
  AND stochastic sampling each added noise that produced false wins twice (a dev-10
  0.405 became 0.274 on full-30; the same adapter read 0.362 under greedy). So
  evaluate on the full 30 held-out cases, and make your config's final generation
  GREEDY (`selectSampling: .greedy`, temp 0) unless the technique INHERENTLY needs
  diverse samples (self-consistency / best-of-N) — in which case the aggregation
  itself must supply the stability. Do not chase single-draw deltas ≤0.03; that's noise.
- **Current best to BUILD ON: `adapter_v2a_e1` = 0.409 (full-30 greedy).** A LoRA
  adapter (fine-tuned on-device weights), used via `DiscoveryConfig.adapter` +
  `ConfiguredAgent.resolveModel()`. It beats the entire in-context plateau (~0.32).
  Prefer it as the BASE model for any generate/critique/ensemble call.
- The harness JUDGES and LOGS automatically when you run the eval command. You do
  not implement judging or scoring.

## HARD RULES (never violate — violations are auto-reverted)
- Edit ONLY files under `research/FMDiscovery/Sources/DiscoveryAgent/`. You may
  also append to `research/FMDiscovery/program.md`.
- NEVER modify `Sources/EvalBench`, `Sources/Contract`, `Sources/fmresearch`,
  `gold/`, `dashboard/`, `results/`, or `autoresearch/`. These are the ruler.
- NEVER hand-edit `results/runs.jsonl` or `results/*.json`. The eval writes them.
- NEVER change the gold answers, the judge, the metric, or the spec gate. Do not
  try to make the metric easier. Improve the agent, not the ruler.
- GOLD/EXEMPLAR LEAK BAN: gold or retrieved exemplar question-sets may be used
  ONLY as in-context few-shot DEMONSTRATIONS that inform questions you GENERATE
  for the user's actual task. NEVER copy, template, paraphrase, or rewrite an
  exemplar's questions one-to-one into the output. A real user's task will not
  match the exemplar bank, so the model must always generate fresh questions for
  the specific task. An experiment that transcribes/adapts gold questions as its
  output is INVALID even if it scores well — do not pursue that class of idea.
- CORPUS MAY GROW (encouraged): generating MORE Sonnet (task→questions) pairs for
  NEW, different tasks — to broaden the retrieval/demonstration bank or to build
  adapter-training data — is allowed and valuable. Those live under
  `research/FMDiscovery/corpus/` (a growable demonstration bank), NOT `gold/`. The
  eval `gold/` and the dev-10 stay FROZEN: never add, edit, or remove eval cases.
  Growing the demonstration bank is fine; changing what you are scored on is not.
- Every experiment MUST end with a GREEN build and exactly one NEW logged run.
- Keep all previous configs intact; each experiment ADDS a new named config.

## One iteration — do all of this, then STOP
1. **Review.** Read `program.md` (the experiment log + current best). Read the
   most recent `results/*.json` and study the judge's per-case `notes` — these are
   the concrete failure modes to attack.
2. **Ideate ONE hypothesis** grounded in those notes. The dominant gap is
   **coverage** (the model misses the single most decision-critical unknown for a
   task) — it is pinned at rubric 3 across EVERY lever tried, including weight-level
   training. Do NOT merely reword prompts — repeatedly proven insufficient.
   Use the real lever space:
   - decoding: per-stage `temperature` / sampling (`DiscoveryConfig`)
   - topology: multi-call pipelines, self-critique/reflexion, best-of-N (`ConfiguredAgent`)
   - guided-schema design: over-generate-then-score, constraints, select-in-Swift
   - deterministic post-processing in Swift: embedding-based dedup, coverage
     enforcement against a dimension scaffold, atomicity/filler detect-and-repair
   - retrieval-augmented few-shot: embed the input, retrieve nearest exemplar
     question-sets from the demonstration bank (`corpus/`, may be grown), inject
     as dynamic few-shot (on-device). On-device embeddings: `NLEmbedding`/`NLContextualEmbedding`.
   - **adapter (NOW AVAILABLE, and it's the best base):** `adapter_v2a_e1` (0.409).
     Use it via `config.adapter` (see `resolveModel()`); build multi-call topologies
     ON the adapter, not the stock 3B — every prior multi-FM loss was on the weak 3B.
   Build on the current BEST config (the adapter); periodically try a bold, different idea.

   WHAT THE DATA SAYS — the LoRA adapter (`adapter_v2a_e1`, 0.409 full-30 greedy) is
   the BEST and the only thing that beat the ~0.32 in-context plateau; single-call RAG
   (exp003, 0.320) led the in-context family. NAIVE multi-FM on the STOCK 3B has lost
   every time: chained brainstorm→select (exp001, 0.235), best-of-N over 4 temps
   (exp004, 0.245), reflexion editor (exp005, 0.315) — extra weak-3B passes compound
   weak judgment. More/differently-shaped TRAINING DATA also failed to move coverage:
   v2b (coverage-forced gold) stayed at coverage 3 and below v2a. Do NOT repeat those.

   TWO GENUINELY-UNTRIED, HIGH-PRIORITY LEVERS (try these first):
   (A) **Divergent→convergent free-text.** EVERY call so far was schema-constrained.
       Try an UNCONSTRAINED conversational first call (plain text, NO `@Generable`
       schema, `includeSchemaInPrompt`): let the model freely brainstorm what matters
       for the task in prose; then a SECOND guided call converges that prose into the
       7 structured questions. Hypothesis: removing the schema straitjacket on the
       *thinking* step lets task-specific unknowns surface before they're forced into
       slots. Run BOTH calls on the adapter.
   (B) **Smart multi-FM ON THE ADAPTER.** Now that per-call judgment is higher (the
       adapter), re-test multi-FM done RIGHT: (a) scope a critique to ONE named failure
       mode (e.g. "which decision-critical unknown is missing?"), not a general audit;
       (b) best-of-N selected via PAIRWISE adapter comparisons / a tournament (relative
       judgment beats absolute scoring), not an absolute scorer; (c) self-consistency
       voting across diverse adapter generations.
3. **Code it** as a NEW named config in `Configs.swift`. CHOOSE A UNIQUE LABEL:
   scan BOTH `results/runs.jsonl` and `Configs.swift` for the highest existing
   `expNNN` and use the next integer. NEVER reuse a label that already appears in
   `results/runs.jsonl` — duplicate labels corrupt the dashboard, cost, and diagram
   mapping. Add any new topology/post-processing code in `DiscoveryAgent`; keep old configs.
4. **Build** until green: `swift build --package-path research/FMDiscovery`.
   Fix your own compile errors. (Swift 6 strict concurrency: `[String:Any]`
   statics must be computed `var`; agents must be `Sendable`.)
5. **Run** on the FULL-30 gate (this judges via Sonnet and logs automatically; the
   key is already in the environment):
   `swift run --package-path research/FMDiscovery fmresearch evaluate --agent <expNNN> --subset full --label <expNNN> --note "<short move description>"`
6. **Compare.** Read the printed `QUALITY` and the per-case judge notes. Compare
   to the current best (adapter_v2a_e1 = 0.409) in `program.md`. A delta ≤0.03 is noise.
7. **Log.** Prepend ONE line to the experiment log in `program.md`:
   `- <expNNN> <move> — quality X.XXX (full-30 greedy), <new best | discarded>, <one-line insight>`
   If it is the new best, say so explicitly.

Make exactly ONE experiment. Be rigorous and brutally honest about whether it
helped. If your idea regressed, that is useful signal — log it and stop.
