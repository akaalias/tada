import SwiftUI

struct NumberFieldRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse
    @Environment(\.phaseColor) private var phaseColor

    @State private var number: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            TextField(field.placeholder ?? "0", value: $number, format: .number)
                .font(.system(size: Theme.fontSize))
                .textFieldStyle(.plain)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(phaseColor.opacity(0.25))
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

