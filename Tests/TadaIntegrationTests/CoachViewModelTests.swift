import Foundation
import SwiftData
import Testing
@testable import Tada

// MARK: - Helpers

@MainActor
private func makeCoachVM(_ container: IntegrationTestContainer) -> CoachViewModel {
    let vm = CoachViewModel(context: CoachContext())
    vm.modelContext = container.modelContext
    vm.knowledgeBase = container.mockKnowledgeBase
    vm.plannerAI = container.mockPlanner
    return vm
}

@MainActor
private func insertTask(_ container: IntegrationTestContainer, title: String, subtasks: [(String, TaskPhase)] = []) -> TodoTask {
    let task = TodoTask(title: title, originalInput: title)
    container.modelContext.insert(task)
    for (i, (t, phase)) in subtasks.enumerated() {
        let st = SubTask(title: t, description: "", order: i, phase: phase)
        if i == 0 { st.markCurrent() }
        task.addSubTask(st)
        st.task = task
        container.modelContext.insert(st)
    }
    try? container.modelContext.save()
    return task
}

// MARK: - Welcome / clearChat / sendMessage guards

@MainActor
@Test func coachVM_starts_with_welcome_message() {
    let vm = CoachViewModel(context: CoachContext())
    #expect(vm.messages.count == 1)
    #expect(vm.messages.first?.role == .coach)
}

@MainActor
@Test func coachVM_clearChat_resets_to_welcome() {
    let vm = CoachViewModel(context: CoachContext())
    vm.messages.append(CoachMessage(role: .user, content: "hi"))
    vm.error = "boom"

    vm.clearChat()
    #expect(vm.messages.count == 1)
    #expect(vm.messages.first?.role == .coach)
    #expect(vm.error == nil)
}

@MainActor
@Test func coachVM_sendMessage_empty_input_does_nothing() async {
    let vm = CoachViewModel(context: CoachContext())
    vm.inputText = "   "
    await vm.sendMessage()
    #expect(vm.messages.count == 1) // only welcome
}

// MARK: - buildTaskSummary

@MainActor
@Test func coachVM_buildTaskSummary_nil_without_context() {
    let vm = CoachViewModel(context: CoachContext())
    #expect(vm.buildTaskSummary() == nil)
}

@MainActor
@Test func coachVM_buildTaskSummary_nil_when_no_active_tasks() {
    let container = IntegrationTestContainer()
    let task = insertTask(container, title: "Done task")
    task.markCompleted()
    try? container.modelContext.save()
    let vm = makeCoachVM(container)
    #expect(vm.buildTaskSummary() == nil)
}

@MainActor
@Test func coachVM_buildTaskSummary_lists_active_tasks() {
    let container = IntegrationTestContainer()
    _ = insertTask(container, title: "Active One", subtasks: [("step", .discovery)])
    let vm = makeCoachVM(container)

    let summary = vm.buildTaskSummary()
    #expect(summary?.contains("Active One") == true)
    #expect(summary?.contains("discovery") == true)
}

// MARK: - executeToolCalls (dispatch + unknown)

@MainActor
@Test func coachVM_executeToolCalls_unknown_tool_reports_failure() async {
    let container = IntegrationTestContainer()
    let vm = makeCoachVM(container)

    let results = await vm.executeToolCalls([ToolCall(id: "x1", name: "not_a_tool", arguments: [:])])
    #expect(results.count == 1)
    #expect(results.first?.success == false)
    #expect(results.first?.message == "Unknown tool")
    #expect(results.first?.toolName == "not_a_tool")
}

@MainActor
@Test func coachVM_executeToolCalls_wraps_results_with_ids() async {
    let container = IntegrationTestContainer()
    let vm = makeCoachVM(container)

    let results = await vm.executeToolCalls([
        ToolCall(id: "cap1", name: "capture_inbox_item", arguments: ["content": "Buy milk"])
    ])
    #expect(results.first?.toolUseId == "cap1")
    #expect(results.first?.success == true)
}

