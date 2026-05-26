import Foundation
import SwiftData
import Testing
@testable import Tada

// MARK: - Helpers

@MainActor
private func makeVM(_ container: IntegrationTestContainer, task: TodoTask) -> ActionCardViewModel {
    let vm = ActionCardViewModel(
        task: task,
        knowledgeBase: container.mockKnowledgeBase,
        executiveAI: container.mockExecutive,
        plannerAI: container.mockPlanner
    )
    vm.modelContext = container.modelContext
    return vm
}

/// Inserts a task with `count` discovery subtasks (first marked current) into the container.
@MainActor
private func makeDiscoveryTask(_ container: IntegrationTestContainer, count: Int, title: String = "Discovery Task") -> TodoTask {
    let task = TodoTask(title: title, originalInput: title)
    container.modelContext.insert(task)
    for i in 0..<count {
        let st = SubTask(title: "Q\(i)", description: "", order: i, phase: .discovery)
        if i == 0 { st.markCurrent() }
        task.addSubTask(st)
        st.task = task
        container.modelContext.insert(st)
    }
    try? container.modelContext.save()
    return task
}

/// Inserts an execution-phase task with `count` execution subtasks (first current).
@MainActor
private func makeExecutionTask(_ container: IntegrationTestContainer, count: Int, externalFirst: Bool = false, title: String = "Execution Task") -> TodoTask {
    let task = TodoTask(title: title, originalInput: title)
    task.transitionToExecution()
    container.modelContext.insert(task)
    for i in 0..<count {
        let st = SubTask(title: "S\(i)", description: "", order: i, phase: .execution, requiresExternalAction: externalFirst && i == 0)
        if i == 0 { st.markCurrent() }
        task.addSubTask(st)
        st.task = task
        container.modelContext.insert(st)
    }
    try? container.modelContext.save()
    return task
}

private func setTestKey() {
}

/// Executive mock that always throws — for error-path coverage.
private final class ThrowingExecutiveAIService: ExecutiveAIServiceProtocol {
    struct Boom: Error {}
    func generateActionUI(subTask: String, subTaskDescription: String, taskContext: String, previousResponses: [[String: String]], taskMemory: String, phase: TaskPhase) async throws -> ActionSchema {
        throw Boom()
    }
}

// MARK: - Schema loading

@MainActor
@Test func acvm_loadOrGenerate_uses_cached_schema_synchronously() throws {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 1)
    let sub = task.currentSubTask!

    let cached = ActionSchema(type: .form, title: "Cached", fields: [ActionField(type: .text, label: "x")])
    sub.actionSchemaData = try JSONEncoder().encode(cached)

    let vm = makeVM(container, task: task)
    vm.loadOrGenerateActionUI(for: sub)

    #expect(vm.actionSchema?.title == "Cached")
    #expect(vm.isLoadingSchema == false)
}

@MainActor
@Test func acvm_generateActionUI_calls_executive_and_caches() async {
    setTestKey()
    let container = IntegrationTestContainer()
    container.mockExecutive.schemaProvider = { sub, _, _, _, _ in
        ActionSchema(type: .form, title: sub, fields: [ActionField(type: .text, label: sub)])
    }
    let task = makeDiscoveryTask(container, count: 1)
    let sub = task.currentSubTask!
    let vm = makeVM(container, task: task)

    vm.generateActionUI(for: sub)

    let ok = await IntegrationTestExpectations.waitFor { vm.actionSchema != nil }
    #expect(ok)
    #expect(vm.actionSchema?.title == "Q0")
    #expect(vm.isLoadingSchema == false)
    #expect(sub.actionSchemaData != nil)
}

@MainActor
@Test func acvm_generateActionUI_sets_error_on_failure() async {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 1)
    let vm = ActionCardViewModel(
        task: task,
        knowledgeBase: container.mockKnowledgeBase,
        executiveAI: ThrowingExecutiveAIService(),
        plannerAI: container.mockPlanner
    )
    vm.modelContext = container.modelContext

    vm.generateActionUI(for: task.currentSubTask!)

    let ok = await IntegrationTestExpectations.waitFor { vm.schemaError != nil }
    #expect(ok)
    #expect(vm.isLoadingSchema == false)
}

