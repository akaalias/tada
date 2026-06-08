import Foundation

/// The input set the harness evaluates over. `kind` documents what the case
/// stresses; `heldOutReal` marks real dogfooded rambles (frozen test, gold
/// human-verified) vs. synthetic seeds. Gold itself is produced by GoldGenerator
/// (Sonnet) and frozen in `gold/`.
public struct RambleInput: Sendable {
    public let id: String
    public let kind: String        // zero | single | multi | interleaved | bait
    public let heldOutReal: Bool
    public let input: String
}

public enum RambleInputs {
    public static let all: [RambleInput] = [
        // Real held-out (dogfooded) — gold human-verified.
        RambleInput(id: "real_franziska", kind: "multi", heldOutReal: true,
            input: "Okay so yeah let me think. I want to review the 2024 tax document with Franziska. I got to talk to her about August. And I should probably bring out the trash."),

        // Synthetic seeds across the kinds.
        RambleInput(id: "zero_venting", kind: "zero", heldOutReal: false,
            input: "Ugh today just dragged on forever, the traffic this morning was insane and I'm completely wiped out. Anyway."),
        RambleInput(id: "bait_journal", kind: "bait", heldOutReal: false,
            input: "I've been thinking it would be nice to be the kind of person who journals more, you know, more reflective."),
        RambleInput(id: "single_paris", kind: "single", heldOutReal: false,
            input: "I really need to finally book the flights for the Paris trip sometime this week."),
        RambleInput(id: "multi_errands", kind: "multi", heldOutReal: false,
            input: "Let me think — I need to call the dentist to reschedule, we're out of coffee so grab some, and I should finally start the quarterly report."),
        RambleInput(id: "interleaved_deck", kind: "interleaved", heldOutReal: false,
            input: "I should email Sarah the deck... oh and I need to book the offsite venue... actually for that deck, make sure the Q3 numbers are in before it goes to Sarah."),
    ]

    /// Small fast subset for quick iteration.
    public static let devSubsetIDs: Set<String> = ["real_franziska", "zero_venting", "multi_errands"]

    public static func named(_ id: String) -> RambleInput? { all.first { $0.id == id } }
}
