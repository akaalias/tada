import Foundation

/// The agentic role responsible for a Claude API request.
enum AIRole: String, Codable, Sendable, CaseIterable {
    case planner
    case executive
    case knowledge

    var displayName: String {
        switch self {
        case .planner: "Planning Agent"
        case .executive: "Executive Agent"
        case .knowledge: "Knowledge Base Agent"
        }
    }
}

/// The task-lifecycle phase a request serves. Drives the Console's colour
/// coding, matching the app's phase palette: discovery (orange), execution
/// (blue), knowledge work on completed tasks (emerald).
enum APIRequestPhase: String, Codable, Sendable {
    case discovery
    case execution
    case knowledge
}

/// One recorded HTTP request/response pair to the Claude API.
struct APILogEntry: Identifiable, Sendable, Codable {
    let id: UUID
    let timestamp: Date
    let method: String
    let url: String
    let requestHeaders: [String: String]
    let requestBody: String?
    /// Which AI agent issued the request, if known.
    let aiRole: AIRole?
    /// The task phase this request serves, if known.
    let phase: APIRequestPhase?

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

    /// A plain-language, phase-aware summary of what the request is for, derived
    /// from the tool it invokes. `nil` for plain (non-tool) messages.
    var requestSummary: String? {
        guard let requestBody,
              let data = requestBody.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tools = json["tools"] as? [[String: Any]],
              let toolName = tools.first?["name"] as? String
        else { return nil }

        switch toolName {
        case "generate_action_ui":        return "Generating an interactive step"
        case "create_task_plan":
            switch phase {
            case .discovery: return "Creating a task plan for discovery"
            case .execution: return "Creating a task plan for execution"
            default:         return "Creating a task plan"
            }
        case "revise_plan":               return "Revising the execution task plan"
        case "break_down_step":           return "Breaking a step into micro-steps"
        case "save_cross_links":          return "Finding links between notes"
        case "save_atomic_note":          return "Writing a knowledge note"
        case "extract_entities_and_link": return "Extracting entities and wikilinks"
        default:                          return nil
        }
    }
}

/// Log of Claude API traffic, surfaced in the Console view.
/// Holds the most recent `maxEntries` requests, newest first, and persists
/// them to disk so they survive relaunches and rebuilds.
@Observable
@MainActor
final class APILog {
    static let shared = APILog(fileURL: APILog.defaultFileURL)

    static let maxEntries = 100
    static let redactedValue = "••••••••"
    private static let sensitiveHeaders = ["x-api-key", "authorization"]

    private(set) var entries: [APILogEntry] = []

    /// File entries are persisted to. `nil` disables persistence (in-memory only).
    private let fileURL: URL?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        load()
    }

    /// `~/Library/Application Support/Tada/console/api-log.json`.
    static var defaultFileURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Tada/console", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("api-log.json")
    }

    /// Records an outgoing request and returns its id for later completion.
    @discardableResult
    func logRequest(_ request: URLRequest, role: AIRole? = nil, phase: APIRequestPhase? = nil) -> UUID {
        let id = UUID()
        let entry = APILogEntry(
            id: id,
            timestamp: Date(),
            method: request.httpMethod ?? "GET",
            url: request.url?.absoluteString ?? "",
            requestHeaders: Self.redact(request.allHTTPHeaderFields ?? [:]),
            requestBody: request.httpBody.map { Self.prettyJSON($0) ?? Self.utf8($0) },
            aiRole: role,
            phase: phase
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        persist()
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
        persist()
    }

    private func update(_ id: UUID, _ mutate: (inout APILogEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        mutate(&entries[index])
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([APILogEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func persist() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Helpers

    /// Masks secret-bearing headers (api key, authorization) regardless of casing.
    private static func redact(_ headers: [String: String]) -> [String: String] {
        var result = headers
        for key in headers.keys where sensitiveHeaders.contains(key.lowercased()) {
            result[key] = mask(headers[key] ?? "")
        }
        return result
    }

    /// Partially masks a secret: keeps the first 16 and last 8 characters
    /// visible so the key can be identified, hiding the middle. Values short
    /// enough that this would reveal most of the secret (≤24 chars) are fully
    /// redacted instead.
    static func mask(_ value: String) -> String {
        guard value.count > 24 else { return redactedValue }
        return "\(value.prefix(16))...\(value.suffix(8))"
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
