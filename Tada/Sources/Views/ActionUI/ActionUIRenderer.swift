import SwiftUI

struct ActionUIRenderer: View {
    let schema: ActionSchema
    @Binding var response: ActionResponse
    var isDiscovery: Bool = false
    var showTitle: Bool = true
    let onSubmit: () -> Void
    var onHelp: (() -> Void)?
    var onChangeFieldType: ((ActionField.FieldType, [FieldOption]?) -> Void)?

    @State private var isValid = false
    @State private var useCustomInput = false
    @State private var customText = ""
    @State private var showingFieldTypePicker = false

    private var phaseColor: Color {
        isDiscovery ? .orange : .blue
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
                            }
                            Section("Visual") {
                                FieldTypeButton(type: .drawing, label: "Drawing", icon: "pencil.tip", onSelect: onChangeFieldType)
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
                }
            }
        }
        .padding(20)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
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
            case .slider:
                SliderRenderer(field: field, response: $response)
            case .rangeSlider:
                RangeSliderRenderer(field: field, response: $response)
            case .countSelector:
                CountSelectorRenderer(field: field, response: $response)
            case .itemTable:
                ItemTableRenderer(field: field, response: $response)
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
                case .number, .boolean, .date:
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

// MARK: - Field Renderers

struct TextFieldRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

    @State private var text = ""

    var body: some View {
        TextField(field.placeholder ?? "", text: $text)
            .font(.system(size: Theme.fontSize))
            .textFieldStyle(.plain)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .onChange(of: text) { _, newValue in
                response[field.id] = .string(newValue)
            }
            .onAppear {
                if text.isEmpty, let defaultValue = field.defaultValue {
                    text = defaultValue
                    response[field.id] = .string(defaultValue)
                }
            }
    }
}

struct NumberFieldRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

    @State private var number: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            TextField(field.placeholder ?? "0", value: $number, format: .number)
                .font(.system(size: Theme.fontSize))
                .textFieldStyle(.plain)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .frame(width: 150)

            if let validation = field.validation {
                if let min = validation.minValue, let max = validation.maxValue {
                    Text("Range: \(Int(min)) - \(Int(max))")
                        .font(.system(size: Theme.fontSize))
                        .foregroundColor(.secondary)
                }
            }
        }
        .onChange(of: number) { _, newValue in
            response[field.id] = .number(newValue)
        }
    }
}

struct TextAreaRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

    @State private var text = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty, let placeholder = field.placeholder {
                Text(placeholder)
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(Color(.placeholderTextColor))
                    .padding(.leading, 19)
                    .padding(.top, 12)
            }

            TextEditor(text: $text)
                .font(.system(size: Theme.fontSize))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .frame(minHeight: 160)
        .background(Color(.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .onChange(of: text) { _, newValue in
            response[field.id] = .string(newValue)
        }
        .onAppear {
            if text.isEmpty, let defaultValue = field.defaultValue {
                text = defaultValue
                response[field.id] = .string(defaultValue)
            }
        }
    }
}

struct SingleSelectRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

    @State private var selected: String?
    @State private var showCustomInput = false
    @State private var customText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(field.options ?? []) { option in
                HStack(spacing: 12) {
                    Image(systemName: selected == option.id ? "circle.inset.filled" : "circle")
                        .foregroundColor(selected == option.id ? .accentColor : .gray.opacity(0.4))
                        .font(.system(size: 20, weight: .light))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.label)
                            .font(.system(size: Theme.fontSize, weight: selected == option.id ? .medium : .regular))

                        if let description = option.description {
                            Text(description)
                                .font(.system(size: Theme.fontSize))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(selected == option.id ? Color.accentColor.opacity(0.08) : Color.clear)
                .cornerRadius(8)
                .contentShape(Rectangle())
                .onTapGesture {
                    showCustomInput = false
                    selected = option.id
                    response[field.id] = .string(option.label)
                }
            }

            // Custom option
            if showCustomInput {
                HStack(spacing: 12) {
                    Image(systemName: "circle.inset.filled")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 20, weight: .light))

                    TextField("Type your answer...", text: $customText)
                        .textFieldStyle(.plain)
                        .font(.system(size: Theme.fontSize))
                        .onChange(of: customText) { _, newValue in
                            selected = "custom"
                            response[field.id] = .string(newValue)
                        }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.accentColor.opacity(0.08))
                .cornerRadius(8)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 20, weight: .light))

                    Text("Other...")
                        .font(.system(size: Theme.fontSize))
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .cornerRadius(8)
                .contentShape(Rectangle())
                .onTapGesture {
                    showCustomInput = true
                    selected = "custom"
                }
            }
        }
    }
}

