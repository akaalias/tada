import Testing
@testable import Tada

/// The on-device executive sometimes returns a structurally valid but semantically
/// wrong field type (e.g. a range slider for "travel dates"). These tests pin the
/// deterministic correction layer that catches the clearest mismatches.
@Suite struct ExecutiveFieldHeuristicsTests {
    @Test func travelDates_rangeSlider_becomesDate() {
        let corrected = ExecutiveFieldHeuristics.correctedType(
            title: "Choose travel dates", label: "Select a date range for the trip", choice: .rangeSlider
        )
        #expect(corrected == .date)
    }

    @Test func departureDate_number_becomesDate() {
        #expect(ExecutiveFieldHeuristics.correctedType(title: "Departure date", label: "", choice: .number) == .date)
    }

    @Test func whenQuestion_slider_becomesDate() {
        #expect(ExecutiveFieldHeuristics.correctedType(title: "When do you want to fly?", label: "", choice: .slider) == .date)
    }

    @Test func budget_singleSlider_becomesRangeSlider() {
        #expect(ExecutiveFieldHeuristics.correctedType(title: "What's your budget?", label: "Budget", choice: .slider) == .rangeSlider)
    }

    @Test func budget_rangeSlider_unchanged() {
        #expect(ExecutiveFieldHeuristics.correctedType(title: "What's your budget?", label: "Budget", choice: .rangeSlider) == .rangeSlider)
    }

    @Test func rating_slider_unchanged() {
        // A genuine slider question (no date/money signal) must not be coerced.
        #expect(ExecutiveFieldHeuristics.correctedType(title: "Rate your satisfaction", label: "Satisfaction", choice: .slider) == .slider)
    }

    @Test func guestCount_countSelector_unchanged() {
        #expect(ExecutiveFieldHeuristics.correctedType(title: "How many guests?", label: "Guests", choice: .countSelector) == .countSelector)
    }

    @Test func dateQuestion_singleSelect_unchanged() {
        // Only numeric/slider mistakes are corrected; a select for a date is left alone.
        #expect(ExecutiveFieldHeuristics.correctedType(title: "Preferred travel date", label: "", choice: .singleSelect) == .singleSelect)
    }

    @Test func fallbackType_infersFromTitle() {
        #expect(ExecutiveFieldHeuristics.fallbackType(title: "Determine travel dates") == .date)
        #expect(ExecutiveFieldHeuristics.fallbackType(title: "When do you leave?") == .date)
        #expect(ExecutiveFieldHeuristics.fallbackType(title: "What's your budget?") == .rangeSlider)
        #expect(ExecutiveFieldHeuristics.fallbackType(title: "Describe your goals") == .textarea)
    }

    @Test func correctingSchema_dropsStaleValidation() {
        let schema = ActionSchema(
            type: .form,
            title: "Choose travel dates",
            fields: [ActionField(type: .rangeSlider, label: "Date range", validation: FieldValidation(minValue: 250, maxValue: 750))],
            submitLabel: "Continue"
        )
        let corrected = ExecutiveFieldHeuristics.corrected(schema)
        #expect(corrected.fields.first?.type == .date)
        #expect(corrected.fields.first?.validation == nil)   // numeric range is meaningless for a date
    }
}
