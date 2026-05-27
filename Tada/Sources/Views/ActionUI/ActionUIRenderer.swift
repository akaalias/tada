import SwiftUI

private struct PhaseColorKey: EnvironmentKey {
    static let defaultValue: Color = .blue
}

extension EnvironmentValues {
    var phaseColor: Color {
        get { self[PhaseColorKey.self] }
        set { self[PhaseColorKey.self] = newValue }
    }
}

struct ActionUIRenderer: View {
    let schema: ActionSchema
    @Binding var response: ActionResponse
    var isDiscovery: Bool = false
    var showTitle: Bool = true
    let onSubmit: () -> Void
    var onHelp: (() -> Void)?
    var onChangeFieldType: ((ActionField.FieldType, [FieldOption]?) -> Void)?

    @State private var useCustomInput = false
    @State private var customText = ""

    private var phaseColor: Color {
        isDiscovery ? Theme.discovery : Theme.execution
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if showTitle {
                Text(schema.title)
                    .font(.system(size: Theme.fontSize, weight: .semibold))
            }

            if let description = schema.description {
                Text(description)
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(.secondary)
            }

            if useCustomInput {
                // Custom text input mode
                VStack(alignment: .leading, spacing: 12) {
                    TextEditor(text: $customText)
                        .font(.system(size: Theme.fontSize))
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )

                    HStack {
                        Button("Back to options") {
                            useCustomInput = false
                        }
                        .font(.system(size: Theme.fontSize))
                        .foregroundColor(.accentColor)

                        Spacer()

                        Button(action: {
                            response["custom_input"] = .string(customText)
                            onSubmit()
                        }) {
                            Text("Submit")
                                .font(.system(size: Theme.fontSize, weight: .medium))
                                .padding(.horizontal, 20)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            } else {
                // Dynamic fields
                ForEach(schema.fields) { field in
                    renderField(field)
                }

                HStack {
                    if let onChangeFieldType = onChangeFieldType {
                        Menu {
                            Section("Input Types") {
                                FieldTypeButton(type: .text, label: "Short Text", icon: "textformat", onSelect: onChangeFieldType)
                                FieldTypeButton(type: .textarea, label: "Long Text", icon: "text.alignleft", onSelect: onChangeFieldType)
                                FieldTypeButton(type: .number, label: "Number", icon: "number", onSelect: onChangeFieldType)
                                FieldTypeButton(type: .countSelector, label: "Count (1-4+)", icon: "person.2", onSelect: onChangeFieldType)
                                FieldTypeButton(type: .slider, label: "Slider", icon: "slider.horizontal.3", onSelect: onChangeFieldType)
                                FieldTypeButton(type: .rangeSlider, label: "Range Slider", icon: "slider.horizontal.2.square", onSelect: onChangeFieldType)
                                FieldTypeButton(type: .date, label: "Date", icon: "calendar", onSelect: onChangeFieldType)
                            }
                            Section("Tables") {
                                FieldTypeButton(
                                    type: .itemTable,
                                    label: "Budget Table (Item + Amount)",
                                    icon: "dollarsign.circle",
                                    options: [
                                        FieldOption(id: "item", label: "Item"),
                                        FieldOption(id: "amount", label: "Amount", description: "currency")
                                    ],
                                    onSelect: onChangeFieldType
                                )
                                FieldTypeButton(
                                    type: .itemTable,
                                    label: "Category Table (Item + Category)",
                                    icon: "folder",
                                    options: [
                                        FieldOption(id: "item", label: "Item"),
                                        FieldOption(id: "category", label: "Category", description: "category")
                                    ],
                                    onSelect: onChangeFieldType
                                )
                                FieldTypeButton(
                                    type: .itemTable,
                                    label: "Simple List (Item only)",
                                    icon: "list.bullet",
                                    options: [
                                        FieldOption(id: "item", label: "Item")
                                    ],
                                    onSelect: onChangeFieldType
                                )
                            }
                            Section("Selection Types") {
                                FieldTypeButton(type: .yesNo, label: "Yes/No", icon: "hand.thumbsup", onSelect: onChangeFieldType)
                                FieldTypeButton(type: .singleSelect, label: "Single Choice", icon: "circle.inset.filled", onSelect: onChangeFieldType)
                                FieldTypeButton(type: .multiSelect, label: "Multiple Choice", icon: "checklist", onSelect: onChangeFieldType)
                                FieldTypeButton(type: .checklist, label: "Checklist (tick off)", icon: "checkmark.square", onSelect: onChangeFieldType)
                                FieldTypeButton(type: .orderedList, label: "Ordered List (drag to reorder)", icon: "arrow.up.arrow.down", onSelect: onChangeFieldType)
                                FieldTypeButton(type: .hierarchicalList, label: "Hierarchical Tree (drag + nest)", icon: "list.bullet.indent", onSelect: onChangeFieldType)
                            }
                            Section("Visual") {
                                FieldTypeButton(type: .drawing, label: "Drawing", icon: "pencil.tip", onSelect: onChangeFieldType)
                                FieldTypeButton(type: .brainstorm, label: "Brainstorm", icon: "lightbulb", onSelect: onChangeFieldType)
                            }
                        } label: {
                            Label("Change input type", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: Theme.fontSize))
                                .foregroundColor(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                    } else {
                        Button("Write something instead...") {
                            useCustomInput = true
                        }
                        .font(.system(size: Theme.fontSize))
                        .foregroundColor(.secondary)
                    }

                    Spacer()

                    if let onHelp = onHelp {
                        Button {
                            onHelp()
                        } label: {
                            Label("Help", systemImage: "questionmark.circle")
                                .font(.system(size: Theme.fontSize, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityIdentifier("actionUI.help")
                    }

                    Button(action: onSubmit) {
                        Text(schema.submitLabel)
                            .font(.system(size: Theme.fontSize, weight: .medium))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(phaseColor)
                    .controlSize(.large)
                    .disabled(!checkValidity())
                    .accessibilityIdentifier("actionUI.submit")
                }
            }
        }
        .padding(20)
        .background(phaseColor.opacity(0.15))
        .cornerRadius(12)
        .environment(\.phaseColor, phaseColor)
    }

    @ViewBuilder
    private func renderField(_ field: ActionField) -> some View {
        switch field.type {
            case .text:
                TextFieldRenderer(field: field, response: $response)
            case .number:
                NumberFieldRenderer(field: field, response: $response)
            case .textarea:
                TextAreaRenderer(field: field, response: $response)
            case .singleSelect:
                SingleSelectRenderer(field: field, response: $response)
            case .multiSelect:
                MultiSelectRenderer(field: field, response: $response)
            case .yesNo:
                YesNoRenderer(field: field, response: $response)
            case .date:
                DateFieldRenderer(field: field, response: $response)
            case .checklist:
                ChecklistRenderer(field: field, response: $response)
            case .drawing:
                DrawingCanvasRenderer(field: field, response: $response)
            case .brainstorm:
                BrainstormCanvasRenderer(field: field, response: $response)
            case .slider:
                SliderRenderer(field: field, response: $response)
            case .rangeSlider:
                RangeSliderRenderer(field: field, response: $response)
            case .countSelector:
                CountSelectorRenderer(field: field, response: $response)
            case .itemTable:
                ItemTableRenderer(field: field, response: $response)
            case .orderedList:
                OrderedListRenderer(field: field, response: $response)
            case .hierarchicalList:
                HierarchicalListRenderer(field: field, response: $response)
        }
    }

    private func checkValidity() -> Bool {
        for field in schema.fields {
            if field.required {
                guard let value = response[field.id] else { return false }

                switch value {
                case .string(let s):
                    if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
                case .stringArray(let arr):
                    if arr.isEmpty { return false }
                case .tree(let nodes):
                    if nodes.isEmpty { return false }
                case .table(let table):
                    if table.rows.isEmpty { return false }
                case .number, .boolean, .date, .range, .image:
                    break // These have values if set
                }
            }
        }
        return true
    }
}

struct FieldTypeButton: View {
    let type: ActionField.FieldType
    let label: String
    let icon: String
    var options: [FieldOption]? = nil
    let onSelect: (ActionField.FieldType, [FieldOption]?) -> Void

    var body: some View {
        Button {
            onSelect(type, options)
        } label: {
            Label(label, systemImage: icon)
        }
    }
}

extension View {
    /// Standard input-field chrome: a filled, rounded background with a hairline border.
    func fieldChrome(_ fill: Color) -> some View {
        self
            .background(fill)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
}