// MARK: - captureInboxItem / createTask

@MainActor
@Test func coachVM_captureInboxItem_creates_task() async {
    let container = IntegrationTestContainer()
    let vm = makeCoachVM(container)

    let (ok, msg) = await vm.executeTool(.captureInboxItem, arguments: ["content": "Remember to call mom"])
    #expect(ok)
    #expect(msg.contains("Remember to call mom"))

    let tasks = try? container.modelContext.fetch(FetchDescriptor<TodoTask>())
    #expect(tasks?.contains { $0.title == "Remember to call mom" } == true)
}

@MainActor
@Test func coachVM_captureInboxItem_fails_without_context() async {
    let vm = CoachViewModel(context: CoachContext()) // no modelContext
    let (ok, msg) = await vm.executeTool(.captureInboxItem, arguments: ["content": "x"])
    #expect(!ok)
    #expect(msg == "No model context")
}

@MainActor
@Test func coachVM_createTask_creates_and_plans() async {
    let container = IntegrationTestContainer()
    container.mockPlanner.discoveryQuestionsProvider = { _ in
        TaskPlan(title: "Planned", description: "d", subTasks: [
            SubTaskPlan(title: "Q1", description: "", requiresExternalAction: false)
        ])
    }
    let vm = makeCoachVM(container)

    let (ok, _) = await vm.executeTool(.createTask, arguments: ["description": "Plan a party"])
    #expect(ok)
    #expect(container.mockKnowledgeBase.handledTaskCreatedOrUpdated.isEmpty == false)

    // The discovery plan runs on a detached Task — wait for the subtasks.
    let planned = await IntegrationTestExpectations.waitFor {
        let tasks = (try? container.modelContext.fetch(FetchDescriptor<TodoTask>())) ?? []
        return tasks.contains { $0.title == "Planned" && !$0.subTasks.isEmpty }
    }
    #expect(planned)
}

// MARK: - searchTasks / getSubtasks

@MainActor
@Test func coachVM_searchTasks_finds_by_word() async {
    let container = IntegrationTestContainer()
    _ = insertTask(container, title: "Plan birthday party")
    let vm = makeCoachVM(container)

    let (ok, msg) = await vm.executeTool(.searchTasks, arguments: ["query": "birthday"])
    #expect(ok)
    #expect(msg.contains("Plan birthday party"))
}

@MainActor
@Test func coachVM_searchTasks_no_match() async {
    let container = IntegrationTestContainer()
    _ = insertTask(container, title: "Taxes")
    let vm = makeCoachVM(container)

    let (ok, msg) = await vm.executeTool(.searchTasks, arguments: ["query": "zzz_nonexistent"])
    #expect(ok)
    #expect(msg.contains("No tasks found"))
}

@MainActor
@Test func coachVM_getSubtasks_invalid_id() async {
    let container = IntegrationTestContainer()
    let vm = makeCoachVM(container)
    let (ok, msg) = await vm.executeTool(.getSubtasks, arguments: ["task_id": "not-a-uuid"])
    #expect(!ok)
    #expect(msg == "Invalid task ID")
}

@MainActor
@Test func coachVM_getSubtasks_lists_steps() async {
    let container = IntegrationTestContainer()
    let task = insertTask(container, title: "T", subtasks: [("Step A", .discovery), ("Step B", .discovery)])
    let vm = makeCoachVM(container)

    let (ok, msg) = await vm.executeTool(.getSubtasks, arguments: ["task_id": task.id.uuidString])
    #expect(ok)
    #expect(msg.contains("Step A"))
    #expect(msg.contains("Step B"))
    #expect(msg.contains("current"))
}

@MainActor
@Test func coachVM_getSubtasks_empty_task() async {
    let container = IntegrationTestContainer()
    let task = insertTask(container, title: "Empty")
    let vm = makeCoachVM(container)
    let (ok, msg) = await vm.executeTool(.getSubtasks, arguments: ["task_id": task.id.uuidString])
    #expect(ok)
    #expect(msg.contains("no subtasks"))
}

