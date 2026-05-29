import Foundation
import FoundationModels
import Contract

/// EXP-001: decompose the judgment into two FM calls the 3B can each handle.
/// Stage 1 brainstorms many candidate unknowns against a universal planning
/// scaffold (targets coverage). Stage 2 selects the 7 most decision-relevant,
/// drops redundant/filler/premature ones, and phrases them atomically (targets
/// specificity, non-redundancy, naturalness).
public struct PipelineAgent: Sendable {
    public init() {}

    public func generate(_ input: String) async throws -> DiscoveryResult {
        let unknowns = try await brainstormUnknowns(input)
        return try await selectAndPhrase(input, unknowns: unknowns)
    }

    private func brainstormUnknowns(_ input: String) async throws -> [String] {
        let session = LanguageModelSession { Self.brainstormInstructions }
        let prompt = """
        The user wants to: "\(input)"

        List the candidate unknowns you'd want to learn from the user before \
        planning this. Cover the relevant planning dimensions. Do not ask about \
        anything the task already states.
        """
        let r = try await session.respond(to: prompt, generating: FMUnknowns.self)
        return r.content.unknowns
    }

    private func selectAndPhrase(_ input: String, unknowns: [String]) async throws -> DiscoveryResult {
        let session = LanguageModelSession { Self.selectInstructions }
        let list = unknowns.enumerated().map { "- \($0.element)" }.joined(separator: "\n")
        let prompt = """
        The user wants to: "\(input)"

        Candidate unknowns brainstormed for this task:
        \(list)

        Choose the 7 MOST decision-relevant unknowns — the ones whose answers \
        would most change the plan. Drop anything redundant, generic, premature, \
        or already implied by the task. Then write each as one natural clarifying \
        question and restate the task as a title and one-sentence description.
        """
        let r = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self)
        return r.content.toContract()
    }

    static let brainstormInstructions = """
    You are a meticulous planning coach. Given a task a user wants to accomplish, \
    enumerate the UNKNOWNS — the specific facts, constraints, and preferences you \
    would need from the user before you could plan it well. Think across these \
    dimensions and include whichever are relevant:
    - Goal / definition of done (what does success look like)
    - Who it is for / who is involved
    - Scale or quantity (how many, how big)
    - Budget or cost limits
    - Timeline, deadline, or timing
    - Location / region / setting
    - Current state / starting point / what already exists
    - Resources already owned or available
    - Constraints, restrictions, must-haves
    - Preferences, style, taste
    - Method / channel (how they want to do it)
    - Whether they will do it themselves or get help
    Prefer the unknowns whose answers would most change the plan. Be specific to \
    THIS task. Do not include anything the task statement already answers.
    """

    static let selectInstructions = """
    You are a personal task coach choosing the best clarifying questions to ask a \
    user before planning their task.

    From the candidate unknowns, pick the 7 whose answers would MOST change the \
    plan. Rules:
    - Drop redundant unknowns that probe the same thing; keep the single best one.
    - Drop generic filler ("any other preferences?", "any concerns?").
    - Drop premature or niche details that don't matter at the planning stage.
    - Drop anything the task already states.
    - Make sure the most critical practical unknown for this task is included.

    Then write each chosen unknown as the question the user sees:
    - A complete question, 5-10 words, natural and conversational.
    - Addressed TO the user (say "you/your", never first person like "my dad").
    - Asks exactly ONE thing. Never combine two asks with "and" or "or".
    - Do not list the answer options inside the question.

    Restate the user's goal as a short specific title (4-9 words) in their terms, \
    never a generic label. Summarise the task in one plain sentence. Set \
    requiresExternalAction true only when answering needs a real-world action \
    outside the app (call, email, visit). No emojis.
    """
}

@Generable
struct FMUnknowns {
    @Guide(description: "Candidate unknowns to learn from the user before planning; specific to this task, no duplicates.", .count(12))
    var unknowns: [String]
}
