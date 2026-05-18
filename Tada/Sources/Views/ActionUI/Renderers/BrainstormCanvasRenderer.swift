import SwiftUI

// MARK: - Model

/// A single term placed on the brainstorm canvas. `position` is in canvas
/// (content) coordinates, independent of the current zoom/pan.
struct BrainstormLabel: Identifiable, Equatable {
    let id: UUID
    var text: String
    var position: CGPoint
    var color: BrainstormLabelColor

    init(id: UUID = UUID(), text: String, position: CGPoint, color: BrainstormLabelColor = .yellow) {
        self.id = id
        self.text = text
        self.position = position
        self.color = color
    }
}

enum BrainstormLabelColor: String, CaseIterable {
    case yellow, blue, green, pink

    var background: Color {
        switch self {
        case .yellow: return Color.yellow.opacity(0.3)
        case .blue: return Color.blue.opacity(0.3)
        case .green: return Color.green.opacity(0.3)
        case .pink: return Color.pink.opacity(0.3)
        }
    }

    var border: Color {
        switch self {
        case .yellow: return Color.yellow.opacity(0.6)
        case .blue: return Color.blue.opacity(0.6)
        case .green: return Color.green.opacity(0.6)
        case .pink: return Color.pink.opacity(0.6)
        }
    }

    var swatch: Color {
        switch self {
        case .yellow: return Color.yellow
        case .blue: return Color.blue
        case .green: return Color.green
        case .pink: return Color.pink
        }
    }
}

/// Pure state + logic for a brainstorm board, kept separate from the view so
/// it can be unit-tested.
struct BrainstormBoard: Equatable {
    var labels: [BrainstormLabel] = []

    @discardableResult
    mutating func addLabel(_ text: String, at position: CGPoint, color: BrainstormLabelColor = .yellow) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        labels.append(BrainstormLabel(text: trimmed, position: position, color: color))
        return true
    }

    mutating func moveLabel(id: UUID, to position: CGPoint) {
        guard let index = labels.firstIndex(where: { $0.id == id }) else { return }
        labels[index].position = position
    }

    mutating func removeLabel(id: UUID) {
        labels.removeAll { $0.id == id }
    }

    /// Human-readable summary of every term, used as the saved response value.
    var summary: String {
        guard !labels.isEmpty else { return "Empty brainstorm" }
        let terms = labels.map(\.text).joined(separator: ", ")
        return "Brainstorm with \(labels.count) term\(labels.count == 1 ? "" : "s"): \(terms)"
    }
}

enum BrainstormCanvas {
    /// A random point inside `bounds`, kept `margin` away from every edge so
    /// freshly added labels never sit half off-screen. Degrades gracefully
    /// when `bounds` is smaller than twice the margin.
    static func randomPosition(in bounds: CGRect, margin: CGFloat = 60) -> CGPoint {
        let minX = bounds.minX + margin
        let maxX = max(minX, bounds.maxX - margin)
        let minY = bounds.minY + margin
        let maxY = max(minY, bounds.maxY - margin)
        return CGPoint(
            x: CGFloat.random(in: minX...maxX),
            y: CGFloat.random(in: minY...maxY)
        )
    }
}

// MARK: - Renderer

