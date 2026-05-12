import SwiftUI

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