@MainActor
@Test func coachVM_getSubtasks_task_not_found() async {
    let container = IntegrationTestContainer()
    let vm = makeCoachVM(container)
    let (ok, msg) = await vm.executeTool(.getSubtasks, arguments: ["task_id": UUID().uuidString])
    #expect(!ok)
    #expect(msg == "Task not found")
}

// MARK: - updateDiscoveryQuestions / replanExecution

@MainActor
@Test func coachVM_updateDiscoveryQuestions_regenerates() async {
    let container = IntegrationTestContainer()
    container.mockPlanner.discoveryQuestionsProvider = { _ in
        TaskPlan(title: "Reframed", description: "d", subTasks: [
            SubTaskPlan(title: "New Q", description: "", requiresExternalAction: false)
        ])
    }
    let task = insertTask(container, title: "Orig", subtasks: [("Old Q", .discovery)])
    let vm = makeCoachVM(container)

    let (ok, msg) = await vm.executeTool(.updateDiscoveryQuestions, arguments: [
        "task_id": task.id.uuidString, "new_framing": "focus on budget"
    ])
    #expect(ok)
    #expect(msg.contains("Reframed"))
    #expect(task.discoverySubTasks.contains { $0.title == "New Q" })
    #expect(!task.discoverySubTasks.contains { $0.title == "Old Q" })
}

@MainActor
@Test func coachVM_replanExecution_regenerates_execution_steps() async {
    let container = IntegrationTestContainer()
    container.mockPlanner.executionPlanProvider = { _, _ in
        TaskPlan(title: "Replanned", description: "d", subTasks: [
            SubTaskPlan(title: "Exec X", description: "", requiresExternalAction: false),
            SubTaskPlan(title: "Exec Y", description: "", requiresExternalAction: true),
        ])
    }
    let task = insertTask(container, title: "T", subtasks: [("Discovery done", .discovery), ("Old exec", .execution)])
    task.transitionToExecution()
    task.discoverySubTasks.first?.markCompleted()
    try? container.modelContext.save()
    let vm = makeCoachVM(container)

    let (ok, msg) = await vm.executeTool(.replanExecution, arguments: [
        "task_id": task.id.uuidString, "guidance": "make it simpler"
    ])
    #expect(ok)
    #expect(msg.contains("Replanned"))
    #expect(task.executionSubTasks.map(\.title) == ["Exec X", "Exec Y"])
    #expect(task.executionSubTasks.first?.isCurrent == true)
}

@MainActor
@Test func coachVM_replanExecution_invalid_id() async {
    let container = IntegrationTestContainer()
    let vm = makeCoachVM(container)
    let (ok, _) = await vm.executeTool(.replanExecution, arguments: ["task_id": "bad"])
    #expect(!ok)
}

// MARK: - complete / skip / split / update subtask

@MainActor
@Test func coachVM_completeSubTask_marks_done_and_advances() async {
    let container = IntegrationTestContainer()
    let task = insertTask(container, title: "T", subtasks: [("A", .discovery), ("B", .discovery)])
    let a = task.sortedSubTasks[0]
    let b = task.sortedSubTasks[1]
    let vm = makeCoachVM(container)

    let (ok, msg) = await vm.executeTool(.completeSubTask, arguments: [
        "task_id": task.id.uuidString, "subtask_id": a.id.uuidString
    ])
    #expect(ok)
    #expect(msg.contains("Completed"))
    #expect(a.isCompleted)
    #expect(b.isCurrent)
}

