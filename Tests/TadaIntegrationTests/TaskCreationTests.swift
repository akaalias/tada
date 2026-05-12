import Foundation
import SwiftData
import Testing
@testable import Tada

// MARK: - Task Creation & Discovery Phase Tests

@MainActor
@Test func task_created_with_planning_discovery_status() async throws {
    APIKeyManager._setTestingStorage(testUserDefaults())
    let container = IntegrationTestContainer()
    defer { container.resetMocks() }

    // Set API key so planning can proceed
    try! APIKeyManager.setAPIKey(testAPIKey)

    // Configure mock to return 3 discovery questions
    container.mockPlanner.discoveryQuestionsProvider = { task in
        TaskPlan(
            title: "Weekend Trip to Paris",
            description: "Planning a weekend getaway to the city of light",
            subTasks: [
                SubTaskPlan(title: "What dates are you looking to travel?", description: "", requiresExternalAction: false),
                SubTaskPlan(title: "What is your budget for the trip?", description: "", requiresExternalAction: false),
                SubTaskPlan(title: "Who is traveling with you?", description: "", requiresExternalAction: false)
            ]
        )
    }

    // Create a task directly (simulating NewTaskSheet.createTask())
    let task = TodoTask(title: "Plan a weekend trip to Paris", originalInput: "Plan a weekend trip to Paris")
    task.planningStatus = .planningDiscovery
    container.modelContext.insert(task)
    try! container.modelContext.save()
    container.appServices.knowledgeBase.handleTaskCreatedOrUpdated(task)

    #expect(task.status == .active)
    #expect(task.planningStatus == .planningDiscovery)

    // Simulate the async planning call that NewTaskSheet does
    do {
        let discoveryPlan = try await container.appServices.plannerAI.generateDiscoveryQuestions(for: "Plan a weekend trip to Paris")

        await MainActor.run {
            task.title = discoveryPlan.title
            task.taskDescription = discoveryPlan.description

            let cappedQuestions = Array(discoveryPlan.subTasks.prefix(7))
            for (index, questionPlan) in cappedQuestions.enumerated() {
                let subTask = SubTask(
                    title: questionPlan.title,
                    description: questionPlan.description,
                    order: index
                )
                if index == 0 {
                    subTask.markCurrent()
                }
                task.addSubTask(subTask)
                        subTask.task = task
                container.modelContext.insert(subTask)
            }

            task.planningStatus = .idle
            try? container.modelContext.save()
            container.appServices.knowledgeBase.handleTaskCreatedOrUpdated(task)
        }
    } catch {
        throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate discovery questions: \(error)"])
    }

    // Verify task state after planning
    let fetchDescriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "Weekend Trip to Paris" })
    let tasks = try! container.modelContext.fetch(fetchDescriptor)
    let updatedTask = try #require(tasks.first, "Task not found after planning")

    #expect(updatedTask.title == "Weekend Trip to Paris")
    #expect(updatedTask.planningStatus == .idle)
    #expect(updatedTask.status == .active)
    #expect(updatedTask.phase == .discovery)

    // Verify discovery subtasks were created
    let subTasks = updatedTask.subTasks
    #expect(subTasks.count == 3)

    // Verify first subtask is marked current
    let currentSubTask = updatedTask.currentSubTask
    #expect(currentSubTask != nil)
    #expect(currentSubTask?.title == "What dates are you looking to travel?")

    // Verify all subtasks have correct order
    let sorted = subTasks.sorted(by: { $0.order < $1.order })
    #expect(sorted[0].order == 0)
    #expect(sorted[1].order == 1)
    #expect(sorted[2].order == 2)

    // Verify knowledge base was notified
    #expect(container.mockKnowledgeBase.handledTaskCreatedOrUpdated.count == 2) // initial + after planning
}

@MainActor
@Test func task_created_without_api_key_stays_idle() async throws {
    APIKeyManager._setTestingStorage(testUserDefaults())
    let container = IntegrationTestContainer()

    // No API key set — planning should not proceed
    APIKeyManager.deleteAPIKey()

    let task = TodoTask(title: "Test Task Without Key", originalInput: "Test")
    container.modelContext.insert(task)
    try! container.modelContext.save()

    #expect(task.planningStatus == .idle)
    #expect(task.status == .active)

    // Creating a task without API key should not trigger planning
    let fetchDescriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "Test Task Without Key" })
    let tasks = try! container.modelContext.fetch(fetchDescriptor)
    let savedTask = try #require(tasks.first)

    #expect(savedTask.planningStatus == .idle)
    #expect(savedTask.subTasks.isEmpty)
}

@MainActor
@Test func task_creation_triggers_knowledge_base_notification() async throws {
    APIKeyManager._setTestingStorage(testUserDefaults())
    let container = IntegrationTestContainer()

    try! APIKeyManager.setAPIKey(testAPIKey)
    container.mockPlanner.discoveryQuestionsProvider = { _ in
        TaskPlan(title: "Test", description: "", subTasks: [])
    }

    let task = TodoTask(title: "KB Test Task", originalInput: "Test")
    container.modelContext.insert(task)
    try! container.modelContext.save()

    // Simulate knowledge base notification from NewTaskSheet
    container.appServices.knowledgeBase.handleTaskCreatedOrUpdated(task)

    #expect(container.mockKnowledgeBase.handledTaskCreatedOrUpdated.count == 1)
    #expect(container.mockKnowledgeBase.handledTaskCreatedOrUpdated[0].title == "KB Test Task")
}

@MainActor
@Test func task_with_no_discovery_questions_stays_in_discovery_phase() async throws {
    APIKeyManager._setTestingStorage(testUserDefaults())
    let container = IntegrationTestContainer()

    try! APIKeyManager.setAPIKey(testAPIKey)
    // Return empty subtasks — task is clear enough
    container.mockPlanner.discoveryQuestionsProvider = { _ in
        TaskPlan(title: "Quick Note", description: "", subTasks: [])
    }

    let task = TodoTask(title: "Quick Note", originalInput: "Quick Note")
    container.modelContext.insert(task)
    try! container.modelContext.save()

    do {
        let plan = try await container.appServices.plannerAI.generateDiscoveryQuestions(for: "Quick Note")
        await MainActor.run {
            task.title = plan.title
            task.taskDescription = plan.description
            // No subtasks to add — empty array
            task.planningStatus = .idle
            try? container.modelContext.save()
        }
    } catch {
        throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Planning failed: \(error)"])
    }

    let fetchDescriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "Quick Note" })
    let tasks = try! container.modelContext.fetch(fetchDescriptor)
    let savedTask = try #require(tasks.first)

    // Even with no questions, the task should be in discovery phase
    #expect(savedTask.phase == .discovery)
    #expect(savedTask.planningStatus == .idle)
}
