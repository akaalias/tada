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

@Generable
struct GenFieldOption {
    var id: String
    var label: String
    @Guide(description: "Optional helper text. For an itemTable column, set this to the column TYPE: 'currency' for money amounts, 'select:A,B,C' for a dropdown, or leave empty for plain text.")
    var description: String
}

/// One row of a hierarchicalList's seeded starter tree.
@Generable
struct GenTreeItem {
    var label: String
    @Guide(description: "Nesting depth: 0 = top level, 1 = child, 2 = grandchild.")
    var depth: Int
}

/// The activity/UI control for a sub-task, modeled as an enum with associated values
/// so each type carries ONLY its valid payload. Options exist solely on selection
/// cases — the model literally cannot attach choices to a free-text or numeric field,
/// so the type it picks is always consistent with its data. To present choices it
/// MUST choose a selection case; this is what makes the model commit to the right type
/// instead of dumping options into a text field.
@Generable
enum GenField {
    /// Short free-form text: names, phone numbers, brief answers. placeholder = an
    /// example answer; defaultValue = pre-filled from the user's prior exact words.
    case text(label: String, placeholder: String, defaultValue: String)
    /// Longer free-form text: explanations, details, availability.
    case textarea(label: String, placeholder: String, defaultValue: String)
    /// A single numeric value with units. placeholder = an example value.
    case number(label: String, placeholder: String)
    /// A single calendar date. Use for any date / "when" / travel-dates question.
    case date(label: String)
    /// A small whole-number count: passengers, tickets, rooms, guests.
    case countSelector(label: String)
    /// A physical room layout or floor plan. Physical/spatial only.
    case drawing(label: String)
    /// A single value on a scale (ratings 1-10, satisfaction). NEVER for budgets.
    case slider(label: String, minValue: Double, maxValue: Double)
    /// A min-max range with two handles. Use for ALL budget/price questions.
    case rangeSlider(label: String, minValue: Double, maxValue: Double)
    /// A yes/no confirmation — use for external actions (calls, emails, research).
    /// Provide exactly two options: a "yes, I did it" and a "no, not yet".
    case yesNo(label: String, options: [GenFieldOption])
    /// Pick ONE option from a list. Use whenever you can enumerate the choices.
    case singleSelect(label: String, options: [GenFieldOption])
    /// Pick MULTIPLE options from a list.
    case multiSelect(label: String, options: [GenFieldOption])
    /// Drag-and-drop to put the given items in order (arrange / sort / prioritize).
    case orderedList(label: String, options: [GenFieldOption])
    /// Drag-and-drop to group or nest items (organize / outline / mind map). Seed the
    /// starter tree with `items`, each carrying its nesting depth.
    case hierarchicalList(label: String, items: [GenTreeItem])
    /// A table with up to 3 columns; each option defines one column.
    case itemTable(label: String, columns: [GenFieldOption])
}

@Generable
struct GenActionSchema {
    @Guide(description: "Use the EXACT sub-task title provided.")
    var title: String
    /// Decoded BEFORE `field` so the model commits to a reasoned type choice first
    /// (chain-of-thought), instead of picking a type as an afterthought.
    @Guide(description: "FIRST decide the single best control for THIS sub-task and say why in one short sentence. Is it an EXTERNAL action — make a call, send an email, book, arrange, research/compare options online? -> yesNo. A date or a 'when' question? -> date. A budget / price / 'how much'? -> rangeSlider. A small whole-number count (passengers, nights)? -> countSelector. Can you list the choices (even numeric, like '1 day / 2 days')? -> singleSelect for one, multiSelect for several. A rating on a scale? -> slider. Arrange/sort? -> orderedList. Group/nest? -> hierarchicalList. A shopping/expense list? -> itemTable. Otherwise short text, or textarea for longer text.")
    var typeReasoning: String
    @Guide(description: "The control you chose in your reasoning; its data must match.")
    var field: GenField
    @Guide(description: "True for real-world actions outside the app (calls, emails, calendar, travel, talking to someone, researching online); false for in-app data entry.")
    var requiresExternalAction: Bool
    @Guide(description: "Button label: Confirm (yesNo), Save (entering info), Continue (selection), Complete (final). Never 'Done'.")
    var submitLabel: String
    @Guide(description: "Optional helpful context. Empty string if none.")
    var description: String
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

extension GenField {
    func toDomain() -> ActionField {
        func make(
            _ type: ActionField.FieldType,
            _ label: String,
            placeholder: String = "",
            defaultValue: String = "",
            options: [GenFieldOption] = [],
            validation: FieldValidation? = nil,
            prefillRows: [[String: String]]? = nil
        ) -> ActionField {
            let mapped = options.map { $0.toDomain() }
            return ActionField(
                id: "answer",
                type: type,
                label: label,
                placeholder: placeholder.isEmpty ? nil : placeholder,
                required: true,
                options: mapped.isEmpty ? nil : mapped,
                validation: validation,
                defaultValue: defaultValue.isEmpty ? nil : defaultValue,
                prefillRows: prefillRows
            )
        }
        switch self {
        case .text(let label, let ph, let dv): return make(.text, label, placeholder: ph, defaultValue: dv)
        case .textarea(let label, let ph, let dv): return make(.textarea, label, placeholder: ph, defaultValue: dv)
        case .number(let label, let ph): return make(.number, label, placeholder: ph)
        case .date(let label): return make(.date, label)
        case .countSelector(let label): return make(.countSelector, label)
        case .drawing(let label): return make(.drawing, label)
        case .slider(let label, let mn, let mx): return make(.slider, label, validation: FieldValidation(minValue: mn, maxValue: mx))
        case .rangeSlider(let label, let mn, let mx): return make(.rangeSlider, label, validation: FieldValidation(minValue: mn, maxValue: mx))
        case .yesNo(let label, let options): return make(.yesNo, label, options: options)
        case .singleSelect(let label, let options): return make(.singleSelect, label, options: options)
        case .multiSelect(let label, let options): return make(.multiSelect, label, options: options)
        case .orderedList(let label, let options): return make(.orderedList, label, options: options)
        case .hierarchicalList(let label, let items):
            let rows = items.map { ["item": $0.label, "depth": String($0.depth)] }
            return make(.hierarchicalList, label, prefillRows: rows.isEmpty ? nil : rows)
        case .itemTable(let label, let columns): return make(.itemTable, label, options: columns)
        }
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