struct BrainstormCanvasRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse
    @Environment(\.phaseColor) private var phaseColor

    @State private var board = BrainstormBoard()
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    @State private var zoom: CGFloat = 1.0
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize = .zero
    @State private var zoomStart: CGFloat = 1.0
    @State private var canvasSize: CGSize = CGSize(width: 800, height: 400)
    @State private var dragStartPositions: [UUID: CGPoint] = [:]
    @State private var selectedColor: BrainstormLabelColor = .yellow

    private let canvasHeight: CGFloat = 400
    private let minZoom: CGFloat = 0.25
    private let maxZoom: CGFloat = 3.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            canvas
            if let placeholder = field.placeholder {
                Text(placeholder)
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear { inputFocused = true }
    }

    // MARK: Input Toolbar

    private var inputToolbar: some View {
        HStack(spacing: 8) {
            TextField("Type a term and press Return…", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: Theme.fontSize))
                .focused($inputFocused)
                .onSubmit(addCurrentTerm)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial)
                .cornerRadius(6)
                .accessibilityIdentifier("brainstorm.input")

            ForEach(BrainstormLabelColor.allCases, id: \.self) { color in
                Button {
                    selectedColor = color
                } label: {
                    Circle()
                        .fill(color.swatch)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: selectedColor == color ? 2 : 0)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.regularMaterial)
        .cornerRadius(8)
    }

    private func addCurrentTerm() {
        let visibleBounds = CGRect(origin: .zero, size: canvasSize)
        let screenPoint = BrainstormCanvas.randomPosition(in: visibleBounds)
        let added = board.addLabel(inputText, at: contentPoint(fromScreen: screenPoint), color: selectedColor)
        guard added else { return }
        inputText = ""
        inputFocused = true
        saveBoard()
    }

    // MARK: Canvas

    private var canvas: some View {
        ZStack {
            phaseColor.opacity(0.18)

            contentLayer
                .scaleEffect(zoom)
                .offset(pan)
        }
        .frame(height: canvasHeight)
        .clipped()
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { canvasSize = proxy.size }
                    .onChange(of: proxy.size) { _, newSize in canvasSize = newSize }
            }
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            inputToolbar
                .padding(8)
        }
        .overlay(alignment: .bottomTrailing) { zoomControls }
        .gesture(panGesture)
        .gesture(magnifyGesture)
    }

    private var contentLayer: some View {
        ZStack {
            ForEach(board.labels) { label in
                labelView(label)
            }
        }
        .frame(width: canvasSize.width, height: canvasHeight)
    }

    private func labelView(_ label: BrainstormLabel) -> some View {
        Text(label.text)
            .font(.system(size: Theme.fontSize, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(label.color.background)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(label.color.border, lineWidth: 1)
            )
            .position(label.position)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartPositions[label.id] == nil {
                            dragStartPositions[label.id] = label.position
                        }
                        let origin = dragStartPositions[label.id]!
                        board.moveLabel(
                            id: label.id,
                            to: CGPoint(
                                x: origin.x + value.translation.width,
                                y: origin.y + value.translation.height
                            )
                        )
                    }
                    .onEnded { _ in
                        dragStartPositions.removeValue(forKey: label.id)
                        saveBoard()
                    }
            )
            .contextMenu {
                Button("Delete", role: .destructive) {
                    board.removeLabel(id: label.id)
                    saveBoard()
                }
            }
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            zoomButton("minus.magnifyingglass") { setZoom(zoom / 1.25) }
            Text("\(Int(zoom * 100))%")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(minWidth: 40)
            zoomButton("plus.magnifyingglass") { setZoom(zoom * 1.25) }
            zoomButton("arrow.counterclockwise") {
                withAnimation(.easeOut(duration: 0.15)) {
                    zoom = 1.0
                    pan = .zero
                }
            }
        }
        .padding(4)
        .background(.regularMaterial)
        .cornerRadius(8)
        .padding(8)
    }

    private func zoomButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 26, height: 22)
        }
        .buttonStyle(.plain)
    }

    // MARK: Gestures

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                pan = CGSize(
                    width: panStart.width + value.translation.width,
                    height: panStart.height + value.translation.height
                )
            }
            .onEnded { _ in panStart = pan }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in setZoom(zoomStart * value) }
            .onEnded { _ in zoomStart = zoom }
    }

    private func setZoom(_ newValue: CGFloat) {
        zoom = min(maxZoom, max(minZoom, newValue))
        zoomStart = zoom
    }

    // MARK: Coordinate conversion

    /// Converts a point in the visible canvas (screen space) into the
    /// content-layer coordinate space, accounting for the current zoom and pan.
    /// `scaleEffect` uses the view's centre as its anchor.
    private func contentPoint(fromScreen screen: CGPoint) -> CGPoint {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasHeight / 2)
        return CGPoint(
            x: (screen.x - center.x - pan.width) / zoom + center.x,
            y: (screen.y - center.y - pan.height) / zoom + center.y
        )
    }

    // MARK: Persistence

    private func saveBoard() {
        response[field.id] = .string(board.summary)
        if board.labels.isEmpty {
            response[field.id + "_image"] = nil
        } else if let dataURL = renderBoardPNG() {
            response[field.id + "_image"] = .string(dataURL)
        }
    }

    @MainActor
    private func renderBoardPNG() -> String? {
        let snapshot = BrainstormBoardSnapshot(labels: board.labels)
        let renderer = ImageRenderer(content: snapshot)
        renderer.scale = 2.0
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return "data:image/png;base64,\(pngData.base64EncodedString())"
    }
}

// MARK: - Snapshot

/// Renders the brainstorm board into a fixed image — sized to the bounding box
/// of every label — so the wiki can embed it and the AI can read the layout.
struct BrainstormBoardSnapshot: View {
    let labels: [BrainstormLabel]

    private let padding: CGFloat = 80

    private var bounds: CGRect {
        guard let first = labels.first else {
            return CGRect(x: 0, y: 0, width: 400, height: 300)
        }
        var rect = CGRect(origin: first.position, size: .zero)
        for label in labels.dropFirst() {
            rect = rect.union(CGRect(origin: label.position, size: .zero))
        }
        return rect.insetBy(dx: -padding, dy: -padding)
    }

    var body: some View {
        let frame = bounds
        return ZStack {
            Color(.textBackgroundColor)

            ForEach(labels) { label in
                Text(label.text)
                    .font(.system(size: Theme.fontSize, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(label.color.background)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(label.color.border, lineWidth: 1)
                    )
                    .position(
                        x: label.position.x - frame.minX,
                        y: label.position.y - frame.minY
                    )
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipped()
    }
}

#Preview {
    @Previewable @State var response = ActionResponse()

    let schema = ActionSchema(
        type: .form,
        title: "Brainstorm",
        description: "Type terms and press Return to scatter them on the canvas.",
        fields: [
            ActionField(id: "ideas", type: .brainstorm, label: "Ideas", placeholder: "Drag to group. Pinch or use the controls to zoom.")
        ],
        submitLabel: "Done"
    )

    return ActionUIRenderer(schema: schema, response: $response) {
        print("Submitted: \(response)")
    }
    .frame(width: 600)
    .padding()
}
