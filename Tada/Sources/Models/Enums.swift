import Foundation

// MARK: - Task Status

enum TaskStatus: String, Codable, CaseIterable {
    case active
    case completed
    case archived

    var isCompleted: Bool { self == .completed }
}

// MARK: - Sub-Task Status

enum SubTaskStatus: String, Codable, CaseIterable {
    case pending
    case current
    case completed
    case skipped

    var isCompleted: Bool { self == .completed }
}

// MARK: - Task Phase

enum TaskPhase: String, Codable, CaseIterable {
    case discovery
    case execution
}

// MARK: - Planning Status

enum PlanningStatus: String, Codable, CaseIterable {
    case idle
    case planningDiscovery
    case planningExecution

    var isPlanning: Bool { self != .idle }
}
