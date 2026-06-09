import Foundation

/// The experiment registry — the mutable lever space the autoresearch loop edits.
/// One named entry = one experiment (a SplitConfig). Fresh start: only `baseline`
/// (stock single-shot, greedy). The loop adds exp001, exp002, … as it runs.
public enum Configs {
    public static let registry: [String: SplitConfig] = [
        "baseline": SplitConfig(topology: .singleShot, sampling: .greedy),
        // exp001: baseline single-shot + a reasoning/gate field. Before listing tasks,
        // the model writes a one-line analysis naming non-actionable material
        // (venting / musing / vague wishes / retractions) and sets hasActionableTasks;
        // the gate deterministically forces an EMPTY list when nothing is actionable.
        // Directly attacks the documented #1 failure mode (ZERO-TASK invention). Greedy.
        "exp001": SplitConfig(topology: .singleShotReasoned, sampling: .greedy),
    ]

    public static func named(_ name: String) -> SplitConfig? { registry[name] }
}
