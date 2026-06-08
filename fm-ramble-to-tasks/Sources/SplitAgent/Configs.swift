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
        // exp004: extractAudit GATED to multi-task contexts. Same recovery audit as
        // exp003, but it only fires when the base extraction found >=2 tasks. exp003's
        // only regressions were two SINGLE-task cases where the audit re-added a
        // paraphrase dup; gating to base.count>=2 keeps the multi-task recall wins
        // (interleaved_deck, multi_errands -> 1.0) without that single-task cost.
        "exp004": SplitConfig(topology: .extractAuditGated, sampling: .greedy),
        // exp005: extractAuditGated, but the gated audit ENUMERATES every action in
        // the input (soft/hedged ones included) before diffing against the committed
        // list. exp004's only residual was long_monday (0.909): a softly-hedged task
        // buried among digressions that both base AND single-read audit dropped. The
        // forced enumerate-then-diff sweep aims to surface it without precision cost.
        "exp005": SplitConfig(topology: .extractAuditSweep, sampling: .greedy),
        // exp006: OVER-GENERATE -> FILTER. exp004's only residual (long_monday) is a
        // hedged task buried mid-ramble that the precise base drops and even exp005's
        // audit sweep missed (grabbing the wrong "someday" garage). Per the exp005
        // log, the fix must be EARLIER: call 1 over-lists exhaustively (grabbing the
        // insurance call AND the someday-garage and split-dups), then call 2 filters
        // to only genuinely-committed candidates and merges duplicates — separating
        // the kept softly-hedged action from the dropped explicit deferral.
        "exp006": SplitConfig(topology: .overGenerateFilter, sampling: .greedy),
    ]

    public static func named(_ name: String) -> SplitConfig? { registry[name] }
}
