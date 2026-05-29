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
        case .ragCoverageScaffold: return try await ragCoverageScaffold(input)
        case .ragFewShotSemantic: return try await ragFewShotSemantic(input)
        case .ragAdaptExemplar:  return try await ragAdaptExemplar(input)
        case .ragCoverageRepair: return try await ragCoverageRepair(input)
        case .ragSelfConsistency: return try await ragSelfConsistency(input)
        case .ragContrastiveFewShot: return try await ragContrastiveFewShot(input)
        case .ragTournament:     return try await ragTournament(input)
        case .ragPlanAssumptions: return try await ragPlanAssumptions(input)
        }
    }

    /// EXP-012: smart best-of-N via a PAIRWISE 3B TOURNAMENT. The log shows two
    /// SELECTION strategies over the 3B's own multi-samples have failed: exp004's
    /// absolute Swift coverage scorer (keyword span) picked worse sets, and exp010's
    /// cross-sample frequency clustering concentrated the model's generic catch-alls.
    /// Both ask for ABSOLUTE judgment. A 3B is far better at RELATIVE judgment, so
    /// here selection is a single-elimination bracket of pairwise comparisons: each
    /// match shows the 3B the task plus two whole 7-question sets and asks which set
    /// is better. To damp position bias each match is judged in BOTH orderings and
    /// votes are tallied (tie → the lower-temp incumbent). The winning set is returned
    /// VERBATIM, so atomicity and natural phrasing are never mangled. If pairwise
    /// selection lifts even slightly above chance, best-of-4 should beat a single draw.
    private func ragTournament(_ input: String) async throws -> DiscoveryResult {
        let system = ragSystemPrompt(input)
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let temps = config.sampleTemps ?? [0.3, 0.5, 0.7, 0.9]

        var plans: [DiscoveryResult] = []
        for t in temps {
            let session = LanguageModelSession { system }
            let r = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                              options: config.options(temp: t, sampling: .modelDefault))
            plans.append(r.content.toContract())
        }
        guard plans.count > 1 else { return plans.first! }

        // Single-elimination bracket; lower index = lower-temp incumbent (tie-break).
        var bracket = plans
        while bracket.count > 1 {
            var next: [DiscoveryResult] = []
            var i = 0
            while i < bracket.count {
                if i + 1 < bracket.count {
                    next.append(try await pickBetterSet(input, bracket[i], bracket[i + 1]))
                    i += 2
                } else {
                    next.append(bracket[i]); i += 1
                }
            }
            bracket = next
        }
        return bracket[0]
    }

    /// Two-order pairwise vote between two whole sets; tie → `a` (incumbent).
    private func pickBetterSet(_ input: String, _ a: DiscoveryResult, _ b: DiscoveryResult) async throws -> DiscoveryResult {
        // Forward: a is set 1 → 0 means a wins. Backward: b is set 1 → 1 means a wins.
        let aVotesForward = (try await judgeBetter(input, a, b)) == 0 ? 1 : 0
        let aVotesBackward = (try await judgeBetter(input, b, a)) == 1 ? 1 : 0
        let aVotes = aVotesForward + aVotesBackward
        return aVotes >= 1 ? a : b   // b only wins by sweeping both orderings.
    }

    /// Returns 0 if `first` is the better set, 1 if `second` is. Greedy/deterministic.
    private func judgeBetter(_ input: String, _ first: DiscoveryResult, _ second: DiscoveryResult) async throws -> Int {
        func numbered(_ r: DiscoveryResult) -> String {
            r.questions.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "\n")
        }
        let session = LanguageModelSession { Prompts.setComparator }
        let p = """
        Task the user entered: "\(input)"

        SET 1:
        \(numbered(first))

        SET 2:
        \(numbered(second))

        Which set is the better set of clarifying questions for planning this task? Answer 1 or 2.
        """
        let r = try await session.respond(to: p, generating: FMSetComparison.self,
                                          options: config.options(temp: 0.0, sampling: .greedy)).content
        return r.betterSet == 2 ? 1 : 0
    }

    /// EXP-011: contrastive (negative) few-shot. Builds on exp003's robust
    /// single-call positive few-shot (the running best), but PREPENDS one worked
    /// GOOD-vs-BAD example on a neutral, non-eval task. Every prior coverage fix
    /// added a runtime JUDGING step (auditor/repair/scaffold/consensus) and
    /// regressed — the 3B can't judge. Here the judgment is baked into a
    /// demonstration CONTRAST instead of asked at runtime: the BAD set illustrates
    /// the exact anti-patterns the judge flags on exp003 (restating given facts,
    /// off-task/self-defeating questions, vague filler, compound asks, redundant
    /// pairs), so the model learns by example what NOT to spend a slot on.
    private func ragContrastiveFewShot(_ input: String) async throws -> DiscoveryResult {
        let contrast = """


        ── WORKED CONTRAST: what makes a question set strong ──
        For an example task "Organize my garage", here is a STRONG set and a WEAK set.

        STRONG (each question targets a decision-critical unknown, asks ONE thing):
        1. What is your main goal: more storage, a workshop, or parking space?
        2. How large is your garage?
        3. Roughly how much stuff needs sorting or removing?
        4. What is your budget for shelving or storage systems?
        5. Do you have a deadline to finish by?
        6. What will you do with items you no longer want?
        7. Will anyone be helping you with the work?

        WEAK (avoid every one of these patterns):
        • "Do you have a garage?" — restates a fact the task already gives.
        • "What color should the walls be?" — niche/premature, off the core task.
        • "Do you have any other preferences?" — vague filler, not decision-critical.
        • "What is your budget and timeline?" — compound, asks two things at once.
        • "How big is your garage and what fits in it?" — redundant and compound.

        The STRONG set wins because every slot probes a different decision-critical \
        unknown, each asks exactly one thing, and none restates what the task already \
        states. Never produce a question that fits a WEAK pattern.
        """
        let session = LanguageModelSession { ragSystemPrompt(input) + contrast }
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let r = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                          options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    /// EXP-010: self-consistency consensus. Draw N independent RAG sets (same
    /// exp003 few-shot prompt) at varying temperatures, then in Swift cluster all
    /// ~Nx7 questions by embedding similarity and keep the 7 clusters with the
    /// broadest CROSS-SAMPLE agreement. Redundant clusters collapse to one question;
    /// one-off niche slots (single-sample singletons) drop out; the recurring
    /// decision-critical unknowns rise to the top. Falls back to a single sample if
    /// embeddings are unavailable.
    private func ragSelfConsistency(_ input: String) async throws -> DiscoveryResult {
        let system = ragSystemPrompt(input)
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let temps = config.sampleTemps ?? [0.4, 0.6, 0.8, 1.0]

        var items: [SelfConsistency.Item] = []
        var title = ""
        var summary = ""
        for (s, t) in temps.enumerated() {
            let session = LanguageModelSession { system }
            let plan = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                                  options: config.options(temp: t, sampling: .modelDefault)).content
            if s == 0 { title = plan.title; summary = plan.summary }
            for (p, q) in plan.questions.enumerated() {
                items.append(.init(text: q.question, requiresExternalAction: q.requiresExternalAction,
                                   sample: s, position: p))
            }
        }

        guard let selected = SelfConsistency.select(items, count: 7), selected.count == 7 else {
            // Fallback: return the first (lowest-temp) sample verbatim.
            let session = LanguageModelSession { system }
            return try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                              options: config.options(temp: temps.first, sampling: .modelDefault))
                .content.toContract()
        }
        return DiscoveryResult(
            taskTitle: title, taskDescription: summary,
            questions: selected.map { DiscoveryQuestion(title: $0.text, description: "", requiresExternalAction: $0.requiresExternalAction) })
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
    /// Default retrieval is word-overlap; pass `examples` to override (EXP-007 uses
    /// semantic retrieval).
    private func ragSystemPrompt(_ input: String, examples: [GoldExemplar]? = nil) -> String {
        // Retrieve 2 nearest gold exemplars (word-overlap by default).
        let examples = examples ?? GoldExemplars.nearest(to: input, k: 2)
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

    /// EXP-006: RAG few-shot + an EXPLICIT task-conditioned coverage checklist.
    /// exp003 shows strong exemplars only as demonstrations, which does not transfer
    /// into a coverage requirement (the 3B keeps missing budget/who-for/etc). Here we
    /// aggregate the decision-critical DIMENSIONS from the same nearest exemplars and
    /// inject them as an explicit (but adaptable) coverage requirement. Unlike exp005's
    /// universal checklist, these dimensions are RETRIEVED per task type, and unlike the
    /// auditor it stays a SINGLE call to preserve naturalness/atomicity.
    private func ragCoverageScaffold(_ input: String) async throws -> DiscoveryResult {
        let dims = GoldExemplars.coverageDimensions(to: input, k: 2)
        let dimList = dims.map { "• \($0)" }.joined(separator: "\n")
        let scaffold = """


        ── COVERAGE CHECKLIST (task-conditioned) ──
        For tasks like this one, the most decision-critical unknowns tend to fall in \
        these dimensions:
        \(dimList)
        Make sure your 7 questions probe the MOST decision-critical of these for THIS \
        specific task. Adapt the wording to this task; this is a guide, not a template. \
        SKIP any dimension the task statement already answers, and skip any that clearly \
        does not apply here. Prefer covering a critical missing dimension over adding a \
        second question about something you already covered.
        """
        let session = LanguageModelSession { ragSystemPrompt(input) + scaffold }
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let r = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                          options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    private func ragFewShot(_ input: String) async throws -> DiscoveryResult {
        let session = LanguageModelSession { ragSystemPrompt(input) }
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let r = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                          options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    /// EXP-013: plan-then-extract-assumptions. Every prior coverage attempt asked the
    /// 3B to RANK which unknowns matter (abstract judgment it lacks) or to select/
    /// aggregate/critique its own generic question samples — all stuck at coverage 3.
    /// Here we change the COGNITIVE task: stage 1 makes the 3B draft a CONCRETE plan to
    /// actually accomplish the task and surface the ASSUMPTIONS it was forced to commit
    /// to (to write a real plan for "trip to Paris" it must assume a departure city,
    /// dates, budget, group size — exactly the decision-critical unknowns). Those
    /// assumptions emerge grounded in THIS specific task (unlike brainstormSelect's
    /// abstract unknown-listing, which went generic). Stage 2 turns them into 7 natural
    /// questions using the proven exp003 RAG exemplars to anchor phrasing/atomicity.
    private func ragPlanAssumptions(_ input: String) async throws -> DiscoveryResult {
        // Stage 1: draft a concrete plan and surface the assumptions it required.
        let planner = LanguageModelSession { Prompts.planAssumptions }
        let pa = try await planner.respond(
            to: "The user wants to: \"\(input)\"\n\nDraft a concrete plan to accomplish this, then list the specific assumptions you had to make because the task didn't tell you.",
            generating: FMPlanAssumptions.self,
            options: config.options(temp: config.brainstormTemp, sampling: config.brainstormSampling)
        ).content
        let assumptionList = pa.assumptions.map { "- \($0)" }.joined(separator: "\n")

        // Stage 2: turn the most decision-critical assumed unknowns into 7 questions,
        // reusing the exp003 RAG few-shot scaffold for phrasing/atomicity/non-redundancy.
        let scaffold = """


        ── SOURCE: WHAT THE PLAN HAD TO ASSUME ──
        To plan this task, the following facts had to be ASSUMED because the user never \
        stated them. Each is a decision-critical unknown — the real answer could differ \
        and change the plan:
        \(assumptionList)

        Turn the MOST decision-critical of these assumed unknowns into exactly 7 \
        clarifying questions. Merge any that overlap into one, drop any the task already \
        answers or that are trivial, and put the single most important missing thing \
        first. Ask each as a natural question; do not mention the word "assumption".
        """
        let session = LanguageModelSession { ragSystemPrompt(input) + scaffold }
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions, each probing one assumed unknown above."
        let r = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                          options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    /// EXP-007: identical to ragFewShot but exemplars are retrieved by on-device
    /// semantic similarity (NLEmbedding cosine) instead of word overlap, so the
    /// few-shot demonstrations are the nearest task TYPE even with no shared words.
    private func ragFewShotSemantic(_ input: String) async throws -> DiscoveryResult {
        let examples = GoldExemplars.nearestSemantic(to: input, k: 2)
        let session = LanguageModelSession { ragSystemPrompt(input, examples: examples) }
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let r = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                          options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    /// EXP-008: adapt-the-exemplar. The log's recurring conclusion is that the 3B
    /// imitates surface form but can't DISCOVER which unknowns are decision-critical
    /// (coverage stuck at 3 across exp003-007; checklists/labels in exp005/006 failed
    /// because labels aren't questions). exp003 shows exemplars only as demonstrations.
    /// Here we make the nearest exemplar's 7 concrete gold questions HARD CONSTRAINTS:
    /// the model must adapt each one ONE-TO-ONE to the new task, preserving the
    /// underlying unknown each probes (so gold's excellent dimension SPAN transfers
    /// directly) while doing only the surface rewrite the 3B is good at. If an
    /// exemplar question's unknown is already answered by the new task statement, it
    /// replaces that single slot with the next most decision-critical unknown.
    private func ragAdaptExemplar(_ input: String) async throws -> DiscoveryResult {
        let ex = GoldExemplars.nearest(to: input, k: 1).first!
        let numbered = ex.questions.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        let system = """
        You are a personal task coach. For a closely related task, an expert wrote a \
        PROVEN set of 7 clarifying questions. Your job is to ADAPT that proven set, \
        question by question, to the user's new task — so the new questions probe the \
        SAME kinds of decision-critical unknowns that made the proven set excellent.

        ── PROVEN SET (related task: "\(ex.input)") ──
        \(numbered)

        ── HOW TO ADAPT ──
        • Produce exactly 7 questions, one adapted from each proven question IN ORDER.
        • Keep the SAME underlying unknown each proven question probes (its budget \
          question → your budget question; its timeline question → your timeline \
          question; its who-for question → your who-for question), but reword it to be \
          specific and natural for THIS task.
        • Use the proven set's DIRECT phrasing. If it asks "What is your budget?", you \
          ask "What is your budget?" — never soften to "Do you have a budget?".
        • If, and only if, a proven question's unknown is ALREADY answered by the user's \
          task statement, drop just that one and replace it with the next most \
          decision-critical unknown for this task (do not duplicate another slot).

        ── RULES ──
        TASK TITLE: restate the user's goal as a short specific title (4-9 words) in \
        their own terms. Never a generic label like "Clarifying Questions".
        DESCRIPTION: summarise the task in one plain sentence.
        QUESTIONS:
        • Each question title IS the complete question, 5-15 words, natural.
        • ONE thing per question. NEVER combine two asks with "and" or "or".
        • Be SPECIFIC to THIS task; no vague catch-alls like "any other preferences?".
        • Addressed to the user ("you/your"). Never first-person ("my dad", "I").
        • requiresExternalAction true only when answering needs a real-world action \
          outside the app (call, email, visit). False for in-app data entry.
        • Do NOT use emojis.
        """
        let session = LanguageModelSession { system }
        let prompt = """
        Task the user entered: "\(input)"

        Adapt the proven set to this task: generate exactly 7 clarifying questions.
        """
        let r = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                          options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    /// EXP-009: coverage-gap REPAIR on the exp003 draft. exp003 is the best config
    /// but the judge consistently dings it for missing the single most decision-
    /// critical unknown (coverage stuck at 3). Every prior fix asked the 3B to JUDGE
    /// which unknown is missing — it can't. Here the judgment is deterministic: build
    /// the exp003 draft, then in Swift (NLEmbedding) find the concrete gold question
    /// (from the same nearest exemplars) whose unknown the draft covers LEAST and the
    /// most-redundant draft slot. A single focused FM call adapts that one gold
    /// question to this task; we swap it into the redundant slot, leaving the other
    /// six draft questions untouched. Coverage gets fixed without mangling the draft.
    private func ragCoverageRepair(_ input: String) async throws -> DiscoveryResult {
        let exemplars = GoldExemplars.nearest(to: input, k: 2)
        let draftSession = LanguageModelSession { ragSystemPrompt(input, examples: exemplars) }
        let draftPrompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let plan = try await draftSession.respond(
            to: draftPrompt, generating: FMDiscoveryPlan.self,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
        ).content

        var questions = plan.questions.map {
            DiscoveryQuestion(title: $0.question, description: $0.detail, requiresExternalAction: $0.requiresExternalAction)
        }
        let draftTitles = questions.map { $0.title }

        guard let repair = CoverageRepair.plan(draft: draftTitles, exemplars: exemplars) else {
            return DiscoveryResult(taskTitle: plan.title, taskDescription: plan.summary, questions: questions)
        }

        let alreadyAsked = draftTitles.enumerated()
            .map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let repairSystem = """
        You are a personal task coach. A proven clarifying question from a closely \
        related task probes a decision-critical unknown that the user's task very \
        likely shares but that the current question set does NOT yet cover. Adapt it \
        into ONE natural clarifying question specific to the user's task.

        ── PROVEN QUESTION (probes the missing unknown) ──
        \(repair.missing)

        ── RULES ──
        • Output exactly ONE question that probes the SAME underlying unknown, reworded \
          to be specific and natural for the user's task.
        • 5-12 words, ONE thing only, never combine asks with "and"/"or", addressed to \
          the user ("you"/"your").
        • If the user's task statement ALREADY answers that unknown, instead ask the \
          single most decision-critical unknown still missing for this task.
        • Do NOT duplicate any of these already-asked questions:
        \(alreadyAsked)
        • No emojis.
        """
        let repairSession = LanguageModelSession { repairSystem }
        let adapted = try await repairSession.respond(
            to: "Task the user entered: \"\(input)\"\n\nWrite the one clarifying question.",
            generating: FMSingleQuestion.self,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
        ).content

        questions[repair.replaceIndex] = DiscoveryQuestion(
            title: adapted.question, description: "", requiresExternalAction: adapted.requiresExternalAction)
        return DiscoveryResult(taskTitle: plan.title, taskDescription: plan.summary, questions: questions)
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
struct FMSingleQuestion {
    @Guide(description: "One complete clarifying question, 5-12 words, asking exactly ONE thing. Never combine two asks with 'and' or 'or'. Addressed to the user ('you'/'your').")
    var question: String
    @Guide(description: "True only if answering requires a real-world action outside the app (call, email, visit). False for in-app data entry.")
    var requiresExternalAction: Bool
}

@Generable
struct FMSetComparison {
    @Guide(description: "Which set is the better set of clarifying questions: answer exactly 1 or 2.")
    var betterSet: Int
}

@Generable
struct FMPlanAssumptions {
    @Guide(description: "A concrete, specific plan to actually accomplish this task, 3-6 sentences. Commit to concrete choices (a route, a budget level, a schedule, an approach) even though the user hasn't given the details.")
    var plan: String
    @Guide(description: "The specific facts about THIS task you had to ASSUME to write that plan because the user did not state them — e.g. where they're starting from, how much they can spend, who it's for, when it needs to happen, what they already have, how many, where. Each is one concrete, task-specific assumed fact, never a generic placeholder. List the ones whose real answer would MOST change the plan first.", .count(8))
    var assumptions: [String]
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
