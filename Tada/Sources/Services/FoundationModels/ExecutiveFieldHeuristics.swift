import Foundation

/// Deterministic safety net over the on-device executive's field-type choice.
/// Guided generation guarantees the output *shape*, not the *decision*, and the 3B
/// model occasionally maps a question to a valid-but-wrong control (e.g. a range
/// slider for "travel dates"). These high-precision corrections fix the clearest
/// mismatches; the user can still override via "Change input type".
enum ExecutiveFieldHeuristics {

    /// Returns the field type that should actually be used, given the question text
    /// and the model's choice.
    static func correctedType(
        title: String,
        label: String,
        choice: ActionField.FieldType
    ) -> ActionField.FieldType {
        let text = (title + " " + label).lowercased()

        // A date/timing question can never be a numeric or slider input.
        let numericish: Set<ActionField.FieldType> = [.slider, .rangeSlider, .number, .countSelector]
        if mentionsDate(text), numericish.contains(choice) {
            return .date
        }

        // Money is a min–max range, not a single-value slider.
        if mentionsMoney(text), choice == .slider {
            return .rangeSlider
        }

        return choice
    }

    /// Applies `correctedType` to a generated schema's field, dropping numeric
    /// validation when a field is coerced to a date.
    static func corrected(_ schema: ActionSchema) -> ActionSchema {
        let fields = schema.fields.map { field -> ActionField in
            let newType = correctedType(title: schema.title, label: field.label, choice: field.type)
            guard newType != field.type else { return field }
            return ActionField(
                id: field.id,
                type: newType,
                label: field.label,
                placeholder: field.placeholder,
                required: field.required,
                options: field.options,
                validation: newType == .date ? nil : field.validation,
                defaultValue: field.defaultValue,
                prefillRows: field.prefillRows
            )
        }
        return ActionSchema(
            type: schema.type,
            title: schema.title,
            description: schema.description,
            fields: fields,
            submitLabel: schema.submitLabel,
            requiresExternalAction: schema.requiresExternalAction
        )
    }

    private static func mentionsDate(_ text: String) -> Bool {
        let tokens = ["date", "deadline", "depart", "arriv", "check-in", "checkin",
                      "check-out", "checkout", "when", "what day", "which day"]
        return tokens.contains { text.contains($0) }
    }

    private static func mentionsMoney(_ text: String) -> Bool {
        let tokens = ["budget", "price", "cost", "how much", "spend"]
        return tokens.contains { text.contains($0) }
    }
}
