import Foundation
import Contract

/// Deterministic, objective technical-spec checks. NOT quality — quality is the
/// judge's job. The gate only enforces the hard contract the app depends on.
/// A failed gate forces the case's quality score to 0.
public struct SpecResult: Sendable, Equatable {
    public let passed: Bool
    public let violations: [String]
}

public enum SpecGate {
    public static let requiredQuestionCount = 7

    /// Generic labels the task title must never be (it must name the user's
    /// goal, not describe our output). Lowercased for comparison.
    static let genericTitleLabels: Set<String> = [
        "clarifying questions", "task discovery", "questions",
        "understanding your task", "discovery", "discovery questions"
    ]

    public static func check(_ r: DiscoveryResult) -> SpecResult {
        var v: [String] = []

        if r.questions.count != requiredQuestionCount {
            v.append("question count is \(r.questions.count), must be \(requiredQuestionCount)")
        }
        if r.taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            v.append("task title is empty")
        }
        if genericTitleLabels.contains(r.taskTitle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) {
            v.append("task title is a generic label: \"\(r.taskTitle)\"")
        }
        if containsEmoji(r.taskTitle) || containsEmoji(r.taskDescription) {
            v.append("task title/description contains an emoji")
        }
        for (i, q) in r.questions.enumerated() {
            let t = q.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty {
                v.append("question \(i + 1) title is empty")
            }
            if containsEmoji(q.title) || containsEmoji(q.description) {
                v.append("question \(i + 1) contains an emoji")
            }
        }

        return SpecResult(passed: v.isEmpty, violations: v)
    }

    static func containsEmoji(_ s: String) -> Bool {
        for scalar in s.unicodeScalars {
            if scalar.properties.isEmoji && (scalar.value > 0x238C || scalar.properties.isEmojiPresentation) {
                return true
            }
        }
        return false
    }
}
