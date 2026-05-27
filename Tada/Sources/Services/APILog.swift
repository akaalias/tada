import Foundation

/// The on-device agent responsible for a Foundation Models call.
enum AIRole: String, Codable, Sendable, CaseIterable {
    case planner
    case executive
    case knowledge
    case coach

    var displayName: String {
        switch self {
        case .planner: "Planning Agent"
        case .executive: "Executive Agent"
        case .knowledge: "Knowledge Base Agent"
        case .coach: "Productivity Coach"
        }
    }
}

/// The task-lifecycle phase a call serves. Drives the Console's colour coding,
/// matching the app's phase palette: discovery (orange), execution (blue),
/// knowledge work on completed tasks (emerald).
enum APIRequestPhase: String, Codable, Sendable {
    case discovery
    case execution
    case knowledge

    /// Maps a task-lifecycle phase to the call phase it corresponds to, so a
    /// call inherits the colour of the work item it serves.
    init(_ taskPhase: TaskPhase) {
        switch taskPhase {
        case .discovery: self = .discovery
        case .execution: self = .execution
        }
    }
}

/// One recorded on-device Foundation Models call: the instructions and prompt
/// we sent, and the rendered output (or failure) we got back. Replaces the old
/// HTTP request/response pair now that the app runs entirely on-device.
struct APILogEntry: Identifiable, Sendable, Codable {
    let id: UUID
    let timestamp: Date
    /// Which on-device agent issued the call.
    let role: AIRole
    /// Plain-language name of the operation, e.g. "Discovery questions".
    let operation: String
    /// The session instructions (system prompt) for this call.
    let instructions: String
    /// The user prompt sent to the model.
    let prompt: String
    /// Sampling temperature, if one was set.
    let temperature: Double?
    /// The `@Generable` output type the model was asked to produce; `nil` for
    /// free-form text responses.
    let outputType: String?
    /// The task phase this call serves, if known.
    let phase: APIRequestPhase?
    /// The task or sub-task title this call serves, if known. Shown as a badge
    /// in the Console so each call is traceable to its work item.
    let taskTitle: String?

    /// The model's rendered output: pretty JSON for guided generation, plain
    /// text otherwise. `nil` until the call completes.
    var output: String?
    var errorMessage: String?
    var durationMS: Int?

    /// True once an output or failure has been recorded.
    var isComplete: Bool { output != nil || errorMessage != nil }

    /// True for a completed call that produced output without error.
    var isSuccess: Bool { isComplete && errorMessage == nil }
}

/// Log of on-device Foundation Models traffic, surfaced in the Console view.
/// Holds the most recent `maxEntries` calls, newest first, and persists them to
/// disk so they survive relaunches and rebuilds.
@Observable
@MainActor
final class APILog {
    static let shared = APILog(fileURL: APILog.defaultFileURL)

    static let maxEntries = 100

    private(set) var entries: [APILogEntry] = []

    /// True while any logged call has not yet produced output or a failure.
    /// Drives the Console sidebar spinner.
    var hasPendingRequests: Bool {
        entries.contains { !$0.isComplete }
    }

    /// File entries are persisted to. `nil` disables persistence (in-memory only).
    private let fileURL: URL?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        load()
    }

    /// `~/Library/Application Support/Tada/console/model-calls.json`.
    static var defaultFileURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Tada/console", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("model-calls.json")
    }

    // MARK: - Logging

    /// Records an outgoing call and returns its id for later completion.
    @discardableResult
    func begin(
        role: AIRole,
        operation: String,
        instructions: String,
        prompt: String,
        temperature: Double? = nil,
        outputType: String? = nil,
        phase: APIRequestPhase? = nil,
        taskTitle: String? = nil
    ) -> UUID {
        let id = UUID()
        let entry = APILogEntry(
            id: id,
            timestamp: Date(),
            role: role,
            operation: operation,
            instructions: instructions,
            prompt: prompt,
            temperature: temperature,
            outputType: outputType,
            phase: phase,
            taskTitle: taskTitle
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        persist()
        return id
    }

    /// Completes an entry with the model's rendered output.
    func complete(id: UUID, output: String, durationMS: Int) {
        update(id) {
            $0.output = output
            $0.durationMS = durationMS
        }
    }

    /// Completes an entry with a failure.
    func fail(id: UUID, error: String, durationMS: Int) {
        update(id) {
            $0.errorMessage = error
            $0.durationMS = durationMS
        }
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    /// Times a single model call: logs the instructions + prompt, runs `perform`,
    /// then records its rendered output or the failure with elapsed time. Returns
    /// the call's value; rethrows any error after logging it.
    ///
    /// `perform` runs off the main actor (this method is `nonisolated`); only the
    /// log mutations hop to the main actor.
    nonisolated func record<Value>(
        role: AIRole,
        operation: String,
        instructions: String,
        prompt: String,
        temperature: Double?,
        outputType: String? = nil,
        phase: APIRequestPhase? = nil,
        taskTitle: String? = nil,
        perform: () async throws -> (value: Value, output: String)
    ) async throws -> Value {
        let id = await begin(
            role: role,
            operation: operation,
            instructions: instructions,
            prompt: prompt,
            temperature: temperature,
            outputType: outputType,
            phase: phase,
            taskTitle: taskTitle
        )
        let start = Date()
        do {
            let (value, output) = try await perform()
            await complete(id: id, output: output, durationMS: Self.elapsedMS(since: start))
            return value
        } catch {
            await fail(id: id, error: String(describing: error), durationMS: Self.elapsedMS(since: start))
            throw error
        }
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

        // A call still pending in a freshly loaded log was interrupted by app
        // termination — it cannot still be running. Mark it cancelled so its
        // spinner doesn't reappear on the next launch.
        let interrupted = entries.indices.filter { !entries[$0].isComplete }
        for index in interrupted {
            entries[index].errorMessage = "Call interrupted — app closed before it completed"
        }
        if !interrupted.isEmpty { persist() }
    }

    private func persist() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Helpers

    nonisolated private static func elapsedMS(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    /// Renders a generated DTO as pretty JSON for display, falling back to its
    /// reflective description if it isn't JSON-encodable.
    nonisolated static func describe<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }
}
