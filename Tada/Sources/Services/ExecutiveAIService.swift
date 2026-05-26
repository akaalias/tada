import Foundation

/// Formatting helpers shared by the on-device executive service
/// (`FoundationModelsExecutiveService`).
enum ExecutiveAIService {
    /// Renders prior sub-task answers as prompt text. Drawing/brainstorm answers
    /// contribute only their text description; the `data:image` guard drops any
    /// legacy data-URL string that might slip through.
    static func formatPreviousResponses(_ responses: [[String: String]]) -> String {
        responses.map { dict in
            dict
                .filter { !$0.value.hasPrefix("data:image") }
                .map { "- \($0.key): \($0.value)" }
                .joined(separator: "\n")
        }.joined(separator: "\n")
    }
}
