import Foundation
import Testing

@testable import Tada

// MARK: - formatResponseValue Tests

@Test func formatResponseValue_string_returns_as_is() {
    #expect(formatResponseValue(.string("hello")) == "hello")
}

@Test func formatResponseValue_number_returns_as_string() {
    #expect(formatResponseValue(.number(42)) == "42.0")
    #expect(formatResponseValue(.number(3.14)) == "3.14")
}

@Test func formatResponseValue_boolean_returns_yes_or_no() {
    #expect(formatResponseValue(.boolean(true)) == "Yes")
    #expect(formatResponseValue(.boolean(false)) == "No")
}

@Test func formatResponseValue_stringArray_joins_with_comma() {
    #expect(formatResponseValue(.stringArray(["a", "b", "c"])) == "a, b, c")
    #expect(formatResponseValue(.stringArray(["single"])) == "single")
}

@Test func formatResponseValue_date_returns_formatted() {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.locale = Locale(identifier: "en_US")

    let date = Date(timeIntervalSinceReferenceDate: 0)
    let formatted = formatResponseValue(.date(date))

    // Just verify it's a non-empty string (actual format depends on locale)
    #expect(!formatted.isEmpty)
}

// MARK: - formatResponseValues Tests

@Test func formatResponseValues_empty_returns_placeholder() {
    let response = ActionResponse()
    #expect(formatResponseValues(response) == "(no response)")
}

@Test func formatResponseValues_single_value() {
    var response = ActionResponse()
    response["name"] = .string("Alice")

    #expect(formatResponseValues(response) == "Alice")
}

@Test func formatResponseValues_multiple_values_joined() {
    var response = ActionResponse()
    response["name"] = .string("Alice")
    response["age"] = .number(30)

    let result = formatResponseValues(response)
    #expect(result.contains("Alice"))
    #expect(result.contains("30"))
    #expect(result.contains("; "))
}

@Test func formatResponseValues_mixed_types() {
    var response = ActionResponse()
    response["active"] = .boolean(true)
    response["tags"] = .stringArray(["swift", "testing"])

    let result = formatResponseValues(response)
    #expect(result.contains("Yes"))
    #expect(result.contains("swift, testing"))
}

// MARK: - actionResponseToDict Tests

@Test func actionResponseToDict_empty_returns_empty_dict() {
    let response = ActionResponse()
    #expect(actionResponseToDict(response).isEmpty)
}

@Test func actionResponseToDict_string_values() {
    var response = ActionResponse()
    response["name"] = .string("Alice")

    let dict = actionResponseToDict(response)
    #expect(dict["name"] == "Alice")
}

@Test func actionResponseToDict_number_values() {
    var response = ActionResponse()
    response["count"] = .number(42)

    let dict = actionResponseToDict(response)
    #expect(dict["count"] == "42.0")
}

@Test func actionResponseToDict_boolean_values() {
    var response = ActionResponse()
    response["yes"] = .boolean(true)
    response["no"] = .boolean(false)

    let dict = actionResponseToDict(response)
    #expect(dict["yes"] == "Yes")
    #expect(dict["no"] == "No")
}

@Test func actionResponseToDict_stringArray_values() {
    var response = ActionResponse()
    response["tags"] = .stringArray(["a", "b"])

    let dict = actionResponseToDict(response)
    #expect(dict["tags"] == "a, b")
}

@Test func actionResponseToDict_mixed_values() {
    var response = ActionResponse()
    response["name"] = .string("Alice")
    response["age"] = .number(30)
    response["active"] = .boolean(true)

    let dict = actionResponseToDict(response)
    #expect(dict["name"] == "Alice")
    #expect(dict["age"] == "30.0")
    #expect(dict["active"] == "Yes")
}

@Test func actionResponseToDict_preserves_all_keys() {
    var response = ActionResponse()
    response["a"] = .string("1")
    response["b"] = .number(2)
    response["c"] = .boolean(true)

    let dict = actionResponseToDict(response)
    #expect(dict.count == 3)
}
