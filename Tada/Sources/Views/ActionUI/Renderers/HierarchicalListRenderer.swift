import SwiftUI
import UniformTypeIdentifiers

struct HierarchicalListRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse
    @Environment(\.phaseColor) private var phaseColor

    @State private var items: [TreeItem] = []
    @State private var draggingItem: TreeItem?
    @State private var nestTargetID: UUID?
    @State private var newItemText = ""
    @State private var isAddingItem = false

    private let nestThreshold: CGFloat = 80

    struct TreeItem: Identifiable, Equatable {
        let id = UUID()
        var label: String
        var depth: Int
    }

    private let indentWidth: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(for: item, at: index)
                    .onDrag {
                        draggingItem = item
                        return NSItemProvider(object: item.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: TreeDropDelegate(
                        target: item,
                        items: $items,
                        draggingItem: $draggingItem,
                        nestTargetID: $nestTargetID,
                        nestThreshold: nestThreshold,
                        onReorder: normalizeAndSave
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
                Text("Drag to reorder · Use ← → to nest · \(items.count) item\(items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .onAppear(perform: loadInitialItems)
    }

    private func row(for item: TreeItem, at index: Int) -> some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: CGFloat(item.depth) * indentWidth, height: 1)

            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
                .frame(width: 18)

            Image(systemName: item.depth == 0 ? "circle.fill" : "arrow.turn.down.right")
                .foregroundColor(.secondary.opacity(0.7))
                .font(.system(size: item.depth == 0 ? 6 : 11))
                .frame(width: 14)

            Text(item.label)
                .font(.system(size: Theme.fontSize))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                outdent(index: index)
            } label: {
                Image(systemName: "arrow.left")
                    .foregroundColor(canOutdent(index: index) ? .secondary : .secondary.opacity(0.3))
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!canOutdent(index: index))

            Button {
                indent(index: index)
            } label: {
                Image(systemName: "arrow.right")
                    .foregroundColor(canIndent(index: index) ? .secondary : .secondary.opacity(0.3))
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!canIndent(index: index))

            Button {
                items.remove(at: index)
                normalizeAndSave()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary.opacity(0.6))
                    .font(.system(size: Theme.fontSize))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground(for: item))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(nestTargetID == item.id ? Color.accentColor : Color.gray.opacity(0.3),
                        lineWidth: nestTargetID == item.id ? 2 : 1)
        )
        .opacity(draggingItem == item ? 0.5 : 1.0)
    }

    private func rowBackground(for item: TreeItem) -> Color {
        if nestTargetID == item.id { return Color.accentColor.opacity(0.35) }
        if draggingItem == item { return phaseColor.opacity(0.45) }
        return phaseColor.opacity(0.25)
    }

    private var addItemRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: Theme.fontSize))
                .frame(width: 18)

            TextField("Type a new item...", text: $newItemText, onCommit: addItem)
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

    // MARK: - Indent / outdent

    private func canIndent(index: Int) -> Bool {
        guard index > 0 else { return false }
        return items[index].depth <= items[index - 1].depth
    }

    private func canOutdent(index: Int) -> Bool {
        items[index].depth > 0
    }

    private func indent(index: Int) {
        guard canIndent(index: index) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            items[index].depth += 1
        }
        normalizeAndSave()
    }

    private func outdent(index: Int) {
        guard canOutdent(index: index) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            items[index].depth -= 1
        }
        normalizeAndSave()
    }

    // MARK: - Add / load / persist

    private func addItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let depth = items.last?.depth ?? 0
        items.append(TreeItem(label: trimmed, depth: depth))
        newItemText = ""
        isAddingItem = false
        normalizeAndSave()
    }

    private func loadInitialItems() {
        guard items.isEmpty else { return }

        if let prefill = field.prefillRows, !prefill.isEmpty {
            items = prefill.compactMap { dict in
                guard let label = (dict["item"] ?? dict.values.first)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !label.isEmpty else { return nil }
                let depth = Int(dict["depth"] ?? "0") ?? 0
                return TreeItem(label: label, depth: max(0, depth))
            }
        } else if let options = field.options, !options.isEmpty {
            items = options.map { TreeItem(label: $0.label, depth: 0) }
        } else if let defaultValue = field.defaultValue, !defaultValue.isEmpty {
            items = Self.parseIndentedText(defaultValue)
        }

        normalizeAndSave()
    }

    /// Static + internal so the indent parsing can be unit-tested without rendering.
    static func parseIndentedText(_ text: String) -> [TreeItem] {
        text.components(separatedBy: "\n").compactMap { rawLine in
            let leading = rawLine.prefix(while: { $0 == " " || $0 == "\t" }).count
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return TreeItem(label: trimmed, depth: leading / 2)
        }
    }

    private func normalizeAndSave() {
        if !items.isEmpty {
            items[0].depth = 0
        }
        for i in 1..<items.count {
            let maxAllowed = items[i - 1].depth + 1
            if items[i].depth > maxAllowed {
                items[i].depth = maxAllowed
            }
            if items[i].depth < 0 {
                items[i].depth = 0
            }
        }

        response[field.id] = .tree(items.map { TreeNode(label: $0.label, depth: $0.depth) })
    }
}

private struct TreeDropDelegate: DropDelegate {
    let target: HierarchicalListRenderer.TreeItem
    @Binding var items: [HierarchicalListRenderer.TreeItem]
    @Binding var draggingItem: HierarchicalListRenderer.TreeItem?
    @Binding var nestTargetID: UUID?
    let nestThreshold: CGFloat
    let onReorder: () -> Void

    func dropEntered(info: DropInfo) {
        guard info.location.x <= nestThreshold else { return }
        reorderUnderHover()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let dragging = draggingItem, dragging != target else {
            return DropProposal(operation: .move)
        }

        if info.location.x > nestThreshold {
            if nestTargetID != target.id {
                nestTargetID = target.id
            }
        } else {
            if nestTargetID == target.id {
                nestTargetID = nil
            }
            reorderUnderHover()
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if nestTargetID == target.id {
            nestTargetID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggingItem = nil
            nestTargetID = nil
        }

        if info.location.x > nestThreshold,
           let dragging = draggingItem,
           dragging != target,
           let draggingIdx = items.firstIndex(of: dragging),
           let targetIdx = items.firstIndex(of: target) {

            var moved = items.remove(at: draggingIdx)
            let adjustedTargetIdx = draggingIdx < targetIdx ? targetIdx - 1 : targetIdx
            moved.depth = items[adjustedTargetIdx].depth + 1
            items.insert(moved, at: adjustedTargetIdx + 1)
        }

        onReorder()
        return true
    }

    private func reorderUnderHover() {
        guard let dragging = draggingItem,
              dragging != target,
              let from = items.firstIndex(of: dragging),
              let to = items.firstIndex(of: target),
              items[to] != dragging else { return }

        withAnimation(.easeInOut(duration: 0.15)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }
}
