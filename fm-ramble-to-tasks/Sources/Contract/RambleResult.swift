import Foundation

/// The ramble-split output contract: the distinct, actionable tasks extracted
/// from a free-form user input. Empty when the input contains no actionable task.
/// Mirrors the app's `split_into_tasks` Sonnet output. This is part of the spec —
/// the candidate must produce exactly this shape regardless of how it gets there.
public struct RambleResult: Codable, Equatable, Sendable {
    /// Each distinct, actionable task as a short one-liner, in the user's own
    /// terms (0..N; an empty list is valid and correct for non-actionable input).
    public var tasks: [String]

    public init(tasks: [String]) {
        self.tasks = tasks
    }
}
