import Foundation
import Testing
@testable import Tada

// MARK: - API Key Validation Tests

/// Verifies that test keys are rejected by hasValidAPIKey.
@MainActor
@Test func test_api_key_is_rejected() async throws {
    APIKeyManager.deleteAPIKey()

    // Set a test key (the one that was accidentally used)
    try! APIKeyManager.setAPIKey("sk-ant-test-integration-key")

    // Test keys should NOT be considered valid
    #expect(APIKeyManager.hasValidAPIKey == false)

    // Clean up
    APIKeyManager.deleteAPIKey()
}

/// Verifies that a real-looking Anthropic key is accepted.
@MainActor
@Test func valid_api_key_is_accepted() async throws {
    APIKeyManager.deleteAPIKey()

    // Simulate a real Anthropic key (sk-ant- + 40+ chars, total >= 50)
    let realKey = "sk-ant-abcdefghijklmnopqrstuvwxyz1234567890ABCDEFGH"
    try! APIKeyManager.setAPIKey(realKey)

    #expect(APIKeyManager.hasValidAPIKey == true)

    // Clean up
    APIKeyManager.deleteAPIKey()
}

/// Verifies that a key that's too short is rejected.
@MainActor
@Test func api_key_too_short_is_rejected() async throws {
    APIKeyManager.deleteAPIKey()

    // Real prefix but too short
    try! APIKeyManager.setAPIKey("sk-ant-short")

    #expect(APIKeyManager.hasValidAPIKey == false)

    // Clean up
    APIKeyManager.deleteAPIKey()
}

/// Verifies that no key means hasValidAPIKey is false.
@MainActor
@Test func no_api_key_means_invalid() async throws {
    APIKeyManager.deleteAPIKey()

    #expect(APIKeyManager.hasValidAPIKey == false)
}
