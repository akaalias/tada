import Foundation
import FoundationModels
import Contract

/// The single mutable artifact: a discovery agent driven entirely by a
/// DiscoveryConfig. Topology, decoding, and (later) post-processing/retrieval
/// are all config. New experiments add named configs in Configs.swift.
public struct ConfiguredAgent: Sendable {
    let config: DiscoveryConfig
    public init(_ config: DiscoveryConfig) { self.config = config }

    public func generate(_ input: String) async throws -> DiscoveryResult {
        switch config.topology {
        case .singleShot:        return try await singleShot(input)
        case .brainstormSelect:  return try await brainstormSelect(input)
        case .overGenerateScore: return try await overGenerateScore(input)
        }
    }

    // MARK: topologies

    private func singleShot(_ input: String) async throws -> DiscoveryResult {
        let session = LanguageModelSession { Prompts.singleShot }
        let prompt = """
        Task the user entered: "\(input)"

        Generate exactly 7 clarifying questions. Each must ask about ONE thing only — never combine two asks with "and" or "or".
        """
        let r = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                          options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    private func brainstormSelect(_ input: String) async throws -> DiscoveryResult {
        let bs = LanguageModelSession { Prompts.brainstorm }
        let unknowns = try await bs.respond(
            to: "The user wants to: \"\(input)\"\n\nList the candidate unknowns you'd want to learn before planning this. Do not ask about anything the task already states.",
            generating: FMUnknowns.self,
            options: config.options(temp: config.brainstormTemp, sampling: config.brainstormSampling)
        ).content.unknowns

        let sel = LanguageModelSession { Prompts.select }
        let list = unknowns.map { "- \($0)" }.joined(separator: "\n")
        let prompt = """
        The user wants to: "\(input)"

        Candidate unknowns brainstormed for this task:
        \(list)

        Choose the 7 MOST decision-relevant unknowns — the ones whose answers would most change the plan. Drop anything redundant, generic, premature, or already implied by the task. Write each as one natural clarifying question, and restate the task as a title and one-sentence description.
        """
        return try await sel.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                     options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
            .content.toContract()
    }

    private func overGenerateScore(_ input: String) async throws -> DiscoveryResult {
        let session = LanguageModelSession { Prompts.overGenerate }
        let prompt = """
        The user wants to: "\(input)"

        Brainstorm 12 candidate clarifying questions across the planning dimensions. For each, rate how much its answer would change the plan (importance 1-5). Restate the task as a title and one-sentence description.
        """
        let plan = try await session.respond(to: prompt, generating: FMScoredPlan.self,
                                             options: config.options(temp: config.brainstormTemp, sampling: config.brainstormSampling)).content
        // Selection moved OUT of the model into Swift: top 7 by importance, stable order.
        let top = plan.candidates.enumerated()
            .sorted { ($0.element.importance, -$0.offset) > ($1.element.importance, -$1.offset) }
            .prefix(7)
            .sorted { $0.offset < $1.offset }
            .map { $0.element }
        return DiscoveryResult(
            taskTitle: plan.title, taskDescription: plan.summary,
            questions: top.map { DiscoveryQuestion(title: $0.question, description: "", requiresExternalAction: $0.requiresExternalAction) }
        )
    }
}

// MARK: - Guided-generation types

@Generable
struct FMDiscoveryPlan {
    @Guide(description: "The user's task restated as a short specific title, 4-9 words, in their own words. Never a generic label like 'Clarifying Questions'.")
    var title: String
    @Guide(description: "One plain sentence summarising the task.")
    var summary: String
    @Guide(description: "Exactly 7 clarifying questions.", .count(7))
    var questions: [FMQuestion]

    func toContract() -> DiscoveryResult {
        DiscoveryResult(taskTitle: title, taskDescription: summary,
                        questions: questions.map { DiscoveryQuestion(title: $0.question, description: $0.detail, requiresExternalAction: $0.requiresExternalAction) })
    }
}

@Generable
struct FMQuestion {
    @Guide(description: "A complete clarifying question, 5-10 words, asking exactly ONE thing. Never combine two asks with 'and' or 'or'. Addressed to the user ('you'/'your').")
    var question: String
    @Guide(description: "Optional short extra context. May be empty.")
    var detail: String
    @Guide(description: "True only if answering requires a real-world action outside the app (call, email, visit). False for in-app data entry.")
    var requiresExternalAction: Bool
}

@Generable
struct FMUnknowns {
    @Guide(description: "Candidate unknowns to learn from the user before planning; specific to this task, no duplicates.", .count(12))
    var unknowns: [String]
}

@Generable
struct FMScoredPlan {
    @Guide(description: "The user's task restated as a short specific title, 4-9 words, in their terms.")
    var title: String
    @Guide(description: "One plain sentence summarising the task.")
    var summary: String
    @Guide(description: "12 candidate clarifying questions, diverse across planning dimensions.", .count(12))
    var candidates: [FMScoredCandidate]
}

@Generable
struct FMScoredCandidate {
    @Guide(description: "A complete clarifying question, 5-10 words, one thing only, addressed to the user.")
    var question: String
    @Guide(description: "How much this answer would change the plan, 1 (minor) to 5 (critical).")
    var importance: Int
    @Guide(description: "True only if answering needs a real-world action outside the app.")
    var requiresExternalAction: Bool
}
