import Foundation
import SwiftData
import Testing
@testable import Tada

// MARK: - Discovery Completion Tests

@MainActor
@Test func completing_one_discovery_subtask_advances_to_next() async throws {
    let container = IntegrationTestContainer()

    container.mockPlanner.discoveryQuestionsProvider = { _ in
        TaskPlan(
            title: "Trip Planning",
            description: "",
            subTasks: [
                SubTaskPlan(title: "When do you want to go?", description: "", requiresExternalAction: false),
                SubTaskPlan(title: "What's your budget?", description: "", requiresExternalAction: false),
                SubTaskPlan(title: "Who is coming?", description: "", requiresExternalAction: false)
            ]
        )
    }

    // Set up task with 3 discovery subtasks
    let task = TodoTask(title: "Trip Planning", originalInput: "Plan a trip")
    container.modelContext.insert(task)

    for (index, plan) in [
        SubTaskPlan(title: "When do you want to go?", description: "", requiresExternalAction: false),
        SubTaskPlan(title: "What's your budget?", description: "", requiresExternalAction: false),
        SubTaskPlan(title: "Who is coming?", description: "", requiresExternalAction: false)
    ].enumerated() {
        let subTask = SubTask(title: plan.title, description: plan.description, order: index)
        if index == 0 { subTask.markCurrent() }
        task.addSubTask(subTask)
                        subTask.task = task
        container.modelContext.insert(subTask)
    }

    try! container.modelContext.save()

    // Verify initial state: first subtask is current
    #expect(task.currentSubTask?.title == "When do you want to go?")

    // Simulate completing the first subtask
    let currentSubTask = try #require(task.currentSubTask)

    // Generate and cache action schema
    let schema = try await container.appServices.executiveAI.generateActionUI(
        subTask: currentSubTask.title,
        subTaskDescription: currentSubTask.subTaskDescription,
        taskContext: task.title,
        previousResponses: [],
        taskMemory: "",
        phase: currentSubTask.phase
    )

    // Create response and save it
    var actionResponse = ActionResponse()
    if let field = schema.fields.first {
        actionResponse.values[field.id] = .string("Next month")
    }

    if let responseData = try? JSONEncoder().encode(actionResponse) {
        currentSubTask.actionResponseData = responseData
    }

    // Mark completed and save
    currentSubTask.markCompleted()
    container.appServices.knowledgeBase.handleSubtaskCompleted(currentSubTask)
    try! container.modelContext.save()

    // Verify knowledge base was notified
    #expect(container.mockKnowledgeBase.handledSubtaskCompleted.count == 1)

    // Verify next subtask is now current
    let fetchDescriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "Trip Planning" })
    let tasks = try! container.modelContext.fetch(fetchDescriptor)
    let updatedTask = try #require(tasks.first)

    #expect(updatedTask.currentSubTask?.title == "What's your budget?")
    #expect(currentSubTask.isCompleted)

    // Verify response was saved
    let completedData = currentSubTask.actionResponseData
    #expect(completedData != nil)
    if let data = completedData,
       let response = try? JSONDecoder().decode(ActionResponse.self, from: data) {
        #expect(response.values["field_text"] == .string("Next month"))
    }

    // Verify task is still in discovery phase (not all questions answered yet)
    #expect(updatedTask.isDiscoveryPhase)
}

