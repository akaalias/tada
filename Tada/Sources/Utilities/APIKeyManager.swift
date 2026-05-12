import Foundation

extension Notification.Name {
    static let apiKeyChanged = Notification.Name("apiKeyChanged")
}

enum APIKeyManager {
    private static let key = "claude-api-key"
    private static var storage: UserDefaults = .standard

    /// Swap in an isolated UserDefaults for testing so tests never touch the user's real key.
    static func _setTestingStorage(_ defaults: UserDefaults) {
        storage = defaults
    }

    static func getAPIKey() -> String? {
        storage.string(forKey: key)
    }

    static func setAPIKey(_ apiKey: String) throws {
        storage.set(apiKey, forKey: key)
        NotificationCenter.default.post(name: .apiKeyChanged, object: nil)
    }

    static func deleteAPIKey() {
        storage.removeObject(forKey: key)
        NotificationCenter.default.post(name: .apiKeyChanged, object: nil)
    }

    static var hasValidAPIKey: Bool {
        guard let key = getAPIKey() else { return false }
        // Reject obviously fake / test keys
        if key.hasPrefix("sk-ant-test") { return false }
        // Real Anthropic keys are at least 50 chars and start with sk-ant-
        return key.hasPrefix("sk-ant-") && key.count >= 50
    }

    static var hasAPIKey: Bool {
        getAPIKey() != nil
    }
}
