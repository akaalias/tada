import XCTest
import FoundationModels
@testable import Tada

/// Tests the pure mapping from on-device guided-generation DTOs to the app's
/// domain types. The model I/O itself is verified manually; this locks down the
/// translation layer so a backend swap can't silently corrupt plans or schemas.
final class FMGenerableMappingTests: XCTestCase {
    func test_taskPlan_mapsToDomain() {
        let gen = GenTaskPlan(title: "Sort Taxes", description: "Do the thing", subTasks: [
            GenSubTask(title: "Call accountant", description: "Phone them", requiresExternalAction: true),
            GenSubTask(title: "Record income", description: "Enter it", requiresExternalAction: false)
        ])
        let domain = gen.toDomain()
        XCTAssertEqual(domain.title, "Sort Taxes")
        XCTAssertEqual(domain.description, "Do the thing")
        XCTAssertEqual(domain.subTasks.count, 2)
        XCTAssertEqual(domain.subTasks[0].requiresExternalAction, true)
        XCTAssertEqual(domain.subTasks[1].requiresExternalAction, false)
    }

    func test_planRevision_notRevised_dropsSubtasksAndReason() {
        let gen = GenPlanRevision(revised: false, reason: "", subTasks: [])
        let domain = gen.toDomain()
        XCTAssertFalse(domain.revised)
        XCTAssertNil(domain.reason)
        XCTAssertNil(domain.subTasks)
    }

    func test_planRevision_revised_keepsSubtasksAndReason() {
        let gen = GenPlanRevision(revised: true, reason: "Split compounds", subTasks: [
            GenSubTask(title: "A", description: "", requiresExternalAction: false)
        ])
        let domain = gen.toDomain()
        XCTAssertTrue(domain.revised)
        XCTAssertEqual(domain.reason, "Split compounds")
        XCTAssertEqual(domain.subTasks?.count, 1)
    }

    func test_microSteps_mapToSubTaskPlans() {
        let gen = GenMicroSteps(microSteps: [
            GenSubTask(title: "Buy bamboo", description: "", requiresExternalAction: true),
            GenSubTask(title: "Buy daybed", description: "", requiresExternalAction: true)
        ])
        let domain = gen.toDomain()
        XCTAssertEqual(domain.count, 2)
        XCTAssertEqual(domain[0].title, "Buy bamboo")
    }

    func test_actionSchema_mapsSingleFieldAndType() {
        let gen = GenActionSchema(
            title: "What's your budget?",
            description: "",
            submitLabel: "Continue",
            requiresExternalAction: false,
            field: GenActionField(
                id: "answer",
                type: .rangeSlider,
                label: "Budget range",
                options: [],
                validation: GenFieldValidation(minValue: 100, maxValue: 3000)
            )
        )
        let domain = gen.toDomain()
        XCTAssertEqual(domain.type, .form)
        XCTAssertEqual(domain.title, "What's your budget?")
        XCTAssertNil(domain.description)          // empty string -> nil
        XCTAssertEqual(domain.fields.count, 1)    // single field -> one-element array
        XCTAssertEqual(domain.fields[0].type, .rangeSlider)
        XCTAssertEqual(domain.fields[0].validation?.minValue, 100)
        XCTAssertEqual(domain.fields[0].validation?.maxValue, 3000)
    }

    func test_actionField_emptyIdAndOptionsDefaulted() {
        let gen = GenActionField(id: "", type: .text, label: "Name", options: [], validation: nil)
        let domain = gen.toDomain()
        XCTAssertEqual(domain.id, "answer")  // empty id defaulted
        XCTAssertNil(domain.options)         // empty options -> nil
        XCTAssertNil(domain.validation)
        XCTAssertEqual(domain.type, .text)
    }

    func test_actionField_optionsMap() {
        let gen = GenActionField(
            id: "cabin",
            type: .singleSelect,
            label: "Cabin class",
            options: [
                GenFieldOption(id: "eco", label: "Economy", description: ""),
                GenFieldOption(id: "biz", label: "Business", description: "More legroom")
            ],
            validation: nil
        )
        let domain = gen.toDomain()
        XCTAssertEqual(domain.options?.count, 2)
        XCTAssertEqual(domain.options?[0].label, "Economy")
        XCTAssertNil(domain.options?[0].description)        // empty -> nil
        XCTAssertEqual(domain.options?[1].description, "More legroom")
    }

    func test_allGenFieldTypes_haveMatchingDomainMapping() {
        let pairs: [(GenFieldType, ActionField.FieldType)] = [
            (.text, .text), (.number, .number), (.multiSelect, .multiSelect),
            (.singleSelect, .singleSelect), (.yesNo, .yesNo), (.date, .date),
            (.textarea, .textarea), (.drawing, .drawing), (.slider, .slider),
            (.rangeSlider, .rangeSlider), (.countSelector, .countSelector),
            (.itemTable, .itemTable), (.orderedList, .orderedList),
            (.hierarchicalList, .hierarchicalList)
        ]
        for (gen, expected) in pairs {
            XCTAssertEqual(gen.domain, expected)
        }
    }
}