@MainActor
@Test func acvm_clearSchemaForNewSubTask_resets_state() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 1)
    let vm = makeVM(container, task: task)
    vm.actionSchema = ActionSchema(type: .form, title: "x", fields: [])
    vm.actionResponse["a"] = .string("b")
    vm.schemaError = "err"

    vm.clearSchemaForNewSubTask()

    #expect(vm.actionSchema == nil)
    #expect(vm.actionResponse.values.isEmpty)
    #expect(vm.schemaError == nil)
}

@MainActor
@Test func acvm_regenerateActionUI_clears_cache_then_generates() async {
    setTestKey()
    let container = IntegrationTestContainer()
    container.mockExecutive.schemaProvider = { sub, _, _, _, _ in
        ActionSchema(type: .form, title: "fresh-\(sub)", fields: [ActionField(type: .text, label: sub)])
    }
    let task = makeDiscoveryTask(container, count: 1)
    let sub = task.currentSubTask!
    sub.actionSchemaData = try? JSONEncoder().encode(ActionSchema(type: .form, title: "stale", fields: []))
    let vm = makeVM(container, task: task)

    vm.regenerateActionUI(for: sub)

    let ok = await IntegrationTestExpectations.waitFor { vm.actionSchema?.title == "fresh-Q0" }
    #expect(ok)
}

// MARK: - changeFieldType

@MainActor
@Test func acvm_changeFieldType_to_textarea_seeds_default_from_string_array() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 1)
    let sub = task.currentSubTask!
    let vm = makeVM(container, task: task)
    vm.actionResponse["field"] = .stringArray(["one", "two", "three"])

    vm.changeFieldType(to: .textarea, options: nil, for: sub)

    let field = vm.actionSchema?.fields.first
    #expect(field?.type == .textarea)
    #expect(field?.defaultValue == "one\ntwo\nthree")
    #expect(sub.actionSchemaData != nil)
    #expect(vm.actionResponse.values.isEmpty)
}

@MainActor
@Test func acvm_changeFieldType_to_itemTable_seeds_prefill_rows() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 1)
    let sub = task.currentSubTask!
    let vm = makeVM(container, task: task)
    vm.actionResponse["field"] = .stringArray(["Milk", "Bread"])

    vm.changeFieldType(to: .itemTable, options: nil, for: sub)

    let field = vm.actionSchema?.fields.first
    #expect(field?.type == .itemTable)
    #expect(field?.prefillRows == [["item": "Milk"], ["item": "Bread"]])
}

@MainActor
@Test func acvm_changeFieldType_to_orderedList_seeds_options_from_lines() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 1)
    let sub = task.currentSubTask!
    let vm = makeVM(container, task: task)
    vm.actionResponse["field"] = .stringArray(["First", "Second"])

    vm.changeFieldType(to: .orderedList, options: nil, for: sub)

    let field = vm.actionSchema?.fields.first
    #expect(field?.type == .orderedList)
    #expect(field?.options?.map(\.label) == ["First", "Second"])
}

@MainActor
@Test func acvm_changeFieldType_to_hierarchicalList_parses_depth() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 1)
    let sub = task.currentSubTask!
    let vm = makeVM(container, task: task)
    // Tree value flattens with two-space indentation per depth.
    vm.actionResponse["field"] = .tree([
        TreeNode(label: "Parent", depth: 0),
        TreeNode(label: "Child", depth: 1),
    ])

    vm.changeFieldType(to: .hierarchicalList, options: nil, for: sub)

    let field = vm.actionSchema?.fields.first
    #expect(field?.type == .hierarchicalList)
    #expect(field?.prefillRows?.first?["item"] == "Parent")
    #expect(field?.prefillRows?.first?["depth"] == "0")
    #expect(field?.prefillRows?.last?["item"] == "Child")
    #expect(field?.prefillRows?.last?["depth"] == "1")
}

@MainActor
@Test func acvm_changeFieldType_text_from_table_summary_splits_items() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 1)
    let sub = task.currentSubTask!
    let vm = makeVM(container, task: task)
    let table = TableData(
        columns: [TableData.Column(id: "item", label: "Item", type: "text"),
                  TableData.Column(id: "price", label: "Price", type: "currency")],
        rows: [["item": "Apples", "price": "5"], ["item": "Oranges", "price": "10"]],
        total: 15, hasCurrency: true
    )
    vm.actionResponse["field"] = .table(table)

    vm.changeFieldType(to: .text, options: nil, for: sub)

    let field = vm.actionSchema?.fields.first
    #expect(field?.type == .text)
    // Summary "Apples - €5; Oranges - €10 (Total: €15)" → split on "; ", total moved to own line.
    let dv = field?.defaultValue ?? ""
    #expect(dv.contains("Apples - €5"))
    #expect(dv.contains("Oranges - €10"))
}

