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
    func runEntityExtractionForCurrentNote(_ url: URL) async
    func backlinks(toEntitySlug slug: String) async -> [KnowledgeBaseEntityLinker.Backlink]
    func buildGraphData() async -> KnowledgeGraphData
}

/// Concrete implementation backed by the singleton. Under UI test mode, routes
/// to a no-op stand-in so tests don't touch the real filesystem wiki.
final class KnowledgeBaseServiceAdapter: KnowledgeBaseServiceProtocol {
    private let testMock: UITestKnowledgeBaseService? = UITestSupport.isActive ? UITestKnowledgeBaseService() : nil

    var rootURL: URL { testMock?.rootURL ?? KnowledgeBaseService.shared.rootURL }
    var indexURL: URL { testMock?.indexURL ?? KnowledgeBaseService.shared.indexURL }
    var isWorking: Bool { testMock?.isWorking ?? KnowledgeBaseService.shared.isWorking }

    func handleTaskCreatedOrUpdated(_ task: TodoTask) {
        if let testMock { testMock.handleTaskCreatedOrUpdated(task); return }
        KnowledgeBaseService.shared.handleTaskCreatedOrUpdated(task)
    }

    func handleSubtaskCompleted(_ subTask: SubTask) {
        if let testMock { testMock.handleSubtaskCompleted(subTask); return }
        KnowledgeBaseService.shared.handleSubtaskCompleted(subTask)
    }

    func handleTaskCompleted(_ task: TodoTask) {
        if let testMock { testMock.handleTaskCompleted(task); return }
        KnowledgeBaseService.shared.handleTaskCompleted(task)
    }

    func reconcile(tasks: [TodoTask]) {
        if let testMock { testMock.reconcile(tasks: tasks); return }
        KnowledgeBaseService.shared.reconcile(tasks: tasks)
    }

    func runLinkDiscoveryNow() async {
        if let testMock { await testMock.runLinkDiscoveryNow(); return }
        await KnowledgeBaseService.shared.runLinkDiscoveryNow()
    }

    func runEntityExtractionForCurrentNote(_ url: URL) async {
        if let testMock { await testMock.runEntityExtractionForCurrentNote(url); return }
        await KnowledgeBaseService.shared.runEntityExtractionForCurrentNote(url)
    }

    func backlinks(toEntitySlug slug: String) async -> [KnowledgeBaseEntityLinker.Backlink] {
        if let testMock { return await testMock.backlinks(toEntitySlug: slug) }
        return await KnowledgeBaseService.shared.backlinks(toEntitySlug: slug)
    }

    func buildGraphData() async -> KnowledgeGraphData {
        if let testMock { return await testMock.buildGraphData() }
        return await KnowledgeBaseService.shared.buildGraphData()
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

/// Concrete implementation backed by the real service. Under UI test mode,
/// returns a deterministic text-field schema instead of hitting Claude.
final class ExecutiveAIServiceAdapter: ExecutiveAIServiceProtocol {
    private let testMock: UITestExecutiveAIService? = UITestSupport.isActive ? UITestExecutiveAIService() : nil

    func generateActionUI(
        subTask: String,
        subTaskDescription: String,
        taskContext: String,
        previousResponses: [[String: String]],
        taskMemory: String
    ) async throws -> ActionSchema {
        if let testMock {
            return try await testMock.generateActionUI(
                subTask: subTask,
                subTaskDescription: subTaskDescription,
                taskContext: taskContext,
                previousResponses: previousResponses,
                taskMemory: taskMemory
            )
        }
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

/// Concrete implementation backed by the real service. Under UI test mode,
/// routes to a deterministic mock so tests don't hit Claude.
@MainActor
final class PlannerAIServiceAdapter: PlannerAIServiceProtocol {
    private let testMock: UITestPlannerAIService? = UITestSupport.isActive ? UITestPlannerAIService() : nil

    func generateDiscoveryQuestions(for task: String) async throws -> TaskPlan {
        if let testMock { return try await testMock.generateDiscoveryQuestions(for: task) }
        let planner = PlannerAIService(apiKey: APIKeyManager.getAPIKey() ?? "")
        return try await planner.generateDiscoveryQuestions(for: task)
    }

    func createExecutionPlan(originalTask: String, discoveryAnswers: [CompletedSubTaskInfo]) async throws -> TaskPlan {
        if let testMock { return try await testMock.createExecutionPlan(originalTask: originalTask, discoveryAnswers: discoveryAnswers) }
        let planner = PlannerAIService(apiKey: APIKeyManager.getAPIKey() ?? "")
        return try await planner.createExecutionPlan(originalTask: originalTask, discoveryAnswers: discoveryAnswers)
    }

    func revisePlan(originalTask: String, completedSubTasks: [CompletedSubTaskInfo], remainingSubTasks: [String], latestResponse: [String: Any]) async throws -> PlanRevision {
        if let testMock { return try await testMock.revisePlan(originalTask: originalTask, completedSubTasks: completedSubTasks, remainingSubTasks: remainingSubTasks, latestResponse: latestResponse) }
        let planner = PlannerAIService(apiKey: APIKeyManager.getAPIKey() ?? "")
        return try await planner.revisePlan(originalTask: originalTask, completedSubTasks: completedSubTasks, remainingSubTasks: remainingSubTasks, latestResponse: latestResponse)
    }

    func breakDownStep(stepTitle: String, stepDescription: String, taskContext: String, discoveryContext: String, executionProgress: String) async throws -> [SubTaskPlan] {
        if let testMock { return try await testMock.breakDownStep(stepTitle: stepTitle, stepDescription: stepDescription, taskContext: taskContext, discoveryContext: discoveryContext, executionProgress: executionProgress) }
        let planner = PlannerAIService(apiKey: APIKeyManager.getAPIKey() ?? "")
        return try await planner.breakDownStep(stepTitle: stepTitle, stepDescription: stepDescription, taskContext: taskContext, discoveryContext: discoveryContext, executionProgress: executionProgress)
    }

    func generateLearning(badStepTitle: String, taskContext: String, discoveryContext: String, executionProgress: String) async throws -> String {
        if let testMock { return try await testMock.generateLearning(badStepTitle: badStepTitle, taskContext: taskContext, discoveryContext: discoveryContext, executionProgress: executionProgress) }
        let planner = PlannerAIService(apiKey: APIKeyManager.getAPIKey() ?? "")
        return try await planner.generateLearning(badStepTitle: badStepTitle, taskContext: taskContext, discoveryContext: discoveryContext, executionProgress: executionProgress)
    }
}
