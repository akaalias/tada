import Testing
import Contract
@testable import EvalBench

private func plan(_ n: Int, title: String = "Plan a Weekend Trip") -> DiscoveryResult {
    DiscoveryResult(
        taskTitle: title,
        taskDescription: "A short trip.",
        questions: (0..<n).map { DiscoveryQuestion(title: "Question \($0)?", description: "", requiresExternalAction: false) }
    )
}

@Test func passesWithExactlySevenCleanQuestions() {
    #expect(SpecGate.check(plan(7)).passed)
}

@Test func failsWithWrongQuestionCount() {
    #expect(!SpecGate.check(plan(5)).passed)
    #expect(!SpecGate.check(plan(8)).passed)
}

@Test func failsOnGenericTitle() {
    let r = SpecGate.check(plan(7, title: "Clarifying Questions"))
    #expect(!r.passed)
    #expect(r.violations.contains { $0.contains("generic label") })
}

@Test func failsOnEmptyTitle() {
    #expect(!SpecGate.check(plan(7, title: "   ")).passed)
}

@Test func failsOnEmojiInQuestion() {
    var r = plan(7)
    r.questions[2].title = "When do you want to leave? 🚀"
    #expect(!SpecGate.check(r).passed)
}

@Test func metricQualityIsZeroWhenSpecFails() {
    let score = CaseScore(
        id: "x", input: "i",
        spec: SpecResult(passed: false, violations: ["bad"]),
        verdict: JudgeVerdict(pairwise: .fmBetter, rubric: Rubric(atomicity: 5, specificity: 5, coverage: 5, naturalness: 5, nonRedundancy: 5), notes: ""),
        candidate: nil, error: nil
    )
    #expect(score.quality == 0)
}

@Test func metricQualityCombinesRubricAndPairwise() {
    // tie (0.5) + rubric all-3 (normalized 0.5) → 0.5*0.5 + 0.5*0.5 = 0.5
    let score = CaseScore(
        id: "x", input: "i",
        spec: SpecResult(passed: true, violations: []),
        verdict: JudgeVerdict(pairwise: .tie, rubric: Rubric(atomicity: 3, specificity: 3, coverage: 3, naturalness: 3, nonRedundancy: 3), notes: ""),
        candidate: nil, error: nil
    )
    #expect(abs(score.quality - 0.5) < 1e-9)
}
