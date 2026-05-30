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
   - guided-schema design: over-generate-then-score, constraints, select-in-Swift.
     Richer `@Guide` than we use today is available: regex/pattern guides, enumerations
     (`.anyOf`), numeric ranges, nested `@Generable` types — not just `.count(n)` + a
     description. A tighter schema is a real lever.
   - **tool-calling (COMPLETELY UNUSED so far — your call whether it helps):** Apple FM
     supports the `Tool` protocol + `LanguageModelSession(tools:)`, letting the model
     invoke Swift functions mid-generation. Plausible uses: a coverage-check tool the
     model calls before finalising, an on-device retrieval tool it queries for exemplars,
     a "is this question atomic?" validator. May or may not pay off — decide for yourself.
   - deterministic post-processing in Swift: embedding-based dedup, coverage
     enforcement against a dimension scaffold, atomicity/filler detect-and-repair
   - retrieval-augmented few-shot: embed the input, retrieve nearest exemplar
     question-sets from the demonstration bank (`corpus/`, may be grown), inject
     as dynamic few-shot (on-device). On-device embeddings: `NLEmbedding`/`NLContextualEmbedding`.
   - **adapter (NOW AVAILABLE, and it's the best base):** `adapter_v2a_e1` (0.409).
     EVERY session in `ConfiguredAgent` now routes through `resolveModel()`, so simply
     setting `adapter: "<path>"` on ANY config runs that ENTIRE topology on the adapter
     (one-line change — no per-call edits). Available `.fmadapter` files: `ls
     research/FMDiscovery/adapter/exports/`; copy a path from an existing `adapter_*`
     config in `Configs.swift`. HIGH-VALUE, barely-explored class: take a proven
     in-context topology (RAG few-shot, contrastive, scoped critique) and run it ON the
     adapter — every prior multi-FM loss was on the weak stock 3B, never the adapter.
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

   RESEARCH-BACKED LEVERS (2024-2025 literature) — THE MISSING IDEA. A deep review found
   that EVERY method that beats baselines scores a question NOT in isolation but against
   an EXPLICIT, materialised set of competing solutions/interpretations it would
   discriminate between. ALL our 27 experiments scored questions in isolation (absolute
   rubric, vague "importance", or whole-set pairwise) — we never enumerated candidate
   SOLUTIONS and asked which question separates them. That is very likely WHY coverage is
   stuck: "which unknown is critical" is undefined until you have competing answers to be
   critical about. The four highest-leverage untried levers (all INFERENCE-TIME, build on
   the adapter):
   (C) **Solution-space information gain (TOP PICK).** Stage 1: have the model generate
       N (4-6) DIVERGENT candidate plans/interpretations for the task (e.g. for "plan a
       trip": budget-backpacking vs luxury-anniversary vs business+1-free-day). Stage 2:
       score each candidate question by how much the plans DISAGREE on its answer (a
       question matters iff answering it changes which plan you'd pick); keep the
       highest-discrimination questions. Grounds "which unknown matters" in concrete
       competing answers. (Active Task Disambiguation, ICLR 2025; SAGE reports +39%
       coverage on a 3B-scale setting.) DISTINCT from exp013, which drafted ONE plan and
       extracted assumptions — this needs a SET of divergent plans scored by discrimination.
   (D) **Principled covering-set selection (deterministic Swift).** Replace "top-7 by
       score + threshold dedup" with a SET-LEVEL coverage objective: over-generate ~15-20
       questions, embed (NLEmbedding), then GREEDILY pick 7 maximising coverage-volume —
       a DPP/facility-location/submodular objective with a (1-1/e) guarantee. Axes are
       derived from the candidates (task-adaptive), NOT a universal taxonomy (that's why
       it differs from the failed exp015 dimensional schema). Pairs naturally with (C):
       greedy submodular info-gain = pick the 7 that JOINTLY best discriminate the plans.
   (E) **Answer-simulation verifier.** Judge a question by SIMULATING its plausible
       answers and checking whether they'd change the downstream plan / cover distinct
       interpretations — "does asking this actually change what I'd produce?" Grounded,
       not rubric-based (replaces the failed reflexion critique). (Zhang, ICLR 2025.)
   (F) **Decomposed binary verification.** Do NOT ask the 3B "are these 7 good?" (holistic
       scoring it provably can't do — small models can't self-correct holistically but CAN
       do local binary checks). Ask many TRIVIAL yes/no checks per question (answerable?
       targets a real ambiguity? non-redundant with the others? atomic?) and aggregate the
       verdicts in deterministic Swift. Enforce anything code-checkable (count=7, embedding
       near-dupes, interrogative form) in Swift, not via the model. (FActScore-style
       decompose-then-verify; CRITIC, ICLR 2024.)
   NOTE — two FM-API limits confirmed: the Apple FM API exposes NO token logprobs (only
   greedy / top-p `random(probabilityThreshold:seed:)` / top-k `random(top:seed:)` +
   temperature) and NO custom-decoding hook. So logprob/self-certainty voting and diverse
   beam search are NOT buildable — do not attempt them. (Seeded sampling IS available for
   reproducible best-of-N diversity.)

   DRAW ON YOUR OWN KNOWLEDGE — you are NOT limited to the levers listed above. You have
   no web access, so you cannot look things up; instead apply what you already know about
   making small LMs strong on a narrow task. Established strategies worth adapting here
   (INFERENCE-TIME, which you CAN build): mixture-of-experts-style routing across
   prompt/adapter "experts" then merge; cascades / speculative routing (cheap draft →
   selective refine); self-consistency & majority/median voting; debate or
   generate-then-verify; constrained / grammar-guided decoding; LLM-as-judge selection
   with PAIRWISE (relative) comparison; retrieval-augmented prompting; ensembling diverse
   decompositions. If you know a technique that fits the coverage gap, name it in your
   write-up and adapt it — novelty grounded in a real method is encouraged.

   TRAINING-TRACK ideas are OUT OF YOUR SCOPE (you only edit inference-side Swift and
   cannot train): new or multiple specialised LoRA adapters, true MoE training,
   changing the distillation data/objective. If your best idea needs one of these,
   DO NOT attempt it — instead log a one-line note in `program.md` proposing it for the
   human operator, and run a different inference-time experiment this iteration.
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
