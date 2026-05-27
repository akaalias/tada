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
                                  field: .text(label: "Your name", placeholder: "e.g. Jane Doe"),
                                  requiresExternalAction: false, submitLabel: "Save", description: "")
        let domain = gen.toDomain()
        #expect(domain.fields[0].type == .text)
        #expect(domain.fields[0].options == nil)
        #expect(domain.fields[0].id == "answer")
        #expect(domain.fields[0].placeholder == "e.g. Jane Doe")   // placeholder (gray hint) restored
        #expect(domain.fields[0].defaultValue == nil)              // never pre-filled by the model
    }

    @Test func textField_emptyPlaceholder_mapsToNil() {
        let gen = GenActionSchema(title: "Notes", typeReasoning: "open text -> textarea",
                                  field: .textarea(label: "Notes", placeholder: ""),
                                  requiresExternalAction: false, submitLabel: "Save", description: "")
        let domain = gen.toDomain()
        #expect(domain.fields[0].placeholder == nil)
        #expect(domain.fields[0].defaultValue == nil)
    }

    @Test func hierarchicalList_seedsPrefillRowsWithDepth() {
        let gen = GenActionSchema(
            title: "Organize", typeReasoning: "group/nest -> hierarchicalList",
            field: .hierarchicalList(label: "Outline", items: [
                GenTreeItem(label: "Transport", depth: 0),
                GenTreeItem(label: "Flights", depth: 1)
            ]),
            requiresExternalAction: false, submitLabel: "Continue", description: ""
        )
        let domain = gen.toDomain()
        #expect(domain.fields[0].type == .hierarchicalList)
        #expect(domain.fields[0].prefillRows?.count == 2)
        #expect(domain.fields[0].prefillRows?[0]["item"] == "Transport")
        #expect(domain.fields[0].prefillRows?[0]["depth"] == "0")
        #expect(domain.fields[0].prefillRows?[1]["depth"] == "1")
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

    @Test func brainstorm_mapsToDomain() {
        let gen = GenActionSchema(
            title: "Coaching topics",
            typeReasoning: "open-ended idea generation -> brainstorm",
            field: .brainstorm(label: "Topics to cover"),
            requiresExternalAction: false,
            submitLabel: "Save",
            description: ""
        )
        let domain = gen.toDomain()
        #expect(domain.fields[0].type == .brainstorm)
        #expect(domain.fields[0].label == "Topics to cover")
        #expect(domain.fields[0].options == nil)
    }

    @Test func checklist_mapsOptionsToDomain() {
        let gen = GenActionSchema(
            title: "Packing",
            typeReasoning: "concrete items to tick off -> checklist",
            field: .checklist(label: "Pack these", options: [
                GenFieldOption(id: "passport", label: "Passport", description: ""),
                GenFieldOption(id: "charger", label: "Charger", description: "")
            ]),
            requiresExternalAction: false,
            submitLabel: "Complete",
            description: ""
        )
        let domain = gen.toDomain()
        #expect(domain.fields[0].type == .checklist)
        #expect(domain.fields[0].options?.count == 2)
        #expect(domain.fields[0].options?[0].label == "Passport")
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
