import Foundation
import Testing

@testable import Tada

// MARK: - APILog Tests

@MainActor
@Test func apiLog_logRequest_redacts_api_key() {
    let log = APILog()
    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
    request.httpMethod = "POST"
    request.setValue("sk-ant-secret-value", forHTTPHeaderField: "x-api-key")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    _ = log.logRequest(request)

    let entry = log.entries.first!
    #expect(entry.requestHeaders["x-api-key"] == APILog.redactedValue)
    #expect(entry.requestHeaders["x-api-key"] != "sk-ant-secret-value")
    #expect(entry.requestHeaders["Content-Type"] == "application/json")
}

@MainActor
@Test func apiLog_logRequest_partially_reveals_long_api_key() {
    let log = APILog()
    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
    request.httpMethod = "POST"
    let key = "sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-abcdEFGH"
    request.setValue(key, forHTTPHeaderField: "x-api-key")

    _ = log.logRequest(request)

    let masked = log.entries.first!.requestHeaders["x-api-key"]!
    #expect(masked == "sk-ant-api03-ABC...abcdEFGH")
    #expect(masked != key)
}

@MainActor
@Test func apiLog_mask_fully_redacts_short_secrets() {
    #expect(APILog.mask("sk-ant-secret-value") == APILog.redactedValue)
    #expect(APILog.mask("") == APILog.redactedValue)
}

@MainActor
@Test func apiLog_logRequest_captures_method_url_and_inserts_at_front() {
    let log = APILog()
    var first = URLRequest(url: URL(string: "https://example.com/one")!)
    first.httpMethod = "POST"
    var second = URLRequest(url: URL(string: "https://example.com/two")!)
    second.httpMethod = "POST"

    _ = log.logRequest(first)
    _ = log.logRequest(second)

    #expect(log.entries.count == 2)
    #expect(log.entries.first?.url == "https://example.com/two")
    #expect(log.entries.first?.method == "POST")
    #expect(log.entries.last?.url == "https://example.com/one")
}

@MainActor
@Test func apiLog_logResponse_updates_entry_and_marks_success() {
    let log = APILog()
    let request = URLRequest(url: URL(string: "https://example.com")!)
    let id = log.logRequest(request)

    let body = #"{"ok":true}"#.data(using: .utf8)!
    log.logResponse(id: id, statusCode: 200, body: body, durationMS: 123)

    let entry = log.entries.first!
    #expect(entry.statusCode == 200)
    #expect(entry.durationMS == 123)
    #expect(entry.isSuccess)
    #expect(entry.isComplete)
    #expect(entry.responseBody?.contains("\"ok\"") == true)
}

@MainActor
@Test func apiLog_logResponse_non_2xx_is_not_success() {
    let log = APILog()
    let id = log.logRequest(URLRequest(url: URL(string: "https://example.com")!))

    log.logResponse(id: id, statusCode: 400, body: Data(), durationMS: 10)

    #expect(log.entries.first?.isSuccess == false)
    #expect(log.entries.first?.isComplete == true)
}

@MainActor
@Test func apiLog_logFailure_records_error_message() {
    let log = APILog()
    let id = log.logRequest(URLRequest(url: URL(string: "https://example.com")!))

    log.logFailure(id: id, error: "The network connection was lost.", durationMS: 50)

    let entry = log.entries.first!
    #expect(entry.errorMessage == "The network connection was lost.")
    #expect(entry.isComplete)
    #expect(entry.isSuccess == false)
}

@MainActor
@Test func apiLog_caps_entries_at_max() {
    let log = APILog()
    for i in 0..<(APILog.maxEntries + 25) {
        _ = log.logRequest(URLRequest(url: URL(string: "https://example.com/\(i)")!))
    }
    #expect(log.entries.count == APILog.maxEntries)
}

@MainActor
@Test func apiLog_clear_removes_all_entries() {
    let log = APILog()
    _ = log.logRequest(URLRequest(url: URL(string: "https://example.com")!))
    log.clear()
    #expect(log.entries.isEmpty)
}

@Test func apiLog_prettyJSON_formats_compact_json() {
    let compact = #"{"b":2,"a":1}"#.data(using: .utf8)!
    let pretty = APILog.prettyJSON(compact)
    #expect(pretty?.contains("\n") == true)
    #expect(pretty?.contains("\"a\"") == true)
}

@Test func apiLog_prettyJSON_returns_nil_for_non_json() {
    #expect(APILog.prettyJSON("not json".data(using: .utf8)!) == nil)
}

// MARK: - Persistence

