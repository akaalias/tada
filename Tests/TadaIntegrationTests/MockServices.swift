import Foundation
@testable import Tada

// MARK: - Mock Planner AI Service

/// Returns deterministic discovery questions for any input task.
final class MockPlannerAIService: PlannerAIServiceProtocol {

    /// Optional callback to customize responses per call.
    var discoveryQuestionsProvider: ((String) -> TaskPlan)?
    var executionPlanProvider: ((String, [CompletedSubTaskInfo]) -> TaskPlan)?
    var revisionProvider: ((String, [CompletedSubTaskInfo], [String], [String: Any]) -> PlanRevision)?
    var breakdownProvider: ((String, String, String, String, String) -> [SubTaskPlan])?
    var learningProvider: ((String, String, String, String) -> String)?

    func generateDiscoveryQuestions(for task: String) async throws -> TaskPlan {
        if let provider = discoveryQuestionsProvider {
            return provider(task)
        }
        // Default: 3 generic discovery questions
        return TaskPlan(
            title: task,
            description: "Exploring your request",
            subTasks: [
                SubTaskPlan(title: "What is the primary goal?", description: "", requiresExternalAction: false),
                SubTaskPlan(title: "What are the constraints?", description: "", requiresExternalAction: false),
                SubTaskPlan(title: "What is the timeline?", description: "", requiresExternalAction: false)
            ]
        )
    }

    func createExecutionPlan(
        originalTask: String,
        discoveryAnswers: [CompletedSubTaskInfo]
    ) async throws -> TaskPlan {
        if let provider = executionPlanProvider {
            return provider(originalTask, discoveryAnswers)
        }
        // Default: 3 generic execution steps
        return TaskPlan(
            title: originalTask,
            description: "Action plan",
            subTasks: [
                SubTaskPlan(title: "Step 1: Prepare", description: "", requiresExternalAction: false),
                SubTaskPlan(title: "Step 2: Execute", description: "", requiresExternalAction: false),
                SubTaskPlan(title: "Step 3: Review", description: "", requiresExternalAction: false)
            ]
        )
    }

    func revisePlan(
        originalTask: String,
        completedSubTasks: [CompletedSubTaskInfo],
        remainingSubTasks: [String],
        latestResponse: [String: Any]
    ) async throws -> PlanRevision {
        if let provider = revisionProvider {
            return provider(originalTask, completedSubTasks, remainingSubTasks, latestResponse)
        }
        // Default: no revision needed
        return PlanRevision(revised: false, reason: nil, subTasks: nil)
    }

    func breakDownStep(
        stepTitle: String,
        stepDescription: String,
        taskContext: String,
        discoveryContext: String,
        executionProgress: String
    ) async throws -> [SubTaskPlan] {
        if let provider = breakdownProvider {
            return provider(stepTitle, stepDescription, taskContext, discoveryContext, executionProgress)
        }
        return [
            SubTaskPlan(title: "Sub-step 1", description: "", requiresExternalAction: false),
            SubTaskPlan(title: "Sub-step 2", description: "", requiresExternalAction: false)
        ]
    }

    func generateLearning(
        badStepTitle: String,
        taskContext: String,
        discoveryContext: String,
        executionProgress: String
    ) async throws -> String {
        if let provider = learningProvider {
            return provider(badStepTitle, taskContext, discoveryContext, executionProgress)
        }
        return "Avoid generic steps; use specific actions."
    }
}

// MARK: - Mock Executive AI Service

/// Returns deterministic action UI schemas for any subtask.
final class MockExecutiveAIService: ExecutiveAIServiceProtocol {

    var schemaProvider: ((String, String, String, [[String: String]], String) -> ActionSchema)?

    func generateActionUI(
        subTask: String,
        subTaskDescription: String,
        taskContext: String,
        previousResponses: [[String: String]],
        taskMemory: String
    ) async throws -> ActionSchema {
        if let provider = schemaProvider {
            return provider(subTask, subTaskDescription, taskContext, previousResponses, taskMemory)
        }
        // Default: simple text field schema
        let field = ActionField(
            id: "field_text",
            type: .text,
            label: subTask,
            placeholder: "Enter your response...",
            options: nil,
            defaultValue: nil,
            prefillRows: nil
        )
        return ActionSchema(
            type: .form,
            title: subTask,
            description: subTaskDescription,
            fields: [field],
            submitLabel: "Continue",
            requiresExternalAction: false
        )
    }
}

// MARK: - Mock Knowledge Base Service

/// Captures all file writes for verification without touching the real filesystem.
final class MockKnowledgeBaseService: KnowledgeBaseServiceProtocol {

    var rootURL: URL = URL(fileURLWithPath: "/tmp/mock-kb")
    var indexURL: URL { rootURL.appendingPathComponent("index.md") }
    var isWorking: Bool = false

    /// Captured file writes keyed by relative path from rootURL.
    var writtenFiles: [String: String] = [:]

    /// Captured task/subtask completion events.
    var handledTaskCreatedOrUpdated: [TodoTask] = []
    var handledSubtaskCompleted: [SubTask] = []
    var handledTaskCompleted: [TodoTask] = []
    var reconciledTasks: [[TodoTask]] = []

    func handleTaskCreatedOrUpdated(_ task: TodoTask) {
        handledTaskCreatedOrUpdated.append(task)
    }

    func handleSubtaskCompleted(_ subTask: SubTask) {
        handledSubtaskCompleted.append(subTask)

        // Write a knowledge base note for this subtask
        let folderName = slugify(subTask.task?.title ?? "unknown")
        let noteName = "\(slugify(subTask.title)).md"
        let relativePath = "tasks/\(folderName)/\(noteName)"

        let noteContent = """
        # \(subTask.title)

        Completed as part of: \(subTask.task?.title ?? "Unknown Task")

        """
        writtenFiles[relativePath] = noteContent

        // Actually write to disk for filesystem verification
        let fileURL = rootURL.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? noteContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func handleTaskCompleted(_ task: TodoTask) {
        handledTaskCompleted.append(task)

        // Write a task summary note
        let folderName = slugify(task.title)
        let relativePath = "tasks/\(folderName)/summary.md"

        let summaryContent = """
        # \(task.title)

        Status: Completed at \(Date.now.formatted(date: .abbreviated, time: .shortened))

        """
        writtenFiles[relativePath] = summaryContent

        // Actually write to disk for filesystem verification
        let fileURL = rootURL.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? summaryContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func reconcile(tasks: [TodoTask]) {
        reconciledTasks.append(tasks)
    }

    func runLinkDiscoveryNow() {
        // No-op for mock
    }

    private func slugify(_ text: String) -> String {
        return text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