@MainActor
@Test func acvm_changeFieldType_preserves_explicit_options() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 1)
    let sub = task.currentSubTask!
    let vm = makeVM(container, task: task)

    let opts = [FieldOption(label: "A"), FieldOption(label: "B")]
    vm.changeFieldType(to: .singleSelect, options: opts, for: sub)

    #expect(vm.actionSchema?.fields.first?.options?.map(\.label) == ["A", "B"])
}

// MARK: - Synchronous navigation

@MainActor
@Test func acvm_completeSubTask_advances_and_notifies_kb() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 2)
    let first = task.sortedSubTasks[0]
    let second = task.sortedSubTasks[1]
    let vm = makeVM(container, task: task)
    vm.actionSchema = ActionSchema(type: .form, title: "x", fields: [])

    vm.completeSubTask(first)

    #expect(first.isCompleted)
    #expect(second.isCurrent)
    #expect(vm.actionSchema == nil)
    #expect(container.mockKnowledgeBase.handledSubtaskCompleted.contains { $0 === first })
}

@MainActor
@Test func acvm_skipSubTask_marks_skipped_and_advances() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 2)
    let first = task.sortedSubTasks[0]
    let second = task.sortedSubTasks[1]
    let vm = makeVM(container, task: task)

    vm.skipSubTask(first)

    #expect(first.status == .skipped)
    #expect(second.isCurrent)
}

@MainActor
@Test func acvm_completeTask_marks_completed_and_notifies_kb() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeExecutionTask(container, count: 1)
    let vm = makeVM(container, task: task)

    vm.completeTask()

    #expect(task.status == .completed)
    #expect(container.mockKnowledgeBase.handledTaskCompleted.contains { $0 === task })
}

@MainActor
@Test func acvm_saveMemory_persists_text() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 1)
    let vm = makeVM(container, task: task)

    vm.saveMemory("Always book mornings")
    #expect(task.memory == "Always book mornings")
}

// MARK: - Computed

@MainActor
@Test func acvm_isTransitioningToExecution_true_when_discovery_all_done() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 2)
    let vm = makeVM(container, task: task)

    #expect(vm.isTransitioningToExecution == false)
    task.sortedSubTasks.forEach { $0.markCompleted() }
    #expect(vm.isTransitioningToExecution == true)
}

@MainActor
@Test func acvm_currentIndex_points_to_current_subtask() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 3)
    let vm = makeVM(container, task: task)

    #expect(vm.currentIndex == 0)
    task.sortedSubTasks[0].markCompleted()
    task.sortedSubTasks[1].markCurrent()
    #expect(vm.currentIndex == 1)
}

// MARK: - Completion flow with response

@MainActor
@Test func acvm_completeWithResponse_external_no_shows_blocker() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeExecutionTask(container, count: 2, externalFirst: true)
    let sub = task.executionSubTasks[0]
    let vm = makeVM(container, task: task)
    vm.actionResponse["answer"] = .boolean(false)

    vm.completeSubTaskWithResponse(sub)

    #expect(vm.showingBlockerSelection == true)
    #expect(vm.pendingSubTask === sub)
    #expect(sub.isCompleted == false)
}

@MainActor
@Test func acvm_completeWithResponse_external_yes_proceeds() async {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 2)
    let sub = task.sortedSubTasks[0]
    sub.requiresExternalAction = true
    let vm = makeVM(container, task: task)
    vm.actionResponse["answer"] = .boolean(true)

    vm.completeSubTaskWithResponse(sub)

    #expect(vm.showingBlockerSelection == false)
    #expect(sub.isCompleted)
    #expect(task.sortedSubTasks[1].isCurrent)
}

@MainActor
@Test func acvm_completeWithResponse_discovery_advances_to_next() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeDiscoveryTask(container, count: 2)
    let first = task.sortedSubTasks[0]
    let vm = makeVM(container, task: task)
    vm.actionResponse["field"] = .string("answer")

    vm.completeSubTaskWithResponse(first)

    #expect(first.isCompleted)
    #expect(first.actionResponseData != nil)
    #expect(task.sortedSubTasks[1].isCurrent)
    #expect(container.mockKnowledgeBase.handledSubtaskCompleted.contains { $0 === first })
}

