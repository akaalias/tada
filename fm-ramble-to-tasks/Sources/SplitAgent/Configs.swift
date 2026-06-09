import Foundation

/// The program registry — the mutable lever space the autoresearch loop edits.
/// One named entry = one program (a SplitConfig). Fresh start: only `baseline`
/// (stock single-shot, greedy). The loop adds prog001, prog002, … as it runs.
public enum Configs {
    public static let registry: [String: SplitConfig] = [
        "baseline": SplitConfig(topology: .singleShot, sampling: .greedy),
        // prog001: from baseline, add a reasoning-first zero-task GATE. The model
        // must first name non-actionable material (venting / musing / vague wishes /
        // retractions) and set hasActionableTasks; toContract() forces an empty list
        // when false. Greedy. Directly attacks the documented #1 failure mode
        // (inventing tasks on non-actionable input) without changing decoding.
        "prog001": SplitConfig(topology: .singleShotReasoned, sampling: .greedy),
        // prog002: build on the elite (prog001 = singleShotReasoned, precision 0.926 /
        // zero-task 100%) + fold in the confirmed gap (PHRASING loses pairwise even at
        // F1=1: dedup_call/dedup_email scored goldBetter on terse all-lowercase fragments
        // that dropped detail like "this weekend"). Adds a DECOUPLED, F1-safe verbatim
        // restyle finisher over prog001's exact task set: 1:1 index map + token-subset
        // anti-hallucination guard + SHOUTING down-case + proper-noun recasing + the
        // completeness-push restyle prompt. Set membership is identical to prog001 by
        // construction, so F1 cannot regress — only the phrasing rubric / pairwise can move.
        "prog002": SplitConfig(topology: .singleShotReasonedRestyle, sampling: .greedy),
    ]

    public static func named(_ name: String) -> SplitConfig? { registry[name] }
}
