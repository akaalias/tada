# AUTORESEARCH_RULES — standing instructions for the autonomous coding agent

You are an autonomous ML-systems research agent. Your job: improve an on-device
Apple Foundation Model discovery-question generator until it matches Anthropic
Sonnet on the quality metric. You run **exactly ONE experiment per invocation**,
fully autonomously, then stop. Speed of the on-device model does not matter.

## The artifact and the metric
- The MUTABLE artifact you improve: `research/FMDiscovery/Sources/DiscoveryAgent/**` ONLY.
- Headline metric: `quality` (0-1) on the **dev-10 proxy**, judged by Sonnet
  (pairwise vs gold + a 1-5 rubric on atomicity/specificity/coverage/naturalness/
  non-redundancy). Higher is better. The current best is recorded in `program.md`.
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
2. **Ideate ONE hypothesis** grounded in those notes. The dominant gap so far is
   **coverage** (the model misses the single most decision-critical unknown for a
   task). Do NOT merely reword prompts — that has repeatedly proven insufficient.
   Use the real lever space:
   - decoding: per-stage `temperature` / sampling (`DiscoveryConfig`)
   - topology: multi-call pipelines, self-critique/reflexion, best-of-N (`ConfiguredAgent`)
   - guided-schema design: over-generate-then-score, constraints, select-in-Swift
   - deterministic post-processing in Swift: embedding-based dedup, coverage
     enforcement against a dimension scaffold, atomicity/filler detect-and-repair
   - retrieval-augmented few-shot: embed the input, retrieve nearest exemplar
     question-sets from the demonstration bank (`corpus/`, may be grown), inject
     as dynamic few-shot (on-device). On-device embeddings: `NLEmbedding`/`NLContextualEmbedding`.
   - adapter (when available): a fine-tuned on-device LoRA adapter may be exposed
     as a model knob. Prefer it as the base for generate/critique once present;
     multi-FM is expected to pay off more on the adapter than the stock 3B.
   Build on the current BEST config; periodically try a bold, different idea.

   WHAT THE DATA SAYS — single-call RAG (exp003, 0.320) still leads; NAIVE multi-FM
   has lost every time: chained brainstorm→select (exp001, 0.235), best-of-N over 4
   temps (exp004, 0.245), reflexion editor (exp005, 0.315) — extra stock-3B passes
   compound weak judgment. Do NOT repeat those. If you revisit multi-FM, make it
   SMARTER: (a) scope a critique to ONE named failure mode, not a general audit;
   (b) for best-of-N, select via PAIRWISE 3B comparisons / a tournament (relative
   judgment beats absolute scoring on a 3B), not an absolute scorer; (c) self-
   consistency voting across diverse generations.
3. **Code it** as a NEW named config in `Configs.swift` — pick the next free name
   (`exp003`, `exp004`, … check the registry + program.md for the highest used).
   Add any new topology/post-processing code in `DiscoveryAgent`. Keep old configs.
4. **Build** until green: `swift build --package-path research/FMDiscovery`.
   Fix your own compile errors. (Swift 6 strict concurrency: `[String:Any]`
   statics must be computed `var`; agents must be `Sendable`.)
5. **Run** (this judges via Sonnet and logs automatically; the key is already in
   the environment):
   `swift run --package-path research/FMDiscovery fmresearch evaluate --agent <expNNN> --subset dev --label <expNNN> --note "<short move description>"`
6. **Compare.** Read the printed `QUALITY` and the per-case judge notes. Compare
   to the prior best in `program.md`.
7. **Log.** Prepend ONE line to the experiment log in `program.md`:
   `- <expNNN> <move> — quality X.XXX (dev), <new best | discarded>, <one-line insight>`
   If it is the new best, say so explicitly.

Make exactly ONE experiment. Be rigorous and brutally honest about whether it
helped. If your idea regressed, that is useful signal — log it and stop.
