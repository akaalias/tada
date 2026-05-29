import Foundation

public struct AnthropicError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

/// Minimal Anthropic Messages client used ONLY at dev time (gold generation +
/// judging). Forces tool_use for guaranteed structured JSON, mirroring the
/// app's ClaudeAPIClient. Reads the key from ANTHROPIC_API_KEY.
public struct AnthropicClient: Sendable {
    let apiKey: String
    let model: String

    public init(model: String = "claude-sonnet-4-6") throws {
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty else {
            throw AnthropicError(message: "ANTHROPIC_API_KEY not set in environment")
        }
        self.apiKey = key
        self.model = model
    }

    /// Force the model to call `tool` and return its `input` object as JSON Data.
    public func toolCall(system: String, user: String, tool: [String: Any], maxTokens: Int = 2048) async throws -> Data {
        guard let toolName = tool["name"] as? String else {
            throw AnthropicError(message: "tool schema missing name")
        }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": toolName],
            "messages": [["role": "user", "content": user]],
        ]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AnthropicError(message: "no HTTP response") }
        guard http.statusCode == 200 else {
            throw AnthropicError(message: "HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else {
            throw AnthropicError(message: "unexpected response shape")
        }
        for block in content where block["type"] as? String == "tool_use" {
            if let input = block["input"] {
                return try JSONSerialization.data(withJSONObject: input)
            }
        }
        throw AnthropicError(message: "no tool_use block in response")
    }
}
