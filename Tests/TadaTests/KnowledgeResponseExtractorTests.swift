import Foundation
import Testing

@testable import Tada

// MARK: - KnowledgeResponseExtractor Tests

@Test func responseString_no_action_response_data() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    subTask.actionResponseData = nil

    #expect(KnowledgeResponseExtractor.responseString(for: subTask) == "(no response recorded)")
}

@Test func responseString_empty_action_response() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    let response = ActionResponse()

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.responseString(for: subTask) == "(no response recorded)")
}

@Test func responseString_string_value() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["answer"] = .string("Yes, it is.")

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.responseString(for: subTask) == "Yes, it is.")
}

@Test func responseString_multiple_values_joined() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["name"] = .string("Alice")
    response["age"] = .number(30)

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    let result = KnowledgeResponseExtractor.responseString(for: subTask)
    #expect(result.contains("Alice"))
    #expect(result.contains("30"))
}

@Test func responseString_boolean_values() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["active"] = .boolean(true)

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.responseString(for: subTask) == "Yes")
}

@Test func responseString_string_array_joined() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["tags"] = .stringArray(["swift", "testing"])

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.responseString(for: subTask) == "swift, testing")
}

@Test func responseString_empty_string_ignored() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["empty"] = .string("")
    response["filled"] = .string("value")

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    let result = KnowledgeResponseExtractor.responseString(for: subTask)
    #expect(result == "value")
}

@Test func responseString_drawing_replaced_with_placeholder() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["sketch"] = .string("data:image/png;base64,abc123")

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.responseString(for: subTask) == "(drawing)")
}

@Test func responseString_number_formatted() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["price"] = .number(19.99)

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    let result = KnowledgeResponseExtractor.responseString(for: subTask)
    #expect(result == "19.99")
}

@Test func responseString_date_formatted() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    formatter.locale = Locale(identifier: "en_US")

    let date = Date(timeIntervalSince1970: 1700000000)
    response["date"] = .date(date)

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    let result = KnowledgeResponseExtractor.responseString(for: subTask)
    // Just verify it's a non-empty string (actual format depends on locale)
    #expect(!result.isEmpty)
    #expect(result != "(no response recorded)")
}

@Test func extractPNG_no_drawing_data() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["text"] = .string("hello")

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.extractPNG(from: subTask) == nil)
}

@Test func extractPNG_no_action_response_data() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    subTask.actionResponseData = nil

    #expect(KnowledgeResponseExtractor.extractPNG(from: subTask) == nil)
}

@Test func extractPNG_valid_png_data() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)

    // Create minimal PNG data
    let pngData = Data(base64Encoded: "iVBORw0KGgo=") ?? Data()
    let base64 = pngData.base64EncodedString()

    var response = ActionResponse()
    response["sketch"] = .string("data:image/png;base64,\(base64)")

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    let extracted = KnowledgeResponseExtractor.extractPNG(from: subTask)
    #expect(extracted != nil)
    #expect(extracted == pngData)
}

@Test func extractPNG_invalid_base64_returns_nil() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)

    var response = ActionResponse()
    response["sketch"] = .string("data:image/png;base64,invalid!!!")

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.extractPNG(from: subTask) == nil)
}

@Test func extractTableMarkdown_no_table_data() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["text"] = .string("hello")

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.extractTableMarkdown(from: subTask) == nil)
}

@Test func extractTableMarkdown_valid_table() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)

    let tableData = [
        "columns": [["id": "item", "label": "Item", "type": "text"]],
        "rows": [["item": "Widget"], ["item": "Gadget"]]
    ] as [String: Any]

    let json = try! JSONSerialization.data(withJSONObject: tableData)
    let jsonString = "__tada_table__\(String(data: json, encoding: .utf8)!)"

    var response = ActionResponse()
    response["table"] = .string(jsonString)

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    let markdown = KnowledgeResponseExtractor.extractTableMarkdown(from: subTask)
    #expect(markdown != nil)
    #expect(markdown?.contains("| Item |") == true)
    #expect(markdown?.contains("| Widget |") == true)
}

@Test func extractTableMarkdown_empty_rows() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)

    let tableData = [
        "columns": [["id": "item", "label": "Item"]],
        "rows": [] as [[String: String]]
    ] as [String: Any]

    let json = try! JSONSerialization.data(withJSONObject: tableData)
    let jsonString = "__tada_table__\(String(data: json, encoding: .utf8)!)"

    var response = ActionResponse()
    response["table"] = .string(jsonString)

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    let markdown = KnowledgeResponseExtractor.extractTableMarkdown(from: subTask)
    #expect(markdown != nil)
}

@Test func extractTableMarkdown_with_currency_total() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)

    let tableData = [
        "columns": [["id": "price", "label": "Price", "type": "currency"]],
        "rows": [["price": "10"], ["price": "20"]],
        "total": 30,
        "hasCurrency": true
    ] as [String: Any]

    let json = try! JSONSerialization.data(withJSONObject: tableData)
    let jsonString = "__tada_table__\(String(data: json, encoding: .utf8)!)"

    var response = ActionResponse()
    response["table"] = .string(jsonString)

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    let markdown = KnowledgeResponseExtractor.extractTableMarkdown(from: subTask)
    #expect(markdown?.contains("_Total: €30_") == true)
}

@Test func extractTableMarkdown_no_total_when_zero() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)

    let tableData = [
        "columns": [["id": "price", "label": "Price", "type": "currency"]],
        "rows": [["price": "10"]],
        "total": 0,
        "hasCurrency": true
    ] as [String: Any]

    let json = try! JSONSerialization.data(withJSONObject: tableData)
    let jsonString = "__tada_table__\(String(data: json, encoding: .utf8)!)"

    var response = ActionResponse()
    response["table"] = .string(jsonString)

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    let markdown = KnowledgeResponseExtractor.extractTableMarkdown(from: subTask)
    #expect(markdown?.contains("_Total:") == false)
}
