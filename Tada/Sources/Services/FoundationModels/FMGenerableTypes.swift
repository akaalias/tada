import Foundation
import FoundationModels

// On-device guided-generation DTOs. Each `@Generable` type replaces a hand-written
// JSON tool schema: constrained decoding guarantees the output *shape*, so the
// behavioral rules that used to live in the prompt (valid field types, "exactly one
// field", required keys) move into the type system and off the token budget.
//
// These are deliberately separate from the domain types (`TaskPlan`, `ActionSchema`)
// so the Claude path and SwiftData/Codable behavior stay untouched. `toDomain()`
// bridges back.

// MARK: - Planner

@Generable
struct GenSubTask {
    @Guide(description: "A short, specific step or question in the user's own terms. Asks/does exactly ONE thing — never combine with 'and' or 'or'.")
    var title: String
    @Guide(description: "One plain sentence of context.")
    var description: String
    @Guide(description: "True ONLY if this step requires real-world action outside the app (phone call, email, calendar, travel, talking to someone). False for in-app data entry.")
    var requiresExternalAction: Bool
}

@Generable
struct GenTaskPlan {
    @Guide(description: "The name of the USER'S task in their own terms (4-9 words). Never a generic label like 'Clarifying Questions' or 'Task Discovery'.")
    var title: String
    @Guide(description: "One plain sentence summarising the task itself.")
    var description: String
    @Guide(description: "The steps or clarifying questions, each atomic.")
    var subTasks: [GenSubTask]
}

@Generable
struct GenPlanRevision {
    @Guide(description: "True only if the plan needs revising into atomic, concrete steps.")
    var revised: Bool
    @Guide(description: "One-sentence reason when revised; empty string otherwise.")
    var reason: String
    @Guide(description: "The replacement steps when revised; empty otherwise.")
    var subTasks: [GenSubTask]
}

@Generable
struct GenMicroSteps {
    @Guide(description: "2-5 smaller, achievable steps, each a single action.")
    var microSteps: [GenSubTask]
}

// MARK: - Executive

/// The valid field types, constrained by the schema. Replaces the long
/// "field type must be exactly one of …" instruction in the Claude prompt.
@Generable
enum GenFieldType {
    case text, number, multiSelect, singleSelect, yesNo, date, textarea
    case drawing, slider, rangeSlider, countSelector, itemTable, orderedList, hierarchicalList

    var domain: ActionField.FieldType {
        switch self {
        case .text: return .text
        case .number: return .number
        case .multiSelect: return .multiSelect
        case .singleSelect: return .singleSelect
        case .yesNo: return .yesNo
        case .date: return .date
        case .textarea: return .textarea
        case .drawing: return .drawing
        case .slider: return .slider
        case .rangeSlider: return .rangeSlider
        case .countSelector: return .countSelector
        case .itemTable: return .itemTable
        case .orderedList: return .orderedList
        case .hierarchicalList: return .hierarchicalList
        }
    }
}

@Generable
struct GenFieldOption {
    var id: String
    var label: String
    @Guide(description: "Optional short helper text. Empty string if none.")
    var description: String
}

@Generable
struct GenFieldValidation {
    @Guide(description: "Minimum numeric value, for slider/rangeSlider.")
    var minValue: Double
    @Guide(description: "Maximum numeric value, for slider/rangeSlider.")
    var maxValue: Double
}

@Generable
struct GenActionField {
    @Guide(description: "Short field identifier, e.g. 'answer'.")
    var id: String
    @Guide(description: "The activity/UI control to present. Use yesNo for yes/no confirmations (especially external actions like calls, emails, research), singleSelect for picking ONE option, multiSelect for several, text for short answers, textarea for long text, date for a calendar date, number for a single numeric value, slider for a value on a scale (NOT budgets), rangeSlider for a min-max range (use for ALL budget/price questions), countSelector for small whole-number counts (passengers, tickets, rooms), itemTable for tables with columns (define columns via options), orderedList for drag-and-drop reordering (items via options), hierarchicalList for nestable trees (items via options), drawing for physical room layouts. If you enumerate choices — even numeric ones — use singleSelect or multiSelect; NEVER pair options with text/number/slider/date.")
    var type: GenFieldType
    @Guide(description: "Field label shown to the user.")
    var label: String
    @Guide(description: "Options for singleSelect/multiSelect/orderedList, or the two choices for yesNo. Empty for other types.")
    var options: [GenFieldOption]
    @Guide(description: "Min/max range for slider and rangeSlider only. Omit otherwise.")
    var validation: GenFieldValidation?
}

@Generable
struct GenActionSchema {
    @Guide(description: "Clear question or prompt for the user. Use the exact sub-task title provided.")
    var title: String
    @Guide(description: "Optional helpful context. Empty string if none.")
    var description: String
    @Guide(description: "Button label: Continue, Save, Confirm, or Complete. Never generic 'Done'.")
    var submitLabel: String
    @Guide(description: "True if the step requires real-world action outside the app.")
    var requiresExternalAction: Bool
    @Guide(description: "Exactly ONE field — the best single input type for this sub-task.")
    var field: GenActionField
}

// MARK: - Mapping to domain types

extension GenSubTask {
    func toDomain() -> SubTaskPlan {
        SubTaskPlan(title: title, description: description, requiresExternalAction: requiresExternalAction)
    }
}

extension GenTaskPlan {
    func toDomain() -> TaskPlan {
        TaskPlan(title: title, description: description, subTasks: subTasks.map { $0.toDomain() })
    }
}

extension GenPlanRevision {
    func toDomain() -> PlanRevision {
        PlanRevision(
            revised: revised,
            reason: reason.isEmpty ? nil : reason,
            subTasks: revised ? subTasks.map { $0.toDomain() } : nil
        )
    }
}

extension GenMicroSteps {
    func toDomain() -> [SubTaskPlan] {
        microSteps.map { $0.toDomain() }
    }
}

extension GenFieldOption {
    func toDomain() -> FieldOption {
        FieldOption(
            id: id.isEmpty ? UUID().uuidString : id,
            label: label,
            description: description.isEmpty ? nil : description
        )
    }
}

extension GenFieldValidation {
    func toDomain() -> FieldValidation {
        FieldValidation(minValue: minValue, maxValue: maxValue)
    }
}

extension GenActionField {
    func toDomain() -> ActionField {
        ActionField(
            id: id.isEmpty ? "answer" : id,
            type: type.domain,
            label: label,
            placeholder: nil,
            required: true,
            options: options.isEmpty ? nil : options.map { $0.toDomain() },
            validation: validation?.toDomain(),
            defaultValue: nil,
            prefillRows: nil
        )
    }
}

extension GenActionSchema {
    func toDomain() -> ActionSchema {
        ActionSchema(
            type: .form,
            title: title,
            description: description.isEmpty ? nil : description,
            fields: [field.toDomain()],
            submitLabel: submitLabel.isEmpty ? "Continue" : submitLabel,
            requiresExternalAction: requiresExternalAction
        )
    }
}
