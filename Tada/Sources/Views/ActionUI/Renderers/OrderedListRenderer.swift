import SwiftUI
import UniformTypeIdentifiers

struct OrderedListRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse
    @Environment(\.phaseColor) private var phaseColor

    @State private var items: [OrderedItem] = []
    @State private var draggingItem: OrderedItem?
    @State private var newItemText = ""
    @State private var isAddingItem = false

    struct OrderedItem: Identifiable, Equatable {
        let id = UUID()
        var label: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(for: item, position: index + 1)
                    .onDrag {
                        draggingItem = item
                        return NSItemProvider(object: item.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: OrderedDropDelegate(
                        target: item,
                        items: $items,
                        draggingItem: $draggingItem,
                        onReorder: saveResponse
                    ))
            }

            if isAddingItem {
                addItemRow
            } else {
                Button {
                    isAddingItem = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.secondary)
                            .font(.system(size: Theme.fontSize))
                        Text("Add an item")
                            .font(.system(size: Theme.fontSize))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if !items.isEmpty {
                Text("Drag to reorder · \(items.count) item\(items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .onAppear(perform: loadInitialItems)
    }

    private func row(for item: OrderedItem, position: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
                .frame(width: 18)

            Text("\(position)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .frame(width: 22, alignment: .trailing)

            Text(item.label)
                .font(.system(size: Theme.fontSize))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if let idx = items.firstIndex(of: item) {
                    items.remove(at: idx)
                    saveResponse()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary.opacity(0.6))
                    .font(.system(size: Theme.fontSize))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .fieldChrome(phaseColor.opacity(draggingItem == item ? 0.45 : 0.25))
        .opacity(draggingItem == item ? 0.5 : 1.0)
    }

    private var addItemRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: Theme.fontSize))
                .frame(width: 18)

            TextField("Type a new step...", text: $newItemText, onCommit: addItem)
                .textFieldStyle(.plain)
                .font(.system(size: Theme.fontSize))

            Button("Add", action: addItem)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(newItemText.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                newItemText = ""
                isAddingItem = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary.opacity(0.6))
                    .font(.system(size: Theme.fontSize))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(phaseColor.opacity(0.15))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    private func addItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        items.append(OrderedItem(label: trimmed))
        newItemText = ""
        isAddingItem = false
        saveResponse()
    }

    private func loadInitialItems() {
        guard items.isEmpty else { return }

        if let options = field.options, !options.isEmpty {
            items = options.map { OrderedItem(label: $0.label) }
        } else if let prefill = field.prefillRows, !prefill.isEmpty {
            items = prefill.compactMap { dict in
                let value = dict["item"] ?? dict.values.first
                guard let label = value?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else { return nil }
                return OrderedItem(label: label)
            }
        } else if let defaultValue = field.defaultValue, !defaultValue.isEmpty {
            items = defaultValue
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { OrderedItem(label: $0) }
        }

        saveResponse()
    }

    private func saveResponse() {
        response[field.id] = .stringArray(items.map(\.label))
    }
}

private struct OrderedDropDelegate: DropDelegate {
    let target: OrderedListRenderer.OrderedItem
    @Binding var items: [OrderedListRenderer.OrderedItem]
    @Binding var draggingItem: OrderedListRenderer.OrderedItem?
    let onReorder: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingItem,
              dragging != target,
              let from = items.firstIndex(of: dragging),
              let to = items.firstIndex(of: target) else { return }

        if items[to] != dragging {
            withAnimation(.easeInOut(duration: 0.15)) {
                items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        onReorder()
        return true
    }
}
