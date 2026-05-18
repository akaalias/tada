import SwiftUI

struct DateFieldRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse
    @Environment(\.phaseColor) private var phaseColor

    @State private var selectedDay: Int = Calendar.current.component(.day, from: Date())
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    private let months = ["January", "February", "March", "April", "May", "June",
                          "July", "August", "September", "October", "November", "December"]

    private var years: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array((currentYear - 1)...(currentYear + 5))
    }

    private var daysInMonth: Int {
        let components = DateComponents(year: selectedYear, month: selectedMonth)
        let calendar = Calendar.current
        if let date = calendar.date(from: components),
           let range = calendar.range(of: .day, in: .month, for: date) {
            return range.count
        }
        return 31
    }

    private var selectedDate: Date {
        let components = DateComponents(year: selectedYear, month: selectedMonth, day: min(selectedDay, daysInMonth))
        return Calendar.current.date(from: components) ?? Date()
    }

    var body: some View {
        HStack(spacing: 12) {
            pickerMenu(String(selectedDay)) {
                ForEach(1...daysInMonth, id: \.self) { day in
                    Button(String(day)) { selectedDay = day }
                }
            }

            pickerMenu(months[selectedMonth - 1]) {
                ForEach(1...12, id: \.self) { month in
                    Button(months[month - 1]) { selectedMonth = month }
                }
            }

            pickerMenu(String(selectedYear)) {
                ForEach(years, id: \.self) { year in
                    Button(String(year)) { selectedYear = year }
                }
            }
        }
        .onChange(of: selectedDay) { _, _ in updateResponse() }
        .onChange(of: selectedMonth) { _, _ in updateResponse() }
        .onChange(of: selectedYear) { _, _ in updateResponse() }
        .onAppear { updateResponse() }
    }

    /// A bordered dropdown showing `display`, with `items` as the menu content.
    @ViewBuilder
    private func pickerMenu<Content: View>(_ display: String, @ViewBuilder items: () -> Content) -> some View {
        Menu {
            items()
        } label: {
            HStack {
                Text(display)
                    .font(.system(size: Theme.fontSize))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .fieldChrome(phaseColor.opacity(0.25))
        }
        .buttonStyle(.plain)
    }

    private func updateResponse() {
        response[field.id] = .date(selectedDate)
    }
}

