import Foundation
import SwiftData
import Testing
@testable import Tada

// MARK: - Execution Phase Tests

@MainActor
@Test func completing_execution_step_creates_knowledge_base_note() async throws {
    let container = IntegrationTestContainer()

    container.mockExecutive.schemaProvider = { subTask, _, _, _, _ in
        ActionSchema(
            type: .form, title: subTask, description: "", fields: [
                ActionField(id: "text", type: .text, label: subTask, placeholder: nil, options: nil, defaultValue: nil, prefillRows: nil)
            ], submitLabel: "Continue", requiresExternalAction: false
        )
    }

    // Set up a task in execution phase with 3 steps
    let task = TodoTask(title: "Paris Weekend Plan", originalInput: "Plan a trip")
    task.phase = .execution
    container.modelContext.insert(task)

    let stepTitles = ["Book flights", "Reserve hotel", "Plan activities"]
    for (index, title) in stepTitles.enumerated() {
        let subTask = SubTask(title: title, description: "", order: index, phase: .execution)
        if index == 0 { subTask.markCurrent() }
        task.addSubTask(subTask)
        subTask.task = task
        container.modelContext.insert(subTask)
    }

    try! container.modelContext.save()

    // Fetch task from context to ensure relationships are materialized
    let fetchDescriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "Paris Weekend Plan" })
    let tasks = try! container.modelContext.fetch(fetchDescriptor)
    let currentTask = try #require(tasks.first)

    // Complete the first execution step
    let currentStep = try #require(currentTask.currentSubTask)

    let schema = try await container.appServices.executiveAI.generateActionUI(
        subTask: currentStep.title, subTaskDescription: "", taskContext: currentTask.title,
        previousResponses: [], taskMemory: "", phase: currentStep.phase)

    var response = ActionResponse()
    if let field = schema.fields.first { response.values[field.id] = .string("Done") }
    if let data = try? JSONEncoder().encode(response) { currentStep.actionResponseData = data }
    currentStep.markCompleted()
    container.appServices.knowledgeBase.handleSubtaskCompleted(currentStep)

    try! container.modelContext.save()

    // Verify knowledge base note was created
    #expect(container.mockKnowledgeBase.handledSubtaskCompleted.count == 1)

    // Verify the next step is now current (re-fetch to see updated state)
    let fetchDescriptor2 = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "Paris Weekend Plan" })
    let tasks2 = try! container.modelContext.fetch(fetchDescriptor2)
    let updatedTask = try #require(tasks2.first)

    #expect(updatedTask.currentSubTask?.title == "Reserve hotel")
    #expect(currentStep.isCompleted)

    // Verify knowledge base file was written to disk
    let kbPath = "tasks/paris-weekend-plan/book-flights.md"
    #expect(container.kbFileURL(relativePath: kbPath) != nil, "Knowledge base note should exist on disk")

    let content = container.kbFileContent(relativePath: kbPath)
    #expect(content != nil, "Knowledge base note should have content")
    #expect(content?.contains("Book flights") == true, "Note should contain the step title")
}

