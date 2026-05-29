import Foundation
import Contract

/// Result of evaluating the agent on a single gold case.
public struct CaseScore: Sendable, Codable {
    public let id: String
    public let input: String
    public let spec: SpecResult
    public let verdict: JudgeVerdict?   // nil if spec gate failed (not judged)
    public let candidate: DiscoveryResult?
    public let error: String?

    /// 0-1 quality: 0 if spec fails or generation errored, else
    /// 0.5*rubricNormalized + 0.5*pairwise.
    public var quality: Double {
        guard error == nil, spec.passed, let v = verdict else { return 0 }
        return 0.5 * v.rubric.normalized + 0.5 * v.pairwise.score
    }
}

/// Aggregate metric over all cases. The headline is `quality`.
public struct Metric: Sendable {
    public let scores: [CaseScore]

    public var count: Int { scores.count }
    public var quality: Double { mean(scores.map(\.quality)) }
    public var specPassRate: Double { mean(scores.map { $0.spec.passed ? 1.0 : 0.0 }) }
    public var errorRate: Double { mean(scores.map { $0.error == nil ? 0.0 : 1.0 }) }

    public var wins: Int { judged.filter { $0.pairwise == .fmBetter }.count }
    public var ties: Int { judged.filter { $0.pairwise == .tie }.count }
    public var losses: Int { judged.filter { $0.pairwise == .goldBetter }.count }

    public var rubricMeans: Rubric {
        let r = judged.map(\.rubric)
        guard !r.isEmpty else { return Rubric(atomicity: 0, specificity: 0, coverage: 0, naturalness: 0, nonRedundancy: 0) }
        func avg(_ kp: (Rubric) -> Int) -> Int { Int((r.map { Double(kp($0)) }.reduce(0, +) / Double(r.count)).rounded()) }
        return Rubric(
            atomicity: avg(\.atomicity), specificity: avg(\.specificity),
            coverage: avg(\.coverage), naturalness: avg(\.naturalness),
            nonRedundancy: avg(\.nonRedundancy)
        )
    }

    private var judged: [JudgeVerdict] { scores.compactMap(\.verdict) }
    private func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }

    public var summary: String {
        let rm = rubricMeans
        return """
        ── metric ──────────────────────────────────────────
        cases:        \(count)
        QUALITY:      \(String(format: "%.3f", quality))   (headline; 0-1)
        spec pass:    \(String(format: "%.0f%%", specPassRate * 100))
        errors:       \(String(format: "%.0f%%", errorRate * 100))
        vs gold:      \(wins) win / \(ties) tie / \(losses) loss
        rubric means: atomicity \(rm.atomicity)  specificity \(rm.specificity)  coverage \(rm.coverage)  naturalness \(rm.naturalness)  nonRedundancy \(rm.nonRedundancy)
        ─────────────────────────────────────────────────────
        """
    }
}
