import Foundation
import Testing

@testable import Tada

// MARK: - AppError Tests

@Test func userMessage_rate_limit_429() {
    let error = NSError(
        domain: "Tada",
        code: 429,
        userInfo: [NSLocalizedDescriptionKey: "Rate limited"]
    )

    #expect(AppError.userMessage(from: error) == "Too many requests. Please wait a moment and try again.")
}

@Test func userMessage_server_error_500() {
    let error = NSError(
        domain: "Tada",
        code: 500,
        userInfo: [NSLocalizedDescriptionKey: "Internal error"]
    )

    #expect(AppError.userMessage(from: error) == "AI service is temporarily unavailable. Please try again later.")
}

@Test func userMessage_server_error_503() {
    let error = NSError(
        domain: "Tada",
        code: 503,
        userInfo: [NSLocalizedDescriptionKey: "Service unavailable"]
    )

    #expect(AppError.userMessage(from: error) == "AI service is temporarily unavailable. Please try again later.")
}

@Test func userMessage_server_error_599() {
    let error = NSError(
        domain: "Tada",
        code: 599,
        userInfo: [NSLocalizedDescriptionKey: "Server error"]
    )

    #expect(AppError.userMessage(from: error) == "AI service is temporarily unavailable. Please try again later.")
}

@Test func userMessage_invalid_api_key() {
    let error = NSError(
        domain: "Tada",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Invalid API key provided"]
    )

    #expect(AppError.userMessage(from: error) == "Please check your API key in Settings.")
}

@Test func userMessage_connection_error() {
    let error = NSError(
        domain: "Tada",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "connection refused"]
    )

    #expect(AppError.userMessage(from: error) == "Unable to reach the AI service. Check your internet connection.")
}

@Test func userMessage_network_error() {
    let error = NSError(
        domain: "Tada",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "network timeout"]
    )

    #expect(AppError.userMessage(from: error) == "Unable to reach the AI service. Check your internet connection.")
}

@Test func userMessage_default_truncates_to_first_sentence() {
    let error = NSError(
        domain: "Tada",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Something went wrong. Please try again."]
    )

    #expect(AppError.userMessage(from: error) == "Something went wrong.")
}

@Test func userMessage_default_no_period() {
    let error = NSError(
        domain: "Tada",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "An error occurred"]
    )

    #expect(AppError.userMessage(from: error) == "An error occurred.")
}

@Test func userMessage_default_single_sentence() {
    let error = NSError(
        domain: "Tada",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to connect"]
    )

    #expect(AppError.userMessage(from: error) == "Failed to connect.")
}

@Test func userMessage_default_trimmed() {
    let error = NSError(
        domain: "Tada",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "  Error message  "]
    )

    #expect(AppError.userMessage(from: error) == "Error message.")
}

@Test func userMessage_non_server_error_uses_localized() {
    let error = NSError(
        domain: "Tada",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Custom error"]
    )

    #expect(AppError.userMessage(from: error) == "Custom error.")
}
