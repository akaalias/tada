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
    func runLinkDiscoveryForNote(_ url: URL) async
    func runEntityExtractionForCurrentNote(_ url: URL) async
    func backlinks(toEntitySlug slug: String) async -> [KnowledgeBaseEntityLinker.Backlink]
    func buildGraphData() async -> KnowledgeGraphData
    func cleanupOrphanedNotes(existingTaskIds: Set<UUID>) async -> (taskFolders: Int, entities: Int)
    func createEntity(name: String, body: String) async throws
    func addLinkToNote(at url: URL, targetEntity: String) async throws
    func replaceTextWithLink(at url: URL, textToFind: String, targetEntity: String) async throws
    func editNoteBody(at url: URL, newBody: String) async throws
    func generateSummary() async throws -> String
    func createUserNote(title: String, body: String) async -> URL
    func listUserNotes() async -> [(slug: String, title: String)]
    func searchNotes(query: String) async -> [(name: String, path: String, kind: String)]
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

    func runLinkDiscoveryForNote(_ url: URL) async {
        if let testMock { await testMock.runLinkDiscoveryForNote(url); return }
        await KnowledgeBaseService.shared.runLinkDiscoveryForNote(url)
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

    func cleanupOrphanedNotes(existingTaskIds: Set<UUID>) async -> (taskFolders: Int, entities: Int) {
        if let testMock { return await testMock.cleanupOrphanedNotes(existingTaskIds: existingTaskIds) }
        return await KnowledgeBaseService.shared.cleanupOrphanedNotes(existingTaskIds: existingTaskIds)
    }

    func createEntity(name: String, body: String) async throws {
        if let testMock { try await testMock.createEntity(name: name, body: body); return }
        try await KnowledgeBaseService.shared.createEntity(name: name, body: body)
    }

    func addLinkToNote(at url: URL, targetEntity: String) async throws {
        if let testMock { try await testMock.addLinkToNote(at: url, targetEntity: targetEntity); return }
        try await KnowledgeBaseService.shared.addLinkToNote(at: url, targetEntity: targetEntity)
    }

    func replaceTextWithLink(at url: URL, textToFind: String, targetEntity: String) async throws {
        if let testMock { try await testMock.replaceTextWithLink(at: url, textToFind: textToFind, targetEntity: targetEntity); return }
        try await KnowledgeBaseService.shared.replaceTextWithLink(at: url, textToFind: textToFind, targetEntity: targetEntity)
    }

    func editNoteBody(at url: URL, newBody: String) async throws {
        if let testMock { try await testMock.editNoteBody(at: url, newBody: newBody); return }
        try await KnowledgeBaseService.shared.editNoteBody(at: url, newBody: newBody)
    }

    func generateSummary() async throws -> String {
        if let testMock { return try await testMock.generateSummary() }
        return try await KnowledgeBaseService.shared.generateSummary()
    }

    func createUserNote(title: String, body: String) async -> URL {
        if let testMock { return await testMock.createUserNote(title: title, body: body) }
        return await KnowledgeBaseService.shared.createUserNote(title: title, body: body)
    }

    func listUserNotes() async -> [(slug: String, title: String)] {
        if let testMock { return await testMock.listUserNotes() }
        return await KnowledgeBaseService.shared.listUserNotes()
    }

    func searchNotes(query: String) async -> [(name: String, path: String, kind: String)] {
        if let testMock { return await testMock.searchNotes(query: query) }
        return await KnowledgeBaseService.shared.searchNotes(query: query)
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
        taskMemory: String,
        phase: TaskPhase
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
        taskMemory: String,
        phase: TaskPhase
    ) async throws -> ActionSchema {
        if let testMock {
            return try await testMock.generateActionUI(
                subTask: subTask,
                subTaskDescription: subTaskDescription,
                taskContext: taskContext,
                previousResponses: previousResponses,
                taskMemory: taskMemory,
                phase: phase
            )
        }
        let executive = ExecutiveAIService(apiKey: APIKeyManager.getAPIKey() ?? "")
        return try await executive.generateActionUI(
            subTask: subTask,
            subTaskDescription: subTaskDescription,
            taskContext: taskContext,
            previousResponses: previousResponses,
            taskMemory: taskMemory,
            phase: phase
        )
    }
}

// MARK: - Planner AI Protocol

/// Protocol for the planner service that generates and revises task plans.
protocol PlannerAIServiceProtocol {
    func generateDiscoveryQuestions(for task: String) async throws -> TaskPlan
    func createExecutionPlan(originalTask: String, discoveryAnswers: [CompletedSubTaskInfo]) async throws -> TaskPlan
    func revisePlan(originalTask: String, completedSubTasks: [CompletedSubTaskInfo], remainingSubTasks: [String]) async throws -> PlanRevision
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
        // Discovery questions run on-device (the fine-tuned FMDiscovery champion)
        // when the system model + bundled adapter are available; on any failure we
        // fall back to the cloud planner so discovery always works. Everything
        // beyond discovery stays on the Claude API.
        if OnDeviceDiscoveryService.isAvailable {
            do {
                return try await OnDeviceDiscoveryService().generateDiscoveryQuestions(for: task)
            } catch {
                NSLog("On-device discovery failed (\(error)); falling back to cloud planner.")
            }
        }
        let planner = PlannerAIService(apiKey: APIKeyManager.getAPIKey() ?? "")
        return try await planner.generateDiscoveryQuestions(for: task)
    }

    func createExecutionPlan(originalTask: String, discoveryAnswers: [CompletedSubTaskInfo]) async throws -> TaskPlan {
        if let testMock { return try await testMock.createExecutionPlan(originalTask: originalTask, discoveryAnswers: discoveryAnswers) }
        let planner = PlannerAIService(apiKey: APIKeyManager.getAPIKey() ?? "")
        return try await planner.createExecutionPlan(originalTask: originalTask, discoveryAnswers: discoveryAnswers)
    }

    func revisePlan(originalTask: String, completedSubTasks: [CompletedSubTaskInfo], remainingSubTasks: [String]) async throws -> PlanRevision {
        if let testMock { return try await testMock.revisePlan(originalTask: originalTask, completedSubTasks: completedSubTasks, remainingSubTasks: remainingSubTasks) }
        let planner = PlannerAIService(apiKey: APIKeyManager.getAPIKey() ?? "")
        return try await planner.revisePlan(originalTask: originalTask, completedSubTasks: completedSubTasks, remainingSubTasks: remainingSubTasks)
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
