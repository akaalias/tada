import Foundation
import SwiftUI
import Testing
@testable import Tada

// MARK: - BrainstormLabelColor

@Test func brainstormLabelColor_all_cases() {
    #expect(BrainstormLabelColor.allCases.count == 4)
    #expect(BrainstormLabelColor(rawValue: "blue") == .blue)
}

@Test func brainstormLabelColor_provides_distinct_palette() {
    // Each case maps to background/border/swatch without crashing; swatches differ.
    let swatches = Set(BrainstormLabelColor.allCases.map { "\($0.swatch)" })
    #expect(swatches.count == BrainstormLabelColor.allCases.count)
    for color in BrainstormLabelColor.allCases {
        _ = color.background
        _ = color.border
        _ = color.swatch
    }
}

// MARK: - BrainstormBoard (extra coverage)

@Test func brainstormBoard_addLabel_with_color() {
    var board = BrainstormBoard()
    let added = board.addLabel("Solar", at: .zero, color: .green)
    #expect(added)
    #expect(board.labels.first?.color == .green)
}

@Test func brainstormBoard_removeLabel() {
    var board = BrainstormBoard()
    _ = board.addLabel("A", at: .zero)
    _ = board.addLabel("B", at: .zero)
    let firstId = board.labels[0].id

    board.removeLabel(id: firstId)
    #expect(board.labels.count == 1)
    #expect(board.labels.first?.text == "B")

    // Removing an unknown id is a no-op.
    board.removeLabel(id: UUID())
    #expect(board.labels.count == 1)
}

@Test func brainstormLabel_init_defaults_to_yellow() {
    let label = BrainstormLabel(text: "X", position: CGPoint(x: 1, y: 2))
    #expect(label.color == .yellow)
    #expect(label.text == "X")
}

// MARK: - DrawingTool / DrawingElement

@Test func drawingTool_cases_map_to_sfsymbols_and_labels() {
    #expect(DrawingTool.allCases.count == 6)
    #expect(DrawingTool.freehand.rawValue == "pencil")
    #expect(DrawingTool.eraser.rawValue == "eraser")
    #expect(DrawingTool.freehand.label == "Draw")
    #expect(DrawingTool.arrow.label == "Arrow")
    #expect(DrawingTool.rectangle.label == "Rectangle")
    // Every case has a non-empty label.
    for tool in DrawingTool.allCases {
        #expect(!tool.label.isEmpty)
    }
}

@Test func drawingElement_init_defaults() {
    let e = DrawingElement(type: .line)
    #expect(e.type == .line)
    #expect(e.points.isEmpty)
    #expect(e.startPoint == .zero)
    #expect(e.endPoint == .zero)

    let e2 = DrawingElement(type: .freehand, points: [CGPoint(x: 1, y: 1)], startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 2, y: 2))
    #expect(e2.points.count == 1)
    #expect(e2.endPoint == CGPoint(x: 2, y: 2))
}

// MARK: - ItemTableRenderer.parseColumnType

@Test func itemTable_parseColumnType_currency_synonyms() {
    for desc in ["currency", "amount", "price", "cost", "PRICE", "Cost"] {
        if case .currency = ItemTableRenderer.parseColumnType(desc) {} else {
            Issue.record("Expected currency for '\(desc)'")
        }
    }
}

@Test func itemTable_parseColumnType_category() {
    if case .category = ItemTableRenderer.parseColumnType("category") {} else {
        Issue.record("Expected category")
    }
}

@Test func itemTable_parseColumnType_select_parses_choices() {
    if case .select(let choices) = ItemTableRenderer.parseColumnType("select:Red, Green ,Blue") {
        #expect(choices == ["red", "green", "blue"])
    } else {
        Issue.record("Expected select")
    }
}

@Test func itemTable_parseColumnType_defaults_to_text() {
    if case .text = ItemTableRenderer.parseColumnType(nil) {} else { Issue.record("nil should be text") }
    if case .text = ItemTableRenderer.parseColumnType("freeform note") {} else { Issue.record("unknown should be text") }
}
