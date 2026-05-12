import Foundation
import Testing
@testable import Tada

// MARK: - API Key Banner Tests

/// Verifies that the app detects when no API key is configured.
@MainActor
@Test func api_key_banner_shows_when_no_api_key() async throws {
    APIKeyManager._setTestingStorage(testUserDefaults())
    // Ensure no API key is set
    APIKeyManager.deleteAPIKey()

    #expect(APIKeyManager.hasAPIKey == false)
    #expect(APIKeyManager.getAPIKey() == nil)

    // The banner should be visible when hasAPIKey is false.
    // This is verified by the ContentView wrapping its detail in an API key check.
}

/// Verifies that the app detects when an API key IS configured.
@MainActor
@Test func api_key_banner_hidden_when_api_key_exists() async throws {
    APIKeyManager._setTestingStorage(testUserDefaults())
    // Set a test API key
    try! APIKeyManager.setAPIKey(testAPIKey)

    #expect(APIKeyManager.hasAPIKey == true)
    #expect(APIKeyManager.getAPIKey() != nil)

    // The banner should NOT be visible when hasAPIKey is true.
}

/// Verifies that the API key persists across retrievals (so the banner doesn't flicker).
@MainActor
@Test func api_key_persists_across_retrievals_in_isolated_storage() async throws {
    APIKeyManager._setTestingStorage(testUserDefaults())
    APIKeyManager.deleteAPIKey()

    // Set a key
    try! APIKeyManager.setAPIKey("sk-ant-test-persistence-key")

    // Retrieve it multiple times
    let key1 = APIKeyManager.getAPIKey()
    let key2 = APIKeyManager.getAPIKey()
    let hasKey1 = APIKeyManager.hasAPIKey
    let hasKey2 = APIKeyManager.hasAPIKey

    #expect(key1 == "sk-ant-test-persistence-key")
    #expect(key2 == "sk-ant-test-persistence-key")
    #expect(hasKey1 == true)
    #expect(hasKey2 == true)

    // Clean up
    APIKeyManager.deleteAPIKey()
}

/// Verifies that deleting the key makes hasAPIKey return false.
@MainActor
@Test func api_key_deletion_makes_banner_visible() async throws {
    APIKeyManager._setTestingStorage(testUserDefaults())
    try! APIKeyManager.setAPIKey("sk-ant-test-delete-key")
    #expect(APIKeyManager.hasAPIKey == true)

    APIKeyManager.deleteAPIKey()
    #expect(APIKeyManager.hasAPIKey == false)
}
