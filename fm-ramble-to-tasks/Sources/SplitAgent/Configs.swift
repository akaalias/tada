import Foundation

/// The experiment registry — the mutable lever space the autoresearch loop edits.
/// One named entry = one experiment (a SplitConfig).
public enum Configs {
    public static let registry: [String: SplitConfig] = [
        "baseline": SplitConfig(topology: .singleShot, sampling: .greedy),
        // exp001: reasoning-first gated schema (analysis + hasActionableTasks gate)
        // to suppress invented tasks on venting/musing and honor retractions.
        "exp001": SplitConfig(topology: .singleShotReasoned, sampling: .greedy),
        // exp002: coverage-first — same gate, plus an exhaustive candidateIntentions
        // sweep before the final list, to recover tasks missed on interleaved
        // many-task rambles (the residual recall/coverage gap in exp001).
        "exp002": SplitConfig(topology: .singleShotCoverage, sampling: .greedy),
        // exp003: extract->coverage-audit. exp001 reasoned extract (precision 1.0),
        // then a scoped second call that sees the committed list and adds ONLY
        // genuinely-missing stated tasks. Audit skipped on zero-task (protects the
        // solved gate). Targets exp001's pure recall gap without exp002's dedup leak.
        "exp003": SplitConfig(topology: .extractAudit, sampling: .greedy),
    ]

    public static func named(_ name: String) -> SplitConfig? { registry[name] }
}