@MainActor
@Test func apiLog_persists_entries_across_instances() {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("apilog-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }

    let first = APILog(fileURL: file)
    let id = first.logRequest(URLRequest(url: URL(string: "https://example.com/x")!))
    first.logResponse(id: id, statusCode: 200, body: #"{"ok":true}"#.data(using: .utf8)!, durationMS: 7)

    let reloaded = APILog(fileURL: file)
    #expect(reloaded.entries.count == 1)
    #expect(reloaded.entries.first?.url == "https://example.com/x")
    #expect(reloaded.entries.first?.statusCode == 200)
    #expect(reloaded.entries.first?.responseBody?.contains("ok") == true)
}

@MainActor
@Test func apiLog_clear_is_persisted() {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("apilog-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }

    let log = APILog(fileURL: file)
    _ = log.logRequest(URLRequest(url: URL(string: "https://example.com")!))
    log.clear()

    #expect(APILog(fileURL: file).entries.isEmpty)
}

@MainActor
@Test func apiLog_without_file_url_does_not_persist() {
    let log = APILog()
    _ = log.logRequest(URLRequest(url: URL(string: "https://example.com")!))
    #expect(log.entries.count == 1)
}

// MARK: - AI Role

@MainActor
@Test func apiLog_logRequest_records_ai_role() {
    let log = APILog()
    _ = log.logRequest(URLRequest(url: URL(string: "https://example.com")!), role: .planner)
    #expect(log.entries.first?.aiRole == .planner)
}

@MainActor
@Test func apiLog_logRequest_role_defaults_to_nil() {
    let log = APILog()
    _ = log.logRequest(URLRequest(url: URL(string: "https://example.com")!))
    #expect(log.entries.first?.aiRole == nil)
}

@MainActor
@Test func apiLog_ai_role_survives_persistence() {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("apilog-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }

    let first = APILog(fileURL: file)
    _ = first.logRequest(URLRequest(url: URL(string: "https://example.com")!), role: .knowledge)

    #expect(APILog(fileURL: file).entries.first?.aiRole == .knowledge)
}

@Test func aiRole_displayNames_are_full_agent_names() {
    #expect(AIRole.planner.displayName == "Planning Agent")
    #expect(AIRole.executive.displayName == "Executive Agent")
    #expect(AIRole.knowledge.displayName == "Knowledge Base Agent")
}

// MARK: - Request Summary

@MainActor
@Test func apiLogEntry_requestSummary_describes_known_tool_requests() {
    let cases: [(tool: String, summary: String)] = [
        ("generate_action_ui", "Generating an interactive step"),
        ("create_task_plan", "Creating a task plan"),
        ("revise_plan", "Revising the execution task plan"),
        ("break_down_step", "Breaking a step into micro-steps"),
        ("save_cross_links", "Finding links between notes"),
        ("save_atomic_note", "Writing a knowledge note"),
        ("extract_entities_and_link", "Extracting entities and wikilinks"),
    ]
    for (tool, summary) in cases {
        let log = APILog()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["tools": [["name": tool]]])
        _ = log.logRequest(request)
        #expect(log.entries.first?.requestSummary == summary)
    }
}

@MainActor
@Test func apiLogEntry_requestSummary_qualifies_task_plan_by_phase() {
    func summary(forPhase phase: APIRequestPhase?) -> String? {
        let log = APILog()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["tools": [["name": "create_task_plan"]]])
        _ = log.logRequest(request, phase: phase)
        return log.entries.first?.requestSummary
    }
    #expect(summary(forPhase: .discovery) == "Creating a task plan for discovery")
    #expect(summary(forPhase: .execution) == "Creating a task plan for execution")
    #expect(summary(forPhase: nil) == "Creating a task plan")
}

@MainActor
@Test func apiLog_logRequest_records_and_persists_phase() {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("apilog-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }

    let log = APILog(fileURL: file)
    _ = log.logRequest(URLRequest(url: URL(string: "https://example.com")!), phase: .execution)
    #expect(log.entries.first?.phase == .execution)
    #expect(APILog(fileURL: file).entries.first?.phase == .execution)
}

@MainActor
@Test func apiLog_logRequest_phase_defaults_to_nil() {
    let log = APILog()
    _ = log.logRequest(URLRequest(url: URL(string: "https://example.com")!))
    #expect(log.entries.first?.phase == nil)
}

@MainActor
@Test func apiLogEntry_requestSummary_is_nil_for_plain_message() {
    let log = APILog()
    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
    request.httpMethod = "POST"
    request.httpBody = try! JSONSerialization.data(withJSONObject: ["messages": []])
    _ = log.logRequest(request)
    #expect(log.entries.first?.requestSummary == nil)
}
