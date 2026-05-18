import SwiftUI

struct ItemTableRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse
    @Environment(\.phaseColor) private var phaseColor

    private let gridLineColor = Color.white.opacity(0.15)

    @State private var rows: [TableRow] = [TableRow()]
    @State private var customCategories: [String: [String]] = [:]  // columnId -> custom categories
    @State private var showingNewCategoryInput: String? = nil  // columnId being edited
    @State private var newCategoryText = ""

    struct TableRow: Identifiable {
        let id = UUID()
        var values: [String: String] = [:]
    }

    // Parse column definitions from options, or use defaults
    private var columns: [TableColumn] {
        if let options = field.options, !options.isEmpty {
            return options.map { option in
                TableColumn(
                    id: option.id,
                    label: option.label,
                    type: parseColumnType(option.description)
                )
            }
        }
        // Default: Item + Amount
        return [
            TableColumn(id: "item", label: "Item", type: .text),
            TableColumn(id: "amount", label: "Amount", type: .currency)
        ]
    }

    struct TableColumn {
        let id: String
        let label: String
        let type: ColumnType
    }

    enum ColumnType {
        case text
        case currency
        case select([String])
        case category
    }

    private func parseColumnType(_ description: String?) -> ColumnType {
        guard let desc = description?.lowercased() else { return .text }
        if desc == "currency" || desc == "amount" || desc == "price" || desc == "cost" {
            return .currency
        }
        if desc == "category" {
            return .category
        }
        if desc.hasPrefix("select:") {
            let choices = String(desc.dropFirst(7)).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            return .select(choices)
        }
        return .text
    }

    private var hasCurrencyColumn: Bool {
        columns.contains { if case .currency = $0.type { return true }; return false }
    }

    private var totalAmount: Double {
        rows.reduce(0) { total, row in
            columns.reduce(total) { colTotal, col in
                if case .currency = col.type {
                    return colTotal + (Double(row.values[col.id] ?? "0") ?? 0)
                }
                return colTotal
            }
        }
    }

    private var filledRowCount: Int {
        rows.filter { row in
            columns.first.map { row.values[$0.id]?.isEmpty == false } ?? false
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    if index > 0 {
                        Rectangle().fill(gridLineColor).frame(width: 1, height: 36)
                    }
                    Text(column.label)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: index == 0 ? .infinity : nil, alignment: .leading)
                        .frame(width: index == 0 ? nil : columnWidth(for: column))
                        .frame(minWidth: index == 0 ? 120 : nil)
                }
                Color.clear.frame(width: 36)
            }
            .background(phaseColor.opacity(0.18))
            .cornerRadius(8, corners: [.topLeft, .topRight])

            Rectangle().fill(gridLineColor).frame(height: 1)

            // Data rows
            ForEach($rows) { $row in
                HStack(spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                        if index > 0 {
                            Rectangle().fill(gridLineColor).frame(width: 1, height: 36)
                        }
                        columnCell(for: column, row: $row, isFirst: index == 0)
                    }

                    Button {
                        if rows.count > 1 {
                            rows.removeAll { $0.id == row.id }
                            saveResponse()
                        }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundColor(rows.count > 1 ? .red.opacity(0.7) : .gray.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 36)
                    .disabled(rows.count <= 1)
                }
                .background(phaseColor.opacity(0.25))

                Rectangle().fill(gridLineColor).frame(height: 1)
            }

            // Add row button
            Button {
                rows.append(TableRow())
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Add row")
                }
                .font(.system(size: Theme.fontSize))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(phaseColor.opacity(0.25))

            Rectangle().fill(gridLineColor).frame(height: 1)

            // Summary row
            HStack(spacing: 0) {
                Text("\(filledRowCount) item\(filledRowCount == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                if hasCurrencyColumn {
                    Text("€\(totalAmount, specifier: "%.0f")")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 120, alignment: .trailing)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                Color.clear.frame(width: 36)
            }
            .background(phaseColor.opacity(0.18))
            .cornerRadius(8, corners: [.bottomLeft, .bottomRight])
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(gridLineColor, lineWidth: 1)
        )
        .onAppear {
            // Initialize with prefill data if available
            if rows.count == 1 && rows[0].values.isEmpty, let prefill = field.prefillRows, !prefill.isEmpty {
                rows = prefill.map { dict in
                    var row = TableRow()
                    row.values = dict
                    return row
                }
                // Add an empty row at the end for new entries
                rows.append(TableRow())
            }
            saveResponse()
        }
        .sheet(isPresented: Binding(
            get: { showingNewCategoryInput != nil },
            set: { if !$0 { showingNewCategoryInput = nil } }
        )) {
            VStack(spacing: 16) {
                Text("Add New Category")
                    .font(.headline)

                TextField("Category name", text: $newCategoryText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                HStack {
                    Button("Cancel") {
                        showingNewCategoryInput = nil
                        newCategoryText = ""
                    }

                    Button("Add") {
                        if !newCategoryText.isEmpty, let columnId = showingNewCategoryInput {
                            var existing = customCategories[columnId] ?? []
                            if !existing.contains(newCategoryText) {
                                existing.append(newCategoryText)
                                customCategories[columnId] = existing
                            }
                            newCategoryText = ""
                            showingNewCategoryInput = nil
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newCategoryText.isEmpty)
                }
            }
            .padding(20)
        }
    }

    private func columnWidth(for column: TableColumn) -> CGFloat {
        switch column.type {
        case .currency: return 130
        case .select: return 180
        case .category: return 180
        case .text: return 180
        }
    }

    @ViewBuilder
    private func columnCell(for column: TableColumn, row: Binding<TableRow>, isFirst: Bool) -> some View {
        let binding = Binding<String>(
            get: { row.wrappedValue.values[column.id] ?? "" },
            set: { row.wrappedValue.values[column.id] = $0; saveResponse() }
        )

        let cellContent = cellContentView(for: column, binding: binding, row: row)

        if isFirst {
            cellContent
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            cellContent
                .frame(width: columnWidth(for: column), alignment: .leading)
        }
    }

    @ViewBuilder
    private func cellContentView(for column: TableColumn, binding: Binding<String>, row: Binding<TableRow>) -> some View {
        switch column.type {
        case .text:
            TextField(column.label, text: binding)
                .textFieldStyle(.plain)
                .font(.system(size: Theme.fontSize))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

        case .currency:
            HStack(spacing: 4) {
                Text("€")
                    .foregroundColor(.secondary)
                TextField("0", text: binding)
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.fontSize))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

        case .select(let choices):
            let currentValue = row.wrappedValue.values[column.id] ?? ""
            let allChoices = choices + (customCategories[column.id] ?? [])

            HStack(spacing: 4) {
                Picker("", selection: Binding(
                    get: { currentValue },
                    set: { row.wrappedValue.values[column.id] = $0; saveResponse() }
                )) {
                    Text("Select...").tag("")
                    ForEach(allChoices, id: \.self) { choice in
                        Text(choice).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Button {
                    showingNewCategoryInput = column.id
                    newCategoryText = ""
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add new category")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

        case .category:
            CategoryCell(
                value: binding,
                existingCategories: existingCategoriesFor(column.id),
                onSave: saveResponse
            )
        }
    }

    private func existingCategoriesFor(_ columnId: String) -> [String] {
        Set(rows.compactMap { $0.values[columnId] }.filter { !$0.isEmpty }).sorted()
    }

    private func saveResponse() {
        let filledRows = rows.filter { row in
            columns.first.map { row.values[$0.id]?.isEmpty == false } ?? false
        }

        let tableColumns = columns.map { col -> TableData.Column in
            let typeString: String
            switch col.type {
            case .text: typeString = "text"
            case .currency: typeString = "currency"
            case .category: typeString = "category"
            case .select: typeString = "select"
            }
            return TableData.Column(id: col.id, label: col.label, type: typeString)
        }

        response[field.id] = .table(TableData(
            columns: tableColumns,
            rows: filledRows.map { $0.values },
            total: hasCurrencyColumn ? Int(totalAmount) : 0,
            hasCurrency: hasCurrencyColumn
        ))
    }
}

struct CategoryCell: View {
    @Binding var value: String
    let existingCategories: [String]
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            TextField("Category", text: $value)
                .textFieldStyle(.plain)
                .font(.system(size: Theme.fontSize))
                .onChange(of: value) { _, _ in onSave() }

            if !existingCategories.isEmpty {
                Menu {
                    ForEach(existingCategories, id: \.self) { category in
                        Button(category) {
                            value = category
                            onSave()
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// Helper for rounded corners on specific sides
extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: RectCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        return path
    }
}
