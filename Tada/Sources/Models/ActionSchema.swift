import Foundation

/// Defines the structure of a dynamically generated action UI
struct ActionSchema: Codable, Equatable {
    let type: ActionType
    let title: String
    let description: String?
    let fields: [ActionField]
    let submitLabel: String
    let requiresExternalAction: Bool

    enum ActionType: String, Codable {
        case form
        case multiSelect
        case singleSelect
        case confirmation
        case freeform
    }

    enum CodingKeys: String, CodingKey {
        case type, title, description, fields, submitLabel, requiresExternalAction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(ActionType.self, forKey: .type)
        self.title = try container.decode(String.self, forKey: .title)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.fields = try container.decode([ActionField].self, forKey: .fields)
        self.submitLabel = try container.decodeIfPresent(String.self, forKey: .submitLabel) ?? "Continue"
        self.requiresExternalAction = try container.decodeIfPresent(Bool.self, forKey: .requiresExternalAction) ?? false
    }

    init(
        type: ActionType,
        title: String,
        description: String? = nil,
        fields: [ActionField],
        submitLabel: String = "Continue",
        requiresExternalAction: Bool = false
    ) {
        self.type = type
        self.title = title
        self.description = description
        self.fields = fields
        self.submitLabel = submitLabel
        self.requiresExternalAction = requiresExternalAction
    }
}

struct ActionField: Codable, Identifiable, Equatable {
    let id: String
    let type: FieldType
    let label: String
    let placeholder: String?
    let required: Bool
    let options: [FieldOption]?
    let validation: FieldValidation?
    let defaultValue: String?
    let prefillRows: [[String: String]]?

    enum FieldType: String, Codable {
        case text
        case number
        case multiSelect
        case singleSelect
        case yesNo
        case date
        case textarea
        case checklist
        case drawing
        case slider
        case rangeSlider
        case countSelector
        case itemTable
    }

    enum CodingKeys: String, CodingKey {
        case id, type, label, placeholder, required, options, validation, defaultValue, prefillRows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.type = try container.decode(FieldType.self, forKey: .type)
        self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        self.required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? true
        self.options = try container.decodeIfPresent([FieldOption].self, forKey: .options)
        self.validation = try container.decodeIfPresent(FieldValidation.self, forKey: .validation)
        self.defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
        self.prefillRows = try container.decodeIfPresent([[String: String]].self, forKey: .prefillRows)
    }

    init(
        id: String = UUID().uuidString,
        type: FieldType,
        label: String,
        placeholder: String? = nil,
        required: Bool = true,
        options: [FieldOption]? = nil,
        validation: FieldValidation? = nil,
        defaultValue: String? = nil,
        prefillRows: [[String: String]]? = nil
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.placeholder = placeholder
        self.required = required
        self.options = options
        self.validation = validation
        self.defaultValue = defaultValue
        self.prefillRows = prefillRows
    }
}

struct FieldOption: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, label, description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.label = try container.decode(String.self, forKey: .label)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    init(id: String = UUID().uuidString, label: String, description: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
    }
}

struct FieldValidation: Codable, Equatable {
    let minLength: Int?
    let maxLength: Int?
    let minValue: Double?
    let maxValue: Double?
    let pattern: String?

    init(
        minLength: Int? = nil,
        maxLength: Int? = nil,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        pattern: String? = nil
    ) {
        self.minLength = minLength
        self.maxLength = maxLength
        self.minValue = minValue
        self.maxValue = maxValue
        self.pattern = pattern
    }
}

// MARK: - Response Types

struct ActionResponse: Codable {
    var values: [String: ResponseValue]

    init() {
        self.values = [:]
    }

    subscript(key: String) -> ResponseValue? {
        get { values[key] }
        set { values[key] = newValue }
    }
}

enum ResponseValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case date(Date)
    case stringArray([String])

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .boolean(let value) = self { return value }
        return nil
    }

    var dateValue: Date? {
        if case .date(let value) = self { return value }
        return nil
    }

    var stringArrayValue: [String]? {
        if case .stringArray(let value) = self { return value }
        return nil
    }
}
