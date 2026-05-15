import Foundation

/// One recorded HTTP request/response pair to the Claude API.
struct APILogEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let method: String
    let url: String
    let requestHeaders: [String: String]
    let requestBody: String?

    var statusCode: Int?
    var responseHeaders: [String: String]?
    var responseBody: String?
    var errorMessage: String?
    var durationMS: Int?

    /// True once a response or failure has been recorded.
    var isComplete: Bool { statusCode != nil || errorMessage != nil }

    /// True only for a completed request with a 2xx status code.
    var isSuccess: Bool {
        guard let statusCode else { return false }
        return (200..<300).contains(statusCode)
    }
}

/// In-memory log of Claude API traffic, surfaced in the Console view.
/// Holds the most recent `maxEntries` requests, newest first.
@Observable
@MainActor
final class APILog {
    static let shared = APILog()

    static let maxEntries = 100
    static let redactedValue = "••••••••"
    private static let sensitiveHeaders = ["x-api-key", "authorization"]

    private(set) var entries: [APILogEntry] = []

    init() {}

    /// Records an outgoing request and returns its id for later completion.
    @discardableResult
    func logRequest(_ request: URLRequest) -> UUID {
        let id = UUID()
        let entry = APILogEntry(
            id: id,
            timestamp: Date(),
            method: request.httpMethod ?? "GET",
            url: request.url?.absoluteString ?? "",
            requestHeaders: Self.redact(request.allHTTPHeaderFields ?? [:]),
            requestBody: request.httpBody.map { Self.prettyJSON($0) ?? Self.utf8($0) }
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        return id
    }

    /// Completes an entry with a received response.
    func logResponse(id: UUID, statusCode: Int, headers: [String: String] = [:], body: Data, durationMS: Int) {
        update(id) {
            $0.statusCode = statusCode
            $0.responseHeaders = Self.redact(headers)
            $0.responseBody = Self.prettyJSON(body) ?? Self.utf8(body)
            $0.durationMS = durationMS
        }
    }

    /// Completes an entry with a transport/decoding failure.
    func logFailure(id: UUID, error: String, durationMS: Int) {
        update(id) {
            $0.errorMessage = error
            $0.durationMS = durationMS
        }
    }

    func clear() {
        entries.removeAll()
    }

    private func update(_ id: UUID, _ mutate: (inout APILogEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        mutate(&entries[index])
    }

    // MARK: - Helpers

    /// Masks secret-bearing headers (api key, authorization) regardless of casing.
    private static func redact(_ headers: [String: String]) -> [String: String] {
        var result = headers
        for key in headers.keys where sensitiveHeaders.contains(key.lowercased()) {
            result[key] = redactedValue
        }
        return result
    }

    /// Pretty-prints JSON data, or returns nil if the data is not valid JSON.
    nonisolated static func prettyJSON(_ data: Data) -> String? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              )
        else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    private static func utf8(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? "<\(data.count) bytes of non-text data>"
    }
}
