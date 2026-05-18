import Foundation

/// Formats a single `ResponseValue` into its display string representation.
/// When `abbreviatedDate` is true, dates render as an abbreviated date with no time component.
func formatResponseValue(_ value: ResponseValue, abbreviatedDate: Bool = false) -> String {
    switch value {
    case .string(let s): return s
    case .number(let n): return String(n)
    case .boolean(let b): return b ? "Yes" : "No"
    case .stringArray(let arr): return arr.joined(separator: ", ")
    case .date(let d): return abbreviatedDate ? d.formatted(date: .abbreviated, time: .omitted) : d.formatted()
    }
}

/// Formats all values from an `ActionResponse` into a semicolon-separated string.
func formatResponseValues(_ response: ActionResponse) -> String {
    guard !response.values.isEmpty else { return "(no response)" }
    return response.values.map { _, value in formatResponseValue(value) }.joined(separator: "; ")
}

/// Converts an `ActionResponse` into a `[String: String]` dictionary.
func actionResponseToDict(_ response: ActionResponse) -> [String: String] {
    var dict: [String: String] = [:]
    for (key, value) in response.values {
        dict[key] = formatResponseValue(value, abbreviatedDate: true)
    }
    return dict
}
