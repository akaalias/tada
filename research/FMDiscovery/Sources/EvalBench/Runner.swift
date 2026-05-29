import Foundation
import Contract

/// An agent is anything that turns a user input into a DiscoveryResult.
public typealias DiscoveryAgentFn = @Sendable (String) async throws -> DiscoveryResult

/// Runs an agent over all gold cases, applies the spec gate, judges the
/// survivors against gold, and aggregates the metric. This is the ruler — keep
/// it stable across experiments.
public struct Runner {
    let judge: Judge
    public init(judge: Judge) { self.judge = judge }

    public func run(_ agent: DiscoveryAgentFn, over cases: [GoldCase], log: ((String) -> Void)? = nil) async -> Metric {
        var scores: [CaseScore] = []
        for c in cases {
            log?("• \(c.id): \"\(c.input)\"")
            do {
                let candidate = try await agent(c.input)
                let spec = SpecGate.check(candidate)
                if !spec.passed {
                    log?("    spec FAIL: \(spec.violations.joined(separator: "; "))")
                    scores.append(CaseScore(id: c.id, input: c.input, spec: spec, verdict: nil, candidate: candidate, error: nil))
                    continue
                }
                let verdict = try await judge.judge(input: c.input, gold: c.gold, candidate: candidate)
                log?("    \(verdict.pairwise.rawValue)  rubric \(String(format: "%.1f", verdict.rubric.mean))")
                scores.append(CaseScore(id: c.id, input: c.input, spec: spec, verdict: verdict, candidate: candidate, error: nil))
            } catch {
                // Distinguish an FM content-moderation refusal (no output, not a quality
                // failure) from any other generation error, so the metric/UI can exclude it.
                let desc = "\(error)"
                let moderated = desc.range(of: "guardrail|safety|moderat|unsafe|sensitive|content polic", options: [.regularExpression, .caseInsensitive]) != nil
                let label = moderated ? "FM content moderation (refused)" : "generation error"
                log?("    \(moderated ? "REFUSED (moderation)" : "ERROR"): \(error)")
                scores.append(CaseScore(id: c.id, input: c.input, spec: SpecResult(passed: false, violations: [label]), verdict: nil, candidate: nil, error: label))
            }
        }
        return Metric(scores: scores)
    }
}
