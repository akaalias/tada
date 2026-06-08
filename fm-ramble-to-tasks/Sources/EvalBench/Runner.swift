import Foundation
import Contract

/// An agent is anything that turns a user input into a RambleResult (0..N tasks).
public typealias RambleAgentFn = @Sendable (String) async throws -> RambleResult

/// Runs an agent over all gold cases, applies the spec gate, scores the
/// deterministic set match against gold, and (when there is content to compare)
/// asks the judge for the diagnostic rubric. This is the ruler — keep it stable.
public struct Runner {
    let judge: Judge
    public init(judge: Judge) { self.judge = judge }

    public func run(_ agent: RambleAgentFn, over cases: [GoldCase], log: ((String) -> Void)? = nil) async -> Metric {
        var scores: [CaseScore] = []
        for c in cases {
            log?("• \(c.id): \"\(c.input)\"")
            do {
                let candidate = try await agent(c.input)
                let spec = SpecGate.check(candidate)
                if !spec.passed {
                    log?("    spec FAIL: \(spec.violations.joined(separator: "; "))")
                    scores.append(CaseScore(id: c.id, input: c.input, spec: spec, match: nil, verdict: nil, candidate: candidate, error: nil))
                    continue
                }
                let match = TaskSetMatcher.match(pred: candidate.tasks, gold: c.gold.tasks)
                // Judge only when there is content on both sides to compare — the
                // rubric is meaningless for an (correctly or incorrectly) empty set.
                var verdict: JudgeVerdict? = nil
                if !candidate.tasks.isEmpty && !c.gold.tasks.isEmpty {
                    verdict = try? await judge.judge(input: c.input, gold: c.gold, candidate: candidate)
                }
                log?("    F1 \(String(format: "%.2f", match.quality))  (p \(String(format: "%.2f", match.precision)) / r \(String(format: "%.2f", match.recall)))")
                scores.append(CaseScore(id: c.id, input: c.input, spec: spec, match: match, verdict: verdict, candidate: candidate, error: nil))
            } catch {
                // Distinguish an FM content-moderation refusal (no output, not a quality
                // failure) from any other generation error, so the metric can exclude it.
                let desc = "\(error)"
                let moderated = desc.range(of: "guardrail|safety|moderat|unsafe|sensitive|content polic", options: [.regularExpression, .caseInsensitive]) != nil
                let label = moderated ? "FM content moderation (refused)" : "generation error"
                log?("    \(moderated ? "REFUSED (moderation)" : "ERROR"): \(error)")
                scores.append(CaseScore(id: c.id, input: c.input, spec: SpecResult(passed: false, violations: [label]), match: nil, verdict: nil, candidate: nil, error: label))
            }
        }
        return Metric(scores: scores)
    }
}
