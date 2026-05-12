import SwiftUI

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

