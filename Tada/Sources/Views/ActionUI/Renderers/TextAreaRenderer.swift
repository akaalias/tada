import SwiftUI

struct TextAreaRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse
    @Environment(\.phaseColor) private var phaseColor

    @State private var text = ""

    private let minHeight: CGFloat = 160
    private let lineHeight: CGFloat = 22
    private let verticalPadding: CGFloat = 24

    private var calculatedHeight: CGFloat {
        let lineCount = max(1, text.components(separatedBy: "\n").count)
        let contentHeight = CGFloat(lineCount) * lineHeight + verticalPadding
        return max(minHeight, contentHeight)
    }

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
        .frame(height: calculatedHeight)
        .background(phaseColor.opacity(0.25))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: calculatedHeight)
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

