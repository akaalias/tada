import Foundation
import Testing

@testable import Tada

// MARK: - formatPreviousResponses

@Test func formatPreviousResponses_drops_image_data_urls() {
    let responses: [[String: String]] = [[
        "subTask": "Measure your balcony",
        "field_drawing": "Drawing with 1 rectangle. Labels: 6m, 2m",
        "field_drawing_image": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA",
    ]]

    let formatted = ExecutiveAIService.formatPreviousResponses(responses)

    #expect(!formatted.contains("data:image"))
    #expect(!formatted.contains("base64"))
    #expect(!formatted.contains("iVBORw0KGgo"))
}

@Test func formatPreviousResponses_keeps_text_descriptions() {
    let responses: [[String: String]] = [[
        "field_drawing": "Drawing with 1 rectangle. Labels: 6m, 2m",
        "field_drawing_image": "data:image/png;base64,iVBORw0KGgo",
    ]]

    let formatted = ExecutiveAIService.formatPreviousResponses(responses)

    #expect(formatted.contains("Drawing with 1 rectangle. Labels: 6m, 2m"))
}
