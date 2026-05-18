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

@Test func responseString_image_uses_description() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["sketch"] = .image(png: Data([0x89, 0x50]), description: "Drawing with 2 lines")

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.responseString(for: subTask) == "Drawing with 2 lines")
}

@Test func responseString_image_without_description_uses_placeholder() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["sketch"] = .image(png: Data([0x89, 0x50]), description: "")

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.responseString(for: subTask) == "(drawing)")
}

@Test func responseString_range_formatted() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["budget"] = .range(lower: 25, upper: 75)

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.responseString(for: subTask) == "25 - 75")
}

@Test func responseString_tree_joins_labels() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["outline"] = .tree([
        TreeNode(label: "Parent", depth: 0),
        TreeNode(label: "Child", depth: 1)
    ])

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.responseString(for: subTask) == "Parent, Child")
}

@Test func responseString_table_uses_summary() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["items"] = .table(TableData(
        columns: [TableData.Column(id: "item", label: "Item", type: "text")],
        rows: [["item": "Widget"]],
        total: 0,
        hasCurrency: false
    ))

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.responseString(for: subTask) == "Widget")
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

@Test func extractPNG_returns_image_png() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)

    let pngData = Data([0x89, 0x50, 0x4E, 0x47])
    var response = ActionResponse()
    response["sketch"] = .image(png: pngData, description: "A sketch")

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    let extracted = KnowledgeResponseExtractor.extractPNG(from: subTask)
    #expect(extracted == pngData)
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
    var response = ActionResponse()
    response["table"] = .table(TableData(
        columns: [TableData.Column(id: "item", label: "Item", type: "text")],
        rows: [["item": "Widget"], ["item": "Gadget"]],
        total: 0,
        hasCurrency: false
    ))

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    let markdown = KnowledgeResponseExtractor.extractTableMarkdown(from: subTask)
    #expect(markdown != nil)
    #expect(markdown?.contains("| Item |") == true)
    #expect(markdown?.contains("| Widget |") == true)
}

@Test func extractTableMarkdown_empty_rows() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["table"] = .table(TableData(
        columns: [TableData.Column(id: "item", label: "Item", type: "text")],
        rows: [],
        total: 0,
        hasCurrency: false
    ))

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    let markdown = KnowledgeResponseExtractor.extractTableMarkdown(from: subTask)
    #expect(markdown != nil)
}

@Test func extractTableMarkdown_with_currency_total() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["table"] = .table(TableData(
        columns: [TableData.Column(id: "price", label: "Price", type: "currency")],
        rows: [["price": "10"], ["price": "20"]],
        total: 30,
        hasCurrency: true
    ))

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    let markdown = KnowledgeResponseExtractor.extractTableMarkdown(from: subTask)
    #expect(markdown?.contains("_Total: €30_") == true)
}

@Test func extractTableMarkdown_no_total_when_zero() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["table"] = .table(TableData(
        columns: [TableData.Column(id: "price", label: "Price", type: "currency")],
        rows: [["price": "10"]],
        total: 0,
        hasCurrency: true
    ))

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    let markdown = KnowledgeResponseExtractor.extractTableMarkdown(from: subTask)
    #expect(markdown?.contains("_Total:") == false)
}

@Test func originalTextInput_returns_description_for_drawing() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["sketch"] = .image(png: Data([0x89]), description: "Drawing with 2 lines. Labels: North wall")

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.originalTextInput(for: subTask) == "Drawing with 2 lines. Labels: North wall")
}

@Test func originalTextInput_returns_nil_for_drawing_without_description() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["sketch"] = .image(png: Data([0x89]), description: "")

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.originalTextInput(for: subTask) == nil)
}

@Test func originalTextInput_returns_nil_for_table() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["table"] = .table(TableData(columns: [], rows: [], total: 0, hasCurrency: false))

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.originalTextInput(for: subTask) == nil)
}

@Test func originalTextInput_returns_text_for_string_value() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["answer"] = .string("I went to Berlin last summer.")

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    #expect(KnowledgeResponseExtractor.originalTextInput(for: subTask) == "I went to Berlin last summer.")
}

@Test func originalTextInput_returns_nil_when_no_data() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    subTask.actionResponseData = nil

    #expect(KnowledgeResponseExtractor.originalTextInput(for: subTask) == nil)
}

@Test func originalTextInput_includes_drawing_description_alongside_text() {
    let subTask = SubTask(title: "Test Step", description: "", order: 0)
    var response = ActionResponse()
    response["sketch"] = .image(png: Data([0x89]), description: "Sketch with labels: North wall")
    response["caption"] = .string("Layout for the kitchen")

    subTask.actionResponseData = try? JSONEncoder().encode(response)

    let result = KnowledgeResponseExtractor.originalTextInput(for: subTask)
    #expect(result?.contains("Sketch with labels: North wall") == true)
    #expect(result?.contains("Layout for the kitchen") == true)
}
