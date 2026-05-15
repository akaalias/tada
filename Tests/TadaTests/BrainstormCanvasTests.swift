import Foundation
import Testing

@testable import Tada

// MARK: - BrainstormBoard Tests

@Test func brainstormBoard_addLabel_appends_trimmed_term() {
    var board = BrainstormBoard()
    let added = board.addLabel("  Climate  ", at: CGPoint(x: 10, y: 20))

    #expect(added)
    #expect(board.labels.count == 1)
    #expect(board.labels[0].text == "Climate")
    #expect(board.labels[0].position == CGPoint(x: 10, y: 20))
}

@Test func brainstormBoard_addLabel_rejects_empty_input() {
    var board = BrainstormBoard()

    #expect(board.addLabel("", at: .zero) == false)
    #expect(board.addLabel("   \n  ", at: .zero) == false)
    #expect(board.labels.isEmpty)
}

@Test func brainstormBoard_moveLabel_updates_position() {
    var board = BrainstormBoard()
    _ = board.addLabel("Idea", at: CGPoint(x: 0, y: 0))
    let id = board.labels[0].id

    board.moveLabel(id: id, to: CGPoint(x: 100, y: 200))

    #expect(board.labels[0].position == CGPoint(x: 100, y: 200))
}

@Test func brainstormBoard_moveLabel_ignores_unknown_id() {
    var board = BrainstormBoard()
    _ = board.addLabel("Idea", at: CGPoint(x: 5, y: 5))

    board.moveLabel(id: UUID(), to: CGPoint(x: 999, y: 999))

    #expect(board.labels[0].position == CGPoint(x: 5, y: 5))
}

@Test func brainstormBoard_description_is_empty_when_no_labels() {
    let board = BrainstormBoard()
    #expect(board.summary == "Empty brainstorm")
}

@Test func brainstormBoard_description_singular_for_one_label() {
    var board = BrainstormBoard()
    _ = board.addLabel("Solar", at: .zero)
    #expect(board.summary == "Brainstorm with 1 term: Solar")
}

@Test func brainstormBoard_description_lists_all_terms() {
    var board = BrainstormBoard()
    _ = board.addLabel("Solar", at: .zero)
    _ = board.addLabel("Wind", at: .zero)
    _ = board.addLabel("Hydro", at: .zero)
    #expect(board.summary == "Brainstorm with 3 terms: Solar, Wind, Hydro")
}

// MARK: - Random Placement Tests

@Test func brainstormCanvas_randomPosition_stays_within_bounds() {
    let bounds = CGRect(x: 0, y: 0, width: 800, height: 400)
    let margin: CGFloat = 60

    for _ in 0..<200 {
        let point = BrainstormCanvas.randomPosition(in: bounds, margin: margin)
        #expect(point.x >= bounds.minX + margin)
        #expect(point.x <= bounds.maxX - margin)
        #expect(point.y >= bounds.minY + margin)
        #expect(point.y <= bounds.maxY - margin)
    }
}

@Test func brainstormCanvas_randomPosition_handles_tiny_bounds() {
    // Bounds smaller than 2x margin should not crash or produce NaN.
    let bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
    let point = BrainstormCanvas.randomPosition(in: bounds, margin: 60)

    #expect(point.x.isFinite)
    #expect(point.y.isFinite)
}
