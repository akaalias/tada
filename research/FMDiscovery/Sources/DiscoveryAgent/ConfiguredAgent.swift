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
        case .ragFewShot:        return try await ragFewShot(input)
        case .ragCoverageBestOfN: return try await ragCoverageBestOfN(input)
        case .ragCritiqueRevise: return try await ragCritiqueRevise(input)
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

    /// Builds the RAG few-shot system prompt (shared by ragFewShot and best-of-N).
    private func ragSystemPrompt(_ input: String) -> String {
        // Retrieve 2 nearest gold exemplars by word-overlap similarity.
        let examples = GoldExemplars.nearest(to: input, k: 2)
        let exampleBlock = examples.enumerated().map { (i, ex) -> String in
            let numbered = ex.questions.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            return """
            ── EXAMPLE \(i + 1) ──
            User task: "\(ex.input)"
            Excellent questions for this task:
            \(numbered)
            """
        }.joined(separator: "\n\n")

        return """
        You are a personal task coach. The user just shared a task they want to \
        accomplish. Before making any plans, generate clarifying questions that \
        uncover what they specifically want, context (who/what/when/where/why), \
        constraints, resources, and key execution details.

        Study these high-quality examples first — they show the level of \
        specificity, coverage, and naturalness you must match:

        \(exampleBlock)

        ── RULES ──
        TASK TITLE: restate the user's goal as a short, specific title (4-9 words) \
        in their own terms. Never use generic labels like "Clarifying Questions".
        DESCRIPTION: summarise the task itself in one plain sentence.
        QUESTIONS — follow these rules without exception:
        • Each question title IS the complete question, 5-15 words, natural.
        • ONE thing per question. NEVER combine two asks with "and" or "or".
        • Be SPECIFIC to THIS task — model the precision in the examples above.
        • The 7 questions must cover the most decision-critical unknowns for \
          THIS task; don't waste slots on generic or premature details.
        • Addressed to the user ("you/your"). Never first-person ("my dad", "I").
        • Do not ask about anything the task statement already tells you.
        • requiresExternalAction true only when answering needs a real-world action \
          outside the app (call, email, visit). False for in-app data entry.
        • Do NOT use emojis.
        """
    }

    private func ragFewShot(_ input: String) async throws -> DiscoveryResult {
        let session = LanguageModelSession { ragSystemPrompt(input) }
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let r = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                          options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    /// EXP-004: best-of-N over the RAG few-shot agent, ranked by a deterministic
    /// Swift coverage scorer. Generate N full sets at varying temperatures, then
    /// pick the set that best covers the universal high-value planning dimensions
    /// (budget, timeline, scale/who-for, location, current-state) while avoiding
    /// redundant clusters and re-asking facts already stated in the task.
    private func ragCoverageBestOfN(_ input: String) async throws -> DiscoveryResult {
        let system = ragSystemPrompt(input)
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let temps = config.sampleTemps ?? [0.3, 0.6, 0.9, 1.0]

        var best: DiscoveryResult?
        var bestScore = -Double.greatestFiniteMagnitude
        for t in temps {
            let session = LanguageModelSession { system }
            let r = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                              options: config.options(temp: t, sampling: .modelDefault))
            let cand = r.content.toContract()
            let s = CoverageScorer.score(cand.questions.map { $0.title }, input: input)
            if s > bestScore { bestScore = s; best = cand }
        }
        return best!
    }

    /// EXP-005: reflexion editor on top of the RAG few-shot draft. Stage 1 is the
    /// current best (ragFewShot). Stage 2 is a second FM call that audits the draft
    /// against an explicit decision-critical dimension checklist: it drops questions
    /// that re-ask facts the task already states, drops low-value/niche slots, splits
    /// double-barreled asks, and ensures the highest-value MISSING unknown is added —
    /// while keeping the strong draft questions verbatim to preserve naturalness.
    private func ragCritiqueRevise(_ input: String) async throws -> DiscoveryResult {
        // Stage 1: strong RAG draft (= exp003 best).
        let draftSession = LanguageModelSession { ragSystemPrompt(input) }
        let draftPrompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let draft = try await draftSession.respond(
            to: draftPrompt, generating: FMDiscoveryPlan.self,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
        ).content

        // Stage 2: auditor revises the draft. Reuse the same exemplars (naturalness
        // anchor) plus an editor instruction with the decision-critical checklist.
        let numbered = draft.questions.enumerated()
            .map { "\($0.offset + 1). \($0.element.question)" }
            .joined(separator: "\n")
        let editorSystem = ragSystemPrompt(input) + "\n\n" + Prompts.critiqueEditor
        let editorSession = LanguageModelSession { editorSystem }
        let editorPrompt = """
        Task the user entered: "\(input)"

        A first draft of 7 clarifying questions:
        \(numbered)

        Audit this draft and output the FINAL exactly 7 questions. Apply the editor rules: \
        delete any question whose answer is already stated in the task; delete the single \
        lowest-value or most niche question; split any question that asks two things; and \
        make sure the set covers the most decision-critical unknown that the draft is MISSING \
        (especially budget/cost, who it is for, timeline/urgency, scale, location, or what \
        already exists). Keep the draft's strong questions worded as they are.
        """
        let revised = try await editorSession.respond(
            to: editorPrompt, generating: FMDiscoveryPlan.self,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
        ).content
        return revised.toContract()
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