struct MultiSelectRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

    @State private var selected: Set<String> = []
    @State private var customOptions: [String] = []
    @State private var newCustomText = ""
    @State private var isAddingCustom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(field.options ?? []) { option in
                HStack(spacing: 12) {
                    Image(systemName: selected.contains(option.label) ? "checkmark.square.fill" : "square")
                        .foregroundColor(selected.contains(option.label) ? .accentColor : .gray.opacity(0.4))
                        .font(.system(size: 18, weight: .light))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.label)
                            .font(.system(size: Theme.fontSize, weight: selected.contains(option.label) ? .medium : .regular))

                        if let description = option.description {
                            Text(description)
                                .font(.system(size: Theme.fontSize))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(selected.contains(option.label) ? Color.accentColor.opacity(0.08) : Color.clear)
                .cornerRadius(8)
                .contentShape(Rectangle())
                .onTapGesture {
                    if selected.contains(option.label) {
                        selected.remove(option.label)
                    } else {
                        selected.insert(option.label)
                    }
                    updateResponse()
                }
            }

            // Custom options that were added
            ForEach(customOptions, id: \.self) { customOption in
                HStack(spacing: 12) {
                    Image(systemName: selected.contains(customOption) ? "checkmark.square.fill" : "square")
                        .foregroundColor(selected.contains(customOption) ? .accentColor : .gray.opacity(0.4))
                        .font(.system(size: 18, weight: .light))

                    Text(customOption)
                        .font(.system(size: Theme.fontSize, weight: selected.contains(customOption) ? .medium : .regular))

                    Spacer()

                    Button {
                        selected.remove(customOption)
                        customOptions.removeAll { $0 == customOption }
                        updateResponse()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: Theme.fontSize))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(selected.contains(customOption) ? Color.accentColor.opacity(0.08) : Color.clear)
                .cornerRadius(8)
                .contentShape(Rectangle())
                .onTapGesture {
                    if selected.contains(customOption) {
                        selected.remove(customOption)
                    } else {
                        selected.insert(customOption)
                    }
                    updateResponse()
                }
            }

            // Add custom option
            if isAddingCustom {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 18, weight: .light))

                    TextField("Type your option...", text: $newCustomText, onCommit: {
                        addCustomOption()
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.fontSize))

                    Button("Add") {
                        addCustomOption()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(newCustomText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.accentColor.opacity(0.08))
                .cornerRadius(8)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 18, weight: .light))

                    Text("Add your own...")
                        .font(.system(size: Theme.fontSize))
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .cornerRadius(8)
                .contentShape(Rectangle())
                .onTapGesture {
                    isAddingCustom = true
                }
            }
        }
    }

    private func addCustomOption() {
        let trimmed = newCustomText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        customOptions.append(trimmed)
        selected.insert(trimmed)
        newCustomText = ""
        isAddingCustom = false
        updateResponse()
    }

    private func updateResponse() {
        response[field.id] = .stringArray(Array(selected))
    }
}

