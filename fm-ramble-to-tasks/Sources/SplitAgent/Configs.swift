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
        // prog003: build on the elite (prog002 = reasoned extract + F1-safe restyle
        // finisher) + fold in its named residual: the restyle UNDER-FIRES on completeness,
        // timidly echoing the terse base instead of re-attaching input-present detail
        // ("about the kitchen sink", "with the post office", "before Tuesday") — the
        // dominant pairwise loss (13 goldBetter, phrasing 2-3 even at F1=1). Same topology
        // and guards as prog002, but the restyle call is now EVIDENCE-FIRST: it must QUOTE
        // each task's dropped detail (subject/recipient/deadline/location) verbatim from the
        // input BEFORE rewriting, so it actually hunts for and re-attaches the detail. The
        // 1:1 + token-subset guard is unchanged -> set membership identical to prog002,
        // F1 cannot regress; only phrasing/pairwise can move. Greedy.
        "prog003": SplitConfig(topology: .singleShotReasonedRestyleGrounded, sampling: .greedy),
    ]

    public static func named(_ name: String) -> SplitConfig? { registry[name] }
}
