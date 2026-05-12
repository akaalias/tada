import SwiftUI

struct DateFieldRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse

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
            Menu {
                ForEach(1...daysInMonth, id: \.self) { day in
                    Button(String(day)) { selectedDay = day }
                }
            } label: {
                HStack {
                    Text(String(selectedDay))
                        .font(.system(size: Theme.fontSize))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(1...12, id: \.self) { month in
                    Button(months[month - 1]) { selectedMonth = month }
                }
            } label: {
                HStack {
                    Text(months[selectedMonth - 1])
                        .font(.system(size: Theme.fontSize))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(years, id: \.self) { year in
                    Button(String(year)) { selectedYear = year }
                }
            } label: {
                HStack {
                    Text(String(selectedYear))
                        .font(.system(size: Theme.fontSize))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .onChange(of: selectedDay) { _, _ in updateResponse() }
        .onChange(of: selectedMonth) { _, _ in updateResponse() }
        .onChange(of: selectedYear) { _, _ in updateResponse() }
        .onAppear { updateResponse() }
    }

    private func updateResponse() {
        response[field.id] = .date(selectedDate)
    }
}

