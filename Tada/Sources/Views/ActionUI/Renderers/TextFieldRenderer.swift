import SwiftUI

struct TextFieldRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse
    @Environment(\.phaseColor) private var phaseColor

    @State private var text = ""

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty, let placeholder = field.placeholder {
                Text(placeholder)
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(Color(.placeholderTextColor))
                    .padding(.leading, 14)
            }

            TextField("", text: $text)
                .font(.system(size: Theme.fontSize))
                .textFieldStyle(.plain)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .accessibilityIdentifier("actionUI.field.\(field.id)")
        }
        .fieldChrome(phaseColor.opacity(0.25))
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

