import Foundation
import Contract

/// Result of evaluating the agent on a single gold case.
public struct CaseScore: Sendable, Codable {
    public let id: String
    public let input: String
    public let spec: SpecResult
    public let match: SetMatch?         // nil if spec gate failed / generation errored
    public let verdict: JudgeVerdict?   // diagnostic rubric (nil when not judged)
    public let candidate: RambleResult?
    public let error: String?

    /// 0-1 quality: 0 if spec fails or generation errored, else the set-match quality.
    public var quality: Double {
        guard error == nil, spec.passed, let m = match else { return 0 }
        return m.quality
    }
}

/// Aggregate metric over all cases. The headline is `quality` (mean set-match F1,
/// with zero-task cases scored binary).
public struct Metric: Sendable {
    public let scores: [CaseScore]

    public var count: Int { scores.count }
    // Quality is averaged ONLY over cases that produced output. An FM content-moderation
    // refusal / generation error yields nothing, so it is excluded here (not a quality-0)
    // and surfaced separately as `refused` — a product signal, not a quality signal.
    public var quality: Double { mean(scores.filter { $0.error == nil }.map(\.quality)) }
    public var refused: Int { scores.filter { $0.error != nil }.count }
    public var answered: Int { scores.filter { $0.error == nil }.count }
    public var specPassRate: Double {
        let a = scores.filter { $0.error == nil }
        return a.isEmpty ? 0 : mean(a.map { $0.spec.passed ? 1.0 : 0.0 })
    }

    public var precision: Double { mean(matches.map(\.precision)) }
    public var recall: Double { mean(matches.map(\.recall)) }
    public var f1: Double { mean(matches.map(\.f1)) }
    public var zeroTaskAccuracy: Double {
        let z = matches.filter { $0.goldEmpty }
        return z.isEmpty ? 1 : mean(z.map { $0.zeroTaskCorrect ? 1.0 : 0.0 })
    }

    public var wins: Int { judged.filter { $0.pairwise == .fmBetter }.count }
    public var ties: Int { judged.filter { $0.pairwise == .tie }.count }
    public var losses: Int { judged.filter { $0.pairwise == .goldBetter }.count }

    public var rubricMeans: Rubric {
        let r = judged.map(\.rubric)
        guard !r.isEmpty else { return Rubric(faithfulness: 0, atomicity: 0, actionability: 0, coverage: 0, nonRedundancy: 0) }
        func avg(_ kp: (Rubric) -> Int) -> Int { Int((r.map { Double(kp($0)) }.reduce(0, +) / Double(r.count)).rounded()) }
        return Rubric(
            faithfulness: avg(\.faithfulness), atomicity: avg(\.atomicity),
            actionability: avg(\.actionability), coverage: avg(\.coverage),
            nonRedundancy: avg(\.nonRedundancy)
        )
    }

    private var matches: [SetMatch] { scores.compactMap(\.match) }
    private var judged: [JudgeVerdict] { scores.compactMap(\.verdict) }
    private func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }

    public var summary: String {
        let rm = rubricMeans
        return """
        ── metric ──────────────────────────────────────────
        cases:        \(count)  (answered \(answered), refused \(refused))
        QUALITY (F1): \(String(format: "%.3f", quality))   (headline; 0-1, over answered cases)
        precision:    \(String(format: "%.3f", precision))   recall: \(String(format: "%.3f", recall))
        zero-task:    \(String(format: "%.0f%%", zeroTaskAccuracy * 100))   (correct empties)
        spec pass:    \(String(format: "%.0f%%", specPassRate * 100))   (of answered)
        refused:      \(refused)   (FM content moderation — excluded from quality)
        vs gold:      \(wins) win / \(ties) tie / \(losses) loss   (diagnostic)
        rubric means: faithfulness \(rm.faithfulness)  atomicity \(rm.atomicity)  actionability \(rm.actionability)  coverage \(rm.coverage)  nonRedundancy \(rm.nonRedundancy)
        ─────────────────────────────────────────────────────
        """
    }
}
