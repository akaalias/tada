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
    ]

    public static func named(_ name: String) -> DiscoveryConfig? { registry[name] }
}
