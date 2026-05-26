import Testing
import Foundation
import FoundationModels
@testable import Tada

/// Tests the pure mapping from on-device guided-generation DTOs to the app's
/// domain types. The model I/O itself is verified manually; this locks down the
/// translation layer so a backend swap can't silently corrupt plans or schemas.
@Suite struct FMGenerableMappingTests {
    @Test func taskPlan_mapsToDomain() {
        let gen = GenTaskPlan(title: "Sort Taxes", description: "Do the thing", subTasks: [
            GenSubTask(title: "Call accountant", description: "Phone them", requiresExternalAction: true),
            GenSubTask(title: "Record income", description: "Enter it", requiresExternalAction: false)
        ])
        let domain = gen.toDomain()
        #expect(domain.title == "Sort Taxes")
        #expect(domain.description == "Do the thing")
        #expect(domain.subTasks.count == 2)
        #expect(domain.subTasks[0].requiresExternalAction == true)
        #expect(domain.subTasks[1].requiresExternalAction == false)
    }

    @Test func planRevision_notRevised_dropsSubtasksAndReason() {
        let gen = GenPlanRevision(revised: false, reason: "", subTasks: [])
        let domain = gen.toDomain()
        #expect(domain.revised == false)
        #expect(domain.reason == nil)
        #expect(domain.subTasks == nil)
    }

    @Test func planRevision_revised_keepsSubtasksAndReason() {
        let gen = GenPlanRevision(revised: true, reason: "Split compounds", subTasks: [
            GenSubTask(title: "A", description: "", requiresExternalAction: false)
        ])
        let domain = gen.toDomain()
        #expect(domain.revised == true)
        #expect(domain.reason == "Split compounds")
        #expect(domain.subTasks?.count == 1)
    }

    @Test func microSteps_mapToSubTaskPlans() {
        let gen = GenMicroSteps(microSteps: [
            GenSubTask(title: "Buy bamboo", description: "", requiresExternalAction: true),
            GenSubTask(title: "Buy daybed", description: "", requiresExternalAction: true)
        ])
        let domain = gen.toDomain()
        #expect(domain.count == 2)
        #expect(domain[0].title == "Buy bamboo")
    }

    @Test func actionSchema_mapsSingleFieldAndType() {
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
        #expect(domain.type == .form)
        #expect(domain.title == "What's your budget?")
        #expect(domain.description == nil)          // empty string -> nil
        #expect(domain.fields.count == 1)           // single field -> one-element array
        #expect(domain.fields[0].type == .rangeSlider)
        #expect(domain.fields[0].validation?.minValue == 100)
        #expect(domain.fields[0].validation?.maxValue == 3000)
    }

    @Test func actionField_emptyIdAndOptionsDefaulted() {
        let gen = GenActionField(id: "", type: .text, label: "Name", options: [], validation: nil)
        let domain = gen.toDomain()
        #expect(domain.id == "answer")  // empty id defaulted
        #expect(domain.options == nil)  // empty options -> nil
        #expect(domain.validation == nil)
        #expect(domain.type == .text)
    }

    @Test func actionField_optionsMap() {
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
        #expect(domain.options?.count == 2)
        #expect(domain.options?[0].label == "Economy")
        #expect(domain.options?[0].description == nil)        // empty -> nil
        #expect(domain.options?[1].description == "More legroom")
    }

    @Test func allGenFieldTypes_haveMatchingDomainMapping() {
        let pairs: [(GenFieldType, ActionField.FieldType)] = [
            (.text, .text), (.number, .number), (.multiSelect, .multiSelect),
            (.singleSelect, .singleSelect), (.yesNo, .yesNo), (.date, .date),
            (.textarea, .textarea), (.drawing, .drawing), (.slider, .slider),
            (.rangeSlider, .rangeSlider), (.countSelector, .countSelector),
            (.itemTable, .itemTable), (.orderedList, .orderedList),
            (.hierarchicalList, .hierarchicalList)
        ]
        for (gen, expected) in pairs {
            #expect(gen.domain == expected)
        }
    }
}
