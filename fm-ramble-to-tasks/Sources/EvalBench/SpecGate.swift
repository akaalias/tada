import Foundation
import Contract

/// Deterministic, objective technical-spec checks. NOT quality — quality is the
/// metric's job. The gate only enforces the hard contract the app depends on.
/// A failed gate forces the case's quality score to 0. An EMPTY task list is
/// valid (the correct answer for non-actionable input).
public struct SpecResult: Sendable, Equatable, Codable {
    public let passed: Bool
    public let violations: [String]
}

public enum SpecGate {
    /// Sanity cap — a single input should never yield this many distinct tasks.
    public static let maxTasks = 12

    public static func check(_ r: RambleResult) -> SpecResult {
        var v: [String] = []

        if r.tasks.count > maxTasks {
            v.append("task count is \(r.tasks.count), exceeds cap \(maxTasks)")
        }
        for (i, t) in r.tasks.enumerated() {
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                v.append("task \(i + 1) is empty")
            }
            if containsEmoji(t) {
                v.append("task \(i + 1) contains an emoji")
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
