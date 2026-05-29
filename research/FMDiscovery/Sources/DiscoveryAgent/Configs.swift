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
    ]

    public static func named(_ name: String) -> DiscoveryConfig? { registry[name] }
}
