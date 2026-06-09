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
        // prog004: combine the elite (prog002 = reasoned extract + F1-safe restyle) with what
        // the inspiration (prog003) learned. prog003's EVIDENCE-FIRST restyle lifted the target
        // phrasing gap (phrasing 3->4, pairwise 8T/13L -> 12T/10L) but its only failure was a
        // MULTI-task scramble: the bolder restyle collapsed distinct tasks into one compound
        // string and duplicated it across slots (multi_car/errands, interleaved_*), which the
        // token-subset guard can't catch (every word is still input-present), so F1 fell
        // 0.877->0.842. prog004 keeps prog003's grounded restyle EXACTLY and adds a per-slot
        // ALIGNMENT guard: each styled slot must stay anchored to its OWN base task (>= half its
        // content stems) and introduce no content stem unique to a DIFFERENT base task —
        // rejecting cross-slot merge/dup and falling back to that slot's base. Set membership
        // stays identical to the reasoned base by construction, so F1 is protected while
        // prog003's completeness/phrasing wins survive. Greedy.
        "prog004": SplitConfig(topology: .singleShotReasonedRestyleAligned, sampling: .greedy),
        // prog005: combine the elite (prog004 = reasoned extract + evidence-first restyle +
        // per-slot alignment guard) with what prog004's OWN log named as the next lever. Its two
        // residuals — recall losses (interleaved_party f1 0.50, long_monday missed the insurance
        // call, multi_errands missed the quarterly report, interleaved_report missed the figure
        // check) AND phrasing-completeness losses (the restyle echoes terse fragments on SHORT
        // tasks because the base handed it nothing fuller) — both trace to the TERSE,
        // under-extracting singleShotReasoned base. prog005 swaps that base for the COVERAGE base
        // (singleShotCoverage: same zero-task analysis gate, plus an EXHAUSTIVE candidate sweep
        // that lists every distinct intention including buried/interleaved ones, then merges
        // dups) and keeps prog004's aligned evidence-first restyle finisher EXACTLY. The fuller
        // base should lift recall directly and give the restyle richer material to style; the
        // 1:1 + token-subset + alignment guards still protect set membership/phrasing. Greedy.
        "prog005": SplitConfig(topology: .singleShotCoverageRestyleAligned, sampling: .greedy),
    ]

    public static func named(_ name: String) -> SplitConfig? { registry[name] }
}
