import Foundation

// MARK: - Knowledge Base Protocol

/// Protocol for knowledge-base lifecycle hooks used by view models.
@MainActor
protocol KnowledgeBaseServiceProtocol {
    var rootURL: URL { get }
    var indexURL: URL { get }
    var isWorking: Bool { get }
    func handleTaskCreatedOrUpdated(_ task: TodoTask)
    func handleSubtaskCompleted(_ subTask: SubTask)
    func handleTaskCompleted(_ task: TodoTask)
    func reconcile(tasks: [TodoTask])
    func runLinkDiscoveryNow() async
}

/// Concrete implementation backed by the singleton.
final class KnowledgeBaseServiceAdapter: KnowledgeBaseServiceProtocol {
    var rootURL: URL { KnowledgeBaseService.shared.rootURL }
    var indexURL: URL { KnowledgeBaseService.shared.indexURL }
    var isWorking: Bool { KnowledgeBaseService.shared.isWorking }

    func handleTaskCreatedOrUpdated(_ task: TodoTask) {
        KnowledgeBaseService.shared.handleTaskCreatedOrUpdated(task)
    }

    func handleSubtaskCompleted(_ subTask: SubTask) {
        KnowledgeBaseService.shared.handleSubtaskCompleted(subTask)
    }

    func handleTaskCompleted(_ task: TodoTask) {
        KnowledgeBaseService.shared.handleTaskCompleted(task)
    }

    func reconcile(tasks: [TodoTask]) {
        KnowledgeBaseService.shared.reconcile(tasks: tasks)
    }

    func runLinkDiscoveryNow() async {
        await KnowledgeBaseService.shared.runLinkDiscoveryNow()
    }
}

// MARK: - Executive AI Protocol

/// Protocol for the executive service that generates action UIs.
protocol ExecutiveAIServiceProtocol {
    func generateActionUI(
        subTask: String,
        subTaskDescription: String,
        taskContext: String,
        previousResponses: [[String: String]],
        taskMemory: String
    ) async throws -> ActionSchema
}

/// Concrete implementation backed by the real service.
final class ExecutiveAIServiceAdapter: ExecutiveAIServiceProtocol {
    func generateActionUI(
        subTask: String,
        subTaskDescription: String,
        taskContext: String,
        previousResponses: [[String: String]],
        taskMemory: String
    ) async throws -> ActionSchema {
        let executive = ExecutiveAIService(apiKey: APIKeyManager.getAPIKey() ?? "")
        return try await executive.generateActionUI(
            subTask: subTask,
            subTaskDescription: subTaskDescription,
            taskContext: taskContext,
            previousResponses: previousResponses,
            taskMemory: taskMemory
        )
    }
}

// MARK: - Planner AI Protocol

/// Protocol for the planner service that generates and revises task plans.
protocol PlannerAIServiceProtocol {
    func generateDiscoveryQuestions(for task: String) async throws -> TaskPlan
    func createExecutionPlan(originalTask: String, discoveryAnswers: [CompletedSubTaskInfo]) async throws -> TaskPlan
    func revisePlan(originalTask: String, completedSubTasks: [CompletedSubTaskInfo], remainingSubTasks: [String], latestResponse: [String: Any]) async throws -> PlanRevision
    func breakDownStep(stepTitle: String, stepDescription: String, taskContext: String, discoveryContext: String, executionProgress: String) async throws -> [SubTaskPlan]
    func generateLearning(badStepTitle: String, taskContext: String, discoveryContext: String, executionProgress: String) async throws -> String
}

/// Concrete implementation backed by the real service.
final class PlannerAIServiceAdapter: PlannerAIServiceProtocol {
    func generateDiscoveryQuestions(for task: String) async throws -> TaskPlan {
        let planner = PlannerAIService(apiKey: APIKeyManager.getAPIKey() ?? "")
        return try await planner.generateDiscoveryQuestions(for: task)
    }

    func createExecutionPlan(originalTask: String, discoveryAnswers: [CompletedSubTaskInfo]) async throws -> TaskPlan {
        let planner = PlannerAIService(apiKey: APIKeyManager.getAPIKey() ?? "")
        return try await planner.createExecutionPlan(originalTask: originalTask, discoveryAnswers: discoveryAnswers)
    }

    func revisePlan(originalTask: String, completedSubTasks: [CompletedSubTaskInfo], remainingSubTasks: [String], latestResponse: [String: Any]) async throws -> PlanRevision {
        let planner = PlannerAIService(apiKey: APIKeyManager.getAPIKey() ?? "")
        return try await planner.revisePlan(originalTask: originalTask, completedSubTasks: completedSubTasks, remainingSubTasks: remainingSubTasks, latestResponse: latestResponse)
    }

    func breakDownStep(stepTitle: String, stepDescription: String, taskContext: String, discoveryContext: String, executionProgress: String) async throws -> [SubTaskPlan] {
        let planner = PlannerAIService(apiKey: APIKeyManager.getAPIKey() ?? "")
        return try await planner.breakDownStep(stepTitle: stepTitle, stepDescription: stepDescription, taskContext: taskContext, discoveryContext: discoveryContext, executionProgress: executionProgress)
    }

    func generateLearning(badStepTitle: String, taskContext: String, discoveryContext: String, executionProgress: String) async throws -> String {
        let planner = PlannerAIService(apiKey: APIKeyManager.getAPIKey() ?? "")
        return try await planner.generateLearning(badStepTitle: badStepTitle, taskContext: taskContext, discoveryContext: discoveryContext, executionProgress: executionProgress)
    }
}
