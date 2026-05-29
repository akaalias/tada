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
    ]

    public static func named(_ name: String) -> DiscoveryConfig? { registry[name] }
}
