import SwiftUI

enum DrawingTool: String, CaseIterable {
    case freehand = "pencil"
    case line = "line.diagonal"
    case arrow = "arrow.right"
    case rectangle = "rectangle"
    case circle = "circle"
    case eraser = "eraser"

    var label: String {
        switch self {
        case .freehand: return "Draw"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .eraser: return "Eraser"
        }
    }
}

struct DrawingElement: Identifiable {
    let id = UUID()
    var type: DrawingTool
    var points: [CGPoint]
    var startPoint: CGPoint
    var endPoint: CGPoint

    init(type: DrawingTool, points: [CGPoint] = [], startPoint: CGPoint = .zero, endPoint: CGPoint = .zero) {
        self.type = type
        self.points = points
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
}

struct DrawingCanvasRenderer: View {
    let field: ActionField
    @Binding var response: ActionResponse
    @Environment(\.phaseColor) private var phaseColor

    @State private var elements: [DrawingElement] = []
    @State private var currentElement: DrawingElement?
    @State private var selectedTool: DrawingTool = .freehand
    @State private var textAnnotations: [TextAnnotation] = []
    @State private var showingTextInput = false
    @State private var newAnnotationText = ""
    @State private var tapLocation: CGPoint = .zero
    @State private var canvasSize: CGSize = CGSize(width: 800, height: 400)

    struct TextAnnotation: Identifiable {
        let id = UUID()
        var position: CGPoint
        var text: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tool palette
            HStack(spacing: 4) {
                ForEach(DrawingTool.allCases, id: \.self) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        Image(systemName: tool.rawValue)
                            .font(.system(size: 16))
                            .frame(width: 36, height: 28)
                            .background(selectedTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
                            .foregroundColor(selectedTool == tool ? .accentColor : .secondary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(tool.label)
                }

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 8)

                Button {
                    tapLocation = CGPoint(x: 100, y: 100)
                    showingTextInput = true
                } label: {
                    Image(systemName: "textformat")
                        .font(.system(size: 16))
                        .frame(width: 36, height: 28)
                        .foregroundColor(.secondary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Add Label")

                Spacer()

                Button {
                    if !elements.isEmpty {
                        elements.removeLast()
                        saveDrawing()
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14))
                        .foregroundColor(elements.isEmpty ? .secondary.opacity(0.5) : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(elements.isEmpty)
                .help("Undo")

                Button {
                    elements = []
                    textAnnotations = []
                    saveDrawing()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear All")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(phaseColor.opacity(0.18))
            .cornerRadius(8)

            ZStack {
                // Canvas background
                phaseColor.opacity(0.25)

                // Drawing layer
                Canvas { context, size in
                    // Draw all completed elements
                    for element in elements {
                        drawElement(element, in: &context)
                    }

                    // Draw current element being created
                    if let current = currentElement {
                        drawElement(current, in: &context)
                    }
                }

                // Text annotations overlay
                ForEach(textAnnotations) { annotation in
                    Text(annotation.text)
                        .font(.system(size: Theme.fontSize, weight: .medium))
                        .padding(6)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                        )
                        .position(annotation.position)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if let index = textAnnotations.firstIndex(where: { $0.id == annotation.id }) {
                                        textAnnotations[index].position = value.location
                                    }
                                }
                                .onEnded { _ in
                                    saveDrawing()
                                }
                        )
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                textAnnotations.removeAll { $0.id == annotation.id }
                                saveDrawing()
                            }
                        }
                }
            }
            .frame(height: 400)
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
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDragChanged(value)
                    }
                    .onEnded { value in
                        handleDragEnded(value)
                    }
            )
            .onTapGesture(count: 2) { location in
                tapLocation = location
                showingTextInput = true
            }

