import Foundation

/// A Claude model available to the account, as returned by `GET /v1/models`.
struct ClaudeModel: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let displayName: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

/// Fetches the list of Claude models available for the configured API key.
enum ModelCatalog {
    private static let url = URL(string: "https://api.anthropic.com/v1/models?limit=1000")!

    private struct ModelsResponse: Decodable {
        let data: [ClaudeModel]
    }

    /// Calls the Anthropic models endpoint and returns the available models,
    /// newest first. Throws `ClaudeAPIError` on a non-200 response.
    static func fetchModels(apiKey: String) async throws -> [ClaudeModel] {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }
        guard http.statusCode == 200 else {
            if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = body["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw ClaudeAPIError.apiError(message)
            }
            throw ClaudeAPIError.httpError(http.statusCode)
        }
        return parseModels(from: data)
    }

    /// Parses a models-list response body. Returns an empty array if the data
    /// is not a valid models response.
    static func parseModels(from data: Data) -> [ClaudeModel] {
        guard let response = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            return []
        }
        return response.data.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
    }
}

/// The user's chosen Claude model, persisted in UserDefaults.
enum ModelPreference {
    static let defaultModel = "claude-sonnet-4-6"
    private static let key = "claude-model"
    private static var storage: UserDefaults = .standard

    /// Swap in an isolated UserDefaults for testing.
    static func _setTestingStorage(_ defaults: UserDefaults) {
        storage = defaults
    }

    static var selectedModel: String {
        get { storage.string(forKey: key) ?? defaultModel }
        set { storage.set(newValue, forKey: key) }
    }
}
