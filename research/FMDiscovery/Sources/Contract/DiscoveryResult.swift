import Foundation

/// The discovery-planner output contract. Mirrors Sonnet's `create_task_plan`
/// tool output (TaskPlan/SubTaskPlan) on `main`. This is part of the spec — the
/// agent must produce exactly this shape regardless of how it gets there.
public struct DiscoveryResult: Codable, Equatable, Sendable {
    /// The user's task restated as a short, specific title (4-9 words).
    public var taskTitle: String
    /// One plain sentence summarising the task itself.
    public var taskDescription: String
    /// The clarifying questions (spec: exactly 7).
    public var questions: [DiscoveryQuestion]

    public init(taskTitle: String, taskDescription: String, questions: [DiscoveryQuestion]) {
        self.taskTitle = taskTitle
        self.taskDescription = taskDescription
        self.questions = questions
    }
}

public struct DiscoveryQuestion: Codable, Equatable, Sendable {
    /// The complete question the user sees (the question IS the title).
    public var title: String
    /// Optional extra context for the question (may be empty).
    public var description: String
    /// True if answering requires real-world action outside the app.
    public var requiresExternalAction: Bool

    public init(title: String, description: String, requiresExternalAction: Bool) {
        self.title = title
        self.description = description
        self.requiresExternalAction = requiresExternalAction
    }
}
