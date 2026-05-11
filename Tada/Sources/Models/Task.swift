import Foundation
import SwiftData

@Model
final class TodoTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var taskDescription: String
    var status: TaskStatus = TaskStatus.active
    var phase: TaskPhase = TaskPhase.discovery
    var planningStatus: PlanningStatus = PlanningStatus.idle
    var createdAt: Date
    var completedAt: Date?
    var originalInput: String
    var memory: String = ""

    @Relationship(deleteRule: .cascade, inverse: \SubTask.task)
    var subTasks: [SubTask] = []

    init(title: String, originalInput: String? = nil) {
        self.id = UUID()
        self.title = title
        self.taskDescription = ""
        self.status = TaskStatus.active
        self.phase = TaskPhase.discovery
        self.planningStatus = PlanningStatus.idle
        self.createdAt = Date()
        self.originalInput = originalInput ?? title
    }

    var isPlanning: Bool {
        planningStatus.isPlanning
    }

    var isPlanningDiscovery: Bool {
        planningStatus == .planningDiscovery
    }

    var isPlanningExecution: Bool {
        planningStatus == .planningExecution
    }

    var isDiscoveryPhase: Bool {
        phase == .discovery
    }

    var isExecutionPhase: Bool {
        phase == .execution
    }

    func transitionToExecution() {
        phase = .execution
    }

    var isActive: Bool {
        status == .active
    }

    var isCompleted: Bool {
        status.isCompleted
    }

    var sortedSubTasks: [SubTask] {
        subTasks.sorted { $0.order < $1.order }
    }

    var discoverySubTasks: [SubTask] {
        sortedSubTasks.filter { $0.phase == .discovery }
    }

    var executionSubTasks: [SubTask] {
        sortedSubTasks.filter { $0.phase == .execution }
    }

    var currentPhaseSubTasks: [SubTask] {
        isDiscoveryPhase ? discoverySubTasks : executionSubTasks
    }

    var currentSubTask: SubTask? {
        // Only look at subtasks in the current phase
        currentPhaseSubTasks.first { $0.status == .current || $0.status == .pending }
    }

    var progress: Double {
        // Progress based on current phase subtasks
        let phaseTasks = currentPhaseSubTasks
        guard !phaseTasks.isEmpty else { return 0 }
        let completed = phaseTasks.filter { $0.status.isCompleted }.count
        return Double(completed) / Double(phaseTasks.count)
    }

    func markCompleted() {
        status = TaskStatus.completed
        completedAt = Date()
    }

    func addSubTask(_ subTask: SubTask) {
        subTask.order = subTasks.count
        subTasks.append(subTask)
    }
}
