import Foundation

private extension KeyedDecodingContainer {
    /// Decodes a value for `key`, falling back to `defaultValue` when the key is absent or null.
    func decode<T: Decodable>(_ key: Key, default defaultValue: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? defaultValue()
    }
}

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
        self.submitLabel = try container.decode(.submitLabel, default: "Continue")
        self.requiresExternalAction = try container.decode(.requiresExternalAction, default: false)
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
        case brainstorm
        case slider
        case rangeSlider
        case countSelector
        case itemTable
        case orderedList
        case hierarchicalList
    }

    enum CodingKeys: String, CodingKey {
        case id, type, label, placeholder, required, options, validation, defaultValue, prefillRows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(.id, default: UUID().uuidString)
        self.type = try container.decode(FieldType.self, forKey: .type)
        self.label = try container.decode(.label, default: "")
        self.placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        self.required = try container.decode(.required, default: true)
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
        self.id = try container.decode(.id, default: UUID().uuidString)
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

// MARK: - Structured Response Payloads

/// A single node in a `hierarchicalList` answer. `depth` is the nesting level (0 = top level).
struct TreeNode: Codable, Equatable {
    let label: String
    let depth: Int
}

/// A structured `itemTable` answer — columns, rows keyed by column id, and currency totals.
struct TableData: Codable, Equatable {
    struct Column: Codable, Equatable {
        let id: String
        let label: String
        /// "text" | "currency" | "category" | "select"
        let type: String
    }

    var columns: [Column]
    var rows: [[String: String]]
    var total: Int
    var hasCurrency: Bool

    /// Human-readable one-line summary, e.g. "Apples - €5; Oranges - €10 (Total: €15)".
    var summary: String {
        let parts = rows.compactMap { row -> String? in
            let cells = columns.compactMap { col -> String? in
                guard let val = row[col.id], !val.isEmpty else { return nil }
                return col.type == "currency" ? "€\(val)" : val
            }
            return cells.isEmpty ? nil : cells.joined(separator: " - ")
        }
        var summary = parts.joined(separator: "; ")
        if hasCurrency && total > 0 {
            summary += " (Total: €\(total))"
        }
        return summary.isEmpty ? "No items" : summary
    }

    /// Markdown table rendering for wiki notes.
    var markdown: String {
        guard !columns.isEmpty else { return "" }
        let header = "| " + columns.map(\.label).joined(separator: " | ") + " |"
        let separator = "| " + columns.map { _ in "---" }.joined(separator: " | ") + " |"
        let rowLines = rows.map { row -> String in
            let cells = columns.map { col -> String in
                let raw = row[col.id] ?? ""
                return (col.type == "currency" && !raw.isEmpty) ? "€\(raw)" : raw
            }
            return "| " + cells.joined(separator: " | ") + " |"
        }
        var table = ([header, separator] + rowLines).joined(separator: "\n")
        if hasCurrency && total > 0 {
            table += "\n\n_Total: €\(total)_"
        }
        return table
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
    /// A `rangeSlider` answer.
    case range(lower: Double, upper: Double)
    /// A `hierarchicalList` answer — an ordered list of nodes carrying explicit depth.
    case tree([TreeNode])
    /// An `itemTable` answer.
    case table(TableData)
    /// A `drawing` or `brainstorm` answer — flattened PNG plus a text description.
    case image(png: Data, description: String)

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

    var rangeValue: (lower: Double, upper: Double)? {
        if case .range(let lower, let upper) = self { return (lower, upper) }
        return nil
    }

    var treeValue: [TreeNode]? {
        if case .tree(let value) = self { return value }
        return nil
    }

    var tableValue: TableData? {
        if case .table(let value) = self { return value }
        return nil
    }

    var imageValue: (png: Data, description: String)? {
        if case .image(let png, let description) = self { return (png, description) }
        return nil
    }
}
