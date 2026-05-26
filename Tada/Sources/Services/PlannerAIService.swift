import Foundation

// Shared planning DTOs. Planning now runs on-device via
// `FoundationModelsPlannerService`; these types are the contract between the
// planner, the view models, and persistence.

struct TaskPlan: Codable {
    let title: String
    let description: String
    let subTasks: [SubTaskPlan]
}

struct SubTaskPlan: Codable {
    let title: String
    let description: String
    let requiresExternalAction: Bool?
}

struct PlanRevision: Codable {
    let revised: Bool
    let reason: String?
    let subTasks: [SubTaskPlan]?
}

struct CompletedSubTaskInfo {
    let title: String
    let response: String
}

struct MicroStepsResponse: Codable {
    let microSteps: [SubTaskPlan]
}
