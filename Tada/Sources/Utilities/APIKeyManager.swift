import Foundation

enum APIKeyManager {
    private static let key = "claude-api-key"

    static func getAPIKey() -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func setAPIKey(_ apiKey: String) throws {
        UserDefaults.standard.set(apiKey, forKey: key)
    }

    static func deleteAPIKey() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static var hasAPIKey: Bool {
        getAPIKey() != nil
    }
}
