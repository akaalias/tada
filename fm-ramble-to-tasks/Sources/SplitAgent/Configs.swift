import Foundation

/// The experiment registry — the mutable lever space the autoresearch loop edits.
/// One named entry = one experiment (a SplitConfig). Fresh start: only `baseline`
/// (stock single-shot, greedy). The loop adds exp001, exp002, … as it runs.
public enum Configs {
    public static let registry: [String: SplitConfig] = [
        "baseline": SplitConfig(topology: .singleShot, sampling: .greedy),
    ]

    public static func named(_ name: String) -> SplitConfig? { registry[name] }
}
