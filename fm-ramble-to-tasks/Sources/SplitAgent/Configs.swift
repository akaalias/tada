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
    ]

    public static func named(_ name: String) -> SplitConfig? { registry[name] }
}
