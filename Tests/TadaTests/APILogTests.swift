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
