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
                // The judge does the semantic (paraphrase-aware) matching AND the rubric
                // in one call. Empty-on-either-side cases are scored deterministically
                // (zero-task binary) with no judge call.
                var verdict: JudgeVerdict? = nil
                let match: SetMatch
                if c.gold.tasks.isEmpty || candidate.tasks.isEmpty {
                    match = TaskSetMatcher.fromMatched(0, predCount: candidate.tasks.count, goldCount: c.gold.tasks.count)
                } else if let v = try? await judge.judge(input: c.input, gold: c.gold, candidate: candidate) {
                    verdict = v
                    match = TaskSetMatcher.fromMatched(v.matched, predCount: candidate.tasks.count, goldCount: c.gold.tasks.count)
                } else {
                    match = TaskSetMatcher.match(pred: candidate.tasks, gold: c.gold.tasks)
                }
                log?("    F1 \(String(format: "%.2f", match.fitness))  (p \(String(format: "%.2f", match.precision)) / r \(String(format: "%.2f", match.recall)))")
                scores.append(CaseScore(id: c.id, input: c.input, spec: spec, match: match, verdict: verdict, candidate: candidate, error: nil))
            } catch {
                // Distinguish an FM content-moderation refusal (no output, not a fitness
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
