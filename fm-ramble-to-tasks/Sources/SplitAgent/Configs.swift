import Foundation

/// The program registry — the mutable lever space the autoresearch loop edits.
/// One named entry = one program (a SplitConfig). Fresh start: only `baseline`
/// (stock single-shot, greedy). The loop adds prog001, prog002, … as it runs.
public enum Configs {
    public static let registry: [String: SplitConfig] = [
        "baseline": SplitConfig(topology: .singleShot, sampling: .greedy),
    ]

    public static func named(_ name: String) -> SplitConfig? { registry[name] }
}
