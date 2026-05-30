import Foundation

/// Named experiment configs. Each new experiment adds an entry here; the CLI
/// runs them via `--agent <name>`. This is the human-readable history of the
/// search — keep it in sync with program.md's experiment log.
public enum Configs {
    public static let registry: [String: DiscoveryConfig] = [
        // EXP-000: single-shot port of the Sonnet prompt. Baseline = 0.282.
        "baseline": DiscoveryConfig(topology: .singleShot),

        // EXP-001: two-stage brainstorm → select+phrase.
        "exp001": DiscoveryConfig(topology: .brainstormSelect),

        // EXP-002: over-generate 12 scored candidates, select top-7 in Swift code.
        "exp002": DiscoveryConfig(topology: .overGenerateScore),

        // EXP-003: retrieval-augmented few-shot — retrieve 2 nearest non-dev gold
        // exemplars by word overlap, inject as few-shot demonstrations, single call.
        "exp003": DiscoveryConfig(topology: .ragFewShot),

        // EXP-004: best-of-N over the RAG agent (4 temps), select the set with the
        // best deterministic coverage score in Swift. Attacks the coverage gap by
        // ranking whole model-generated sets, preserving natural phrasing.
        "exp004": DiscoveryConfig(topology: .ragCoverageBestOfN,
                                  sampleTemps: [0.3, 0.6, 0.9, 1.0]),

        // EXP-005: reflexion editor on the RAG draft. Stage 1 = exp003 best; stage 2 =
        // a 2nd FM auditor that drops already-given/low-value/compound questions and
        // fills the highest-value missing decision-critical unknown. Low temp on both
        // stages for determinism; attacks the coverage wall via revision, not sampling.
        "exp005": DiscoveryConfig(topology: .ragCritiqueRevise, selectTemp: 0.3),

        // EXP-006: RAG few-shot (exp003 best) + an explicit TASK-CONDITIONED coverage
        // checklist. Dimensions are aggregated from the same 2 nearest gold exemplars
        // and injected as an adaptable coverage requirement, single call. Attacks the
        // coverage wall with a retrieved (not universal) checklist — the lever exp005's
        // insight pointed to, without the auditor's redundancy/phrasing regressions.
        "exp006": DiscoveryConfig(topology: .ragCoverageScaffold),

        // EXP-007: exp003 best, but RAG exemplars retrieved by on-device semantic
        // similarity (NLEmbedding sentence-embedding cosine) instead of word-overlap
        // Jaccard. Jaccard returns ~0 for topically distinct queries (resume↔interview,
        // tax↔budget share no words); semantic retrieval surfaces the nearest task TYPE
        // so the few-shot demonstrations model the right decision-critical unknowns.
        "exp007": DiscoveryConfig(topology: .ragFewShotSemantic),

        // EXP-008: adapt-the-exemplar. Make the nearest exemplar's 7 CONCRETE gold
        // questions hard constraints — the model adapts each one-to-one to the new
        // task, preserving the unknown each probes so gold's dimension SPAN transfers
        // directly. exp005/006 failed because they injected dimension LABELS; this
        // injects the actual questions to rewrite, the lever the log keeps pointing to.
        "exp008": DiscoveryConfig(topology: .ragAdaptExemplar),

        // EXP-009: coverage-gap REPAIR. Build the exp003 RAG draft, then deterministically
        // (NLEmbedding) find the concrete gold question whose unknown the draft covers LEAST
        // and the most-redundant draft slot; one focused FM call adapts that gold question to
        // the task and we swap it into the redundant slot. Coverage judgment moves OUT of the
        // 3B into embedding math; 6/7 draft questions stay verbatim. Low temp for determinism.
        "exp009": DiscoveryConfig(topology: .ragCoverageRepair, selectTemp: 0.3),

        // EXP-010: self-consistency consensus. Draw 4 independent RAG sets (the exp003
        // few-shot prompt) at temps [0.4,0.6,0.8,1.0], embedding-cluster all 28 questions,
        // and keep the 7 clusters with the broadest CROSS-SAMPLE agreement. Attacks the
        // redundancy + one-off-niche faults the judge flags in nearly every exp003 case:
        // duplicates collapse to one cluster, single-sample noise drops out, and the
        // recurring (=high-probability=likely critical) planning unknowns rise. New
        // selection signal vs exp002 (self-rated importance) and exp004 (whole-set scoring).
        "exp010": DiscoveryConfig(topology: .ragSelfConsistency,
                                  sampleTemps: [0.4, 0.6, 0.8, 1.0]),

        // EXP-011: contrastive (negative) few-shot. exp003's positive few-shot stays
        // (the running best, single call), but a fixed GOOD-vs-BAD worked example on a
        // neutral task ("Organize my garage") is prepended. The BAD set demonstrates the
        // exact anti-patterns the judge flags on exp003 — restating given facts, off-task/
        // self-defeating questions, vague filler, compound asks, redundant pairs — so the
        // 3B learns by CONTRAST what not to spend a slot on. Every prior coverage fix added
        // a runtime judging step and regressed; this bakes the judgment into a demonstration.
        "exp011": DiscoveryConfig(topology: .ragContrastiveFewShot),

        // EXP-012: smart best-of-N via a PAIRWISE 3B TOURNAMENT. Draw 4 independent
        // exp003 RAG sets at temps [0.3,0.5,0.7,0.9], then run a single-elimination
        // bracket where each match is decided by the 3B comparing the TWO whole sets
        // and picking the better one — run in BOTH orderings (vote, tie→incumbent) to
        // damp position bias. The winner is returned VERBATIM (no mangling → atomicity
        // and natural phrasing preserved). exp004 (absolute Swift coverage scorer) and
        // exp010 (frequency clustering) both failed to pick the better set; the rules
        // note RELATIVE judgment beats absolute scoring on a 3B — the one form of
        // judgment a 3B is actually decent at, and the untried selection signal.
        "exp012": DiscoveryConfig(topology: .ragTournament,
                                  sampleTemps: [0.3, 0.5, 0.7, 0.9]),

        // EXP-013: plan-then-extract-assumptions. The coverage wall is that the 3B
        // can't RANK which unknowns are decision-critical (every selection/aggregation/
        // critique/in-context variant stuck at coverage 3). This changes the COGNITIVE
        // task: stage 1 has the 3B draft a CONCRETE plan and surface the ASSUMPTIONS it
        // was forced to commit to — to write a real plan it must assume a departure
        // city/budget/who-for/dates/scale, i.e. exactly the decision-critical unknowns,
        // and they emerge grounded in THIS task (unlike brainstormSelect's abstract,
        // generic unknown-listing). Stage 2 turns those assumed unknowns into 7 natural
        // questions using the proven exp003 RAG few-shot scaffold for phrasing/atomicity.
        "exp013": DiscoveryConfig(topology: .ragPlanAssumptions,
                                  brainstormTemp: 0.5, selectTemp: 0.3),

        // EXP-014: corpus-backed RAG few-shot. Every prior retrieval variant drew
        // demonstrations from only the 12 generic hardcoded GoldExemplars, so the
        // "nearest" exemplar was often off-domain and modeled the wrong decision-
        // critical unknowns (exp007 wrongly concluded retrieval can't help — but the
        // POOL was the limiter). This swaps the BANK for the 100+ corpus/ Sonnet sets
        // (semantic retrieval, k=3) so the few-shot demos are genuinely close-DOMAIN
        // and model the right unknowns for THIS task type. Built on exp011's
        // contrastive lesson (the current best). Tests whether a richer demonstration
        // bank — the one untapped lever the rules encourage — breaks the coverage wall.
        "exp014": DiscoveryConfig(topology: .ragCorpusFewShot),

        // EXP-015: structural coverage enforcement via a typed guided SCHEMA. Every
        // prior coverage attempt either SHOWED the 3B which unknowns matter (demos/
        // checklists) or asked it to SELECT/RANK/CRITIQUE its samples — all stuck at
        // coverage 3 because the 3B can't rank and freely DROPS the critical slot. New
        // lever (untried — every config used one flat questions[] array): the output
        // schema has SEVEN distinctly-@Guide'd slots, one per universal high-value
        // planning dimension the judge keeps flagging as MISSING (goal/scope/who-for/
        // budget/timeline/current-state/constraints). Guided generation ENFORCES each
        // named field, so the model structurally cannot omit budget/who-for/timeline/
        // current-state — coverage breadth becomes a property of the SCHEMA, not of
        // ranking judgment the 3B lacks. Single call on the exp011 RAG+contrastive base.
        "exp015": DiscoveryConfig(topology: .ragDimensionalSchema),

        // EXP-016: sequential one-question-at-a-time generation. Every prior config
        // emitted all 7 questions in a SINGLE guided generation (flat array, scored
        // pool, or 7 typed slots) and plateaued at coverage 3. exp010's datum: the
        // 3B's MODAL output is the generic catch-all; the sharp task-specific unknowns
        // live in the TAIL of its distribution. Emitting 7 at once lets the model
        // collapse onto the modal cluster. This topology generates ONE question per
        // call, each shown the already-asked set and told to probe a DIFFERENT unknown
        // — forced novelty pushes each successive emission off the modal cluster into
        // the tail. A new generation DYNAMIC (not select/rank/critique/aggregate, the
        // absolute judgment the 3B lacks), on the exp003 RAG few-shot base.
        "exp016": DiscoveryConfig(topology: .ragSequential),

        // EXP-017: filler/redundancy detect-and-repair. The judge's recurring
        // complaint on the best config (exp011) is that redundant near-duplicate
        // clusters (bakery Q1/Q2/Q3/Q7, gp Q3/Q4, guitar Q5/Q7) and vague catch-alls
        // ("specific features or preferences", "specific requirements") "crowd out
        // more valuable questions" — the model often produces task-specific unknowns
        // but WASTES slots, so the critical ones don't make the cut. exp005 (FM audit
        // injecting a universal budget/timeline checklist) and exp009 (embedding
        // gap-finder picking a gold question) both regressed. This keeps detection
        // purely DETERMINISTIC in Swift (filler-phrase patterns + content-word Jaccard
        // near-dupes), so it frees exactly the wasted slots the judge flags, then makes
        // ONE scoped call to refill ONLY those slots with concrete, task-specific
        // questions (shown the kept set, told to be specific, given NO dimension
        // checklist). Strong slots returned verbatim; a defensive re-check reverts any
        // refill that is itself filler or duplicates a kept slot. Built on exp011.
        "exp017": DiscoveryConfig(topology: .ragFillerRepair),

        // EXP-018: in-schema chain-of-thought. The coverage wall is that the 3B
        // can't decide WHICH unknown is decision-critical, so it defaults to generic
        // catch-alls. Every prior config either emitted questions DIRECTLY (no
        // explicit which-unknowns-matter step) or moved the judgment into a SEPARATE
        // FM pass (brainstorm→select exp001, plan→assumptions exp013, auditor exp005,
        // tournament exp012) — all of which compounded the 3B's weak judgment and lost.
        // This is the untried middle path: a SINGLE call whose output schema forces
        // the model to FIRST commit to the 7 most decision-critical unknowns as short
        // phrases, THEN write one natural question probing each, in order. Guided
        // generation emits fields in order, so the leading `criticalUnknowns` list acts
        // as in-schema CoT that conditions the questions — no extra weak-judgment pass.
        // A worked reasoning demonstration (the unknowns for "Organize my garage")
        // anchors what GOOD critical-unknown identification looks like (classic CoT
        // few-shot), on the exp011 contrastive RAG base (current best).
        "exp018": DiscoveryConfig(topology: .ragReasonedFewShot),

        // EXP-019: decoding lever, isolated on the BEST base. Every prior config —
        // including the running best (exp011 contrastive RAG) and exp003 — left the
        // single generation call on STOCHASTIC model-default sampling, so each
        // reported ~0.32 is a NOISY single draw (the exp011 log itself calls its
        // +0.003 "within run-to-run noise"). The decoding lever (rules' lever #1)
        // has never been isolated on the best topology. exp010's datum says the 3B's
        // MODAL output is the generic catch-all and the sharp task-specific unknowns
        // live in the TAIL — a directly falsifiable prediction. This config holds the
        // exp011 contrastive-RAG topology FIXED and only swaps decoding to GREEDY
        // (temperature 0, deterministic mode). If modal=generic is right, greedy
        // should regress coverage (pure mode = most generic) AND remove sampling
        // noise/redundancy; if exp011's score was partly sampling luck, greedy gives
        // the model's single most-confident set. Either way it isolates how much of
        // the plateau is decoding vs. judgment — signal no prior experiment produced.
        "exp019": DiscoveryConfig(topology: .ragContrastiveFewShot,
                                  selectTemp: 0.0, selectSampling: .greedy),

        // EXP-020: corpus-grounded SELECTION over an over-generated candidate pool.
        // The wall: the 3B can't rank which unknown is decision-critical. Every prior
        // selection over its own samples failed because the SIGNAL was weak 3B
        // judgment (exp002/010/012) or a blunt heuristic (exp004/009). This selector's
        // signal is EXTERNAL: rank each candidate by embedding resemblance to the
        // questions Sonnet ACTUALLY asks for the nearest corpus task types — generic
        // 3B catch-alls match Sonnet's sharp questions weakly (demoted), tail
        // task-specific questions match strongly (surfaced). Over-generate at 3 temps
        // so the task-specific TAIL (exp010's datum) lands in the pool; then select 7
        // by max-cosine-to-Sonnet with embedding redundancy suppression. Output stays
        // 3B-generated; corpus is a ranking prior only (no copy/template = leak-safe).
        "exp020": DiscoveryConfig(topology: .ragCorpusSelect,
                                  sampleTemps: [0.4, 0.7, 1.0]),

        // EXP-021: prompt-diverse PERSPECTIVE ENSEMBLE. The coverage wall is that the
        // 3B's single draw collapses onto a generic modal cluster (exp010's datum),
        // and EVERY prior multi-sample config (best-of-N exp004, self-consistency
        // exp010, tournament exp012, corpus-select exp020) drew its samples from ONE
        // prompt at varying TEMPERATURES — so all the samples sit in that SAME modal
        // cluster and no aggregation/selection over them recovers the missing
        // dimensions. This config tests the orthogonal, untried lever: PROMPT
        // diversity. It generates three full sets from three systematically different
        // generation FRAMES (EXECUTION/logistics, SCOPE/goals, DOMAIN-EXPERT), each
        // steering the model into a different region of decision-space so the UNION
        // spans dimensions a single draw misses (the domain-expert frame targets the
        // recurring domain-specificity gap). The 7 are merged DETERMINISTICALLY —
        // round-robin by emission order with filler/near-dup suppression — so NO weak
        // 3B selection/ranking/critique pass is added (the move that sank every prior
        // multi-FM attempt). Built on the exp011 contrastive RAG base.
        "exp021": DiscoveryConfig(topology: .ragPerspectiveEnsemble),

        // EXP-022: interleaved per-question chain-of-thought. exp018 already tried
        // in-schema CoT but as a BATCH leading list (name all 7 unknowns first, then
        // write all 7 questions) — it failed because the model filled the list with
        // the same modal/generic content and the questions inherited it; a batch list
        // conditions all 7 at once but gates no single slot. This tests the untried
        // tight-coupling variant: the schema INTERLEAVES a concrete decision-IMPACT
        // rationale immediately BEFORE each question (guided generation emits fields
        // in order, so slot k's rationale conditions slot k's question). Hypothesis: a
        // per-emission justification is harder to satisfy with filler than a one-shot
        // batch list — forcing the model to name the concrete plan-fork a slot changes,
        // at the moment it writes that slot, should suppress "any other preferences?"
        // catch-alls and nudge specificity/non-redundancy. Single call on the exp011
        // contrastive RAG base (best); rationales are discarded from the output.
        "exp022": DiscoveryConfig(topology: .ragJustifiedQuestions),

        // EXP-023: scoped starting-point critique. Every prior 2nd-pass config ran a
        // GENERAL audit and lost — exp005 (delete-given/delete-low-value/split-
        // compound/fill-from-a-checklist, 0.315) and exp017 (detect+refill all wasted
        // slots, 0.283) both compound the 3B's weak judgment across many independent
        // edits and mangle strong slots. The rules' guidance for a smarter multi-FM
        // pass is to "scope a critique to ONE named failure mode, not a general
        // audit." The single dominant recurring miss across the WHOLE dev set is the
        // same dimension: the model ASSUMES the user's STARTING POINT and never asks
        // it (trip→departure city, resume→current role/existing resume, guitar→skill
        // level, tax→residency/employment, buy_used_car→is a car already chosen,
        // wedding→is the venue booked). Stage 1 = exp011 contrastive RAG draft (best).
        // Stage 2 = ONE call judging ONLY "does any slot establish the starting
        // point?" — if YES, the draft is returned verbatim (zero rewrite risk); if NO,
        // the model names the single weakest slot and writes one task-specific
        // starting-point question, and Swift swaps exactly that one slot (other 6
        // verbatim, filler/near-dup defended). At most one slot changes — the
        // minimal-surface 2nd pass, attacking the one gap that recurs everywhere.
        "exp023": DiscoveryConfig(topology: .ragStartingPointCritique),

        // EXP-024: decoding lever, UPPER endpoint on the BEST base. exp019 isolated
        // the decoding lever's LOWER endpoint — greedy (temp 0) on the exp011
        // contrastive-RAG base scored 0.273 (the deterministic floor), confirming
        // exp010's datum that the 3B's MODAL output is the generic catch-all. The
        // complementary half has never been isolated: if the sharp, task-specific
        // unknowns live in the TAIL of the sampling distribution (exp010), then a
        // HIGHER-temperature single draw should surface more of them and lift
        // coverage — at the known risk (exp004) that very high temp degrades
        // atomicity (compound/parenthetical asks, possible spec-gate failures).
        // This holds the exp011 topology FIXED and only raises temperature to 1.2
        // (clearly above the model default, into tail territory). Together with
        // exp019 (greedy, 0.273) and the model-default draws (~0.32) it maps the
        // temperature/quality curve and decides whether the plateau is decoding-
        // limited or judgment-limited — a clean falsifiable probe, no added
        // 3B-judgment or embedding dependence.
        "exp024": DiscoveryConfig(topology: .ragContrastiveFewShot, selectTemp: 1.2),

        // EXP-025: givens-aware single call. The most-cited waste across the entire
        // log is the 3B spending slots re-asking facts the task ALREADY states
        // (dinner "how many guests?" when the task says 8 friends; trip destination
        // is Paris; buy_used_car assumes a car is already chosen). exp018 tried an
        // in-schema think-first step but its first field — "name the 7 critical
        // unknowns" — demands the which-unknown-is-critical JUDGMENT the 3B lacks, so
        // it filled it with the same modal/generic content and lost. This flips the
        // first field to one the 3B CAN reliably produce: `providedFacts`, the
        // concrete facts literally present in the task text (pure reading
        // comprehension, not judgment). Guided generation emits fields in declared
        // order, so the model commits to the givens FIRST, then writes 7 questions
        // under an absolute no-re-ask-a-given rule — in ONE coherent draw, no separate
        // refill pass. The bet: a meaningful share of the recurring slot-waste is
        // re-asking givens, so freeing those slots lets the 7 span more genuine
        // unknowns. Built on the exp011 contrastive RAG base (current best).
        "exp025": DiscoveryConfig(topology: .ragGivensAware),

        // EXP-026: composite-ruler best-of-N over the BEST generator. exp004 already
        // tried best-of-N and lost, but the log records exactly WHY and what to fix:
        // it ran on the weaker exp003 base and selected by a COVERAGE-ONLY keyword
        // scorer, which is blind to the atomicity/specificity degradation high-temp
        // draws introduce (it "can't see those and selects the worse set"). The log's
        // explicit prescription — "a useful ruler must score atomicity+specificity+
        // task-fit, not just dimension keyword presence; and sampling noise needs a
        // low-temp floor" — was never implemented. This config does precisely that:
        // draw N sets from the exp011 contrastive-RAG generator (the current best,
        // not exp003) with a low-temp floor, then select FULLY DETERMINISTICALLY (no
        // 3B judgment — the trap that sank every multi-FM config) by a COMPOSITE score
        // = CoverageScorer dimension span MINUS penalties for filler catch-alls,
        // near-duplicate pairs, and compound ("and"/"or") asks (the atomicity proxy
        // the rubric rewards). Winner returned verbatim (phrasing never mangled). This
        // is the one untried point in the best-of-N space: best base + composite (not
        // coverage-only) ruler + deterministic selection + low-temp floor.
        "exp026": DiscoveryConfig(topology: .ragCompositeBestOfN,
                                  sampleTemps: [0.4, 0.6, 0.8, 1.0]),

        // EXP-027: anti-modal self-contrast. The plateau is judgment-limited; exp010's
        // datum is that the 3B's MODAL output IS the generic catch-all and the sharp
        // task-specific unknowns live in the TAIL. exp024 reached for the tail with raw
        // TEMPERATURE (undirected → dredged incoherence/demo-bleed, not coverage) and
        // exp011 used a FIXED neutral-task GOOD-vs-BAD anchor. This is the untried
        // DIRECTED, task-specific push: stage 1 draws the model's OWN modal set via
        // GREEDY decoding (most-confident = most-generic, per exp019); stage 2 shows
        // that exact set back as "the generic draft to beat" and generates a FRESH 7
        // that surpasses it (sharper, more domain-specific, covering what it missed).
        // Stage 2 is GENERATION against a maximally-relevant self-anchor — NOT the
        // select/rank/critique judgment that sank every multi-FM config. Built on the
        // exp011 contrastive RAG base (current best). selectTemp = model default.
        "exp027": DiscoveryConfig(topology: .ragAntiModalContrast),

        // LoRA adapter (lever 7) — schema-free guided generation on the fine-tuned
        // on-device model (system+user match the training format, includeSchemaInPrompt
        // false). Three checkpoints compared on the HELD-OUT judge, since the final
        // epoch overfit (train loss ~0.02 vs valid ~1.92): epoch1 / epoch2 / final.
        "adapter_e1": DiscoveryConfig(topology: .adapterDirect,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_e1.fmadapter"),
        "adapter_e2": DiscoveryConfig(topology: .adapterDirect,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_e2.fmadapter"),
        "adapter_final": DiscoveryConfig(topology: .adapterDirect,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v1.fmadapter"),

        // v2 adapters — GREEDY decoding (deterministic) so the metric is reproducible,
        // gated on the full 30. v2a = 558 pairs, lr 5e-4; valid loss bottomed at epoch 2.
        // adapter_e1_g = v1 epoch1 at greedy, as a like-for-like baseline.
        "adapter_e1_g": DiscoveryConfig(topology: .adapterDirect, selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_e1.fmadapter"),
        "adapter_v2a_e1": DiscoveryConfig(topology: .adapterDirect, selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),
        "adapter_v2a_e2": DiscoveryConfig(topology: .adapterDirect, selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e2.fmadapter"),
        "adapter_v2b_e1": DiscoveryConfig(topology: .adapterDirect, selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2b_e1.fmadapter"),
        "adapter_v2b_e2": DiscoveryConfig(topology: .adapterDirect, selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2b_e2.fmadapter"),

        // EXP-028: scoped starting-point critique ON THE CHAMPION ADAPTER (v2a_e1, 0.409).
        // The champion is pinned at coverage 3; its OWN judge notes name ONE recurring
        // miss — the user's STARTING POINT / current state (does the user already know
        // ceramics; prior dog experience; medical clearance to run; whether a resume
        // exists; build-yourself-vs-hire) — while the same sets waste a slot on a
        // redundant near-dupe. exp023 ran this minimal-surface single-slot repair on the
        // STOCK 3B and landed in the noise; the rules' highest-value untapped lever is to
        // re-home a proven topology ON the adapter (higher per-call judgment). Stage 1 =
        // the champion VERBATIM (native adapter format, greedy). Stage 2 = ONE scoped
        // critique judging ONLY starting-point coverage, run on the adapter: if covered,
        // champion returned untouched; if not, swap exactly the weakest slot for a
        // task-specific starting-point question with filler/near-dup guards (≤1 changes).
        "exp028": DiscoveryConfig(topology: .adapterScopedCritique, selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-029: divergent → convergent free-text on the champion adapter (untried
        // lever A). EVERY prior call — including all adapter calls — was schema-
        // constrained, forcing the model into 7 slots before it could analyse the task.
        // Stage 1 is an UNCONSTRAINED plain-prose brainstorm (NO @Generable schema) where
        // the adapter freely reasons about the decision-critical, task-specific unknowns
        // (the starting point / forks the plan hinges on) — the coverage gap pinned at 3.
        // Stage 2 is the champion's exact native-format call, conditioned on that prose,
        // converging the surfaced unknowns into the 7 questions. Both passes are
        // GENERATION (not the judgment that sank exp028), both greedy/deterministic.
        "exp029": DiscoveryConfig(topology: .adapterDivergeConverge, selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-030: solution-space information gain on the champion adapter (Lever C — the
        // rules' TOP PICK, genuinely untried, never run on the adapter). The deep-review
        // finding: every disambiguation method that beats baselines scores a question
        // against an EXPLICIT, materialised set of COMPETING solutions it discriminates
        // between — never in isolation, which is how all 29 prior experiments scored, and
        // very likely WHY coverage is pinned at 3 ("which unknown is critical" is undefined
        // until you have competing answers to be critical about). Stage 1 materialises 4
        // DIVERGENT concrete scenarios (competing interpretations of who/what the user
        // wants); stage 2 is the champion's native-format call reframed as DISCRIMINATION —
        // write the 7 questions whose answers most SEPARATE the scenarios. Distinct from
        // exp013 (ONE plan → assumptions, skewed to logistics) and exp029 (free-prose
        // brainstorm → drifted generic). Both passes GENERATION (not judgment/selection),
        // both greedy; scenario block kept compact to avoid exp029's verbose-drift.
        "exp030": DiscoveryConfig(topology: .adapterSolutionSpaceEIG, selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-031: dispersion best-of-N on the CHAMPION adapter (v2a_e1, 0.409). The
        // champion's OWN judge notes name ONE mechanism in ~half its held-out losses —
        // it wastes 2-3 of its 7 slots on INTERNALLY REDUNDANT / overlapping questions
        // (apartment_move move-date AND how-many-days; dinner_party date AND time AND
        // venue-location AND availability; household_budget total AND fixed AND variable
        // expenses; gp circling "which clinic?" ×4; resume Q1/Q3 + Q2/Q7 mirror pairs),
        // crowding out the missing critical unknown. Redundancy is a SET-LEVEL property:
        // the single greedy draw is redundant, but other low-temp draws spread the 7
        // slots wider. So best-of-N over the adapter (greedy champion as floor + 3 low-
        // temp draws), selecting the whole set VERBATIM by a DETERMINISTIC embedding
        // ruler = max pairwise coverage VOLUME (least internal redundancy, Lever D's
        // covering-set objective) + on-task relevance. Zero model judgment (unlike the
        // failed tournament exp012) and zero regeneration (unlike exp028/029/030's
        // phrasing-degrading 2nd passes); aggregation supplies the stability the greedy
        // gate requires. Untried: best-of-N on the adapter selected by set-level
        // dispersion. selectTemp/greedy here govern the floor draft.
        "exp031": DiscoveryConfig(topology: .adapterDispersionBestOfN,
            selectTemp: 0, selectSampling: .greedy, sampleTemps: [0.4, 0.6, 0.8],
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-032: RAG few-shot demonstrations ON THE CHAMPION adapter (v2a_e1, 0.409).
        // The rules flag a HIGH-VALUE, barely-explored class: run a PROVEN in-context
        // topology on the ADAPTER, not the weak stock 3B. RAG few-shot was the stock 3B's
        // single strongest in-context lever (baseline 0.307 → exp003 0.320) but couldn't
        // move coverage off 3 because the 3B imitated surface, not which-unknown-matters.
        // On the adapter the variant has NEVER been run (exp028 was the scoped-CRITIQUE
        // re-home, not few-shot). Hypothesis: the champion misses the single critical
        // unknown (coverage pinned 3) and NONE of its self-judgment passes (critique
        // exp028 / free-text exp029 / EIG exp030 / best-of-N exp031) recovered it; an
        // EXTERNAL signal — concrete demonstrations of which dimensions strong sets cover
        // for SIMILAR task types — may finally transfer now that the adapter's stronger
        // base frees capacity from phrasing. Single greedy call, native training format +
        // 2 nearest gold exemplars APPENDED as reference demos; adapter generates fresh
        // questions (gold-leak ban respected). No 2nd pass → champion phrasing preserved.
        "exp032": DiscoveryConfig(topology: .adapterRagFewShot,
            selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-033: RAG few-shot ON THE CHAMPION adapter, but LEAVE-ONE-OUT — the
        // HONEST version of exp032. CRITICAL CORRECTION: exp032 (0.498) is INVALID
        // under the gold-leak ban. GoldExemplars holds 12 cases that the comment
        // claims are "not in dev-10" — but the gate MOVED to full-30, and ALL 12
        // exemplar inputs are EXACT eval-gold inputs (Renovate my kitchen=kitchen_reno,
        // Quit smoking=quit_smoking, Adopt a dog=adopt_dog, ...). So for 12/30 cases
        // exp032 retrieved each case's OWN gold 7 questions and showed them to the
        // model as a "demonstration" → it paraphrased gold, and the judge scored vs
        // that same gold. That is transcribing exemplars one-to-one = banned, and
        // explains the +0.089 mirage. exp033 fixes it: leaveOneOut excludes any
        // exemplar whose input matches the eval task, so the 2 retrieved demos are
        // GENUINELY OTHER tasks (kitchen → apartment_move/declutter). This is the
        // first VALID test of "does RAG few-shot lift the adapter's coverage off 3?"
        // on the full-30 gate. Single greedy call, native format, no 2nd pass.
        "exp033": DiscoveryConfig(topology: .adapterRagFewShotLOO,
            selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-034: covering-set facility-location selection over INDIVIDUAL questions on
        // the CHAMPION adapter (v2a_e1, 0.409) — the literal Lever D, genuinely untried.
        // exp031 ran best-of-N on the adapter but selected whole SETS verbatim, so it
        // could only return a set the adapter had already drawn intact; if the missing
        // critical unknown appeared in NO single draw, selection couldn't recover it.
        // Lever D as the rules specify it is different: over-generate a POOL of ~28
        // individual questions (greedy champion + 3 low-temp draws), embed (NLEmbedding),
        // dedup near-dupes (token Jaccard ≥0.6, champion-first wins), then GREEDILY pick 7
        // maximising a submodular facility-location / max-sum-dispersion objective
        // (relevance + λ·min-distance-to-chosen, − filler/compound). This MIXES questions
        // across draws, so a decision-critical unknown that surfaced in only ONE low-temp
        // draw — and is embedding-DISTANT from the modal cluster — gets PROMOTED into the
        // final 7, even when no single draw covered everything. Pure selection, VERBATIM
        // phrasing (no regeneration → champion atomicity/naturalness preserved, the defect
        // that sank exp028/029/030). Distinct from exp010 (stock-3B, MERGE-by-frequency →
        // surfaced filler). Title/summary from the greedy champion draft. selectTemp/greedy
        // govern the floor draft; sampleTemps are the diversity draws.
        "exp034": DiscoveryConfig(topology: .adapterCoverageFacilitySelect,
            selectTemp: 0, selectSampling: .greedy, sampleTemps: [0.4, 0.6, 0.8],
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-035: decomposed BINARY redundancy verification (lever F) + verbatim
        // cross-adapter transplant. The champion's #1 concrete, code-aggregatable loss
        // is REDUNDANCY — its own judge notes flag 2-3 wasted/overlapping slots in ~half
        // the held-out losses (gp cov2 Q1/Q3/Q6/Q7; household_budget Q2/Q3/Q4; find_therapist
        // Q1≈Q2≈Q7; dinner date+time; learn_guitar Q4≈Q6). The two prior dedup attempts lost
        // because their ruler was too coarse: embeddings (exp031, 0.398) and token-Jaccard
        // (exp034, 0.234) both miss paraphrases sharing few literal tokens. Lever F (the only
        // untried verification form): a small model can't score a set holistically but CAN do
        // trivial local binary checks. So detect ONE redundant slot via per-pair binary yes/no
        // "same information?" adapter checks (the redundancy signal embeddings can't give),
        // then replace ONLY that wasted slot VERBATIM with the first donor question from the
        // complementary coverage-forced adapter (v2b_e2) that the binary check confirms is
        // NOVEL vs the kept 6. No from-scratch regeneration (the defect that dup-out/degraded
        // exp009/exp028); both kept + transplant come from a fine-tuned adapter so phrasing
        // discipline holds. Champion-verbatim FLOOR: no redundant pair or no novel donor →
        // unchanged champion (0.409). Base adapter (judge + base draft) = v2a_e1 champion.
        "exp035": DiscoveryConfig(topology: .adapterBinaryDedupTransplant,
            selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-036: dual-adapter coverage merge (champion-priority dedup-and-fill). exp035's
        // single-slot binary-check swap failed because (a) the adapter's binary "same info?"
        // check returned FALSE on truly-redundant pairs and (b) only ONE slot moved. This
        // makes detection DETERMINISTIC + COMBINED (content-word Jaccard OR embedding cosine —
        // either signal firing flags a dup, higher recall than exp031's embedding-only 0.398
        // or exp034's Jaccard-only 0.234) and fills MULTIPLE freed slots VERBATIM from the
        // complementary coverage-forced donor v2b_e2 (4 wins vs champion's 2; trained to span
        // one question per distinct axis). Champion-priority, verbatim, deterministic; floor =
        // champion 0.409 unchanged when no slot is redundant. Base adapter = v2a_e1 champion.
        "exp036": DiscoveryConfig(topology: .adapterDualCoverageMerge,
            selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-037: least-redundant best-of-N over the CHAMPION adapter, scored by BINARY
        // redundancy, returned VERBATIM. The champion (0.409) loses ~half its cases to
        // internal REDUNDANCY crowding out the missing unknown; every EDIT of the draft
        // regressed (exp028 0.398, exp035 0.400, exp036 0.328) by degrading champion
        // phrasing, while whole-set selection held the floor. exp031 (embedding dispersion,
        // 0.398) and exp034 (Jaccard dispersion, 0.234) selected whole sets but with rulers
        // that MISS low-overlap paraphrase dups; exp035 showed the per-pair BINARY "same
        // information?" adapter check catches exactly those, but spent it on a phrasing-
        // degrading single-slot transplant. Here that binary signal is used at the SET
        // level: draw greedy floor + 2 low-temp champion sets, count each set's binary-
        // redundant pairs, return the WHOLE least-redundant set verbatim (tie-break: lower
        // embedding dispersion, then draw order → greedy floor wins exact ties → never
        // below 0.409 by construction). No donor, no regeneration. Base = v2a_e1 champion.
        "exp037": DiscoveryConfig(topology: .adapterLeastRedundantBestOfN,
            selectTemp: 0, selectSampling: .greedy, sampleTemps: [0.5, 0.7],
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-038: answer-simulation VALUE best-of-N on the champion adapter (Lever E).
        // The four research-backed levers the rules flag: C (solution-space EIG, exp030),
        // D (covering-set, exp031/034), F (decomposed binary verification, exp035/037) all
        // tried — E (the answer-simulation verifier, Zhang ICLR'25) is the ONLY one NEVER
        // attempted. Every prior best-of-N SELECTOR scored sets on the REDUNDANCY axis —
        // embedding dispersion (exp031, 0.398), Jaccard dispersion (exp034, 0.234), binary
        // same-info count (exp037, 0.388) — minimising internal overlap. But the champion's
        // dominant judge-flagged loss is NOT only redundancy: it wastes slots on LOW-VALUE /
        // PREMATURE / ALREADY-GIVEN questions that are perfectly DISTINCT yet don't change the
        // plan (salary for interview prep & resume, "new or used?" for a USED car, origin/
        // destination cities for an across-the-city move, "current level of clutter", expected
        // annual return rate, insurance/ID before a GP booking). A redundancy ruler is BLIND
        // to these. Lever E scores the COVERAGE/VALUE axis directly: a question is decision-
        // critical iff two plausible but DIVERGENT simulated answers would yield a materially
        // different plan; low-value questions' answers leave the plan unchanged. Score each
        // WHOLE candidate set (greedy floor + 2 low-temp draws) by # value-passing questions,
        // return the highest-value set VERBATIM. Greedy is the FLOOR (idx 0, wins ties) →
        // 0.409 protected by construction; verbatim → no phrasing degradation (the defect that
        // sank exp028/029/030). selectTemp/greedy govern the floor draft; sampleTemps the draws.
        "exp038": DiscoveryConfig(topology: .adapterAnswerSimValueBestOfN,
            selectTemp: 0, selectSampling: .greedy, sampleTemps: [0.5, 0.7],
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-039: diverse-adapter ENSEMBLE with pairwise relative SET selection (mixture-of-
        // experts + LLM-as-judge tournament). Every best-of-N so far selected over the
        // CHAMPION's OWN draws (exp031/034/037/038, all ≤ 0.409) — but the coverage wall is
        // that the champion rarely GENERATES the missing unknown in any of its own draws, so
        // selecting among them can't recover it. exp036 surfaced the one unused real signal:
        // the coverage-FORCED v2b siblings WIN MORE held-out cases (4 vs 2) — a DIFFERENT
        // training run generates the unknown the champion misses on some tasks — but exp036's
        // dedup-MERGE mangled phrasing (0.328). Here candidates are whole GREEDY sets from 4
        // diverse fine-tuned adapters (disciplined, not temperature noise) and selection is
        // RELATIVE PAIRWISE judgment on the strong champion adapter (exp012's tournament was on
        // the weak stock 3B over same-distribution draws). Winners returned VERBATIM (no merge/
        // edit); champion seeded as incumbent + wins ties → 0.409 floor protected unless a
        // sibling is robustly judged better in both orderings. Base/judge = v2a_e1 champion.
        "exp039": DiscoveryConfig(topology: .adapterEnsembleTournament,
            selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-040: RAG few-shot ON THE CHAMPION adapter from the FULL 619-pair CORPUS bank
        // (not the tiny 12-case GoldExemplars exp032/033 used). exp032 proved the champion
        // USES in-context axis demos brilliantly (0.498) but was a LEAK (all 12 GoldExemplars
        // inputs == eval gold). exp033's honest fix (leave-one-out over the SAME 12-case bank)
        // left only generic, off-domain demos that DISTRACTED the adapter (0.372). The corpus
        // is ~50× larger, so the 2 semantic-nearest demos are genuinely CLOSE task TYPES that
        // model the right decision-critical axes — the honest analogue of the 0.498 leak.
        // Near-dup ceiling (Jaccard ≥ 0.5 dropped) + exact-match LOO guard against leaking a
        // near-identical gold set. Single greedy call, native format, no 2nd pass (champion
        // phrasing preserved); adapter generates FRESH questions (gold-leak ban respected).
        "exp040": DiscoveryConfig(topology: .adapterCorpusRagFewShot,
            selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-041: deterministic phrasing-repair + clean-draft best-of-N on the CHAMPION
        // adapter. Distinct from every prior best-of-N (exp031 embedding-dispersion 0.398,
        // exp034 Jaccard 0.234, exp037 binary-redundancy 0.388, exp038 answer-sim-value 0.383,
        // exp039 pairwise tournament 0.380) in its SELECTION SIGNAL: those all ranked sets on
        // coverage/redundancy via rulers proven too coarse (embeddings, Jaccard, adapter
        // binary/value). This ranks on the ONE thing code measures at ~100% precision — the
        // phrasing/atomicity defects the Sonnet judge explicitly flags: compound " and "
        // (dad_gift "age and birthday", retirement "age and expected retirement age") and
        // generic filler. It ALSO applies a zero-risk pronoun-normalization (third-person
        // "the user/the user's" → "you/your") to EVERY candidate, fixing the running_comeback
        // naturalness flaw (whole set in "the user", naturalness 2) without touching content.
        // Greedy champion = floor (idx 0, wins ALL ties) → cases with no code-defect return the
        // champion EXACTLY (no-op pronoun-fix) so 0.409 is protected; a low-temp draw only
        // displaces it with STRICTLY FEWER code-certain defects. Verbatim, no regeneration.
        "exp041": DiscoveryConfig(topology: .adapterCleanDraftBestOfN,
            selectTemp: 0, selectSampling: .greedy, sampleTemps: [0.3, 0.45, 0.6],
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-042: deterministic, FLOOR-PROTECTED repair of the GREEDY champion. exp041
        // showed the zero-risk pronoun-fix + compound DETECTION are reliable, but it buried
        // them in a best-of-N SELECTION (low-temp draws → pick fewest defects) that displaced
        // good greedy drafts (0.377 < 0.409) — exactly how every best-of-N regressed. The
        // selection was the regressor, not the deterministic fix. This strips the selection:
        // ONE greedy champion draft (identical to adapter_v2a_e1) + ONLY two content-preserving
        // transforms — (a) third→second person (fixes running_comeback naturalness 2), and
        // (b) NEW high-precision compound DE-SPLITTING that truncates "X and <second-ask>?" to
        // its primary atom (exp041 only penalized compounds; never repaired them), restoring
        // atomicity on dad_birthday_gift / retirement_savings. No sampling, no 2nd FM pass, no
        // selection → every defect-free case returns the champion EXACTLY (0.409 is the literal
        // floor); only person/compound cases change, each strictly toward judge-rewarded shape.
        "exp042": DiscoveryConfig(topology: .adapterDeterministicRepair,
            selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-043: MMR-DIVERSE corpus RAG few-shot on the champion adapter. exp040 (0.405,
        // a TIE with the 0.409 champion) appended the 2 SEMANTIC-NEAREST corpus demos — but
        // the two nearest neighbours are near-paraphrases of EACH OTHER (same task TYPE), so
        // the adapter only ever sees ONE cluster of decision-critical axes, and the wall is
        // COVERAGE (the single missing axis). This swaps top-2-nearest for Maximal Marginal
        // Relevance (Carbonell & Goldstein 1998): pick k=3 demos that are each relevant to
        // the task BUT mutually diverse, so the demonstrations span a BROADER union of
        // decision-critical axes for the adapter to model. Same near-dup ceiling (Jaccard
        // ≥0.5 dropped) + exact-match LOO guard; single greedy call, native format, no 2nd
        // pass (champion phrasing preserved); adapter generates FRESH questions (leak ban OK).
        "exp043": DiscoveryConfig(topology: .adapterMMRRagFewShot,
            selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),

        // EXP-044: redundancy-gated, corpus-grounded coverage-gap REFILL on the champion
        // adapter (v2a_e1, 0.409). Synthesis of the two strongest signals in the log: the
        // lever-F binary same-info check is the only reliable redundancy detector (exp037),
        // and an EXTERNAL corpus coverage prior is the only signal that ever matched the
        // champion (exp040, 0.405) since the adapter cannot self-name its missing unknown
        // (exp028/029/030 failed). Greedy champion draft = floor; find ONE binary-redundant
        // slot; if none → champion verbatim (0.409 protected on most cases). Else free that
        // wasted slot and do ONE champion call generating a FRESH question conditioned on the
        // 6 kept questions AND on the nearest-corpus axes the draft MISSES (uncovered by
        // embedding cosine), with strict novelty + anti-leak (Jaccard-vs-corpus) guards that
        // fall back to the floor. Converts a confirmed wasted slot into a coverage slot
        // without ever touching a good slot; deterministic. Distinct from exp035 (donor
        // adapter, no coverage grounding) and exp009 (stock 3B, embedding gap, no redundancy
        // gating). All greedy.
        "exp044": DiscoveryConfig(topology: .adapterRedundancyGapFill,
            selectTemp: 0, selectSampling: .greedy,
            adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v2a_e1.fmadapter"),
    ]

    public static func named(_ name: String) -> DiscoveryConfig? { registry[name] }
}