@MainActor
@Test func coachVM_skipSubTask_marks_skipped() async {
    let container = IntegrationTestContainer()
    let task = insertTask(container, title: "T", subtasks: [("A", .discovery), ("B", .discovery)])
    let a = task.sortedSubTasks[0]
    let vm = makeCoachVM(container)

    let (ok, _) = await vm.executeTool(.skipSubTask, arguments: [
        "task_id": task.id.uuidString, "subtask_id": a.id.uuidString
    ])
    #expect(ok)
    #expect(a.status == .skipped)
    #expect(task.sortedSubTasks[1].isCurrent)
}

@MainActor
@Test func coachVM_completeSubTask_invalid_id() async {
    let container = IntegrationTestContainer()
    let vm = makeCoachVM(container)
    let (ok, msg) = await vm.executeTool(.completeSubTask, arguments: ["task_id": "x", "subtask_id": "y"])
    #expect(!ok)
    #expect(msg == "Invalid ID")
}

@MainActor
@Test func coachVM_splitSubTask_replaces_with_new_steps() async {
    let container = IntegrationTestContainer()
    let task = insertTask(container, title: "T", subtasks: [("Big step", .execution), ("Later", .execution)])
    task.transitionToExecution()
    let big = task.sortedSubTasks[0]
    let vm = makeCoachVM(container)

    let json = "[{\"title\":\"Part 1\",\"description\":\"first\"},{\"title\":\"Part 2\"}]"
    let (ok, msg) = await vm.executeTool(.splitSubTask, arguments: [
        "task_id": task.id.uuidString, "subtask_id": big.id.uuidString, "new_subtasks": json
    ])
    #expect(ok)
    #expect(msg.contains("Part 1"))
    #expect(!task.subTasks.contains { $0.id == big.id })
    #expect(task.subTasks.contains { $0.title == "Part 1" && $0.isCurrent })
    #expect(task.subTasks.contains { $0.title == "Part 2" })
    // "Later" preserved and pushed back in order
    #expect(task.subTasks.contains { $0.title == "Later" })
}

@MainActor
@Test func coachVM_splitSubTask_invalid_json() async {
    let container = IntegrationTestContainer()
    let task = insertTask(container, title: "T", subtasks: [("Step", .discovery)])
    let st = task.sortedSubTasks[0]
    let vm = makeCoachVM(container)

    let (ok, msg) = await vm.executeTool(.splitSubTask, arguments: [
        "task_id": task.id.uuidString, "subtask_id": st.id.uuidString, "new_subtasks": "not json"
    ])
    #expect(!ok)
    #expect(msg.contains("Invalid new_subtasks JSON"))
}

@MainActor
@Test func coachVM_updateSubTask_changes_title_and_description() async {
    let container = IntegrationTestContainer()
    let task = insertTask(container, title: "T", subtasks: [("Old title", .discovery)])
    let st = task.sortedSubTasks[0]
    let vm = makeCoachVM(container)

    let (ok, _) = await vm.executeTool(.updateSubTask, arguments: [
        "task_id": task.id.uuidString, "subtask_id": st.id.uuidString,
        "title": "New title", "description": "New desc"
    ])
    #expect(ok)
    #expect(st.title == "New title")
    #expect(st.subTaskDescription == "New desc")
}

@MainActor
@Test func coachVM_updateSubTask_requires_a_field() async {
    let container = IntegrationTestContainer()
    let task = insertTask(container, title: "T", subtasks: [("S", .discovery)])
    let st = task.sortedSubTasks[0]
    let vm = makeCoachVM(container)

    let (ok, msg) = await vm.executeTool(.updateSubTask, arguments: [
        "task_id": task.id.uuidString, "subtask_id": st.id.uuidString
    ])
    #expect(!ok)
    #expect(msg.contains("Must provide title or description"))
}

// MARK: - Knowledge-base tools

@MainActor
@Test func coachVM_createKnowledgeEntity_succeeds() async {
    let container = IntegrationTestContainer()
    let vm = makeCoachVM(container)
    let (ok, msg) = await vm.executeTool(.createKnowledgeEntity, arguments: ["name": "Dr. Smith"])
    #expect(ok)
    #expect(msg.contains("Dr. Smith"))
}

