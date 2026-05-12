import SwiftUI

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

