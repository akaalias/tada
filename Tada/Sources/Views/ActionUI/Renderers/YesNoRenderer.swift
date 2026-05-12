import SwiftUI

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