struct YesNoRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

    @State private var value: Bool?

    // Use custom labels from options if provided, otherwise defaults
    private var yesLabel: String {
        if let options = field.options, options.count >= 1 {
            return options[0].label
        }
        return "Yes"
    }

    private var noLabel: String {
        if let options = field.options, options.count >= 2 {
            return options[1].label
        }
        return "No"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Yes option
            HStack(spacing: 12) {
                Image(systemName: value == true ? "circle.inset.filled" : "circle")
                    .foregroundColor(value == true ? .accentColor : .gray.opacity(0.4))
                    .font(.system(size: Theme.circleSize))

                Text(yesLabel)
                    .font(.system(size: Theme.fontSize, weight: value == true ? .medium : .regular))

                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(value == true ? Color.accentColor.opacity(0.08) : Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
            .onTapGesture {
                value = true
                response[field.id] = .boolean(true)
            }

            // No option
            HStack(spacing: 12) {
                Image(systemName: value == false ? "circle.inset.filled" : "circle")
                    .foregroundColor(value == false ? .accentColor : .gray.opacity(0.4))
                    .font(.system(size: Theme.circleSize))

                Text(noLabel)
                    .font(.system(size: Theme.fontSize, weight: value == false ? .medium : .regular))

                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(value == false ? Color.accentColor.opacity(0.08) : Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
            .onTapGesture {
                value = false
                response[field.id] = .boolean(false)
            }
        }
    }
}

struct DateFieldRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

    @State private var selectedDay: Int = Calendar.current.component(.day, from: Date())
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    private let months = ["January", "February", "March", "April", "May", "June",
                          "July", "August", "September", "October", "November", "December"]

    private var years: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array((currentYear - 1)...(currentYear + 5))
    }

    private var daysInMonth: Int {
        let components = DateComponents(year: selectedYear, month: selectedMonth)
        let calendar = Calendar.current
        if let date = calendar.date(from: components),
           let range = calendar.range(of: .day, in: .month, for: date) {
            return range.count
        }
        return 31
    }

    private var selectedDate: Date {
        let components = DateComponents(year: selectedYear, month: selectedMonth, day: min(selectedDay, daysInMonth))
        return Calendar.current.date(from: components) ?? Date()
    }

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(1...daysInMonth, id: \.self) { day in
                    Button(String(day)) { selectedDay = day }
                }
            } label: {
                HStack {
                    Text(String(selectedDay))
                        .font(.system(size: Theme.fontSize))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(1...12, id: \.self) { month in
                    Button(months[month - 1]) { selectedMonth = month }
                }
            } label: {
                HStack {
                    Text(months[selectedMonth - 1])
                        .font(.system(size: Theme.fontSize))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(years, id: \.self) { year in
                    Button(String(year)) { selectedYear = year }
                }
            } label: {
                HStack {
                    Text(String(selectedYear))
                        .font(.system(size: Theme.fontSize))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .onChange(of: selectedDay) { _, _ in updateResponse() }
        .onChange(of: selectedMonth) { _, _ in updateResponse() }
        .onChange(of: selectedYear) { _, _ in updateResponse() }
        .onAppear { updateResponse() }
    }

    private func updateResponse() {
        response[field.id] = .date(selectedDate)
    }
}

struct ChecklistRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

    @State private var checked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(field.options ?? []) { option in
                HStack(spacing: 10) {
                    Image(systemName: checked.contains(option.id) ? "checkmark.square.fill" : "square")
                        .foregroundColor(checked.contains(option.id) ? .green : .secondary)
                        .font(.system(size: Theme.fontSize))

                    Text(option.label)
                        .strikethrough(checked.contains(option.id))
                        .foregroundColor(checked.contains(option.id) ? .secondary : .primary)

                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    if checked.contains(option.id) {
                        checked.remove(option.id)
                    } else {
                        checked.insert(option.id)
                    }
                    response[field.id] = .stringArray(Array(checked))
                }
            }

            if let options = field.options, !options.isEmpty {
                Text("\(checked.count)/\(options.count) completed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SliderRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

    @State private var value: Double = 50

    private var minValue: Double {
        field.validation?.minValue ?? 0
    }

    private var maxValue: Double {
        field.validation?.maxValue ?? 100
    }

    // Calculate a reasonable step size based on range
    private var stepSize: Double {
        let range = maxValue - minValue
        if range <= 10 { return 1 }
        if range <= 100 { return 5 }
        if range <= 1000 { return 10 }
        return 50
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Round displayed value to step size
                Text("\(Int((value / stepSize).rounded() * stepSize))")
                    .font(.system(size: 24, weight: .semibold))
                    .monospacedDigit()

                Spacer()

                Text("\(Int(minValue)) - \(Int(maxValue))")
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(.secondary)
            }

            Slider(value: $value, in: minValue...maxValue)
                .onChange(of: value) { _, newValue in
                    // Round to nearest step for cleaner values
                    let rounded = (newValue / stepSize).rounded() * stepSize
                    response[field.id] = .number(rounded)
                }
                .onAppear {
                    value = (minValue + maxValue) / 2
                    response[field.id] = .number(value)
                }
        }
    }
}

struct RangeSliderRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

    @State private var lowerValue: Double = 0
    @State private var upperValue: Double = 100

    private var minValue: Double {
        field.validation?.minValue ?? 0
    }

    private var maxValue: Double {
        field.validation?.maxValue ?? 1000
    }

    private var stepSize: Double {
        let range = maxValue - minValue
        if range <= 10 { return 1 }
        if range <= 100 { return 5 }
        if range <= 1000 { return 50 }
        return 100
    }

    private func roundToStep(_ value: Double) -> Double {
        (value / stepSize).rounded() * stepSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Min")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("\(Int(roundToStep(lowerValue)))")
                        .font(.system(size: 24, weight: .semibold))
                        .monospacedDigit()
                }

                Spacer()

                Text("to")
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Max")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("\(Int(roundToStep(upperValue)))")
                        .font(.system(size: 24, weight: .semibold))
                        .monospacedDigit()
                }
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let lowerX = CGFloat((lowerValue - minValue) / (maxValue - minValue)) * width
                let upperX = CGFloat((upperValue - minValue) / (maxValue - minValue)) * width

                ZStack {
                    // Gray track
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)

                    // Blue range bar - positioned absolutely
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: upperX - lowerX, height: 6)
                        .position(x: (lowerX + upperX) / 2, y: 12)

                    // Lower handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                        .position(x: lowerX, y: 12)
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    let newX = min(max(gesture.location.x, 0), upperX - 20)
                                    lowerValue = minValue + Double(newX / width) * (maxValue - minValue)
                                    updateResponse()
                                }
                        )

                    // Upper handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                        .position(x: upperX, y: 12)
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    let newX = max(min(gesture.location.x, width), lowerX + 20)
                                    upperValue = minValue + Double(newX / width) * (maxValue - minValue)
                                    updateResponse()
                                }
                        )
                }
            }
            .frame(height: 24)

            HStack {
                Text("\(Int(minValue))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(maxValue))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            let range = maxValue - minValue
            lowerValue = minValue + range * 0.25
            upperValue = minValue + range * 0.75
            updateResponse()
        }
    }

    private func updateResponse() {
        let lower = Int(roundToStep(lowerValue))
        let upper = Int(roundToStep(upperValue))
        response[field.id] = .string("\(lower) - \(upper)")
    }
}