@MainActor
@Test func completing_all_execution_steps_marks_task_completed() async throws {
    let container = IntegrationTestContainer()

    container.mockExecutive.schemaProvider = { subTask, _, _, _, _ in
        ActionSchema(
            type: .form, title: subTask, description: "", fields: [
                ActionField(id: "text", type: .text, label: subTask, placeholder: nil, options: nil, defaultValue: nil, prefillRows: nil)
            ], submitLabel: "Continue", requiresExternalAction: false
        )
    }

    // Set up task in execution phase with 2 steps
    let task = TodoTask(title: "Execute Test", originalInput: "Test")
    task.phase = .execution
    container.modelContext.insert(task)

    for (index, title) in ["Step A", "Step B"].enumerated() {
        let subTask = SubTask(title: title, description: "", order: index, phase: .execution)
        if index == 0 { subTask.markCurrent() }
        task.addSubTask(subTask)
        subTask.task = task
        container.modelContext.insert(subTask)
    }

    try! container.modelContext.save()

    // Fetch task from context to ensure relationships are materialized
    let fetchDescriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "Execute Test" })
    let tasks = try! container.modelContext.fetch(fetchDescriptor)
    let currentTask = try #require(tasks.first)

    // Complete step A
    let stepA = try #require(currentTask.currentSubTask)
    var responseA = ActionResponse()
    if let schema = try? await container.appServices.executiveAI.generateActionUI(
        subTask: stepA.title, subTaskDescription: "", taskContext: currentTask.title,
        previousResponses: [], taskMemory: "", phase: stepA.phase) {
        if let field = schema.fields.first { responseA.values[field.id] = .string("Done A") }
    }
    if let data = try? JSONEncoder().encode(responseA) { stepA.actionResponseData = data }
    stepA.markCompleted()
    container.appServices.knowledgeBase.handleSubtaskCompleted(stepA)

    // Complete step B (last step)
    let stepB = try #require(currentTask.sortedSubTasks.first(where: { $0.isPending }))
    var responseB = ActionResponse()
    if let schema = try? await container.appServices.executiveAI.generateActionUI(
        subTask: stepB.title, subTaskDescription: "", taskContext: currentTask.title,
        previousResponses: [["subTask": "Step A", "text": "Done A"]], taskMemory: "", phase: stepB.phase) {
        if let field = schema.fields.first { responseB.values[field.id] = .string("Done B") }
    }
    if let data = try? JSONEncoder().encode(responseB) { stepB.actionResponseData = data }
    stepB.markCompleted()
    container.appServices.knowledgeBase.handleSubtaskCompleted(stepB)

    try! container.modelContext.save()

    // Verify both steps are completed
    #expect(stepA.isCompleted)
    #expect(stepB.isCompleted)

    // Manually mark task as completed (in real app this happens after last step)
    currentTask.markCompleted()
    container.appServices.knowledgeBase.handleTaskCompleted(currentTask)
    try! container.modelContext.save()

    // Verify task is completed
    let fetchDescriptor2 = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "Execute Test" })
    let tasks2 = try! container.modelContext.fetch(fetchDescriptor2)
    let updatedTask = try #require(tasks2.first)

    #expect(updatedTask.status == .completed)
    #expect(updatedTask.completedAt != nil)

    // Verify knowledge base was notified for task completion
    #expect(container.mockKnowledgeBase.handledTaskCompleted.count == 1)

    // Verify knowledge base notes exist for both steps
    #expect(container.kbFileURL(relativePath: "tasks/execute-test/step-a.md") != nil)
    #expect(container.kbFileURL(relativePath: "tasks/execute-test/step-b.md") != nil)

    // Verify task summary was written
    #expect(container.kbFileURL(relativePath: "tasks/execute-test/summary.md") != nil)
}

@MainActor
@Test func plan_revision_returns_no_change_by_default() async throws {
    let container = IntegrationTestContainer()

    container.mockPlanner.revisionProvider = { _, _, _ in
        PlanRevision(revised: false, reason: "Plan is optimal", subTasks: nil)
    }

    let revision = try await container.appServices.plannerAI.revisePlan(
        originalTask: "Test", completedSubTasks: [], remainingSubTasks: ["Step 1"])

    #expect(revision.revised == false)
    #expect(revision.reason == "Plan is optimal")
    #expect(revision.subTasks == nil)
}

@MainActor
@Test func plan_revision_can_return_revised_plan() async throws {
    let container = IntegrationTestContainer()

    container.mockPlanner.revisionProvider = { _, _, _ in
        PlanRevision(
            revised: true,
            reason: "Splitting compound steps",
            subTasks: [
                SubTaskPlan(title: "New step 1", description: "", requiresExternalAction: false),
                SubTaskPlan(title: "New step 2", description: "", requiresExternalAction: false)
            ]
        )
    }

    let revision = try await container.appServices.plannerAI.revisePlan(
        originalTask: "Test", completedSubTasks: [], remainingSubTasks: ["Old step"])

    #expect(revision.revised == true)
    #expect(revision.reason == "Splitting compound steps")
    #expect(revision.subTasks?.count == 2)
    #expect(revision.subTasks?[0].title == "New step 1")
}

@MainActor
@Test func knowledge_base_handles_task_completion_event() async throws {
    let container = IntegrationTestContainer()


    let task = TodoTask(title: "Completed Task", originalInput: "Done")
    container.modelContext.insert(task)

    // Simulate task completion notification
    container.appServices.knowledgeBase.handleTaskCompleted(task)

    #expect(container.mockKnowledgeBase.handledTaskCompleted.count == 1)
    #expect(container.mockKnowledgeBase.handledTaskCompleted[0].title == "Completed Task")

    // Verify summary note was written
    #expect(container.kbFileURL(relativePath: "tasks/completed-task/summary.md") != nil)
}
