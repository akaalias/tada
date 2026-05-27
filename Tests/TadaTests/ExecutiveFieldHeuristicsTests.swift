import Testing
@testable import Tada

/// The model's field type is authoritative (GenField is an associated-value enum, so
/// options can only exist on selection cases). The only remaining heuristic is the
/// fallback type used when guided generation fails to produce any decodable object.
@Suite struct ExecutiveFieldHeuristicsTests {
    @Test func fallbackType_infersFromTitle() {
        #expect(ExecutiveFieldHeuristics.fallbackType(title: "Determine travel dates") == .date)
        #expect(ExecutiveFieldHeuristics.fallbackType(title: "When do you leave?") == .date)
        #expect(ExecutiveFieldHeuristics.fallbackType(title: "What's your budget?") == .rangeSlider)
        #expect(ExecutiveFieldHeuristics.fallbackType(title: "Describe your goals") == .textarea)
    }
}
