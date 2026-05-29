import Foundation
import Contract

/// Generates the GOLD standard by calling Sonnet with the EXACT discovery prompt
/// and `create_task_plan` tool the live app uses (PlannerAIService on main), so
/// gold == what the app produces today. Do not "improve" this prompt — it is the
/// reference we are trying to match.
public struct GoldGenerator: Sendable {
    let client: AnthropicClient
    public init(client: AnthropicClient) { self.client = client }

    public func generate(_ input: String) async throws -> DiscoveryResult {
        let user = """
        Task the user entered: "\(input)"

        Generate EXACTLY 7 clarifying questions. Always 7 — no more, no fewer. Each question must ask about ONE thing only - never combine with "and" or "or".
        """
        let data = try await client.toolCall(system: Self.discoveryPrompt, user: user, tool: Self.tool, maxTokens: 2048)
        let out = try JSONDecoder().decode(GoldToolOutput.self, from: data)
        let questions = out.subTasks.prefix(SpecGate.requiredQuestionCount).map {
            DiscoveryQuestion(title: $0.title, description: $0.description, requiresExternalAction: $0.requiresExternalAction ?? false)
        }
        return DiscoveryResult(taskTitle: out.title, taskDescription: out.description, questions: Array(questions))
    }

    struct GoldToolOutput: Codable {
        let title: String
        let description: String
        let subTasks: [Sub]
        struct Sub: Codable { let title: String; let description: String; let requiresExternalAction: Bool? }
    }

    // Verbatim from PlannerAIService.swift:7-71 (main).
    static let discoveryPrompt = """
    You are a personal task coach. The user just shared a task they want to accomplish.

    Before making any plans, you need to UNDERSTAND what they actually mean. Generate 3-5 clarifying questions that will help you understand:
    - What specifically are they trying to accomplish?
    - What's the context? (who, what, when, where, why)
    - What constraints or preferences do they have?
    - KEY DETAILS needed for execution (names, contact info, locations, etc.)

    TASK TITLE & DESCRIPTION (the top-level "title" and "description" fields):
    - The top-level "title" is the NAME OF THE USER'S TASK - what THEY want to accomplish.
      It is NOT a label for your questions.
    - Restate the user's goal as a short, specific title (4-9 words) in their own terms.
    - NEVER use generic labels like "Clarifying Questions", "Task Discovery", "Questions",
      or "Understanding your task". Those describe your output, not the user's goal.
    - Example: user enters "Untangle my German tax returns for 2020-2024" →
      title: "Sort Out 2020-2024 German Tax Returns"
    - The top-level "description" summarises the task itself in one plain sentence.

    QUESTION TITLE GUIDELINES (each subTask "title"):
    - Titles should be COMPLETE questions that make sense on their own
    - Keep them concise but natural - around 5-10 words
    - Don't list all the options in the title
    - The title IS the question the user sees

    CRITICAL: ONE QUESTION PER ITEM. NEVER COMBINE QUESTIONS WITH "AND" OR "OR".
    Each question must ask about exactly ONE thing. If you're tempted to use "and" or "or", SPLIT into separate questions.

    BAD - NEVER DO THIS:
    - "What are your departure city and travel dates?" (TWO things! Split them!)
    - "What's your budget and preferred cabin class?" (TWO things! Split them!)
    - "Do you have a budget or preferred airline?" (TWO things! Split them!)
    - "When do you need it and how urgent is it?" (TWO things!)

    GOOD - EACH QUESTION ASKS ONE THING:
    - "What city are you flying from?"
    - "When do you need to depart?"
    - "What's your budget for this trip?"
    - "Which cabin class do you prefer?"

    GOOD titles:
    - "Which doctor or clinic do you want to visit?"
    - "What's your budget range for this project?"
    - "What kind of privacy solution appeals to you?"
    - "Do you have any time preferences?"
    - "Is this for you or someone else?"

    BAD titles (combining multiple questions with AND):
    - "What are your departure city and travel dates?" → SPLIT INTO TWO!
    - "What's your budget and preferred class?" → SPLIT INTO TWO!

    BAD titles (too long - listing options):
    - "What kind of privacy solution appeals to you - plants, screens, curtains, or a mix?"

    BAD titles (too short/awkward):
    - "Which doctor?"
    - "Budget?"

    IMPORTANT: Do NOT use emojis. Keep text clean and professional.

    Generate EXACTLY 7 focused questions. Always 7 — no more, no fewer. Keep each question atomic (one thing only).

    The subTask "title" must BE the complete question.
    The "description" can provide additional context if needed.
    """

    // Verbatim from ClaudeAPIClient.swift:287-314 (main).
    static var tool: [String: Any] { [
        "name": "create_task_plan",
        "description": "Create a structured task plan",
        "input_schema": [
            "type": "object",
            "properties": [
                "title": [
                    "type": "string",
                    "description": "Short, specific name for the USER'S task - what they want to accomplish, in their own terms. Never a generic label like 'Clarifying Questions' or 'Task Discovery'.",
                ],
                "description": [
                    "type": "string",
                    "description": "One plain sentence summarising the task itself.",
                ],
                "subTasks": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string", "description": "Question text (the complete question the user sees)"],
                            "description": ["type": "string", "description": "Optional additional context for the question"],
                            "requiresExternalAction": ["type": "boolean", "description": "True if step requires real-world action outside app (calls, emails, calendar, travel). False for in-app data entry."],
                        ],
                        "required": ["title", "description", "requiresExternalAction"],
                    ],
                ],
            ],
            "required": ["title", "description", "subTasks"],
        ],
    ] }
}
