import SwiftUI

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

