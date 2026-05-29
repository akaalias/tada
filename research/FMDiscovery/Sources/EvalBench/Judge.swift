import Foundation
import Contract

/// How the agent's output compares head-to-head with the gold (Sonnet) output.
public enum Pairwise: String, Codable, Sendable {
    case goldBetter
    case tie
    case fmBetter

    var score: Double {
        switch self {
        case .goldBetter: return 0.0
        case .tie: return 0.5
        case .fmBetter: return 1.0
        }
    }
}

/// 1-5 rubric scores on the dimensions that separated Sonnet from the local
/// model in prior attempts.
public struct Rubric: Codable, Sendable, Equatable {
    public var atomicity: Int      // one ask per question, no "and"/"or"
    public var specificity: Int    // concrete to THIS task, not generic
    public var coverage: Int       // the 7 cover the important unknowns
    public var naturalness: Int    // phrasing reads like a thoughtful coach
    public var nonRedundancy: Int  // questions don't overlap

    public var mean: Double {
        Double(atomicity + specificity + coverage + naturalness + nonRedundancy) / 5.0
    }
    /// 0-1 normalisation of a 1-5 mean.
    public var normalized: Double { (mean - 1.0) / 4.0 }
}

public struct JudgeVerdict: Codable, Sendable {
    public var pairwise: Pairwise
    public var rubric: Rubric
    public var notes: String

    public init(pairwise: Pairwise, rubric: Rubric, notes: String) {
        self.pairwise = pairwise
        self.rubric = rubric
        self.notes = notes
    }
}

public protocol Judge: Sendable {
    /// Judge an agent output against the gold output for the same input.
    func judge(input: String, gold: DiscoveryResult, candidate: DiscoveryResult) async throws -> JudgeVerdict
}

/// Offline stub for wiring/dry-runs without the Anthropic key. Deterministic,
/// not meaningful — only used to prove the pipeline runs end to end.
public struct StubJudge: Judge {
    public init() {}
    public func judge(input: String, gold: DiscoveryResult, candidate: DiscoveryResult) async throws -> JudgeVerdict {
        JudgeVerdict(
            pairwise: .tie,
            rubric: Rubric(atomicity: 3, specificity: 3, coverage: 3, naturalness: 3, nonRedundancy: 3),
            notes: "stub judge — no real evaluation"
        )
    }
}
