import Foundation
import Testing

@testable import Tada

// MARK: - ActionSchema Tests

@Test func actionSchema_initialization_with_defaults() {
    let schema = ActionSchema(
        type: .form,
        title: "Test Form",
        description: "A test form",
        fields: []
    )

    #expect(schema.type == .form)
    #expect(schema.title == "Test Form")
    #expect(schema.description == "A test form")
    #expect(schema.fields.isEmpty)
    #expect(schema.submitLabel == "Continue")
    #expect(schema.requiresExternalAction == false)
}

@Test func actionSchema_custom_submit_label() {
    let schema = ActionSchema(
        type: .confirmation,
        title: "Confirm",
        fields: [],
        submitLabel: "Submit"
    )

    #expect(schema.submitLabel == "Submit")
}

@Test func actionSchema_requiresExternalAction() {
    let schema = ActionSchema(
        type: .form,
        title: "External",
        fields: [],
        requiresExternalAction: true
    )

    #expect(schema.requiresExternalAction == true)
}

@Test func actionSchema_codable_roundtrip() async throws {
    let schema = ActionSchema(
        type: .form,
        title: "Test Form",
        description: "A test form with fields",
        fields: [
            ActionField(
                id: "name",
                type: .text,
                label: "Name",
                placeholder: "Enter your name",
                required: true
            )
        ],
        submitLabel: "Go",
        requiresExternalAction: true
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys

    let decoder = JSONDecoder()

    let data = try encoder.encode(schema)
    let decoded = try decoder.decode(ActionSchema.self, from: data)

    #expect(decoded.type == schema.type)
    #expect(decoded.title == schema.title)
    #expect(decoded.description == schema.description)
    #expect(decoded.submitLabel == schema.submitLabel)
    #expect(decoded.requiresExternalAction == schema.requiresExternalAction)
    #expect(decoded.fields.count == 1)
    #expect(decoded.fields[0].id == "name")
    #expect(decoded.fields[0].type == .text)
    #expect(decoded.fields[0].label == "Name")
}

@Test func actionSchema_decodes_missing_submitLabel_as_default() throws {
    let json = """
    {"type":"form","title":"Test","fields":[],"requiresExternalAction":false}
    """

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(ActionSchema.self, from: json.data(using: .utf8)!)

    #expect(decoded.submitLabel == "Continue")
}

@Test func actionSchema_decodes_missing_requiresExternalAction_as_false() throws {
    let json = """
    {"type":"form","title":"Test","fields":[],"submitLabel":"Go"}
    """

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(ActionSchema.self, from: json.data(using: .utf8)!)

    #expect(decoded.requiresExternalAction == false)
}

@Test func actionSchema_allActionTypes() async throws {
    let types: [ActionSchema.ActionType] = [.form, .multiSelect, .singleSelect, .confirmation, .freeform]

    for type in types {
        let schema = ActionSchema(type: type, title: "Test", fields: [])

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(schema)
        let decoded = try decoder.decode(ActionSchema.self, from: data)

        #expect(decoded.type == type)
    }
}

// MARK: - ActionField Tests

@Test func actionField_initialization_with_defaults() {
    let field = ActionField(
        type: .text,
        label: "Name"
    )

    #expect(field.id != nil) // UUID generated
    #expect(field.type == .text)
    #expect(field.label == "Name")
    #expect(field.placeholder == nil)
    #expect(field.required == true) // default
    #expect(field.options == nil)
    #expect(field.validation == nil)
    #expect(field.defaultValue == nil)
}

@Test func actionField_codable_roundtrip() async throws {
    let field = ActionField(
        id: "age",
        type: .number,
        label: "Age",
        placeholder: "Enter age",
        required: false,
        validation: FieldValidation(minValue: 0, maxValue: 120)
    )

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let data = try encoder.encode(field)
    let decoded = try decoder.decode(ActionField.self, from: data)

    #expect(decoded.id == "age")
    #expect(decoded.type == .number)
    #expect(decoded.label == "Age")
    #expect(decoded.placeholder == "Enter age")
    #expect(decoded.required == false)
    #expect(decoded.validation?.minValue == 0)
    #expect(decoded.validation?.maxValue == 120)
}

@Test func actionField_decodes_missing_label_as_empty() throws {
    let json = """
    {"id":"test","type":"text"}
    """

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(ActionField.self, from: json.data(using: .utf8)!)

    #expect(decoded.label == "")
}

@Test func actionField_decodes_missing_required_as_true() throws {
    let json = """
    {"id":"test","type":"text","label":"Test"}
    """

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(ActionField.self, from: json.data(using: .utf8)!)

    #expect(decoded.required == true)
}

@Test func actionField_allFieldTypes() async throws {
    let types: [ActionField.FieldType] = [
        .text, .number, .multiSelect, .singleSelect, .yesNo, .date,
        .textarea, .checklist, .drawing, .slider, .rangeSlider,
        .countSelector, .itemTable, .orderedList, .hierarchicalList
    ]

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    for type in types {
        // Verify each type encodes to its raw string value
        let data = try encoder.encode(type)
        let decoded = try decoder.decode(ActionField.FieldType.self, from: data)

        #expect(decoded == type)
    }
}

// MARK: - FieldOption Tests

@Test func fieldOption_initialization() {
    let option = FieldOption(id: "opt1", label: "Option 1", description: "First option")

    #expect(option.id == "opt1")
    #expect(option.label == "Option 1")
    #expect(option.description == "First option")
}

@Test func fieldOption_codable_roundtrip() async throws {
    let option = FieldOption(id: "opt2", label: "Option 2")

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let data = try encoder.encode(option)
    let decoded = try decoder.decode(FieldOption.self, from: data)

    #expect(decoded.id == "opt2")
    #expect(decoded.label == "Option 2")
}

@Test func fieldOption_decodes_missing_id_as_uuid() throws {
    let json = """
    {"label":"Test"}
    """

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(FieldOption.self, from: json.data(using: .utf8)!)

    #expect(decoded.id != "")
}

// MARK: - FieldValidation Tests

@Test func fieldValidation_all_properties() {
    let validation = FieldValidation(
        minLength: 3,
        maxLength: 50,
        minValue: 0.0,
        maxValue: 100.0,
        pattern: "^[a-z]+$"
    )

    #expect(validation.minLength == 3)
    #expect(validation.maxLength == 50)
    #expect(validation.minValue == 0.0)
    #expect(validation.maxValue == 100.0)
    #expect(validation.pattern == "^[a-z]+$")
}

@Test func fieldValidation_codable_roundtrip() async throws {
    let validation = FieldValidation(minLength: 1, maxLength: 100)

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let data = try encoder.encode(validation)
    let decoded = try decoder.decode(FieldValidation.self, from: data)

    #expect(decoded.minLength == 1)
    #expect(decoded.maxLength == 100)
}

// MARK: - ActionResponse Tests

@Test func actionResponse_initialization_is_empty() {
    let response = ActionResponse()

    #expect(response.values.isEmpty)
}

@Test func actionResponse_subscript_set_and_get() {
    var response = ActionResponse()
    response["key"] = .string("value")

    #expect(response["key"]?.stringValue == "value")
}

@Test func actionResponse_multiple_values() {
    var response = ActionResponse()
    response["name"] = .string("Alice")
    response["age"] = .number(30)
    response["active"] = .boolean(true)

    #expect(response.values.count == 3)
    #expect(response["name"]?.stringValue == "Alice")
    #expect(response["age"]?.numberValue == 30)
    #expect(response["active"]?.boolValue == true)
}

@Test func actionResponse_overwrite_value() {
    var response = ActionResponse()
    response["key"] = .string("old")
    response["key"] = .string("new")

    #expect(response.values.count == 1)
    #expect(response["key"]?.stringValue == "new")
}

// MARK: - ResponseValue Tests

@Test func responseValue_string_roundtrip() {
    let value: ResponseValue = .string("hello")

    #expect(value.stringValue == "hello")
    #expect(value.numberValue == nil)
    #expect(value.boolValue == nil)
}

@Test func responseValue_number_roundtrip() {
    let value: ResponseValue = .number(42.5)

    #expect(value.numberValue == 42.5)
    #expect(value.stringValue == nil)
}

@Test func responseValue_boolean_roundtrip() {
    let value: ResponseValue = .boolean(true)

    #expect(value.boolValue == true)
}

@Test func responseValue_stringArray_roundtrip() {
    let value: ResponseValue = .stringArray(["a", "b", "c"])

    #expect(value.stringArrayValue == ["a", "b", "c"])
}

@Test func responseValue_codable_roundtrip() async throws {
    let values: [ResponseValue] = [
        .string("text"),
        .number(123),
        .boolean(true),
        .stringArray(["x", "y"])
    ]

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    for value in values {
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(ResponseValue.self, from: data)

        #expect(decoded == value)
    }
}

@Test func responseValue_equatable() {
    #expect(ResponseValue.string("a") == ResponseValue.string("a"))
    #expect(ResponseValue.string("a") != ResponseValue.string("b"))
    #expect(ResponseValue.number(1) == ResponseValue.number(1))
    #expect(ResponseValue.boolean(true) != ResponseValue.boolean(false))
}

@Test func responseValue_range_roundtrip() {
    let value: ResponseValue = .range(lower: 10, upper: 90)

    #expect(value.rangeValue?.lower == 10)
    #expect(value.rangeValue?.upper == 90)
    #expect(value.stringValue == nil)
}

@Test func responseValue_tree_roundtrip() {
    let nodes = [TreeNode(label: "A", depth: 0), TreeNode(label: "B", depth: 1)]
    let value: ResponseValue = .tree(nodes)

    #expect(value.treeValue == nodes)
    #expect(value.stringArrayValue == nil)
}

@Test func responseValue_table_roundtrip() {
    let table = TableData(
        columns: [TableData.Column(id: "item", label: "Item", type: "text")],
        rows: [["item": "Widget"]],
        total: 0,
        hasCurrency: false
    )
    let value: ResponseValue = .table(table)

    #expect(value.tableValue == table)
    #expect(value.stringValue == nil)
}

@Test func responseValue_image_roundtrip() {
    let png = Data([0x89, 0x50, 0x4E, 0x47])
    let value: ResponseValue = .image(png: png, description: "Sketch")

    #expect(value.imageValue?.png == png)
    #expect(value.imageValue?.description == "Sketch")
    #expect(value.stringValue == nil)
}

@Test func responseValue_codable_roundtrip_structured_cases() async throws {
    let values: [ResponseValue] = [
        .range(lower: 5, upper: 50),
        .tree([TreeNode(label: "Root", depth: 0), TreeNode(label: "Leaf", depth: 1)]),
        .table(TableData(
            columns: [TableData.Column(id: "c", label: "C", type: "currency")],
            rows: [["c": "12"]],
            total: 12,
            hasCurrency: true
        )),
        .image(png: Data([0x01, 0x02, 0x03]), description: "Diagram")
    ]

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    for value in values {
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(ResponseValue.self, from: data)
        #expect(decoded == value)
    }
}
