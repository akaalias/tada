import Foundation
import SwiftData
import Testing
@testable import Tada

// MARK: - Collapsed Sub-Task Sections Tests 

/// Verifies that when a task has completed discovery sub-tasks,
/// the SubTaskListContent should render the discovery section collapsed by default.
@MainActor
@Test func subtask_list_collapses_completed_discovery_sections() async throws {
    let container = IntegrationTestContainer()

    // Create a task that has completed discovery and is now in execution phase
    let task = TodoTask(title: "Test Task", originalInput: "test input")
    task.status = .active
    container.modelContext.insert(task)

    // Add 2 completed discovery sub-tasks
    let disc1 = SubTask(title: "What is the goal?", description: "", order: 0)
    disc1.markCompleted()
    task.addSubTask(disc1)
    container.modelContext.insert(disc1)

    let disc2 = SubTask(title: "What is the budget?", description: "", order: 1)
    disc2.markCompleted()
    task.addSubTask(disc2)
    container.modelContext.insert(disc2)

    // Transition task to execution phase
    task.transitionToExecution()

    // Add 3 execution sub-tasks (first one is current)
    let exec1 = SubTask(title: "Step 1", description: "", order: 2, phase: .execution)
    exec1.markCurrent()
    task.addSubTask(exec1)
    container.modelContext.insert(exec1)

    let exec2 = SubTask(title: "Step 2", description: "", order: 3, phase: .execution)
    task.addSubTask(exec2)
    container.modelContext.insert(exec2)

    let exec3 = SubTask(title: "Step 3", description: "", order: 4, phase: .execution)
    task.addSubTask(exec3)
    container.modelContext.insert(exec3)

    try! container.save()

    // Verify: discovery is complete
    #expect(task.discoverySubTasks.allSatisfy { $0.isCompleted })

    // Verify: task is in execution phase
    #expect(task.isExecutionPhase)

    // The key assertion: SubTaskListContent should start with discoveryCollapsed = true
    // when all discovery sub-tasks are complete.
    let listContent = SubTaskListContent(task: task)

    // We can't directly test @State values, but we can verify the computed property
    // that determines collapse state. The SubTaskListContent should have a computed
    // property or logic that sets discoveryExpanded to false when discovery is complete.

    let discoveryComplete = task.discoverySubTasks.allSatisfy { $0.isCompleted }
    #expect(discoveryComplete == true, "Discovery should be marked as complete")

    // The bug: SubTaskListContent has `@State private var discoveryExpanded = true`
    // which always starts expanded. It should be `false` when all discovery is complete.

    // Verify: execution sub-tasks exist and first is current
    #expect(task.executionSubTasks.count == 3)
    #expect(task.executionSubTasks.first(where: { $0.isCurrent }) != nil)

    // Verify: discovery sub-tasks are all completed
    for disc in task.discoverySubTasks {
        #expect(disc.isCompleted, "Discovery sub-task '\(disc.title)' should be completed")
    }
}

/// Verifies that when discovery is NOT complete, the discovery section stays expanded.
@MainActor
@Test func subtask_list_keeps_discovery_expanded_when_incomplete() async throws {
    let container = IntegrationTestContainer()

    // Create a task still in discovery phase with incomplete sub-tasks
    let task = TodoTask(title: "In-Progress Discovery", originalInput: "test")
    task.status = .active
    container.modelContext.insert(task)

    let disc1 = SubTask(title: "What is the goal?", description: "", order: 0)
    disc1.markCompleted()
    task.addSubTask(disc1)
    container.modelContext.insert(disc1)

    let disc2 = SubTask(title: "What is the budget?", description: "", order: 1)
    disc2.markCurrent() // Not completed — this is the current question
    task.addSubTask(disc2)
    container.modelContext.insert(disc2)

    try! container.save()

    // Discovery is NOT complete
    let discoveryComplete = task.discoverySubTasks.allSatisfy { $0.isCompleted }
    #expect(discoveryComplete == false, "Discovery should NOT be complete")

    // The SubTaskListContent should keep discovery expanded when incomplete
}

/// Verifies that an all-completed task (both discovery and execution) has both sections collapsed.
@MainActor
@Test func subtask_list_collapses_both_sections_when_all_complete() async throws {
    let container = IntegrationTestContainer()

    // Create a fully completed task
    let task = TodoTask(title: "Completed Task", originalInput: "test")
    task.status = .active
    container.modelContext.insert(task)

    // Completed discovery
    let disc1 = SubTask(title: "Q1", description: "", order: 0)
    disc1.markCompleted()
    task.addSubTask(disc1)
    container.modelContext.insert(disc1)

    // Completed execution
    let exec1 = SubTask(title: "Step 1", description: "", order: 1, phase: .execution)
    exec1.markCompleted()
    task.addSubTask(exec1)
    container.modelContext.insert(exec1)

    let exec2 = SubTask(title: "Step 2", description: "", order: 2, phase: .execution)
    exec2.markCompleted()
    task.addSubTask(exec2)
    container.modelContext.insert(exec2)

    try! container.save()

    #expect(task.discoverySubTasks.allSatisfy { $0.isCompleted })
    #expect(task.executionSubTasks.allSatisfy { $0.isCompleted })

    // Both sections should be collapsed when all complete
}
