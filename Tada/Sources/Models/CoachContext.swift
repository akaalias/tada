import Foundation

/// Represents what the user is currently viewing in the app.
enum CoachViewContext: Equatable {
    case allTasks
    case actionItems
    case completed
    case knowledgeBase(currentNote: URL?)
    case console
    case settings
    case focusedTask(taskId: UUID)
}

/// Full context available to the productivity coach.
@Observable
@MainActor
final class CoachContext {
    var currentView: CoachViewContext = .allTasks
    var selectedTaskId: UUID?
    var selectedSubTaskId: UUID?

    var contextDescription: String {
        switch currentView {
        case .allTasks:
            return "User is viewing the All Tasks list, showing all active tasks with their subtasks."
        case .actionItems:
            return "User is viewing Action Items, showing tasks that need attention or have pending steps."
        case .completed:
            return "User is viewing Completed Tasks, showing tasks that have been finished."
        case .knowledgeBase(let noteURL):
            if let url = noteURL {
                return "User is viewing the Knowledge Base, currently reading note at path: \(url.path)"
            }
            return "User is viewing the Knowledge Base index."
        case .console:
            return "User is viewing the Console, showing API request logs and activity."
        case .settings:
            return "User is viewing Settings."
        case .focusedTask(let taskId):
            return "User is focused on a specific task (ID: \(taskId.uuidString.prefix(8))...)."
        }
    }
}
