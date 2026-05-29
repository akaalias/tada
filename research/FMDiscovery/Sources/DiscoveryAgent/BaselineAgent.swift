import Foundation
import FoundationModels
import Contract

/// EXP-000 baseline: a single-shot port of the Sonnet discovery prompt onto the
/// on-device model, using guided generation to ENFORCE exactly 7 questions (the
/// spec quantity is free; quality is the open problem). This is the number the
/// research loop must beat.
public struct BaselineAgent: Sendable {
    public init() {}

    public func generate(_ input: String) async throws -> DiscoveryResult {
        let session = LanguageModelSession { Self.instructions }
        let prompt = """
        Task the user entered: "\(input)"

        Generate exactly 7 clarifying questions. Each must ask about ONE thing \
        only — never combine two asks with "and" or "or".
        """
        let response = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self)
        return response.content.toContract()
    }

    static let instructions = """
    You are a personal task coach. The user just shared a task they want to \
    accomplish. Before making any plans, you need to UNDERSTAND what they \
    actually mean. Generate clarifying questions that uncover: what specifically \
    they want, the context (who/what/when/where/why), their constraints and \
    preferences, and key details needed for execution (names, locations, etc.).

    TASK TITLE: restate the user's goal as a short, specific title (4-9 words) \
    in their own terms. It names THEIR task, not your questions. Never use \
    generic labels like "Clarifying Questions" or "Task Discovery".

    DESCRIPTION: summarise the task itself in one plain sentence.

    QUESTIONS:
    - Each question title IS the complete question the user sees, 5-10 words, \
    natural and conversational.
    - ONE thing per question. NEVER combine with "and" or "or". If tempted, split.
      BAD: "What are your departure city and travel dates?"
      GOOD: "What city are you flying from?"  /  "When do you want to leave?"
    - Be specific to THIS task, not generic filler like "Any other preferences?".
    - Set requiresExternalAction true only when answering needs a real-world \
    action outside the app (a phone call, email, visit); false for in-app entry.

    Do NOT use emojis. Keep text clean and professional.
    """
}

@Generable
struct FMDiscoveryPlan {
    @Guide(description: "The user's task restated as a short specific title, 4-9 words, in their own words. Never a generic label like 'Clarifying Questions'.")
    var title: String

    @Guide(description: "One plain sentence summarising the task.")
    var summary: String

    @Guide(description: "Exactly 7 clarifying questions.", .count(7))
    var questions: [FMQuestion]

    func toContract() -> DiscoveryResult {
        DiscoveryResult(
            taskTitle: title,
            taskDescription: summary,
            questions: questions.map {
                DiscoveryQuestion(title: $0.question, description: $0.detail, requiresExternalAction: $0.requiresExternalAction)
            }
        )
    }
}

@Generable
struct FMQuestion {
    @Guide(description: "A complete clarifying question, 5-10 words, asking exactly ONE thing. Never combine two asks with 'and' or 'or'.")
    var question: String

    @Guide(description: "Optional short extra context for the question. May be empty.")
    var detail: String

    @Guide(description: "True only if answering requires a real-world action outside the app (call, email, visit). False for in-app data entry.")
    var requiresExternalAction: Bool
}
