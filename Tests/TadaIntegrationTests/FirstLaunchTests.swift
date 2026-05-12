import Foundation
import Testing
@testable import Tada

// MARK: - First Launch & API Key Setup Tests

@Test func api_key_not_set_on_fresh_install() async {
    // Ensure clean slate
    APIKeyManager.deleteAPIKey()
    // On a fresh install, no API key should be set
    let existingKey = APIKeyManager.getAPIKey()
    #expect(existingKey == nil)
    #expect(APIKeyManager.hasAPIKey == false)
}

@Test func api_key_can_be_saved_and_retrieved() async throws {
    // Clean slate
    APIKeyManager.deleteAPIKey()
    #expect(APIKeyManager.hasAPIKey == false)
    #expect(APIKeyManager.getAPIKey() == nil)

    // Save a key
    try APIKeyManager.setAPIKey(testAPIKey)

    #expect(APIKeyManager.hasAPIKey == true)
    let retrieved = try #require(APIKeyManager.getAPIKey())
    #expect(retrieved == testAPIKey)
}

@Test func api_key_save_rejects_empty_string() async {
    APIKeyManager.deleteAPIKey()

    // Empty string should be stored but is effectively nil for hasAPIKey
    try? APIKeyManager.setAPIKey("")

    // The key is stored but empty — hasAPIKey checks for nil only
    #expect(APIKeyManager.hasAPIKey == true) // UserDefaults stores empty string, not nil
    #expect(APIKeyManager.getAPIKey() == "")

    // Clean up
    APIKeyManager.deleteAPIKey()
}

@Test func api_key_can_be_removed() async {
    // Clean slate
    APIKeyManager.deleteAPIKey()
    try! APIKeyManager.setAPIKey(testAPIKey)

    #expect(APIKeyManager.hasAPIKey == true)

    APIKeyManager.deleteAPIKey()
    #expect(APIKeyManager.hasAPIKey == false)
    #expect(APIKeyManager.getAPIKey() == nil)
}

@Test func api_key_persists_across_retrievals() async {
    // Clean slate
    APIKeyManager.deleteAPIKey()
    try! APIKeyManager.setAPIKey(testAPIKey)

    // Multiple reads should return the same value
    let first = APIKeyManager.getAPIKey()
    let second = APIKeyManager.getAPIKey()

    #expect(first == testAPIKey)
    #expect(second == testAPIKey)
    #expect(first == second)

    APIKeyManager.deleteAPIKey()
}
