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
    ]

    public static func named(_ name: String) -> DiscoveryConfig? { registry[name] }
}
