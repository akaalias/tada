import Foundation
import Contract

/// How the candidate's task set compares head-to-head with the gold (Sonnet) set.
/// Diagnostic only — the headline score is the deterministic set-match F1.
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

/// 1-5 rubric scores on the dimensions that separate a good task extraction from
/// a bad one. Diagnostic signal for the scientist — NOT the headline number.
public struct Rubric: Codable, Sendable, Equatable {
    public var faithfulness: Int   // every task traces to the input; nothing invented
    public var atomicity: Int      // each task is ONE action, no "and"/"or"
    public var actionability: Int  // real to-dos, not vague musings or feelings
    public var coverage: Int       // the set captures every distinct intention
    public var nonRedundancy: Int  // no two tasks are the same intention

    public var mean: Double {
        Double(faithfulness + atomicity + actionability + coverage + nonRedundancy) / 5.0
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
    /// Judge a candidate task set against the gold task set for the same input.
    func judge(input: String, gold: RambleResult, candidate: RambleResult) async throws -> JudgeVerdict
}

/// Offline stub for wiring/dry-runs without the Anthropic key. Deterministic,
/// not meaningful — only used to prove the pipeline runs end to end.
public struct StubJudge: Judge {
    public init() {}
    public func judge(input: String, gold: RambleResult, candidate: RambleResult) async throws -> JudgeVerdict {
        JudgeVerdict(
            pairwise: .tie,
            rubric: Rubric(faithfulness: 3, atomicity: 3, actionability: 3, coverage: 3, nonRedundancy: 3),
            notes: "stub judge — no real evaluation"
        )
    }
}