struct CountSelectorRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

    @State private var selectedCount: Int = 1
    @State private var customCount: Int = 5
    @State private var showingCustomInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ForEach(1...4, id: \.self) { count in
                    Button {
                        selectedCount = count
                        showingCustomInput = false
                        response[field.id] = .number(Double(count))
                    } label: {
                        Text("\(count)")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 56, height: 56)
                            .background(selectedCount == count && !showingCustomInput ? Color.blue : Color(.controlBackgroundColor))
                            .foregroundColor(selectedCount == count && !showingCustomInput ? .white : .primary)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    if count < 4 {
                        Spacer()
                    }
                }

                Spacer()

                Button {
                    showingCustomInput = true
                    selectedCount = customCount
                    response[field.id] = .number(Double(customCount))
                } label: {
                    if showingCustomInput {
                        HStack(spacing: 4) {
                            TextField("", value: $customCount, format: .number)
                                .textFieldStyle(.plain)
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 30)
                                .multilineTextAlignment(.center)
                                .onChange(of: customCount) { _, newValue in
                                    response[field.id] = .number(Double(newValue))
                                }
                            Stepper("", value: $customCount, in: 5...99)
                                .labelsHidden()
                                .onChange(of: customCount) { _, newValue in
                                    response[field.id] = .number(Double(newValue))
                                }
                        }
                        .frame(width: 80, height: 56)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    } else {
                        Text("5+")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 56, height: 56)
                            .background(Color(.controlBackgroundColor))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            response[field.id] = .number(Double(selectedCount))
        }
    }
}

