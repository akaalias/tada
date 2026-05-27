import Foundation
import Testing

@testable import Tada

// MARK: - APILog Tests
//
// The Console now logs on-device Foundation Models calls, not HTTP requests to
// Anthropic. An entry captures the agent role, the operation, the instructions +
// prompt sent to the model, and the rendered output (or the failure).

@MainActor
@Test func apiLog_begin_records_call_metadata_and_inserts_at_front() {
    let log = APILog()
    _ = log.begin(
        role: .planner,
        operation: "Discovery questions",
        instructions: "You are a task coach.",
        prompt: "Plan a trip",
        temperature: 0.6,
        outputType: "TaskPlan",
        phase: .discovery,
        taskTitle: "Plan a trip to Lisbon"
    )
    _ = log.begin(role: .executive, operation: "Action UI", instructions: "i", prompt: "p")

    #expect(log.entries.count == 2)
    let newest = log.entries.first!
    #expect(newest.role == .executive)
    #expect(newest.operation == "Action UI")
    let oldest = log.entries.last!
    #expect(oldest.role == .planner)
    #expect(oldest.instructions == "You are a task coach.")
    #expect(oldest.prompt == "Plan a trip")
    #expect(oldest.temperature == 0.6)
    #expect(oldest.outputType == "TaskPlan")
    #expect(oldest.phase == .discovery)
    #expect(oldest.taskTitle == "Plan a trip to Lisbon")
    #expect(oldest.isComplete == false)
}

@MainActor
@Test func apiLog_complete_records_output_and_marks_success() {
    let log = APILog()
    let id = log.begin(role: .planner, operation: "Discovery questions", instructions: "i", prompt: "p")

    log.complete(id: id, output: #"{"title":"Trip"}"#, durationMS: 1234)

    let entry = log.entries.first!
    #expect(entry.output == #"{"title":"Trip"}"#)
    #expect(entry.durationMS == 1234)
    #expect(entry.isSuccess)
    #expect(entry.isComplete)
    #expect(entry.errorMessage == nil)
}

@MainActor
@Test func apiLog_fail_records_error_and_is_not_success() {
    let log = APILog()
    let id = log.begin(role: .coach, operation: "Chat", instructions: "i", prompt: "p")

    log.fail(id: id, error: "Model unavailable", durationMS: 50)

    let entry = log.entries.first!
    #expect(entry.errorMessage == "Model unavailable")
    #expect(entry.isComplete)
    #expect(entry.isSuccess == false)
}

@MainActor
@Test func apiLog_caps_entries_at_max() {
    let log = APILog()
    for i in 0..<(APILog.maxEntries + 25) {
        _ = log.begin(role: .planner, operation: "op \(i)", instructions: "i", prompt: "p")
    }
    #expect(log.entries.count == APILog.maxEntries)
}

@MainActor
@Test func apiLog_clear_removes_all_entries() {
    let log = APILog()
    _ = log.begin(role: .planner, operation: "op", instructions: "i", prompt: "p")
    log.clear()
    #expect(log.entries.isEmpty)
}

// MARK: - record wrapper

@MainActor
@Test func apiLog_record_logs_success_with_rendered_output() async throws {
    let log = APILog()
    let result: Int = try await log.record(
        role: .planner,
        operation: "Discovery questions",
        instructions: "sys",
        prompt: "hi",
        temperature: 0.6,
        outputType: "TaskPlan",
        phase: .discovery,
        taskTitle: "Plan a trip"
    ) {
        (value: 42, output: "rendered output")
    }

    #expect(result == 42)
    let entry = log.entries.first!
    #expect(entry.role == .planner)
    #expect(entry.operation == "Discovery questions")
    #expect(entry.instructions == "sys")
    #expect(entry.prompt == "hi")
    #expect(entry.temperature == 0.6)
    #expect(entry.outputType == "TaskPlan")
    #expect(entry.phase == .discovery)
    #expect(entry.taskTitle == "Plan a trip")
    #expect(entry.output == "rendered output")
    #expect(entry.isSuccess)
    #expect(entry.durationMS != nil)
}

@MainActor
@Test func apiLog_record_logs_failure_and_rethrows() async {
    struct Boom: Error {}
    let log = APILog()

    await #expect(throws: Boom.self) {
        try await log.record(
            role: .coach,
            operation: "Chat",
            instructions: "i",
            prompt: "p",
            temperature: nil
        ) { () -> (value: Int, output: String) in
            throw Boom()
        }
    }

    let entry = log.entries.first!
    #expect(entry.errorMessage != nil)
    #expect(entry.isComplete)
    #expect(entry.isSuccess == false)
}