            if let placeholder = field.placeholder {
                Text(placeholder)
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingTextInput) {
            VStack(spacing: 16) {
                Text("Add Label")
                    .font(.headline)

                TextField("Enter text", text: $newAnnotationText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                HStack {
                    Button("Cancel") {
                        newAnnotationText = ""
                        showingTextInput = false
                    }

                    Button("Add") {
                        if !newAnnotationText.isEmpty {
                            textAnnotations.append(TextAnnotation(
                                position: tapLocation,
                                text: newAnnotationText
                            ))
                            saveDrawing()
                            newAnnotationText = ""
                        }
                        showingTextInput = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        switch selectedTool {
        case .freehand:
            if currentElement == nil {
                currentElement = DrawingElement(type: .freehand, points: [value.startLocation])
            }
            currentElement?.points.append(value.location)

        case .eraser:
            eraseAt(value.location)

        case .line, .arrow, .rectangle, .circle:
            if currentElement == nil {
                currentElement = DrawingElement(type: selectedTool, startPoint: value.startLocation, endPoint: value.location)
            } else {
                currentElement?.endPoint = value.location
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        if selectedTool == .eraser {
            return
        }

        if var element = currentElement {
            if selectedTool == .freehand {
                if element.points.count > 1 {
                    elements.append(element)
                }
            } else {
                element.endPoint = value.location
                elements.append(element)
            }
            currentElement = nil
            saveDrawing()
        }
    }

    private func eraseAt(_ point: CGPoint) {
        let eraseRadius: CGFloat = 20

        elements.removeAll { element in
            switch element.type {
            case .freehand:
                return element.points.contains { p in
                    distance(p, point) < eraseRadius
                }
            case .line, .arrow:
                return distanceToLine(point, from: element.startPoint, to: element.endPoint) < eraseRadius
            case .rectangle:
                let rect = CGRect(
                    x: min(element.startPoint.x, element.endPoint.x),
                    y: min(element.startPoint.y, element.endPoint.y),
                    width: abs(element.endPoint.x - element.startPoint.x),
                    height: abs(element.endPoint.y - element.startPoint.y)
                )
                return rect.insetBy(dx: -eraseRadius, dy: -eraseRadius).contains(point)
            case .circle:
                let center = CGPoint(
                    x: (element.startPoint.x + element.endPoint.x) / 2,
                    y: (element.startPoint.y + element.endPoint.y) / 2
                )
                let radiusX = abs(element.endPoint.x - element.startPoint.x) / 2
                let radiusY = abs(element.endPoint.y - element.startPoint.y) / 2
                let avgRadius = (radiusX + radiusY) / 2
                let dist = distance(point, center)
                return abs(dist - avgRadius) < eraseRadius
            case .eraser:
                return false
            }
        }
        saveDrawing()
    }

    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        sqrt(pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2))
    }

    private func distanceToLine(_ point: CGPoint, from start: CGPoint, to end: CGPoint) -> CGFloat {
        let lineLength = distance(start, end)
        if lineLength == 0 { return distance(point, start) }

        let t = max(0, min(1, ((point.x - start.x) * (end.x - start.x) + (point.y - start.y) * (end.y - start.y)) / pow(lineLength, 2)))
        let projection = CGPoint(
            x: start.x + t * (end.x - start.x),
            y: start.y + t * (end.y - start.y)
        )
        return distance(point, projection)
    }

    private func drawElement(_ element: DrawingElement, in context: inout GraphicsContext) {
        let strokeColor = Color.primary
        let lineWidth: CGFloat = 2

        switch element.type {
        case .freehand:
            var path = Path()
            if let first = element.points.first {
                path.move(to: first)
                for point in element.points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

        case .line:
            var path = Path()
            path.move(to: element.startPoint)
            path.addLine(to: element.endPoint)
            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

        case .arrow:
            var path = Path()
            path.move(to: element.startPoint)
            path.addLine(to: element.endPoint)

            // Draw arrowhead
            let angle = atan2(element.endPoint.y - element.startPoint.y, element.endPoint.x - element.startPoint.x)
            let arrowLength: CGFloat = 12
            let arrowAngle: CGFloat = .pi / 6

            let point1 = CGPoint(
                x: element.endPoint.x - arrowLength * cos(angle - arrowAngle),
                y: element.endPoint.y - arrowLength * sin(angle - arrowAngle)
            )
            let point2 = CGPoint(
                x: element.endPoint.x - arrowLength * cos(angle + arrowAngle),
                y: element.endPoint.y - arrowLength * sin(angle + arrowAngle)
            )

            path.move(to: element.endPoint)
            path.addLine(to: point1)
            path.move(to: element.endPoint)
            path.addLine(to: point2)

            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

        case .rectangle:
            let rect = CGRect(
                x: min(element.startPoint.x, element.endPoint.x),
                y: min(element.startPoint.y, element.endPoint.y),
                width: abs(element.endPoint.x - element.startPoint.x),
                height: abs(element.endPoint.y - element.startPoint.y)
            )
            let path = Path(rect)
            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

        case .circle:
            let rect = CGRect(
                x: min(element.startPoint.x, element.endPoint.x),
                y: min(element.startPoint.y, element.endPoint.y),
                width: abs(element.endPoint.x - element.startPoint.x),
                height: abs(element.endPoint.y - element.startPoint.y)
            )
            let path = Path(ellipseIn: rect)
            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

        case .eraser:
            break
        }
    }

    private func saveDrawing() {
        // Always generate text description with labels for AI to read
        var shapeCounts: [String: Int] = [:]
        for element in elements {
            shapeCounts[element.type.label, default: 0] += 1
        }

        var parts: [String] = []
        for (shape, count) in shapeCounts.sorted(by: { $0.key < $1.key }) {
            parts.append("\(count) \(shape.lowercased())\(count > 1 ? "s" : "")")
        }

        var description = parts.isEmpty ? "Empty drawing" : "Drawing with \(parts.joined(separator: ", "))"
        if !textAnnotations.isEmpty {
            let labels = textAnnotations.map { $0.text }.joined(separator: ", ")
            description += ". Labels: \(labels)"
        }

        // Snapshot the canvas as PNG so the wiki can embed the image and the AI can see it.
        // The text description rides along inside the .image case so the AI can read the labels.
        if (!elements.isEmpty || !textAnnotations.isEmpty), let png = renderCanvasPNG() {
            response[field.id] = .image(png: png, description: description)
        } else {
            response[field.id] = .string(description)
        }
    }

    @MainActor
    private func renderCanvasPNG() -> Data? {
        // Use the actual size the user was drawing on so element coordinates line up perfectly,
        // and clip so anything pulled past the edges (e.g. dragged labels) isn't captured.
        let width = max(canvasSize.width, 100)
        let height = max(canvasSize.height, 100)

        let snapshot = DrawingCanvasSnapshot(
            elements: elements,
            textAnnotations: textAnnotations,
            drawElement: { element, context in
                self.drawElement(element, in: &context)
            }
        )
        .frame(width: width, height: height)
        .clipped()

        let renderer = ImageRenderer(content: snapshot)
        renderer.scale = 2.0
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
    }
}

struct DrawingCanvasSnapshot: View {
    let elements: [DrawingElement]
    let textAnnotations: [DrawingCanvasRenderer.TextAnnotation]
    let drawElement: (DrawingElement, inout GraphicsContext) -> Void

    var body: some View {
        ZStack {
            Color(.textBackgroundColor)

            Canvas { context, size in
                for element in elements {
                    drawElement(element, &context)
                }
            }

            ForEach(textAnnotations) { annotation in
                Text(annotation.text)
                    .font(.system(size: Theme.fontSize, weight: .medium))
                    .padding(6)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                    )
                    .position(annotation.position)
            }
        }
        .clipped()
    }
}

#Preview {
    @Previewable @State var response = ActionResponse()

    let sampleSchema = ActionSchema(
        type: .form,
        title: "How do you want to use the balcony?",
        description: "Select all that apply",
        fields: [
            ActionField(
                id: "uses",
                type: .multiSelect,
                label: "Intended uses",
                options: [
                    FieldOption(id: "coffee", label: "Morning coffee", description: "Start your day outside"),
                    FieldOption(id: "dinner", label: "Evening dinners", description: "Al fresco dining"),
                    FieldOption(id: "reading", label: "Reading nook", description: "Quiet relaxation spot"),
                    FieldOption(id: "plants", label: "Plant corner", description: "Urban gardening")
                ]
            )
        ],
        submitLabel: "Continue"
    )

    return ActionUIRenderer(schema: sampleSchema, response: $response) {
        print("Submitted: \(response)")
    }
    .frame(width: 400)
    .padding()
}
