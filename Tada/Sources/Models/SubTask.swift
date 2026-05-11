import Foundation
import SwiftData

@Model
final class SubTask {
    @Attribute(.unique) var id: UUID
    var task: TodoTask?
    var title: String
    var subTaskDescription: String
    var order: Int
    var status: SubTaskStatus = SubTaskStatus.pending
    var phase: TaskPhase = TaskPhase.discovery
    var actionType: String?
    var actionSchemaData: Data?
    var actionResponseData: Data?
    var completedAt: Date?
    var requiresExternalAction: Bool = false

    init(title: String, description: String = "", order: Int = 0, phase: TaskPhase = .discovery, requiresExternalAction: Bool = false) {
        self.id = UUID()
        self.title = title
        self.subTaskDescription = description
        self.order = order
        self.status = SubTaskStatus.pending
        self.phase = phase
        self.requiresExternalAction = requiresExternalAction
    }

    var isDiscoveryPhase: Bool {
        phase == .discovery
    }

    var isExecutionPhase: Bool {
        phase == .execution
    }

    var isPending: Bool {
        status == .pending
    }

    var isCurrent: Bool {
        status == .current
    }

    var isCompleted: Bool {
        status.isCompleted
    }

    func markCompleted() {
        status = SubTaskStatus.completed
        completedAt = Date()
    }

    func markCurrent() {
        status = SubTaskStatus.current
    }

    func skip() {
        status = SubTaskStatus.skipped
    }

    var effectiveRequiresExternalAction: Bool {
        if requiresExternalAction { return true }
        guard let data = actionSchemaData,
              let schema = try? JSONDecoder().decode(ActionSchema.self, from: data) else {
            return false
        }
        return schema.requiresExternalAction
    }
}