// MARK: - describe

@Test func apiLog_describe_renders_encodable_as_pretty_json() {
    struct Payload: Encodable { let a: Int; let b: String }
    let rendered = APILog.describe(Payload(a: 1, b: "x"))
    #expect(rendered.contains("\"a\""))
    #expect(rendered.contains("\"b\""))
    #expect(rendered.contains("\n"))
}

// MARK: - Persistence

@MainActor
@Test func apiLog_persists_entries_across_instances() {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("apilog-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }

    let first = APILog(fileURL: file)
    let id = first.begin(
        role: .knowledge,
        operation: "Knowledge note",
        instructions: "i",
        prompt: "p",
        temperature: 0.4,
        outputType: "GeneratedKnowledgeNote",
        phase: .knowledge,
        taskTitle: "Lisbon trip"
    )
    first.complete(id: id, output: #"{"title":"Note"}"#, durationMS: 7)

    let reloaded = APILog(fileURL: file)
    #expect(reloaded.entries.count == 1)
    let entry = reloaded.entries.first!
    #expect(entry.role == .knowledge)
    #expect(entry.operation == "Knowledge note")
    #expect(entry.phase == .knowledge)
    #expect(entry.taskTitle == "Lisbon trip")
    #expect(entry.output?.contains("Note") == true)
    #expect(entry.isSuccess)
}

@MainActor
@Test func apiLog_clear_is_persisted() {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("apilog-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }

    let log = APILog(fileURL: file)
    _ = log.begin(role: .planner, operation: "op", instructions: "i", prompt: "p")
    log.clear()

    #expect(APILog(fileURL: file).entries.isEmpty)
}

@MainActor
@Test func apiLog_without_file_url_does_not_persist() {
    let log = APILog()
    _ = log.begin(role: .planner, operation: "op", instructions: "i", prompt: "p")
    #expect(log.entries.count == 1)
}

// MARK: - Pending Requests

@MainActor
@Test func apiLog_hasPendingRequests_reflects_incomplete_entries() {
    let log = APILog()
    #expect(log.hasPendingRequests == false)

    let id = log.begin(role: .planner, operation: "op", instructions: "i", prompt: "p")
    #expect(log.hasPendingRequests == true)

    log.complete(id: id, output: "done", durationMS: 5)
    #expect(log.hasPendingRequests == false)
}

@MainActor
@Test func apiLog_marks_interrupted_call_as_cancelled_on_reload() {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("apilog-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }

    let first = APILog(fileURL: file)
    _ = first.begin(role: .planner, operation: "pending op", instructions: "i", prompt: "p")
    #expect(first.entries.first?.isComplete == false)

    // Reloading simulates a relaunch after the app was terminated mid-call.
    let reloaded = APILog(fileURL: file)
    #expect(reloaded.entries.first?.isComplete == true)
    #expect(reloaded.entries.first?.errorMessage != nil)
    #expect(reloaded.hasPendingRequests == false)

    // The cancellation is persisted, so a second relaunch stays clean.
    #expect(APILog(fileURL: file).hasPendingRequests == false)
}

@MainActor
@Test func apiLog_reload_leaves_completed_entries_untouched() {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("apilog-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }

    let first = APILog(fileURL: file)
    let id = first.begin(role: .planner, operation: "op", instructions: "i", prompt: "p")
    first.complete(id: id, output: "ok", durationMS: 9)

    let reloaded = APILog(fileURL: file)
    #expect(reloaded.entries.first?.output == "ok")
    #expect(reloaded.entries.first?.errorMessage == nil)
}

// MARK: - Enums

@Test func apiRequestPhase_maps_from_task_phase() {
    #expect(APIRequestPhase(TaskPhase.discovery) == .discovery)
    #expect(APIRequestPhase(TaskPhase.execution) == .execution)
}

@Test func aiRole_displayNames_are_full_agent_names() {
    #expect(AIRole.planner.displayName == "Planning Agent")
    #expect(AIRole.executive.displayName == "Executive Agent")
    #expect(AIRole.knowledge.displayName == "Knowledge Base Agent")
    #expect(AIRole.coach.displayName == "Productivity Coach")
}
