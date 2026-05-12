import SwiftUI

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

