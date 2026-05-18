import SwiftUI

struct RangeSliderRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

    @State private var lowerValue: Double = 0
    @State private var upperValue: Double = 100

    private var minValue: Double {
        field.validation?.minValue ?? 0
    }

    private var maxValue: Double {
        field.validation?.maxValue ?? 1000
    }

    private var stepSize: Double {
        let range = maxValue - minValue
        if range <= 10 { return 1 }
        if range <= 100 { return 5 }
        if range <= 1000 { return 50 }
        return 100
    }

    private func roundToStep(_ value: Double) -> Double {
        (value / stepSize).rounded() * stepSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Min")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("\(Int(roundToStep(lowerValue)))")
                        .font(.system(size: 24, weight: .semibold))
                        .monospacedDigit()
                }

                Spacer()

                Text("to")
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Max")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("\(Int(roundToStep(upperValue)))")
                        .font(.system(size: 24, weight: .semibold))
                        .monospacedDigit()
                }
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let lowerX = CGFloat((lowerValue - minValue) / (maxValue - minValue)) * width
                let upperX = CGFloat((upperValue - minValue) / (maxValue - minValue)) * width

                ZStack {
                    // Gray track
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)

                    // Blue range bar - positioned absolutely
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: upperX - lowerX, height: 6)
                        .position(x: (lowerX + upperX) / 2, y: 12)

                    // Lower handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                        .position(x: lowerX, y: 12)
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    let newX = min(max(gesture.location.x, 0), upperX - 20)
                                    lowerValue = minValue + Double(newX / width) * (maxValue - minValue)
                                    updateResponse()
                                }
                        )

                    // Upper handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                        .position(x: upperX, y: 12)
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    let newX = max(min(gesture.location.x, width), lowerX + 20)
                                    upperValue = minValue + Double(newX / width) * (maxValue - minValue)
                                    updateResponse()
                                }
                        )
                }
            }
            .frame(height: 24)

            HStack {
                Text("\(Int(minValue))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(maxValue))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            let range = maxValue - minValue
            lowerValue = minValue + range * 0.25
            upperValue = minValue + range * 0.75
            updateResponse()
        }
    }

    private func updateResponse() {
        let lower = roundToStep(lowerValue)
        let upper = roundToStep(upperValue)
        response[field.id] = .range(lower: lower, upper: upper)
    }
}

