import Foundation

/// User-friendly error display abstraction.
enum AppError {
    /// Returns a user-facing message for AI service errors.
    static func userMessage(from error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case 429: return "Too many requests. Please wait a moment and try again."
        case 500...599: return "AI service is temporarily unavailable. Please try again later."
        default: break
        }

        let localized = error.localizedDescription
        if localized.contains("Invalid API key") {
            return "Please check your API key in Settings."
        }
        if localized.contains("connection") || localized.contains("network") {
            return "Unable to reach the AI service. Check your internet connection."
        }
        let sentences = localized.split(separator: ".")
        if let first = sentences.first {
            return String(first).trimmingCharacters(in: .whitespacesAndNewlines) + "."
        }
        return localized
    }
}