@MainActor
@Test func coachVM_generateKnowledgeSummary_succeeds() async {
    let container = IntegrationTestContainer()
    let vm = makeCoachVM(container)
    let (ok, msg) = await vm.executeTool(.generateKnowledgeSummary, arguments: [:])
    #expect(ok)
    #expect(msg == "Mock knowledge base summary")
}

@MainActor
@Test func coachVM_searchNotes_no_results() async {
    let container = IntegrationTestContainer()
    let vm = makeCoachVM(container)
    let (ok, msg) = await vm.executeTool(.searchNotes, arguments: ["query": "anything"])
    #expect(ok)
    #expect(msg.contains("No notes found"))
}

@MainActor
@Test func coachVM_readNote_not_found() async {
    let container = IntegrationTestContainer()
    let vm = makeCoachVM(container)
    let (ok, msg) = await vm.executeTool(.readNote, arguments: ["note_path": "/tmp/does-not-exist-\(UUID()).md"])
    #expect(!ok)
    #expect(msg.contains("Note not found"))
}

@MainActor
@Test func coachVM_readNote_reads_existing_file() async throws {
    let container = IntegrationTestContainer()
    let url = container.kbTempDir.appendingPathComponent("note.md")
    try "# Hello\n\nbody".write(to: url, atomically: true, encoding: .utf8)
    let vm = makeCoachVM(container)

    let (ok, msg) = await vm.executeTool(.readNote, arguments: ["note_path": url.path])
    #expect(ok)
    #expect(msg.contains("Hello"))
}

@MainActor
@Test func coachVM_editNote_and_replaceTextWithLink_on_existing_file() async throws {
    let container = IntegrationTestContainer()
    let url = container.kbTempDir.appendingPathComponent("editable.md")
    try "original text".write(to: url, atomically: true, encoding: .utf8)
    let vm = makeCoachVM(container)

    let (editOk, _) = await vm.executeTool(.editNote, arguments: ["note_path": url.path, "new_body": "new"])
    #expect(editOk)

    let (replaceOk, _) = await vm.executeTool(.replaceTextWithLink, arguments: [
        "note_path": url.path, "text_to_find": "original", "target_entity": "Thing"
    ])
    #expect(replaceOk)
}

@MainActor
@Test func coachVM_linkKnowledgeEntities_source_not_found() async {
    let container = IntegrationTestContainer()
    let vm = makeCoachVM(container)
    let (ok, msg) = await vm.executeTool(.linkKnowledgeEntities, arguments: [
        "source_note": "Nonexistent Entity", "target_entity": "Other"
    ])
    #expect(!ok)
    #expect(msg.contains("Source note not found"))
}

@MainActor
@Test func coachVM_linkKnowledgeEntities_with_existing_entity_file() async throws {
    let container = IntegrationTestContainer()
    // Create the entity file under rootURL/notes/_entities/<slug>.md
    let entitiesDir = container.mockKnowledgeBase.rootURL.appendingPathComponent("notes/_entities")
    try FileManager.default.createDirectory(at: entitiesDir, withIntermediateDirectories: true)
    let entityURL = entitiesDir.appendingPathComponent("dr-smith.md")
    try "# Dr Smith".write(to: entityURL, atomically: true, encoding: .utf8)
    let vm = makeCoachVM(container)

    let (ok, _) = await vm.executeTool(.linkKnowledgeEntities, arguments: [
        "source_note": "Dr Smith", "target_entity": "Clinic"
    ])
    #expect(ok)
}

@MainActor
@Test func coachVM_knowledge_tools_fail_without_knowledgeBase() async {
    let vm = CoachViewModel(context: CoachContext()) // no knowledgeBase
    let (ok, msg) = await vm.executeTool(.generateKnowledgeSummary, arguments: [:])
    #expect(!ok)
    #expect(msg.contains("Knowledge base not available"))
}
