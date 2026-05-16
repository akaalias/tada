import Foundation

/// A message in the coach chat conversation.
struct CoachMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    var toolCalls: [ToolCall]?
    var toolResults: [ToolResult]?

    enum Role: Equatable {
        case user
        case coach
        case system
    }

    struct ToolResult: Identifiable, Equatable {
        let id: UUID
        let toolUseId: String
        let toolName: String
        let success: Bool
        let message: String

        init(toolUseId: String, toolName: String, success: Bool, message: String) {
            self.id = UUID()
            self.toolUseId = toolUseId
            self.toolName = toolName
            self.success = success
            self.message = message
        }
    }

    init(role: Role, content: String, toolCalls: [ToolCall]? = nil, toolResults: [ToolResult]? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.toolCalls = toolCalls
        self.toolResults = toolResults
    }
}
