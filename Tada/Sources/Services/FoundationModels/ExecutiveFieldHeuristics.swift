import Foundation

/// Field-type inference used ONLY when guided generation fails to produce any
/// decodable object (see `FoundationModelsExecutiveService.fallbackSchema`). This is
/// a last resort when the model returned nothing usable — it does NOT override a
/// successful response. The model's own field type is always authoritative.
enum ExecutiveFieldHeuristics {

    /// A deterministic field type inferred from the question title, for the fallback
    /// schema when generation fails entirely. Defaults to free text.
    static func fallbackType(title: String) -> ActionField.FieldType {
        let text = title.lowercased()
        if mentionsDate(text) { return .date }
        if mentionsMoney(text) { return .rangeSlider }
        return .textarea
    }

    private static func mentionsDate(_ text: String) -> Bool {
        let tokens = ["date", "deadline", "depart", "arriv", "check-in", "checkin",
                      "check-out", "checkout", "when", "what day", "which day"]
        return tokens.contains { text.contains($0) }
    }

    private static func mentionsMoney(_ text: String) -> Bool {
        let tokens = ["budget", "price", "cost", "how much", "spend"]
        return tokens.contains { text.contains($0) }
    }
}
