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

    @Test func actionSchema_rangeSlider_mapsValidation() {
        let gen = GenActionSchema(
            title: "What's your budget?",
            typeReasoning: "budget question -> rangeSlider",
            field: .rangeSlider(label: "Budget range", minValue: 100, maxValue: 3000),
            requiresExternalAction: false,
            submitLabel: "Continue",
            description: ""
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

    @Test func textField_hasNoOptionsAndDefaultId() {
        // A text case has no options slot at all — options-on-text is unrepresentable.
        let gen = GenActionSchema(title: "Name", typeReasoning: "short answer -> text",
                                  field: .text(label: "Your name"), requiresExternalAction: false,
                                  submitLabel: "Save", description: "")
        let domain = gen.toDomain()
        #expect(domain.fields[0].type == .text)
        #expect(domain.fields[0].options == nil)
        #expect(domain.fields[0].id == "answer")
    }

    @Test func singleSelect_mapsOptions() {
        let gen = GenActionSchema(
            title: "Cabin class",
            typeReasoning: "enumerable choices -> singleSelect",
            field: .singleSelect(label: "Cabin class", options: [
                GenFieldOption(id: "eco", label: "Economy", description: ""),
                GenFieldOption(id: "biz", label: "Business", description: "More legroom")
            ]),
            requiresExternalAction: false,
            submitLabel: "Continue",
            description: ""
        )
        let domain = gen.toDomain()
        #expect(domain.fields[0].type == .singleSelect)
        #expect(domain.fields[0].options?.count == 2)
        #expect(domain.fields[0].options?[0].label == "Economy")
        #expect(domain.fields[0].options?[0].description == nil)        // empty -> nil
        #expect(domain.fields[0].options?[1].description == "More legroom")
    }

    @Test func itemTable_mapsColumnsToOptions() {
        let gen = GenActionSchema(
            title: "Shopping list",
            typeReasoning: "shopping list -> itemTable",
            field: .itemTable(label: "Items", columns: [
                GenFieldOption(id: "item", label: "Item", description: "")
            ]),
            requiresExternalAction: false,
            submitLabel: "Save",
            description: ""
        )
        let domain = gen.toDomain()
        #expect(domain.fields[0].type == .itemTable)
        #expect(domain.fields[0].options?.count == 1)
    }
}
