import Foundation
import SwiftData

/// Service that powers the productivity coach chat interface.
actor CoachService {
    private let client: ClaudeAPIClient

    private let systemPrompt = """
    You are Tada's built-in productivity coach. You help users manage their tasks and knowledge base through natural conversation.

    PERSONALITY:
    - Warm, supportive, and encouraging
    - Concise - keep responses brief and actionable
    - Proactive - suggest next steps when appropriate
    - Context-aware - use information about what the user is currently viewing

    CAPABILITIES:
    You have access to tools that let you take actions on behalf of the user:

    1. capture_inbox_item - Quickly capture a thought for later
    2. create_task - Create a new task with AI-generated planning
    3. update_discovery_questions - Reframe discovery questions for a task
    4. replan_execution - Regenerate execution steps with new guidance
    5. read_note - Read the content of a note to see its text
    6. create_knowledge_entity - Create a new entity in the knowledge base
    7. link_knowledge_entities - Add an entity to the Related section of a note
    8. replace_text_with_link - Find and replace text in a note with a wiki link
    9. edit_note - Edit the body content of a note
    10. generate_knowledge_summary - Generate a summary of the knowledge base
    11. complete_subtask - Mark a subtask as done
    12. skip_subtask - Skip a subtask

    CRITICAL - WORKING WITH NOTES:
    - When you need to see a note's content, use read_note first with the note_path from context
    - When creating an entity while viewing a note, you MUST ALWAYS do BOTH:
      1. create_knowledge_entity - create the new entity
      2. link_knowledge_entities - add the link to the current note's Related section
    - When replacing text with a link, first read_note to find the exact text, then replace_text_with_link
    - NEVER create an entity without also linking it
    - Use the note_path from context for all note operations

    GUIDELINES:
    - Use tools proactively when the user's intent is clear
    - Ask for clarification only when necessary
    - After using a tool, briefly confirm what you did
    - If a tool fails, explain what went wrong and suggest alternatives
    - Keep conversations focused and productive
    - No emojis

    CONTEXT USAGE:
    The user's current view context will be provided. Use this to:
    - Understand what they're looking at
    - Offer relevant suggestions
    - Know which task/note they might be referring to
    """

    init(apiKey: String) {
        self.client = ClaudeAPIClient(apiKey: apiKey, role: .coach, phase: .execution)
    }

    func chat(
        userMessage: String,
        context: String,
        conversationHistory: [CoachMessage],
        taskSummary: String?,
        toolResults: [CoachMessage.ToolResult]? = nil
    ) async throws -> CoachChatResponse {
        let contextBlock = """
        CURRENT CONTEXT:
        \(context)
        \(taskSummary.map { "\n\nACTIVE TASKS SUMMARY:\n\($0)" } ?? "")
        """

        var messages: [[String: Any]] = []

        // Add conversation history (last 10 messages)
        for message in conversationHistory.suffix(10) {
            let role = message.role == .user ? "user" : "assistant"

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                // Assistant message with tool_use blocks
                var content: [[String: Any]] = []
                if !message.content.isEmpty {
                    content.append(["type": "text", "text": message.content])
                }
                for call in toolCalls {
                    var input: [String: Any] = [:]
                    for (key, value) in call.arguments {
                        input[key] = value
                    }
                    content.append([
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name,
                        "input": input
                    ])
                }
                messages.append(["role": "assistant", "content": content])

                // Then add the tool results as a user message
                if let results = message.toolResults, !results.isEmpty {
                    var resultContent: [[String: Any]] = []
                    for result in results {
                        resultContent.append([
                            "type": "tool_result",
                            "tool_use_id": result.toolUseId,
                            "content": result.message
                        ])
                    }
                    messages.append(["role": "user", "content": resultContent])
                }
            } else {
                messages.append(["role": role, "content": message.content])
            }
        }

        // If we have pending tool results, they should already be in history via the last coach message
        // Just add the user's original message if this is not a tool result continuation
        if toolResults == nil || toolResults!.isEmpty {
            messages.append(["role": "user", "content": "\(contextBlock)\n\nUser: \(userMessage)"])
        }

        let tools = CoachTool.allCases.map { $0.toAPISchema() }

        return try await client.sendCoachMessage(
            systemPrompt: systemPrompt,
            messages: messages,
            tools: tools
        )
    }
}

struct CoachChatResponse {
    let message: String
    let toolCalls: [ToolCall]?
}

// MARK: - ClaudeAPIClient extension for coach

extension ClaudeAPIClient {
    func sendCoachMessage(
        systemPrompt: String,
        messages: [[String: Any]],
        tools: [[String: Any]]
    ) async throws -> CoachChatResponse {
        var body: [String: Any] = [
            "model": ModelPreference.selectedModel,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": messages
        ]

        if !tools.isEmpty {
            body["tools"] = tools
        }

        let response = try await sendRequest(body: body, phase: .execution, taskTitle: "Coach chat")

        var responseText = ""
        var toolCalls: [ToolCall] = []

        if let content = response["content"] as? [[String: Any]] {
            for block in content {
                if let type = block["type"] as? String {
                    if type == "text", let text = block["text"] as? String {
                        responseText = text
                    } else if type == "tool_use",
                              let toolId = block["id"] as? String,
                              let name = block["name"] as? String,
                              let input = block["input"] as? [String: Any] {
                        let args = input.compactMapValues { value -> String? in
                            if let str = value as? String { return str }
                            if let num = value as? NSNumber { return num.stringValue }
                            return nil
                        }
                        toolCalls.append(ToolCall(id: toolId, name: name, arguments: args))
                    }
                }
            }
        }

        return CoachChatResponse(
            message: responseText,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls
        )
    }
}