struct ItemTableRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

    @State private var rows: [TableRow] = [TableRow()]
    @State private var customCategories: [String: [String]] = [:]  // columnId -> custom categories
    @State private var showingNewCategoryInput: String? = nil  // columnId being edited
    @State private var newCategoryText = ""

    struct TableRow: Identifiable {
        let id = UUID()
        var values: [String: String] = [:]
    }

    // Parse column definitions from options, or use defaults
    private var columns: [TableColumn] {
        if let options = field.options, !options.isEmpty {
            return options.map { option in
                TableColumn(
                    id: option.id,
                    label: option.label,
                    type: parseColumnType(option.description)
                )
            }
        }
        // Default: Item + Amount
        return [
            TableColumn(id: "item", label: "Item", type: .text),
            TableColumn(id: "amount", label: "Amount", type: .currency)
        ]
    }

    struct TableColumn {
        let id: String
        let label: String
        let type: ColumnType
    }

    enum ColumnType {
        case text
        case currency
        case select([String])
        case category
    }

    private func parseColumnType(_ description: String?) -> ColumnType {
        guard let desc = description?.lowercased() else { return .text }
        if desc == "currency" || desc == "amount" || desc == "price" || desc == "cost" {
            return .currency
        }
        if desc == "category" {
            return .category
        }
        if desc.hasPrefix("select:") {
            let choices = String(desc.dropFirst(7)).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            return .select(choices)
        }
        return .text
    }

    private var hasCurrencyColumn: Bool {
        columns.contains { if case .currency = $0.type { return true }; return false }
    }

    private var totalAmount: Double {
        rows.reduce(0) { total, row in
            columns.reduce(total) { colTotal, col in
                if case .currency = col.type {
                    return colTotal + (Double(row.values[col.id] ?? "0") ?? 0)
                }
                return colTotal
            }
        }
    }

    private var filledRowCount: Int {
        rows.filter { row in
            columns.first.map { row.values[$0.id]?.isEmpty == false } ?? false
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    if index > 0 {
                        Divider().frame(height: 36)
                    }
                    Text(column.label)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: index == 0 ? .infinity : nil, alignment: .leading)
                        .frame(width: index == 0 ? nil : columnWidth(for: column))
                        .frame(minWidth: index == 0 ? 120 : nil)
                }
                Color.clear.frame(width: 36)
            }
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8, corners: [.topLeft, .topRight])

            Divider()

            // Data rows
            ForEach($rows) { $row in
                HStack(spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                        if index > 0 {
                            Divider().frame(height: 36)
                        }
                        columnCell(for: column, row: $row, isFirst: index == 0)
                    }

                    Button {
                        if rows.count > 1 {
                            rows.removeAll { $0.id == row.id }
                            saveResponse()
                        }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundColor(rows.count > 1 ? .red.opacity(0.7) : .gray.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 36)
                    .disabled(rows.count <= 1)
                }
                .background(Color(.textBackgroundColor))

                Divider()
            }

            // Add row button
            Button {
                rows.append(TableRow())
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Add row")
                }
                .font(.system(size: Theme.fontSize))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.textBackgroundColor))

            Divider()

            // Summary row
            HStack(spacing: 0) {
                Text("\(filledRowCount) item\(filledRowCount == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                if hasCurrencyColumn {
                    Text("€\(totalAmount, specifier: "%.0f")")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 120, alignment: .trailing)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                Color.clear.frame(width: 36)
            }
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8, corners: [.bottomLeft, .bottomRight])
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            // Initialize with prefill data if available
            if rows.count == 1 && rows[0].values.isEmpty, let prefill = field.prefillRows, !prefill.isEmpty {
                rows = prefill.map { dict in
                    var row = TableRow()
                    row.values = dict
                    return row
                }
                // Add an empty row at the end for new entries
                rows.append(TableRow())
            }
            saveResponse()
        }
        .sheet(isPresented: Binding(
            get: { showingNewCategoryInput != nil },
            set: { if !$0 { showingNewCategoryInput = nil } }
        )) {
            VStack(spacing: 16) {
                Text("Add New Category")
                    .font(.headline)

                TextField("Category name", text: $newCategoryText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                HStack {
                    Button("Cancel") {
                        showingNewCategoryInput = nil
                        newCategoryText = ""
                    }

                    Button("Add") {
                        if !newCategoryText.isEmpty, let columnId = showingNewCategoryInput {
                            var existing = customCategories[columnId] ?? []
                            if !existing.contains(newCategoryText) {
                                existing.append(newCategoryText)
                                customCategories[columnId] = existing
                            }
                            newCategoryText = ""
                            showingNewCategoryInput = nil
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newCategoryText.isEmpty)
                }
            }
            .padding(20)
        }
    }

    private func columnWidth(for column: TableColumn) -> CGFloat {
        switch column.type {
        case .currency: return 130
        case .select: return 180
        case .category: return 180
        case .text: return 180
        }
    }

    @ViewBuilder
    private func columnCell(for column: TableColumn, row: Binding<TableRow>, isFirst: Bool) -> some View {
        let binding = Binding<String>(
            get: { row.wrappedValue.values[column.id] ?? "" },
            set: { row.wrappedValue.values[column.id] = $0; saveResponse() }
        )

        let cellContent = cellContentView(for: column, binding: binding, row: row)

        if isFirst {
            cellContent
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            cellContent
                .frame(width: columnWidth(for: column), alignment: .leading)
        }
    }

    @ViewBuilder
    private func cellContentView(for column: TableColumn, binding: Binding<String>, row: Binding<TableRow>) -> some View {
        switch column.type {
        case .text:
            TextField(column.label, text: binding)
                .textFieldStyle(.plain)
                .font(.system(size: Theme.fontSize))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

        case .currency:
            HStack(spacing: 4) {
                Text("€")
                    .foregroundColor(.secondary)
                TextField("0", text: binding)
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.fontSize))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

        case .select(let choices):
            let currentValue = row.wrappedValue.values[column.id] ?? ""
            let allChoices = choices + (customCategories[column.id] ?? [])

            HStack(spacing: 4) {
                Picker("", selection: Binding(
                    get: { currentValue },
                    set: { row.wrappedValue.values[column.id] = $0; saveResponse() }
                )) {
                    Text("Select...").tag("")
                    ForEach(allChoices, id: \.self) { choice in
                        Text(choice).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Button {
                    showingNewCategoryInput = column.id
                    newCategoryText = ""
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add new category")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

        case .category:
            CategoryCell(
                value: binding,
                existingCategories: existingCategoriesFor(column.id),
                onSave: saveResponse
            )
        }
    }

    private func existingCategoriesFor(_ columnId: String) -> [String] {
        Set(rows.compactMap { $0.values[columnId] }.filter { !$0.isEmpty }).sorted()
    }

    private func saveResponse() {
        let filledRows = rows.filter { row in
            columns.first.map { row.values[$0.id]?.isEmpty == false } ?? false
        }

        var parts: [String] = []
        for row in filledRows {
            let rowParts = columns.compactMap { col -> String? in
                guard let val = row.values[col.id], !val.isEmpty else { return nil }
                switch col.type {
                case .currency:
                    return "€\(val)"
                default:
                    return val
                }
            }
            if !rowParts.isEmpty {
                parts.append(rowParts.joined(separator: " - "))
            }
        }

        var summary = parts.joined(separator: "; ")
        if hasCurrencyColumn {
            summary += " (Total: €\(Int(totalAmount)))"
        }
        response[field.id] = .string(summary.isEmpty ? "No items" : summary)
    }
}

struct CategoryCell: View {
    @Binding var value: String
    let existingCategories: [String]
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            TextField("Category", text: $value)
                .textFieldStyle(.plain)
                .font(.system(size: Theme.fontSize))
                .onChange(of: value) { _, _ in onSave() }

            if !existingCategories.isEmpty {
                Menu {
                    ForEach(existingCategories, id: \.self) { category in
                        Button(category) {
                            value = category
                            onSave()
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// Helper for rounded corners on specific sides
extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: RectCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        return path
    }
}

enum DrawingTool: String, CaseIterable {
    case freehand = "pencil"
    case line = "line.diagonal"
    case arrow = "arrow.right"
    case rectangle = "rectangle"
    case circle = "circle"
    case eraser = "eraser"

    var label: String {
        switch self {
        case .freehand: return "Draw"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .eraser: return "Eraser"
        }
    }
}

struct DrawingElement: Identifiable {
    let id = UUID()
    var type: DrawingTool
    var points: [CGPoint]
    var startPoint: CGPoint
    var endPoint: CGPoint

    init(type: DrawingTool, points: [CGPoint] = [], startPoint: CGPoint = .zero, endPoint: CGPoint = .zero) {
        self.type = type
        self.points = points
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
}

struct DrawingCanvasRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

    @State private var elements: [DrawingElement] = []
    @State private var currentElement: DrawingElement?
    @State private var selectedTool: DrawingTool = .freehand
    @State private var textAnnotations: [TextAnnotation] = []
    @State private var showingTextInput = false
    @State private var newAnnotationText = ""
    @State private var tapLocation: CGPoint = .zero

    struct TextAnnotation: Identifiable {
        let id = UUID()
        var position: CGPoint
        var text: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tool palette
            HStack(spacing: 4) {
                ForEach(DrawingTool.allCases, id: \.self) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        Image(systemName: tool.rawValue)
                            .font(.system(size: 16))
                            .frame(width: 36, height: 28)
                            .background(selectedTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
                            .foregroundColor(selectedTool == tool ? .accentColor : .secondary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(tool.label)
                }

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 8)

                Button {
                    tapLocation = CGPoint(x: 100, y: 100)
                    showingTextInput = true
                } label: {
                    Image(systemName: "textformat")
                        .font(.system(size: 16))
                        .frame(width: 36, height: 28)
                        .foregroundColor(.secondary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Add Label")

                Spacer()

                Button {
                    if !elements.isEmpty {
                        elements.removeLast()
                        saveDrawing()
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14))
                        .foregroundColor(elements.isEmpty ? .secondary.opacity(0.5) : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(elements.isEmpty)
                .help("Undo")

                Button {
                    elements = []
                    textAnnotations = []
                    saveDrawing()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear All")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)

            ZStack {
                // Canvas background
                Color(.textBackgroundColor)

                // Drawing layer
                Canvas { context, size in
                    // Draw all completed elements
                    for element in elements {
                        drawElement(element, in: &context)
                    }

                    // Draw current element being created
                    if let current = currentElement {
                        drawElement(current, in: &context)
                    }
                }

                // Text annotations overlay
                ForEach(textAnnotations) { annotation in
                    Text(annotation.text)
                        .font(.system(size: Theme.fontSize, weight: .medium))
                        .padding(6)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                        )
                        .position(annotation.position)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if let index = textAnnotations.firstIndex(where: { $0.id == annotation.id }) {
                                        textAnnotations[index].position = value.location
                                    }
                                }
                                .onEnded { _ in
                                    saveDrawing()
                                }
                        )
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                textAnnotations.removeAll { $0.id == annotation.id }
                                saveDrawing()
                            }
                        }
                }
            }
            .frame(height: 400)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDragChanged(value)
                    }
                    .onEnded { value in
                        handleDragEnded(value)
                    }
            )
            .onTapGesture(count: 2) { location in
                tapLocation = location
                showingTextInput = true
            }

            if let placeholder = field.placeholder {
                Text(placeholder)
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingTextInput) {
            VStack(spacing: 16) {
                Text("Add Label")
                    .font(.headline)

                TextField("Enter text", text: $newAnnotationText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                HStack {
                    Button("Cancel") {
                        newAnnotationText = ""
                        showingTextInput = false
                    }

                    Button("Add") {
                        if !newAnnotationText.isEmpty {
                            textAnnotations.append(TextAnnotation(
                                position: tapLocation,
                                text: newAnnotationText
                            ))
                            saveDrawing()
                            newAnnotationText = ""
                        }
                        showingTextInput = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        switch selectedTool {
        case .freehand:
            if currentElement == nil {
                currentElement = DrawingElement(type: .freehand, points: [value.startLocation])
            }
            currentElement?.points.append(value.location)

        case .eraser:
            eraseAt(value.location)

        case .line, .arrow, .rectangle, .circle:
            if currentElement == nil {
                currentElement = DrawingElement(type: selectedTool, startPoint: value.startLocation, endPoint: value.location)
            } else {
                currentElement?.endPoint = value.location
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        if selectedTool == .eraser {
            return
        }

        if var element = currentElement {
            if selectedTool == .freehand {
                if element.points.count > 1 {
                    elements.append(element)
                }
            } else {
                element.endPoint = value.location
                elements.append(element)
            }
            currentElement = nil
            saveDrawing()
        }
    }

    private func eraseAt(_ point: CGPoint) {
        let eraseRadius: CGFloat = 20

        elements.removeAll { element in
            switch element.type {
            case .freehand:
                return element.points.contains { p in
                    distance(p, point) < eraseRadius
                }
            case .line, .arrow:
                return distanceToLine(point, from: element.startPoint, to: element.endPoint) < eraseRadius
            case .rectangle:
                let rect = CGRect(
                    x: min(element.startPoint.x, element.endPoint.x),
                    y: min(element.startPoint.y, element.endPoint.y),
                    width: abs(element.endPoint.x - element.startPoint.x),
                    height: abs(element.endPoint.y - element.startPoint.y)
                )
                return rect.insetBy(dx: -eraseRadius, dy: -eraseRadius).contains(point)
            case .circle:
                let center = CGPoint(
                    x: (element.startPoint.x + element.endPoint.x) / 2,
                    y: (element.startPoint.y + element.endPoint.y) / 2
                )
                let radiusX = abs(element.endPoint.x - element.startPoint.x) / 2
                let radiusY = abs(element.endPoint.y - element.startPoint.y) / 2
                let avgRadius = (radiusX + radiusY) / 2
                let dist = distance(point, center)
                return abs(dist - avgRadius) < eraseRadius
            case .eraser:
                return false
            }
        }
        saveDrawing()
    }

    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        sqrt(pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2))
    }

    private func distanceToLine(_ point: CGPoint, from start: CGPoint, to end: CGPoint) -> CGFloat {
        let lineLength = distance(start, end)
        if lineLength == 0 { return distance(point, start) }

        let t = max(0, min(1, ((point.x - start.x) * (end.x - start.x) + (point.y - start.y) * (end.y - start.y)) / pow(lineLength, 2)))
        let projection = CGPoint(
            x: start.x + t * (end.x - start.x),
            y: start.y + t * (end.y - start.y)
        )
        return distance(point, projection)
    }

    private func drawElement(_ element: DrawingElement, in context: inout GraphicsContext) {
        let strokeColor = Color.primary
        let lineWidth: CGFloat = 2

        switch element.type {
        case .freehand:
            var path = Path()
            if let first = element.points.first {
                path.move(to: first)
                for point in element.points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

        case .line:
            var path = Path()
            path.move(to: element.startPoint)
            path.addLine(to: element.endPoint)
            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

        case .arrow:
            var path = Path()
            path.move(to: element.startPoint)
            path.addLine(to: element.endPoint)

            // Draw arrowhead
            let angle = atan2(element.endPoint.y - element.startPoint.y, element.endPoint.x - element.startPoint.x)
            let arrowLength: CGFloat = 12
            let arrowAngle: CGFloat = .pi / 6

            let point1 = CGPoint(
                x: element.endPoint.x - arrowLength * cos(angle - arrowAngle),
                y: element.endPoint.y - arrowLength * sin(angle - arrowAngle)
            )
            let point2 = CGPoint(
                x: element.endPoint.x - arrowLength * cos(angle + arrowAngle),
                y: element.endPoint.y - arrowLength * sin(angle + arrowAngle)
            )

            path.move(to: element.endPoint)
            path.addLine(to: point1)
            path.move(to: element.endPoint)
            path.addLine(to: point2)

            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

        case .rectangle:
            let rect = CGRect(
                x: min(element.startPoint.x, element.endPoint.x),
                y: min(element.startPoint.y, element.endPoint.y),
                width: abs(element.endPoint.x - element.startPoint.x),
                height: abs(element.endPoint.y - element.startPoint.y)
            )
            let path = Path(rect)
            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

        case .circle:
            let rect = CGRect(
                x: min(element.startPoint.x, element.endPoint.x),
                y: min(element.startPoint.y, element.endPoint.y),
                width: abs(element.endPoint.x - element.startPoint.x),
                height: abs(element.endPoint.y - element.startPoint.y)
            )
            let path = Path(ellipseIn: rect)
            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

        case .eraser:
            break
        }
    }

    private func saveDrawing() {
        // Always generate text description with labels for AI to read
        var shapeCounts: [String: Int] = [:]
        for element in elements {
            shapeCounts[element.type.label, default: 0] += 1
        }

        var parts: [String] = []
        for (shape, count) in shapeCounts.sorted(by: { $0.key < $1.key }) {
            parts.append("\(count) \(shape.lowercased())\(count > 1 ? "s" : "")")
        }

        var description = parts.isEmpty ? "Empty drawing" : "Drawing with \(parts.joined(separator: ", "))"
        if !textAnnotations.isEmpty {
            let labels = textAnnotations.map { $0.text }.joined(separator: ", ")
            description += ". Labels: \(labels)"
        }

        // Save text description so AI can read the labels
        response[field.id] = .string(description)
    }
}

struct DrawingCanvasSnapshot: View {
    let elements: [DrawingElement]
    let textAnnotations: [DrawingCanvasRenderer.TextAnnotation]
    let drawElement: (DrawingElement, inout GraphicsContext) -> Void

    var body: some View {
        ZStack {
            Color(.textBackgroundColor)

            Canvas { context, size in
                for element in elements {
                    drawElement(element, &context)
                }
            }

            ForEach(textAnnotations) { annotation in
                Text(annotation.text)
                    .font(.system(size: Theme.fontSize, weight: .medium))
                    .padding(6)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                    )
                    .position(annotation.position)
            }
        }
        .frame(width: 600, height: 400)
    }
}

#Preview {
    @Previewable @State var response = ActionResponse()

    let sampleSchema = ActionSchema(
        type: .form,
        title: "How do you want to use the balcony?",
        description: "Select all that apply",
        fields: [
            ActionField(
                id: "uses",
                type: .multiSelect,
                label: "Intended uses",
                options: [
                    FieldOption(id: "coffee", label: "Morning coffee", description: "Start your day outside"),
                    FieldOption(id: "dinner", label: "Evening dinners", description: "Al fresco dining"),
                    FieldOption(id: "reading", label: "Reading nook", description: "Quiet relaxation spot"),
                    FieldOption(id: "plants", label: "Plant corner", description: "Urban gardening")
                ]
            )
        ],
        submitLabel: "Continue"
    )

    return ActionUIRenderer(schema: sampleSchema, response: $response) {
        print("Submitted: \(response)")
    }
    .frame(width: 400)
    .padding()
}