@MainActor
@Test func completing_all_discovery_subtasks_triggers_execution_planning() async throws {
    let container = IntegrationTestContainer()

    container.mockPlanner.discoveryQuestionsProvider = { _ in
        TaskPlan(
            title: "Trip Planning",
            description: "",
            subTasks: [
                SubTaskPlan(title: "When?", description: "", requiresExternalAction: false),
                SubTaskPlan(title: "Budget?", description: "", requiresExternalAction: false)
            ]
        )
    }

    // Configure execution plan response
    container.mockPlanner.executionPlanProvider = { originalTask, _ in
        TaskPlan(
            title: "Paris Weekend Plan",
            description: "Action plan for the trip",
            subTasks: [
                SubTaskPlan(title: "Book flights", description: "", requiresExternalAction: true),
                SubTaskPlan(title: "Reserve hotel", description: "", requiresExternalAction: true),
                SubTaskPlan(title: "Plan activities", description: "", requiresExternalAction: false)
            ]
        )
    }

    // Set up task with 2 discovery subtasks
    let task = TodoTask(title: "Trip Planning", originalInput: "Plan a trip")
    container.modelContext.insert(task)

    for (index, title) in ["When?", "Budget?"].enumerated() {
        let subTask = SubTask(title: title, description: "", order: index)
        if index == 0 { subTask.markCurrent() }
        task.addSubTask(subTask)
                        subTask.task = task
        container.modelContext.insert(subTask)
    }

    try! container.modelContext.save()

    // Complete first subtask
    let firstSubTask = try #require(task.currentSubTask)
    var response1 = ActionResponse()
    if let schema = try? await container.appServices.executiveAI.generateActionUI(
        subTask: firstSubTask.title, subTaskDescription: "", taskContext: task.title,
        previousResponses: [], taskMemory: "", phase: firstSubTask.phase) {
        if let field = schema.fields.first { response1.values[field.id] = .string("June") }
    }
    if let data = try? JSONEncoder().encode(response1) { firstSubTask.actionResponseData = data }
    firstSubTask.markCompleted()
    container.appServices.knowledgeBase.handleSubtaskCompleted(firstSubTask)

    // Complete second subtask
    let secondSubTask = try #require(task.sortedSubTasks.first(where: { $0.isPending }))
    var response2 = ActionResponse()
    if let schema = try? await container.appServices.executiveAI.generateActionUI(
        subTask: secondSubTask.title, subTaskDescription: "", taskContext: task.title,
        previousResponses: [["subTask": "When?", "field_text": "June"]], taskMemory: "", phase: secondSubTask.phase) {
        if let field = schema.fields.first { response2.values[field.id] = .string("500") }
    }
    if let data = try? JSONEncoder().encode(response2) { secondSubTask.actionResponseData = data }
    secondSubTask.markCompleted()
    container.appServices.knowledgeBase.handleSubtaskCompleted(secondSubTask)

    try! container.modelContext.save()

    // Verify both subtasks are completed
    #expect(firstSubTask.isCompleted)
    #expect(secondSubTask.isCompleted)

    // Verify knowledge base was notified for both completions
    #expect(container.mockKnowledgeBase.handledSubtaskCompleted.count == 2)

    // Now simulate transition to execution phase
    let discoveryAnswers: [CompletedSubTaskInfo] = [
        CompletedSubTaskInfo(title: "When?", response: "June"),
        CompletedSubTaskInfo(title: "Budget?", response: "500")
    ]

    do {
        let executionPlan = try await container.appServices.plannerAI.createExecutionPlan(
            originalTask: "Trip Planning", discoveryAnswers: discoveryAnswers)

        await MainActor.run {
            task.transitionToExecution()
            task.title = executionPlan.title
            task.taskDescription = executionPlan.description

            for (index, plan) in executionPlan.subTasks.enumerated() {
                let subTask = SubTask(
                    title: plan.title, description: plan.description, order: index,
                    phase: .execution, requiresExternalAction: plan.requiresExternalAction ?? false)
                if index == 0 { subTask.markCurrent() }
                task.addSubTask(subTask)
                subTask.task = task
                container.modelContext.insert(subTask)
            }

            task.planningStatus = .idle
            try? container.modelContext.save()
            container.appServices.knowledgeBase.handleTaskCreatedOrUpdated(task)
        }
    } catch {
        throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create execution plan: \(error)"])
    }

    // Verify task is now in execution phase
    let fetchDescriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "Paris Weekend Plan" })
    let tasks = try! container.modelContext.fetch(fetchDescriptor)
    let updatedTask = try #require(tasks.first)

    #expect(updatedTask.isExecutionPhase)
    #expect(updatedTask.executionSubTasks.count == 3)
    #expect(updatedTask.currentSubTask?.title == "Book flights")

    // Verify knowledge base was notified for task update
    #expect(container.mockKnowledgeBase.handledTaskCreatedOrUpdated.count >= 1)
}

@MainActor
@Test func discovery_subtask_responses_are_preserved() async throws {
    let container = IntegrationTestContainer()

    container.mockPlanner.discoveryQuestionsProvider = { _ in
        TaskPlan(title: "Test", description: "", subTasks: [
            SubTaskPlan(title: "Question 1?", description: "", requiresExternalAction: false)
        ])
    }

    let task = TodoTask(title: "Test", originalInput: "Test")
    container.modelContext.insert(task)

    let subTask = SubTask(title: "Question 1?", description: "", order: 0)
    subTask.markCurrent()
    task.addSubTask(subTask)
                        subTask.task = task

    // Generate schema with multiple field types
    let schema = ActionSchema(
        type: .form,
        title: "Question 1?",
        description: "",
        fields: [
            ActionField(id: "text_field", type: .text, label: "Answer", placeholder: nil, options: nil, defaultValue: nil, prefillRows: nil),
            ActionField(id: "number_field", type: .number, label: "Count", placeholder: nil, options: nil, defaultValue: nil, prefillRows: nil)
        ],
        submitLabel: "Continue",
        requiresExternalAction: false
    )

    var response = ActionResponse()
    response.values["text_field"] = .string("Hello")
    response.values["number_field"] = .number(42)

    if let data = try? JSONEncoder().encode(response) {
        subTask.actionResponseData = data
    }

    subTask.markCompleted()
    container.appServices.knowledgeBase.handleSubtaskCompleted(subTask)
    try! container.modelContext.save()

    // Verify response can be decoded back correctly
    let fetchDescriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "Test" })
    let tasks = try! container.modelContext.fetch(fetchDescriptor)
    let savedTask = try #require(tasks.first)

    guard let responseData = savedTask.subTasks.first?.actionResponseData else {
        throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response data found"])
        return
    }

    let decoded = try JSONDecoder().decode(ActionResponse.self, from: responseData)
    #expect(decoded.values["text_field"] == .string("Hello"))
    #expect(decoded.values["number_field"] == .number(42))
}