@MainActor
@Test func acvm_completeWithResponse_last_discovery_transitions_to_execution() async {
    setTestKey()
    let container = IntegrationTestContainer()
    container.mockPlanner.executionPlanProvider = { _, _ in
        TaskPlan(title: "Exec Plan", description: "", subTasks: [
            SubTaskPlan(title: "Do step", description: "", requiresExternalAction: false)
        ])
    }
    let task = makeDiscoveryTask(container, count: 1)
    let only = task.sortedSubTasks[0]
    let vm = makeVM(container, task: task)
    vm.actionResponse["field"] = .string("answer")

    vm.completeSubTaskWithResponse(only)

    let ok = await IntegrationTestExpectations.waitFor { task.isExecutionPhase && !task.executionSubTasks.isEmpty }
    #expect(ok)
    #expect(task.executionSubTasks.first?.title == "Do step")
}

@MainActor
@Test func acvm_completeWithResponse_last_execution_step_completes_task() async {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeExecutionTask(container, count: 1)
    let only = task.executionSubTasks[0]
    let vm = makeVM(container, task: task)
    vm.actionResponse["field"] = .string("done")

    vm.completeSubTaskWithResponse(only)

    let ok = await IntegrationTestExpectations.waitFor({ task.status == .completed }, timeout: 5)
    #expect(ok)
    #expect(container.mockKnowledgeBase.handledTaskCompleted.contains { $0 === task })
}

@MainActor
@Test func acvm_completeWithResponse_execution_revises_plan_when_revised() async {
    setTestKey()
    let container = IntegrationTestContainer()
    container.mockPlanner.revisionProvider = { _, _, _ in
        PlanRevision(revised: true, reason: "split", subTasks: [
            SubTaskPlan(title: "New A", description: "", requiresExternalAction: false),
            SubTaskPlan(title: "New B", description: "", requiresExternalAction: false),
        ])
    }
    let task = makeExecutionTask(container, count: 3)
    let first = task.executionSubTasks[0]
    let vm = makeVM(container, task: task)
    vm.actionResponse["field"] = .string("done")

    vm.completeSubTaskWithResponse(first)

    let ok = await IntegrationTestExpectations.waitFor {
        task.executionSubTasks.contains { $0.title == "New A" } &&
        task.executionSubTasks.contains { $0.title == "New B" }
    }
    #expect(ok)
}

@MainActor
@Test func acvm_completeWithResponse_execution_keeps_plan_when_not_revised() async {
    setTestKey()
    let container = IntegrationTestContainer()
    // default revisionProvider → revised:false → moveToNextStep
    let task = makeExecutionTask(container, count: 3)
    let first = task.executionSubTasks[0]
    let second = task.executionSubTasks[1]
    let vm = makeVM(container, task: task)
    vm.actionResponse["field"] = .string("done")

    vm.completeSubTaskWithResponse(first)

    let ok = await IntegrationTestExpectations.waitFor { first.isCompleted && second.isCurrent }
    #expect(ok)
}

// MARK: - Blocker handling

@MainActor
@Test func acvm_blocker_remember_shows_nudge_input() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeExecutionTask(container, count: 1)
    let vm = makeVM(container, task: task)
    vm.pendingSubTask = task.executionSubTasks[0]

    vm.handleBlockerSelection(.remember)

    #expect(vm.showingBlockerSelection == false)
    #expect(vm.showingNudgeInput == true)
    #expect(vm.pendingSubTask == nil)
}

@MainActor
@Test func acvm_blocker_badTiming_clears_pending_and_logs() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeExecutionTask(container, count: 1)
    let vm = makeVM(container, task: task)
    vm.pendingSubTask = task.executionSubTasks[0]

    vm.handleBlockerSelection(.badTiming)

    #expect(vm.pendingSubTask == nil)
    #expect(vm.progressLog.contains { $0.contains("come back to this later") })
}

