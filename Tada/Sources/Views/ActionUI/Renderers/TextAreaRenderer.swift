import SwiftUI

struct TextAreaRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse
    @Environment(\.phaseColor) private var phaseColor

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
        .frame(height: 160)
        .background(phaseColor.opacity(0.25))
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

