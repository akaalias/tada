import Foundation
import SwiftData
@testable import Tada

/// Async polling helpers for integration tests that need to wait on state changes.
enum IntegrationTestExpectations {

    /// Polls a condition with the given timeout and interval.
    /// Returns true if the condition becomes true within the timeout, false otherwise.
    static func waitFor(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval = 5.0,
        interval: TimeInterval = 0.1,
        description: String = "condition"
    ) async -> Bool {
        let start = Date.now
        while Date.now.timeIntervalSince(start) < timeout {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        return false
    }

    /// Waits for a task to have discovery subtasks.
    static func waitForDiscoverySubtasks(
        in context: ModelContext,
        taskTitle: String,
        minCount: Int = 1,
        timeout: TimeInterval = 5.0
    ) async -> [SubTask]? {
        await waitFor({
            let fetchDescriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == taskTitle })
            guard let tasks = try? context.fetch(fetchDescriptor), let task = tasks.first else { return false }
            return task.subTasks.count >= minCount && task.isDiscoveryPhase
        }, timeout: timeout) ? fetchSubtasks(in: context, taskTitle: taskTitle) : nil
    }

    /// Waits for a task to have execution subtasks.
    static func waitForExecutionSubtasks(
        in context: ModelContext,
        taskTitle: String,
        minCount: Int = 1,
        timeout: TimeInterval = 5.0
    ) async -> [SubTask]? {
        await waitFor({
            let fetchDescriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == taskTitle })
            guard let tasks = try? context.fetch(fetchDescriptor), let task = tasks.first else { return false }
            return !task.executionSubTasks.isEmpty && task.isExecutionPhase
        }, timeout: timeout) ? fetchExecutionSubtasks(in: context, taskTitle: taskTitle) : nil
    }

    /// Waits for a task to be completed.
    static func waitForTaskCompletion(
        in context: ModelContext,
        taskTitle: String,
        timeout: TimeInterval = 5.0
    ) async -> Bool {
        await waitFor({
            let fetchDescriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == taskTitle })
            guard let tasks = try? context.fetch(fetchDescriptor), let task = tasks.first else { return false }
            return task.status == .completed && task.completedAt != nil
        }, timeout: timeout)
    }

    /// Waits for a knowledge base note to be written.
    static func waitForKBNote(
        in container: IntegrationTestContainer,
        relativePath: String,
        timeout: TimeInterval = 5.0
    ) async -> Bool {
        await waitFor({
            container.kbFileURL(relativePath: relativePath) != nil
        }, timeout: timeout)
    }

    /// Waits for a knowledge base file to contain specific content.
    static func waitForKBNoteContent(
        in container: IntegrationTestContainer,
        relativePath: String,
        contains substring: String,
        timeout: TimeInterval = 5.0
    ) async -> Bool {
        await waitFor({
            guard let content = container.kbFileContent(relativePath: relativePath) else { return false }
            return content.contains(substring)
        }, timeout: timeout)
    }

    /// Fetches discovery subtasks for a task.
    private static func fetchSubtasks(in context: ModelContext, taskTitle: String) -> [SubTask]? {
        let fetchDescriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == taskTitle })
        guard let tasks = try? context.fetch(fetchDescriptor), let task = tasks.first else { return nil }
        return task.subTasks.filter { $0.isDiscoveryPhase || $0.phase != .execution }
    }

    /// Fetches execution subtasks for a task.
    private static func fetchExecutionSubtasks(in context: ModelContext, taskTitle: String) -> [SubTask]? {
        let fetchDescriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == taskTitle })
        guard let tasks = try? context.fetch(fetchDescriptor), let task = tasks.first else { return nil }
        return task.executionSubTasks
    }
}