@MainActor
@Test func acvm_blocker_needInfo_and_anxious_clear_pending() {
    setTestKey()
    let container = IntegrationTestContainer()
    let task = makeExecutionTask(container, count: 1)
    let vm = makeVM(container, task: task)

    vm.pendingSubTask = task.executionSubTasks[0]
    vm.handleBlockerSelection(.needInfo)
    #expect(vm.pendingSubTask == nil)

    vm.pendingSubTask = task.executionSubTasks[0]
    vm.handleBlockerSelection(.anxious)
    #expect(vm.pendingSubTask == nil)
}

@MainActor
@Test func acvm_blocker_doesntMakeSense_deletes_step_without_apikey() async {
    // No API key → skips learning generation (avoids touching real PlanningMemoryService).
    let container = IntegrationTestContainer()
    let task = makeExecutionTask(container, count: 2)
    let first = task.executionSubTasks[0]
    let second = task.executionSubTasks[1]
    let vm = makeVM(container, task: task)
    vm.pendingSubTask = first

    vm.handleBlockerSelection(.doesntMakeSense)

    let ok = await IntegrationTestExpectations.waitFor {
        !task.executionSubTasks.contains { $0.id == first.id } && second.isCurrent
    }
    #expect(ok)
}

@MainActor
@Test func acvm_blocker_overwhelming_breaks_down_step() async {
    setTestKey()
    let container = IntegrationTestContainer()
    container.mockPlanner.breakdownProvider = { _, _, _, _, _ in
        [SubTaskPlan(title: "Micro 1", description: "", requiresExternalAction: false),
         SubTaskPlan(title: "Micro 2", description: "", requiresExternalAction: false)]
    }
    let task = makeExecutionTask(container, count: 1)
    let only = task.executionSubTasks[0]
    let vm = makeVM(container, task: task)
    vm.pendingSubTask = only

    vm.handleBlockerSelection(.overwhelming)

    let ok = await IntegrationTestExpectations.waitFor {
        task.executionSubTasks.contains { $0.title == "Micro 1" } &&
        task.executionSubTasks.contains { $0.title == "Micro 2" } &&
        !task.executionSubTasks.contains { $0.id == only.id }
    }
    #expect(ok)
}

// MARK: - Planning

@MainActor
@Test func acvm_planWithAI_generates_discovery_subtasks() async {
    setTestKey()
    let container = IntegrationTestContainer()
    container.mockPlanner.discoveryQuestionsProvider = { _ in
        TaskPlan(title: "Planned Title", description: "desc", subTasks: [
            SubTaskPlan(title: "QA", description: "", requiresExternalAction: false),
            SubTaskPlan(title: "QB", description: "", requiresExternalAction: false),
        ])
    }
    let task = TodoTask(title: "raw input", originalInput: "raw input")
    container.modelContext.insert(task)
    let vm = makeVM(container, task: task)

    vm.planWithAI()

    let ok = await IntegrationTestExpectations.waitFor {
        task.planningStatus == .idle && task.discoverySubTasks.count == 2
    }
    #expect(ok)
    #expect(task.title == "Planned Title")
    #expect(task.discoverySubTasks.first?.isCurrent == true)
    #expect(container.mockKnowledgeBase.handledTaskCreatedOrUpdated.contains { $0 === task })
}

@MainActor
@Test func acvm_planWithAI_without_apikey_noops() {
    let container = IntegrationTestContainer()
    let task = TodoTask(title: "raw", originalInput: "raw")
    container.modelContext.insert(task)
    let vm = makeVM(container, task: task)

    vm.planWithAI()
    #expect(task.subTasks.isEmpty)
}

@MainActor
@Test func acvm_transitionToExecutionPhase_builds_plan() async {
    setTestKey()
    let container = IntegrationTestContainer()
    container.mockPlanner.executionPlanProvider = { _, _ in
        TaskPlan(title: "Exec", description: "ed", subTasks: [
            SubTaskPlan(title: "Step A", description: "", requiresExternalAction: false),
            SubTaskPlan(title: "Step B", description: "", requiresExternalAction: true),
        ])
    }
    let task = makeDiscoveryTask(container, count: 1)
    task.sortedSubTasks[0].markCompleted()
    let vm = makeVM(container, task: task)

    vm.transitionToExecutionPhase()

    let ok = await IntegrationTestExpectations.waitFor {
        task.isExecutionPhase && task.executionSubTasks.count == 2 && task.planningStatus == .idle
    }
    #expect(ok)
    #expect(task.executionSubTasks.first?.isCurrent == true)
    #expect(task.executionSubTasks.last?.requiresExternalAction == true)
}
