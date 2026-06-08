import Foundation
import Contract

/// Generates the GOLD standard by calling Sonnet with the EXACT split prompt and
/// `split_into_tasks` tool the shipped app uses (PlannerAIService.splitIntoTasks
/// on feat/ramble-split), so gold == what the app produces today. Do not
/// "improve" this prompt — it is the reference we are trying to match on-device.
public struct GoldGenerator: Sendable {
    let client: AnthropicClient
    public init(client: AnthropicClient) { self.client = client }

    public func generate(_ input: String) async throws -> RambleResult {
        let user = """
        Here is what the user brain-dumped:

        "\(input)"

        Extract each distinct, actionable task as a short one-liner. If there are none, return an empty list.
        """
        let data = try await client.toolCall(system: Self.splitPrompt, user: user, tool: Self.tool, maxTokens: 1024)
        let out = try JSONDecoder().decode(GoldToolOutput.self, from: data)
        return RambleResult(tasks: out.tasks)
    }

    struct GoldToolOutput: Codable { let tasks: [String] }

    // Verbatim from PlannerAIService.splitIntoTasks (feat/ramble-split).
    static let splitPrompt = """
    You take a free-form brain-dump from the user and extract the distinct, actionable tasks in it.

    The input is stream-of-consciousness text (often dictated). It may contain:
    - ZERO tasks (venting, musing, or thinking out loud with nothing actionable)
    - ONE task
    - SEVERAL distinct tasks, sometimes interleaved (the user jumps back to an earlier thought)

    RULES:
    - Each task is a short, actionable one-liner in the user's own terms (around 4-9 words).
    - ONE intention = ONE task. If the user mentions the same thing more than once, output it ONCE.
    - Only extract things the user actually wants to DO. A vague wish or feeling
      ("I'd love to be more organized someday") is NOT a task.
    - NEVER invent tasks. Every task must trace directly to something in the input.
    - If nothing in the input is an actionable task, return an empty list. Do not force a task.
    - Do NOT use emojis. Keep text clean and professional.

    Return the list of task one-liners.
    """

    // Verbatim from ClaudeAPIClient.swift `split_into_tasks` (feat/ramble-split).
    static var tool: [String: Any] { [
        "name": "split_into_tasks",
        "description": "Extract the distinct, actionable tasks from a free-form user brain-dump. Return an empty list if there are none.",
        "input_schema": [
            "type": "object",
            "properties": [
                "tasks": [
                    "type": "array",
                    "description": "Each distinct, actionable task as a short one-liner in the user's own terms. Empty array if the input contains no actionable task.",
                    "items": ["type": "string"],
                ],
            ],
            "required": ["tasks"],
        ],
    ] }
}
