import Foundation
import FoundationModels

/// On-device productivity coach. Uses guided generation to emit, each turn, a reply
/// plus at most one tool call. The CoachViewModel executes the tool and loops, so the
/// agentic behaviour is preserved without the remote tool-use round-trip.
///
/// Note: this is the documented degradation of the previously remote, 17-tool agentic
/// coach — the on-device model is weaker at multi-step tool reasoning and the full tool
/// catalogue plus history can approach the 4,096-token context window.
actor CoachService {
    init() {}

    func chat(
        userMessage: String,
        context: String,
        conversationHistory: [CoachMessage],
        taskSummary: String?,
        toolResults: [CoachMessage.ToolResult]? = nil
    ) async throws -> CoachChatResponse {
        let session = LanguageModelSession { Self.instructions }

        var prompt = "CURRENT CONTEXT:\n\(context)"
        if let taskSummary { prompt += "\n\nACTIVE TASKS:\n\(taskSummary)" }
        prompt += "\n\nCONVERSATION:\n\(Self.transcript(conversationHistory))"
        prompt += "\n\nReply to the user. If an action is clearly needed, set one tool; otherwise tool = none."
        let temperature = 0.4

        return try await APILog.shared.record(
            role: .coach,
            operation: "Coach chat",
            instructions: Self.instructions,
            prompt: prompt,
            temperature: temperature,
            outputType: "CoachTurn"
        ) {
            let result = try await session.respond(
                to: prompt,
                generating: GenCoachTurn.self,
                options: GenerationOptions(temperature: temperature)
            )
            let response = result.content.toChatResponse()
            return (response, Self.render(response))
        }
    }

    /// Renders a coach turn for the Console: the reply text, plus any tool call.
    private static func render(_ response: CoachChatResponse) -> String {
        var text = response.message
        for call in response.toolCalls ?? [] {
            let args = call.arguments.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            text += "\n\n→ \(call.name)(\(args))"
        }
        return text
    }

    /// Renders recent history (including tool calls and their results) as plain text.
    private static func transcript(_ history: [CoachMessage]) -> String {
        history.suffix(10).map { message in
            switch message.role {
            case .user:
                return "User: \(message.content)"
            case .coach:
                var line = "Coach: \(message.content)"
                if let calls = message.toolCalls, !calls.isEmpty {
                    line += "\n  (called: \(calls.map(\.name).joined(separator: ", ")))"
                }
                if let results = message.toolResults, !results.isEmpty {
                    line += "\n  (results: \(results.map { "\($0.toolName) -> \($0.message)" }.joined(separator: "; ")))"
                }
                return line
            case .system:
                return "System: \(message.content)"
            }
        }.joined(separator: "\n")
    }

    private static let instructions = """
    You are Tada's on-device productivity coach. Warm, concise, proactive. You help the user \
    manage tasks and their knowledge base. Each turn you reply with a brief message and may \
    invoke ONE tool. Use the note_path from context for note operations. When creating an \
    entity, also link it. If the user is stuck on a step, first ask how they'd like it broken \
    down before splitting. No emojis.

    Tools (set `tool` to one of these, else none):
    - captureInboxItem(content)
    - createTask(description)
    - searchTasks(query) / getSubtasks(taskId)
    - updateDiscoveryQuestions(taskId, newFraming) / replanExecution(taskId, guidance)
    - readNote(notePath) / editNote(notePath, newBody)
    - createKnowledgeEntity(name, content) / linkKnowledgeEntities(sourceNote, targetEntity)
    - replaceTextWithLink(notePath, textToFind, targetEntity)
    - generateKnowledgeSummary / searchNotes(query)
    - completeSubtask(taskId, subtaskId) / skipSubtask(taskId, subtaskId)
    - splitSubtask(taskId, subtaskId, newSubtasks) / updateSubtask(taskId, subtaskId, title, description)
    """
}

struct CoachChatResponse {
    let message: String
    let toolCalls: [ToolCall]?
}

// MARK: - Guided-generation types

@Generable
enum GenCoachTool {
    case none
    case captureInboxItem, createTask, searchTasks, getSubtasks
    case updateDiscoveryQuestions, replanExecution
    case readNote, createKnowledgeEntity, linkKnowledgeEntities, replaceTextWithLink, editNote
    case generateKnowledgeSummary, searchNotes
    case completeSubtask, skipSubtask, splitSubtask, updateSubtask
}

@Generable
struct GenCoachTurn {
    @Guide(description: "Your brief reply to the user. Always provide this.")
    var message: String
    @Guide(description: "The single tool to call this turn, or none to just reply.")
    var tool: GenCoachTool

    var content: String?
    var taskDescription: String?
    var query: String?
    var taskId: String?
    var subtaskId: String?
    var newFraming: String?
    var guidance: String?
    var notePath: String?
    var name: String?
    var sourceNote: String?
    var targetEntity: String?
    var textToFind: String?
    var newBody: String?
    var newSubtasks: String?
    var title: String?

    func toChatResponse() -> CoachChatResponse {
        guard let toolName = tool.rawName else {
            return CoachChatResponse(message: message, toolCalls: nil)
        }
        var args: [String: String] = [:]
        func put(_ key: String, _ value: String?) {
            if let value, !value.isEmpty { args[key] = value }
        }
        put("content", content)
        put("description", taskDescription)
        put("query", query)
        put("task_id", taskId)
        put("subtask_id", subtaskId)
        put("new_framing", newFraming)
        put("guidance", guidance)
        put("note_path", notePath)
        put("name", name)
        put("source_note", sourceNote)
        put("target_entity", targetEntity)
        put("text_to_find", textToFind)
        put("new_body", newBody)
        put("new_subtasks", newSubtasks)
        put("title", title)

        let call = ToolCall(id: UUID().uuidString, name: toolName, arguments: args)
        return CoachChatResponse(message: message, toolCalls: [call])
    }
}

private extension GenCoachTool {
    /// The matching `CoachTool` raw value, or nil for `.none`.
    var rawName: String? {
        switch self {
        case .none: return nil
        case .captureInboxItem: return CoachTool.captureInboxItem.rawValue
        case .createTask: return CoachTool.createTask.rawValue
        case .searchTasks: return CoachTool.searchTasks.rawValue
        case .getSubtasks: return CoachTool.getSubtasks.rawValue
        case .updateDiscoveryQuestions: return CoachTool.updateDiscoveryQuestions.rawValue
        case .replanExecution: return CoachTool.replanExecution.rawValue
        case .readNote: return CoachTool.readNote.rawValue
        case .createKnowledgeEntity: return CoachTool.createKnowledgeEntity.rawValue
        case .linkKnowledgeEntities: return CoachTool.linkKnowledgeEntities.rawValue
        case .replaceTextWithLink: return CoachTool.replaceTextWithLink.rawValue
        case .editNote: return CoachTool.editNote.rawValue
        case .generateKnowledgeSummary: return CoachTool.generateKnowledgeSummary.rawValue
        case .searchNotes: return CoachTool.searchNotes.rawValue
        case .completeSubtask: return CoachTool.completeSubTask.rawValue
        case .skipSubtask: return CoachTool.skipSubTask.rawValue
        case .splitSubtask: return CoachTool.splitSubTask.rawValue
        case .updateSubtask: return CoachTool.updateSubTask.rawValue
        }
    }
}
