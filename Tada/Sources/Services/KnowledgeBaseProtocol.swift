import Foundation

/// Protocol for knowledge-base lifecycle hooks used by view models.
@MainActor
protocol KnowledgeBaseServiceProtocol {
    func handleTaskCreatedOrUpdated(_ task: TodoTask)
    func handleSubtaskCompleted(_ subTask: SubTask)
    func handleTaskCompleted(_ task: TodoTask)
}

/// Concrete implementation backed by the singleton.
final class KnowledgeBaseServiceAdapter: KnowledgeBaseServiceProtocol {
    func handleTaskCreatedOrUpdated(_ task: TodoTask) {
        KnowledgeBaseService.shared.handleTaskCreatedOrUpdated(task)
    }

    func handleSubtaskCompleted(_ subTask: SubTask) {
        KnowledgeBaseService.shared.handleSubtaskCompleted(subTask)
    }

    func handleTaskCompleted(_ task: TodoTask) {
        KnowledgeBaseService.shared.handleTaskCompleted(task)
    }
}
