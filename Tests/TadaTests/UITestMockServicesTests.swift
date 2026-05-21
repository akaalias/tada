import Foundation
import Testing
@testable import Tada

// MARK: - UITestPlannerAIService

@MainActor
@Test func uiPlanner_discoveryQuestions_returns_scripted_plan() async throws {
    let planner = UITestPlannerAIService()
    let plan = try await planner.generateDiscoveryQuestions(for: "Book a trip")
    #expect(plan.title == "Book a trip")
    #expect(plan.subTasks.map(\.title) == UITestPlannerAIService.discoveryQuestions)
}

@MainActor
@Test func uiPlanner_executionPlan_returns_scripted_steps() async throws {
    let planner = UITestPlannerAIService()
    let plan = try await planner.createExecutionPlan(originalTask: "Book a trip", discoveryAnswers: [])
    #expect(plan.subTasks.map(\.title) == UITestPlannerAIService.executionSteps)
}

@MainActor
@Test func uiPlanner_revise_breakdown_learning() async throws {
    let planner = UITestPlannerAIService()
    let revision = try await planner.revisePlan(originalTask: "T", completedSubTasks: [], remainingSubTasks: [])
    #expect(revision.revised == false)

    let steps = try await planner.breakDownStep(stepTitle: "Big", stepDescription: "", taskContext: "", discoveryContext: "", executionProgress: "")
    #expect(steps.count == 1)

    let lesson = try await planner.generateLearning(badStepTitle: "B", taskContext: "", discoveryContext: "", executionProgress: "")
    #expect(lesson == "Test learning")
}

// MARK: - UITestExecutiveAIService

@Test func uiExecutive_returns_text_field_schema() async throws {
    let executive = UITestExecutiveAIService()
    let schema = try await executive.generateActionUI(
        subTask: "Pick a date", subTaskDescription: "desc", taskContext: "Trip",
        previousResponses: [], taskMemory: "", phase: .discovery
    )
    #expect(schema.title == "Pick a date")
    #expect(schema.fields.count == 1)
    #expect(schema.fields.first?.type == .text)
    #expect(schema.submitLabel == "Continue")
}

// MARK: - UITestKnowledgeBaseService

@MainActor
private func freshKBRoot() -> URL {
    let root = UITestKnowledgeBaseService.stableRootURL
    try? FileManager.default.removeItem(at: root)
    try? FileManager.default.createDirectory(at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
    return root
}

@MainActor
@Test func uiKB_handleTaskCreatedOrUpdated_writes_overview_and_index() {
    let root = freshKBRoot()
    let kb = UITestKnowledgeBaseService()

    let task = TodoTask(title: "Trip Plan", originalInput: "trip")
    kb.handleTaskCreatedOrUpdated(task)

    let index = try? String(contentsOf: kb.indexURL, encoding: .utf8)
    #expect(index?.contains("Trip Plan") == true)
    #expect(index?.contains("## In progress") == true)

    let folder = root.appendingPathComponent("notes/\(task.id.uuidString)__trip-plan/_overview.md")
    #expect(FileManager.default.fileExists(atPath: folder.path))
}

@MainActor
@Test func uiKB_handleSubtaskCompleted_writes_note() {
    _ = freshKBRoot()
    let kb = UITestKnowledgeBaseService()

    let task = TodoTask(title: "Trip", originalInput: "trip")
    let sub = SubTask(title: "Pick dates", description: "", order: 0, phase: .discovery)
    sub.markCompleted()
    task.addSubTask(sub)
    sub.task = task

    kb.handleSubtaskCompleted(sub)

    let noteURL = kb.rootURL.appendingPathComponent("notes/\(task.id.uuidString)__trip/01-pick-dates.md")
    #expect(FileManager.default.fileExists(atPath: noteURL.path))
    let overview = try? String(contentsOf: kb.rootURL.appendingPathComponent("notes/\(task.id.uuidString)__trip/_overview.md"), encoding: .utf8)
    #expect(overview?.contains("Pick dates") == true)
}

@MainActor
@Test func uiKB_handleTaskCompleted_marks_completed_in_index() {
    _ = freshKBRoot()
    let kb = UITestKnowledgeBaseService()

    let task = TodoTask(title: "Finished", originalInput: "done")
    task.markCompleted()
    kb.handleTaskCompleted(task)

    let index = try? String(contentsOf: kb.indexURL, encoding: .utf8)
    #expect(index?.contains("## Completed") == true)
    #expect(index?.contains("Finished") == true)
}

@MainActor
@Test func uiKB_reconcile_writes_all_tasks() {
    _ = freshKBRoot()
    let kb = UITestKnowledgeBaseService()
    let a = TodoTask(title: "Alpha", originalInput: "a")
    let b = TodoTask(title: "Beta", originalInput: "b")
    kb.reconcile(tasks: [a, b])

    let index = try? String(contentsOf: kb.indexURL, encoding: .utf8)
    #expect(index?.contains("Alpha") == true)
    #expect(index?.contains("Beta") == true)
}

@MainActor
@Test func uiKB_createUserNote_and_listUserNotes() async {
    _ = freshKBRoot()
    let kb = UITestKnowledgeBaseService()
    let url = await kb.createUserNote(title: "My Idea", body: "do something")
    #expect(FileManager.default.fileExists(atPath: url.path))
    let notes = await kb.listUserNotes()
    #expect(notes.contains { $0.title == "My Idea" })
}

@MainActor
@Test func uiKB_noop_methods_return_defaults() async throws {
    _ = freshKBRoot()
    let kb = UITestKnowledgeBaseService()

    #expect(kb.isWorking == false)
    #expect(await kb.backlinks(toEntitySlug: "x").isEmpty)
    let graph = await kb.buildGraphData()
    #expect(graph.nodes.isEmpty && graph.links.isEmpty)
    let cleanup = await kb.cleanupOrphanedNotes(existingTaskIds: [])
    #expect(cleanup.taskFolders == 0 && cleanup.entities == 0)
    #expect(await kb.searchNotes(query: "x").isEmpty)
    #expect(try await kb.generateSummary() == "Test knowledge base summary")

    // The remaining hooks are no-ops that must not throw.
    let url = kb.rootURL.appendingPathComponent("notes/x.md")
    await kb.runLinkDiscoveryForNote(url)
    await kb.runEntityExtractionForCurrentNote(url)
    try await kb.createEntity(name: "E", body: "b")
    try await kb.addLinkToNote(at: url, targetEntity: "E")
    try await kb.replaceTextWithLink(at: url, textToFind: "a", targetEntity: "E")
    try await kb.editNoteBody(at: url, newBody: "b")
}

@MainActor
@Test func uiKB_slugify_normalizes() {
    #expect(UITestKnowledgeBaseService.slugify("Plan My Trip!") == "plan-my-trip")
    #expect(UITestKnowledgeBaseService.slugify("  spaces  ") == "spaces")
}
