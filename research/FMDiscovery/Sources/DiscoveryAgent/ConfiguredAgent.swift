import Foundation
import FoundationModels
import Contract

/// The single mutable artifact: a discovery agent driven entirely by a
/// DiscoveryConfig. Topology, decoding, and (later) post-processing/retrieval
/// are all config. New experiments add named configs in Configs.swift.
public struct ConfiguredAgent: Sendable {
    let config: DiscoveryConfig
    public init(_ config: DiscoveryConfig) { self.config = config }

    /// EXP-011's worked GOOD-vs-BAD contrastive lesson (the current-best base).
    /// Shared by exp011 and exp014 verbatim so both teach the same anti-patterns.
    static let contrastLesson = """


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
        case .ragCorpusFewShot:  return try await ragCorpusFewShot(input)
        case .ragDimensionalSchema: return try await ragDimensionalSchema(input)
        case .ragSequential:     return try await ragSequential(input)
        case .ragFillerRepair:   return try await ragFillerRepair(input)
        case .ragReasonedFewShot: return try await ragReasonedFewShot(input)
        case .ragCorpusSelect:   return try await ragCorpusSelect(input)
        case .ragPerspectiveEnsemble: return try await ragPerspectiveEnsemble(input)
        case .ragJustifiedQuestions: return try await ragJustifiedQuestions(input)
        case .ragStartingPointCritique: return try await ragStartingPointCritique(input)
        case .ragGivensAware:    return try await ragGivensAware(input)
        case .ragCompositeBestOfN: return try await ragCompositeBestOfN(input)
        case .ragAntiModalContrast: return try await ragAntiModalContrast(input)
        case .adapterDirect:     return try await adapterDirect(input)
        case .adapterScopedCritique: return try await adapterScopedCritique(input)
        case .adapterDivergeConverge: return try await adapterDivergeConverge(input)
        case .adapterSolutionSpaceEIG: return try await adapterSolutionSpaceEIG(input)
        case .adapterDispersionBestOfN: return try await adapterDispersionBestOfN(input)
        case .adapterRagFewShot: return try await adapterRagFewShot(input)
        case .adapterRagFewShotLOO: return try await adapterRagFewShot(input, leaveOneOut: true)
        }
    }

    /// EXP-030: solution-space information gain on the champion adapter (Lever C, the
    /// rules' TOP PICK — genuinely untried, never run on the adapter). A deep review of
    /// the 2024-25 disambiguation literature found that EVERY method beating baselines
    /// scores a question NOT in isolation but against an EXPLICIT, materialised set of
    /// competing solutions it would discriminate between. ALL 29 prior experiments scored
    /// questions in isolation (absolute rubric, vague "importance", whole-set pairwise) or
    /// asked the model to introspect "which unknown is critical" — undefined until you
    /// have competing answers to be critical ABOUT. That is very likely WHY coverage is
    /// pinned at 3. This is distinct from exp013 (drafted ONE plan, extracted its
    /// assumptions → skewed to logistics) and exp029 (free-prose brainstorm → drifted
    /// generic): it materialises a SET of N DIVERGENT concrete scenarios — competing
    /// plausible interpretations of who the user is and what they specifically want
    /// (e.g. for "plan a trip": shoestring solo backpacker / luxury anniversary couple /
    /// business trip with one free day / family of five on a budget) — then frames
    /// generation as DISCRIMINATION: write the 7 questions whose answers would most
    /// SEPARATE which scenario is the real one. "Which unknown matters" is now grounded —
    /// a question matters iff the scenarios disagree on its answer. Both passes are
    /// GENERATION (not the judgment/selection that sank every multi-FM loss), both greedy.
    /// Stage 2 keeps the champion's native training-format anchor first to stay in
    /// distribution; the scenario block is compact to avoid exp029's verbose-drift failure.
    /// Falsifiable: if grounding question value in competing concrete answers surfaces the
    /// decision-critical unknown, coverage lifts above 3; if the adapter just restates its
    /// modal set, it lands at/below the champion's 0.409.
    private func adapterSolutionSpaceEIG(_ input: String) async throws -> DiscoveryResult {
        // Stage 1: materialise N divergent competing scenarios for the task.
        let scenarioSystem = """
        You are a sharp planning analyst. Before any clarifying questions are written, \
        you imagine the DIFFERENT realistic situations a user who entered this task could \
        actually be in — because the right plan depends entirely on which one is true.

        Produce 4 DIVERGENT, concrete, plausible interpretations of who THIS user is and \
        what they specifically want. Make them genuinely DISAGREE on the decisions that \
        matter: different goal, scale, budget, audience, starting point, constraints, or \
        stakes — whatever is decision-critical for this kind of task. Each is one vivid \
        sentence committing to SPECIFIC choices (not vague hedging), and the four together \
        should span the realistic range of how this task could really go.
        """
        let scenarioSession = LanguageModelSession(model: try resolveModel()) { scenarioSystem }
        let scenarios = try await scenarioSession.respond(
            to: "The user's task: \"\(input)\"\n\nList 4 divergent concrete scenarios for who this user is and what they want.",
            generating: FMScenarios.self,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
        ).content.scenarios
        let scenarioList = scenarios.enumerated()
            .map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        // Stage 2: champion's native-format call, framed as DISCRIMINATION between the
        // competing scenarios. Training-format anchor first to stay in distribution.
        let convergeSession = LanguageModelSession(model: try resolveModel()) { Self.adapterSystem }
        let convergePrompt = """
        Task the user entered: "\(input)"

        This task could mean very different things. Four plausible situations the user \
        could be in:
        \(scenarioList)

        Write the 7 clarifying questions that would best tell us WHICH of these situations \
        is the real one — the questions on which these scenarios most DISAGREE. A question \
        earns its slot only if answering it would change which situation you'd plan for. \
        Prioritise the decision-critical forks the scenarios differ on over generic filler.
        """
        let plan = try await convergeSession.respond(
            to: convergePrompt, generating: FMDiscoveryPlan.self,
            includeSchemaInPrompt: false,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
        ).content
        return plan.toContract()
    }

    // MARK: - Adapter (lever 7)

    /// System prompt for the adapter path. MUST match the training data's system
    /// content (format_training_data.py): toolkit default + our coach instruction.
    static let adapterSystem =
        "A conversation between a user and a helpful assistant. "
        + "Taking the role of a personal task coach. Given a task the user wants to accomplish, "
        + "generate clarifying questions that uncover what they specifically want, the context "
        + "(who/what/when/where/why), constraints and preferences, and key execution details. "
        + "Restate the user's goal as a short specific title (4-9 words), never a generic label. "
        + "Summarise the task in one sentence. Each question is complete, 5-10 words, asks ONE "
        + "thing (never combine with \"and\"/\"or\"), specific to THIS task, addressed to the user, "
        + "no emojis. Produce exactly 7 questions."

    private func resolveModel() throws -> SystemLanguageModel {
        guard let path = config.adapter else { return SystemLanguageModel.default }
        let adapter = try SystemLanguageModel.Adapter(fileURL: URL(filePath: path))
        return SystemLanguageModel(adapter: adapter)
    }

    /// Schema-free guided generation on the fine-tuned adapter: same system+user as
    /// training, schema omitted from the prompt (the adapter learned the format).
    private func adapterDirect(_ input: String) async throws -> DiscoveryResult {
        let session = LanguageModelSession(model: try resolveModel()) { Self.adapterSystem }
        let prompt = "Task the user entered: \"\(input)\""
        let r = try await session.respond(
            to: prompt, generating: FMDiscoveryPlan.self,
            includeSchemaInPrompt: false,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    /// EXP-032: RAG few-shot demonstrations ON THE CHAMPION ADAPTER. The rules name a
    /// HIGH-VALUE, barely-explored class: take a proven IN-CONTEXT topology and run it
    /// on the ADAPTER (every prior in-context win/loss was measured on the weak stock
    /// 3B, never the fine-tuned base). The scoped-critique variant of this was exp028;
    /// the RAG few-shot variant — which lifted the stock 3B from baseline 0.307 to its
    /// in-context best (exp003 0.320) and was the single strongest in-context lever — has
    /// NEVER been run on the adapter. Rationale grounded in the champion's judge notes:
    /// the adapter has strong phrasing/format discipline (atom 4, spec 4, nat 4) but is
    /// pinned at coverage 3 — it reliably MISSES the single most decision-critical unknown
    /// (trip departure-city, resume existing-resume, dinner budget, etc.). Every attempt
    /// to recover that unknown from the adapter's OWN judgment failed: scoped critique
    /// (exp028), free-text brainstorm (exp029), solution-space EIG (exp030), best-of-N
    /// over its own draws (exp031) all stayed ≤ 0.398. The missing piece is an EXTERNAL
    /// coverage signal — concrete demonstrations of WHICH unknowns matter for similar
    /// task types. exp003 supplied exactly that to the stock 3B; the 3B couldn't transfer
    /// the demonstrated dimensions (it imitated surface, not which-unknown-is-critical
    /// judgment). The open question this tests: with the adapter's far stronger base
    /// judgment freeing capacity from phrasing, does demonstrating the critical dimensions
    /// now TRANSFER and move coverage off 3? Minimal surface, single greedy call (no extra
    /// judgment pass that degraded exp028-030): keep the adapter's EXACT training system
    /// prompt + user format (so the adapter stays on its native learned distribution,
    /// unlike exp029's free-text conditioning), and APPEND the 2 nearest gold exemplar
    /// question-sets as reference demonstrations. Exemplars are demonstrations only —
    /// the adapter generates FRESH task-specific questions (gold-leak ban respected).
    private func adapterRagFewShot(_ input: String) async throws -> DiscoveryResult {
        let examples = GoldExemplars.nearest(to: input, k: 2)
        let block = examples.map { ex -> String in
            let qs = ex.questions.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            return "Task: \"\(ex.input)\"\n\(qs)"
        }.joined(separator: "\n\n")

        let system = Self.adapterSystem + """


            For reference, here are strong question sets other coaches wrote for SIMILAR \
            tasks. Study which decision-critical unknowns they cover (budget, scope, \
            who-for, timeline, current-state, location), then write FRESH questions \
            specific to the user's actual task. Do not copy or paraphrase these.

            \(block)
            """

        let session = LanguageModelSession(model: try resolveModel()) { system }
        let prompt = "Task the user entered: \"\(input)\""
        let r = try await session.respond(
            to: prompt, generating: FMDiscoveryPlan.self,
            includeSchemaInPrompt: false,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    /// EXP-031: dispersion best-of-N ON THE CHAMPION ADAPTER. The champion
    /// (adapter_v2a_e1, 0.409) is pinned at coverage 3, and its OWN judge notes name
    /// the SAME mechanism in ~half the held-out losses: it wastes 2-3 of its 7 slots
    /// on INTERNALLY REDUNDANT / overlapping questions, which crowds out the missing
    /// decision-critical unknown. Verbatim from the notes: apartment_move asks move-
    /// date AND how-many-days; dinner_party asks date AND time AND venue-location AND
    /// venue-availability; gp_appointment circles "which clinic?" across Q1/Q3/Q6/Q7;
    /// household_budget asks total AND fixed AND variable expenses (the same thing
    /// three ways); learn_guitar Q4≈Q6 (how to learn); resume_refresh has Q1/Q3 and
    /// Q2/Q7 mirror pairs; find_therapist Q1≈Q2≈Q7; side_business splits where-to-sell
    /// across two slots. Redundancy is a SET-LEVEL property: the champion's single
    /// greedy draw happens to be redundant, but OTHER low-temperature draws from the
    /// same adapter spread their 7 slots across more distinct unknowns. So rather than
    /// a 2nd FM pass (every adapter-side critique/converge pass — exp028/029/030 —
    /// REGRESSED by degrading the champion's hard-won phrasing), this is best-of-N with
    /// a DETERMINISTIC, embedding-based set selector that directly optimises the flaw:
    /// pick the candidate set whose 7 questions have the highest pairwise embedding
    /// DISPERSION (coverage VOLUME — the submodular/facility-location covering-set
    /// objective, Lever D) while staying on-task (relevance term guards against high-
    /// temp drift into "dispersed-because-irrelevant"). The greedy champion draft is
    /// always in the pool as a FLOOR (ties favour it), and winners are returned
    /// BYTE-FOR-BYTE — no question is ever regenerated, so atomicity/naturalness are
    /// never mangled. Distinct from the failed selection family: exp004/exp026 ran
    /// best-of-N on the weak STOCK 3B/RAG generators (low per-call quality), never the
    /// adapter; exp010 tried to MERGE paraphrases across samples (NLEmbedding too
    /// coarse to merge) — this never merges, it selects a whole coherent set; exp012's
    /// tournament asked the 3B to JUDGE (it can't) — this uses zero model judgment.
    private func adapterDispersionBestOfN(_ input: String) async throws -> DiscoveryResult {
        let temps = config.sampleTemps ?? [0.4, 0.6, 0.8]
        let prompt = "Task the user entered: \"\(input)\""

        // Floor candidate: the champion greedy draft (always first → wins ties).
        var candidates: [DiscoveryResult] = []
        let greedySession = LanguageModelSession(model: try resolveModel()) { Self.adapterSystem }
        candidates.append(try await greedySession.respond(
            to: prompt, generating: FMDiscoveryPlan.self,
            includeSchemaInPrompt: false,
            options: config.options(temp: 0, sampling: .greedy)).content.toContract())

        // Diverse low-temp draws from the SAME adapter (modest temps preserve the
        // adapter's phrasing discipline; exp004 showed high temp degrades atomicity).
        for t in temps {
            let session = LanguageModelSession(model: try resolveModel()) { Self.adapterSystem }
            candidates.append(try await session.respond(
                to: prompt, generating: FMDiscoveryPlan.self,
                includeSchemaInPrompt: false,
                options: config.options(temp: t, sampling: .modelDefault)).content.toContract())
        }

        // Deterministic set selection: maximise coverage volume + on-task relevance.
        var best = candidates[0]
        var bestScore = Self.dispersionScore(best.questions.map { $0.title }, input: input)
        for cand in candidates.dropFirst() {
            let s = Self.dispersionScore(cand.questions.map { $0.title }, input: input)
            if s > bestScore { bestScore = s; best = cand }   // strict > keeps greedy on ties
        }
        return best
    }

    /// EXP-031 ruler — purely deterministic, on-device (NLEmbedding). Rewards a set
    /// whose 7 questions span the MOST distinct conceptual space (coverage volume =
    /// mean pairwise cosine DISTANCE — high when slots aren't redundant) while keeping
    /// every question ON-TASK (mean cosine to the task text — guards against a high-
    /// temp set that is "dispersed" only because it drifted off-topic). Small
    /// deterministic penalties for the lexical defects embeddings miss (filler catch-
    /// alls, compound and/or asks). Falls back to the exp026 composite ruler when the
    /// sentence embedder is unavailable, so selection is always defined.
    static func dispersionScore(_ questions: [String], input: String) -> Double {
        guard let qVecs = SemanticRetrieval.vectors(for: questions),
              let taskVec = SemanticRetrieval.vectors(for: [input])?.first,
              qVecs.count >= 2 else {
            return compositeScore(questions, input: input)
        }
        // Coverage volume: mean pairwise distance (1 - cosine) among the 7 questions.
        var pairSum = 0.0, pairN = 0.0
        for i in 0..<qVecs.count {
            for j in (i + 1)..<qVecs.count {
                pairSum += (1.0 - SemanticRetrieval.cos(qVecs[i], qVecs[j]))
                pairN += 1
            }
        }
        let coverageVolume = pairN == 0 ? 0 : pairSum / pairN
        // On-task relevance: mean cosine of each question to the task statement.
        let relevance = qVecs.map { SemanticRetrieval.cos($0, taskVec) }.reduce(0, +) / Double(qVecs.count)
        var score = coverageVolume + 0.5 * relevance
        // Lexical defect guards (small, embedding-scale).
        for q in questions where FillerDetector.isFiller(q) { score -= 0.15 }
        for q in questions {
            let l = " " + q.lowercased() + " "
            if l.contains(" and ") || l.contains(" or ") { score -= 0.10 }
        }
        return score
    }

    /// EXP-028: scoped starting-point critique ON THE ADAPTER. exp023 ran this exact
    /// minimal-surface single-slot repair on the STOCK 3B's contrastive-RAG draft and
    /// landed in the noise (0.273 dev) — the documented reason every prior multi-FM
    /// loss occurred: extra passes on the weak 3B compound weak judgment. The rules'
    /// highest-value untapped lever is to re-home a proven in-context topology ON the
    /// adapter, whose per-call judgment is the only thing that ever beat the plateau.
    /// The champion adapter (v2a_e1, 0.409) is strong on atomicity but PINNED at
    /// coverage 3, and its OWN judge notes name ONE recurring miss across the held set:
    /// the user's STARTING POINT / current state (side_business: does the user already
    /// know ceramics; adopt_dog: prior dog experience + living situation; running:
    /// medical clearance; resume: whether a resume already exists; portfolio:
    /// build-yourself-vs-hire; buy_used_car: is a car already chosen) — and these miss
    /// while the SAME sets waste slots on redundant near-dupes. Stage 1 is the champion
    /// VERBATIM (native adapter format, greedy = its 0.409 output). Stage 2 is ONE
    /// scoped critique — judging ONLY starting-point coverage — run ON THE ADAPTER, not
    /// the stock 3B. If covered, the champion is returned untouched (zero rewrite risk).
    /// If not, the model names the single weakest slot and writes one task-specific
    /// starting-point question; Swift swaps exactly that slot with deterministic
    /// filler/near-dup guards (≤1 slot changes, ≥6 verbatim). Bounded downside, attacks
    /// the one coverage gap that recurs in the champion's own losses.
    private func adapterScopedCritique(_ input: String) async throws -> DiscoveryResult {
        // Stage 1: the champion draft, byte-for-byte identical to adapterDirect.
        let draftSession = LanguageModelSession(model: try resolveModel()) { Self.adapterSystem }
        let plan = try await draftSession.respond(
            to: "Task the user entered: \"\(input)\"",
            generating: FMDiscoveryPlan.self,
            includeSchemaInPrompt: false,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
        ).content

        var questions = plan.questions.map {
            DiscoveryQuestion(title: $0.question, description: $0.detail, requiresExternalAction: $0.requiresExternalAction)
        }
        let titles = questions.map { $0.title }
        let numbered = titles.enumerated().map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        // Stage 2: ONE scoped critique — starting-point coverage ONLY — on the ADAPTER.
        let critiqueSystem = """
        You are reviewing a set of 7 clarifying questions a coach will ask BEFORE \
        planning the user's task. Focus on ONE thing only: the user's STARTING POINT.

        Almost every plan depends on where the user is starting FROM — their current \
        situation, what they already have or have done, or the concrete thing they are \
        starting with. Examples: for a trip, the city they are departing from; for a \
        resume, their current role and whether a resume already exists; for learning an \
        instrument, their current skill level; for buying something used, whether they \
        have already picked a specific one; for an event, whether the venue is booked.

        Read the 7 draft questions. Decide: do ANY of them establish the user's \
        STARTING POINT for THIS task?
        • If YES, set startingPointCovered = true (everything else is ignored).
        • If NO, set startingPointCovered = false, give the 1-based position of the \
          single WEAKEST question (the most generic, premature, or least \
          decision-critical one), and write ONE natural, task-specific question that \
          establishes the starting point — 5-12 words, asking exactly ONE thing, \
          addressed to the user, never generic filler, never restating a fact the \
          task already gives.

        Judge ONLY starting-point coverage. Do not comment on anything else.
        """
        let critiqueSession = LanguageModelSession(model: try resolveModel()) { critiqueSystem }
        let critiquePrompt = """
        Task the user entered: "\(input)"

        Draft questions:
        \(numbered)

        Does any draft question establish the user's starting point for this task?
        """
        let fix = try await critiqueSession.respond(
            to: critiquePrompt, generating: FMStartingPointFix.self,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
        ).content

        // Covered → return the champion draft verbatim (no rewrite, no risk).
        if fix.startingPointCovered {
            return DiscoveryResult(taskTitle: plan.title, taskDescription: plan.summary, questions: questions)
        }

        // Not covered → swap exactly the named weakest slot, with defensive guards.
        let idx = fix.weakestIndex - 1
        let cand = fix.startingPointQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard questions.indices.contains(idx), !cand.isEmpty, !FillerDetector.isFiller(cand) else {
            return DiscoveryResult(taskTitle: plan.title, taskDescription: plan.summary, questions: questions)
        }
        // Don't introduce a near-duplicate of any slot we are KEEPING.
        let kept = titles.enumerated().filter { $0.offset != idx }.map { $0.element }
        if kept.contains(where: { FillerDetector.jaccard(cand, $0) >= 0.5 }) {
            return DiscoveryResult(taskTitle: plan.title, taskDescription: plan.summary, questions: questions)
        }
        questions[idx] = DiscoveryQuestion(title: cand, description: "",
                                           requiresExternalAction: fix.requiresExternalAction)
        return DiscoveryResult(taskTitle: plan.title, taskDescription: plan.summary, questions: questions)
    }

    /// EXP-029: divergent → convergent free-text on the adapter (untried lever A).
    /// EVERY call in the search so far — including all adapter calls — was SCHEMA-
    /// CONSTRAINED: the model is forced straight into 7 typed slots, so the FIRST tokens
    /// it commits to are already a question, not an analysis of the task. The champion
    /// adapter (v2a_e1, 0.409) is strong on atomicity/specificity but PINNED at coverage
    /// 3: its own losses recur on the ONE decision-critical, task-specific unknown
    /// (starting point / current state / what's unique here) that never makes the 7. The
    /// hypothesis: the schema straitjacket on the THINKING step is part of the cause —
    /// forced to emit slots immediately, the adapter falls into its modal generic set
    /// before the sharp task-specific unknowns can surface. exp028 (a scoped CRITIQUE
    /// pass on the adapter) failed because that is JUDGMENT, which the adapter can't do
    /// reliably. This is different: BOTH passes are GENERATION. Stage 1 is an
    /// UNCONSTRAINED, plain-prose brainstorm (NO @Generable schema) where the adapter
    /// freely reasons about what most determines how THIS task should go — the
    /// task-specific unknowns, the user's starting point, the forks a plan hinges on.
    /// Stage 2 is the native adapter format (the champion's exact call) but conditioned
    /// on that prose, converging the surfaced unknowns into the 7 atomic questions. Both
    /// greedy/deterministic (no diversity needed — breadth comes from the open format,
    /// not from sampling). Falsifiable: if freeing the thinking step lets task-specific
    /// unknowns surface, coverage lifts above 3; if the adapter just restates its modal
    /// set after the brainstorm, it lands back at the champion's 0.409 (bounded downside).
    private func adapterDivergeConverge(_ input: String) async throws -> DiscoveryResult {
        // Stage 1: UNCONSTRAINED free-text brainstorm on the adapter. A thinking-oriented
        // system prompt (NOT the question-formatting coach) + plain-text respond, so the
        // adapter analyses the task in prose before any slot is committed.
        let brainstormSystem = """
        You are a sharp planning analyst. Before any clarifying questions are written, \
        you think out loud — in plain prose, NOT a list of questions — about what would \
        MOST determine how to actually do the user's task well.

        Focus on what is SPECIFIC to THIS task, not generic planning boilerplate. Reason \
        about: where the user is starting FROM (their current situation, what they \
        already have or have done, the concrete thing they're starting with); the forks \
        on which the whole plan hinges (the unknowns whose answer would most change the \
        approach); the constraints, scale, audience, and stakes that are particular to \
        this kind of task. Name the single most decision-critical unknown explicitly.

        Write 4-8 sentences of analysis. Do NOT write any questions yet.
        """
        let brainSession = LanguageModelSession(model: try resolveModel()) { brainstormSystem }
        let brainstorm = try await brainSession.respond(
            to: "The user's task: \"\(input)\"\n\nThink through what matters most for this specific task.",
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
        ).content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Stage 2: the champion's native-format call, now CONDITIONED on the prose. Keep
        // the training-format "Task the user entered:" anchor first so the adapter stays
        // in distribution; append the analysis as decision-critical context to cover.
        let convergeSession = LanguageModelSession(model: try resolveModel()) { Self.adapterSystem }
        let convergePrompt = """
        Task the user entered: "\(input)"

        Analysis of what matters most for this specific task:
        \(brainstorm)

        Using that analysis, write the 7 clarifying questions. Make sure the most \
        decision-critical, task-specific unknowns it identified are covered, not generic \
        filler.
        """
        let plan = try await convergeSession.respond(
            to: convergePrompt, generating: FMDiscoveryPlan.self,
            includeSchemaInPrompt: false,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
        ).content
        return plan.toContract()
    }

    /// EXP-027: anti-modal self-contrast. The plateau is judgment-limited and exp010's
    /// central datum is precise: the 3B's MODAL output IS the generic catch-all set,
    /// while the sharp task-specific unknowns live in the TAIL of its distribution.
    /// Two prior levers tried to reach that tail and failed for diagnosable reasons:
    /// exp024 raised TEMPERATURE (an UNDIRECTED widening that dredged up incoherence
    /// and demo-bleed faster than coverage), and exp011 prepended a FIXED GOOD-vs-BAD
    /// demo on a NEUTRAL task (a generic, task-agnostic anchor). The untried move is a
    /// DIRECTED, task-specific push: first draw the model's OWN modal set with GREEDY
    /// decoding (temp 0 = the most-confident = most-generic draw, confirmed by exp019),
    /// then in a second call show that exact set back to the model AS the generic
    /// baseline to beat and have it generate a FRESH 7 that surpasses it — sharper,
    /// more domain-specific, targeting the unknowns the generic draft missed. Crucially
    /// the second pass is GENERATION, not the select/rank/critique judgment that sank
    /// every multi-FM config (exp001/004/005/012/017/023): the model isn't asked to
    /// evaluate anything, only to out-do a concrete, maximally-relevant negative anchor
    /// of its own making. Falsifiable: if a self-generated anti-modal anchor steers the
    /// model off its modal cluster into the sharp tail, coverage/specificity lift above
    /// the plateau; if the model just rewords its defaults or drifts off-task, it lands
    /// in the ~0.27-0.32 noise and confirms the tail is unreachable by in-context steering.
    private func ragAntiModalContrast(_ input: String) async throws -> DiscoveryResult {
        let baseSystem = ragSystemPrompt(input) + Self.contrastLesson
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."

        // Stage 1: the MODAL set — greedy decoding = the model's single most-confident
        // (= most generic, per exp019) draw. This is the concrete anchor to surpass.
        let modalSession = LanguageModelSession(model: try resolveModel()) { baseSystem }
        let modal = try await modalSession.respond(
            to: prompt, generating: FMDiscoveryPlan.self,
            options: config.options(temp: 0.0, sampling: .greedy)
        ).content
        let modalList = modal.questions.enumerated()
            .map { "  \($0.offset + 1). \($0.element.question)" }.joined(separator: "\n")

        // Stage 2: generate a FRESH set told to beat the model's own generic defaults —
        // a directed push off the modal cluster using a dynamic, task-specific anchor.
        let antiModal = """


            ── A GENERIC ASSISTANT'S DRAFT FOR THIS EXACT TASK (do markedly BETTER) ──
            A generic, unimaginative assistant asked these 7 questions for this task:
            \(modalList)

            Those are the OBVIOUS, default questions — what almost anyone would ask first, \
            and several are vague or interchangeable across tasks. Your job is to do \
            markedly BETTER. Write 7 SHARPER clarifying questions that a seasoned \
            specialist in THIS task would prioritise: target the decision-critical \
            unknowns the generic draft MISSED or only gestured at, ground them in the \
            specifics of THIS task's domain, and do NOT merely restate or lightly reword \
            any question above. You may keep a genuinely essential unknown the generic \
            draft happened to include, but spend most of your 7 slots on the \
            higher-leverage, more task-specific unknowns it overlooked.
            """
        let session = LanguageModelSession(model: try resolveModel()) { baseSystem + antiModal }
        let r = try await session.respond(
            to: prompt, generating: FMDiscoveryPlan.self,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    /// EXP-026: best-of-N over the BEST generator (exp011 contrastive RAG), selected
    /// by a COMPOSITE deterministic ruler. exp004 already tried best-of-N but its
    /// failure is documented precisely in the log: it ran on the plain exp003 base
    /// and selected by a COVERAGE-ONLY keyword scorer, so it (a) couldn't see the
    /// atomicity/specificity degradation that high-temp draws introduce (compound/
    /// parenthetical asks) and (b) picked the worse set. The log's own prescription
    /// was never built: "A useful ruler must score atomicity+specificity+task-fit,
    /// not just dimension keyword presence; and sampling noise needs a low-temp
    /// floor." This config does exactly that. It draws N sets from the exp011
    /// contrastive-RAG generator (the current best, not the weaker exp003 base) with
    /// a low-temp floor, then selects fully DETERMINISTICALLY (no 3B judgment — the
    /// move that sank every multi-FM config) by a composite score: CoverageScorer's
    /// dimension span MINUS penalties for filler catch-alls (FillerDetector), near-
    /// duplicate pairs (content Jaccard), and compound asks ("and"/"or" — the
    /// atomicity proxy the rubric rewards). The winning set is returned VERBATIM so
    /// phrasing is never mangled. Falsifiable: if every draw sits in the same modal
    /// generic cluster (exp010's datum), selecting the best by a quality proxy
    /// cannot lift coverage and this lands within the ~0.27-0.32 plateau noise; if
    /// the best base produces a genuinely stronger draw that a composite ruler (but
    /// not a coverage-only one) can spot, it should edge above the plateau.
    private func ragCompositeBestOfN(_ input: String) async throws -> DiscoveryResult {
        let system = ragSystemPrompt(input) + Self.contrastLesson
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let temps = config.sampleTemps ?? [0.4, 0.6, 0.8, 1.0]

        var best: DiscoveryResult?
        var bestScore = -Double.greatestFiniteMagnitude
        for t in temps {   // ascending temps; strict `>` keeps the lower-temp set on ties
            let session = LanguageModelSession(model: try resolveModel()) { system }
            let cand = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                                  options: config.options(temp: t, sampling: .modelDefault))
                .content.toContract()
            let s = Self.compositeScore(cand.questions.map { $0.title }, input: input)
            if s > bestScore { bestScore = s; best = cand }
        }
        return best!
    }

    /// EXP-026 composite ruler: rewards dimension coverage span (CoverageScorer) and
    /// subtracts the rubric-relevant defects a coverage-only scorer is blind to —
    /// filler catch-alls, near-duplicate pairs, and compound (non-atomic) asks. All
    /// deterministic, on-device; no model judgment.
    static func compositeScore(_ questions: [String], input: String) -> Double {
        var score = CoverageScorer.score(questions, input: input)
        for q in questions where FillerDetector.isFiller(q) { score -= 1.5 }
        for i in 0..<questions.count {
            for j in (i + 1)..<questions.count
            where FillerDetector.jaccard(questions[i], questions[j]) >= 0.5 {
                score -= 1.0   // near-duplicate pair wastes a slot
            }
        }
        for q in questions {
            let l = " " + q.lowercased() + " "
            if l.contains(" and ") || l.contains(" or ") { score -= 1.0 }  // compound = non-atomic
        }
        return score
    }

    /// EXP-025: givens-aware single call. The most-cited waste across the whole log
    /// is the 3B spending slots re-asking facts the task ALREADY states (dinner
    /// "how many guests?" when the task says 8 friends; trip destination is Paris;
    /// buy_used_car assumes a car already chosen). exp018 tried a think-first schema
    /// (name the critical unknowns first) and lost because that first field demands
    /// the which-unknown-is-critical JUDGMENT the 3B lacks — it filled it with the
    /// same modal/generic content. This config flips the first field to one the 3B
    /// CAN reliably produce: `providedFacts` — the concrete facts literally present
    /// in the task text (pure reading comprehension, not judgment). Guided generation
    /// emits fields in declared order, so the model commits to the givens FIRST, then
    /// writes 7 questions under an absolute rule that none may re-ask a given. The
    /// bet: a meaningful share of the recurring slot-waste is re-asking givens, so
    /// freeing those slots — in one coherent draw, no separate refill pass — lets the
    /// 7 span more genuine unknowns. Built on the exp011 contrastive RAG base (best).
    private func ragGivensAware(_ input: String) async throws -> DiscoveryResult {
        let session = LanguageModelSession(model: try resolveModel()) { ragSystemPrompt(input) + Self.contrastLesson + Self.givensGuidance }
        let prompt = """
        Task the user entered: "\(input)"

        First list the facts this task statement ALREADY tells you (the givens), then \
        write exactly 7 clarifying questions — none of which may ask about, restate, or \
        re-confirm any given fact. Every slot must probe a genuine unknown.
        """
        let r = try await session.respond(to: prompt, generating: FMGivensPlan.self,
                                          options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    /// EXP-025: appended after the contrastive lesson — teaches the extract-givens-
    /// first format the schema enforces, with worked examples of pulling concrete
    /// facts straight out of the task text (an EASY reading task) and the absolute
    /// no-re-ask-a-given rule that frees the wasted slots.
    static let givensGuidance = """


        ── STEP 1: LIST WHAT THE TASK ALREADY TELLS YOU ──
        Before writing any questions, extract the concrete facts the task statement \
        ALREADY gives you — the things you do NOT need to ask because the user already \
        said them. This is simple reading: pull the facts straight out of the text.
        • "Plan a dinner party for 8 friends this Saturday" → givens: it is a dinner \
          party; 8 guests; this Saturday. (So NEVER ask how many guests or what day.)
        • "Buy a used Toyota Corolla under $10k" → givens: a used car; make/model is \
          Toyota Corolla; budget is under $10k. (So NEVER ask the type, make, or budget.)
        • "Learn to play guitar" → givens: the instrument is guitar. (So NEVER ask \
          which instrument.)

        Then write your 7 questions. ABSOLUTE RULE: none of the 7 may ask about, \
        restate, or re-confirm any fact you listed as given — every slot must probe a \
        genuine UNKNOWN. Spending a slot on a fact the task already states is the most \
        wasteful mistake; freeing that slot for a real decision-critical unknown is \
        exactly what makes the set strong.
        """

    /// EXP-022: interleaved per-question chain-of-thought. exp018 (in-schema CoT)
    /// listed all 7 critical unknowns FIRST in a batch and then wrote all 7
    /// questions — and it FAILED because the model filled the leading list with the
    /// same modal/generic content and the questions inherited it; the batch list
    /// conditions all 7 questions at once but doesn't gate any single slot. This
    /// config tests the untried tight-coupling variant: the schema INTERLEAVES the
    /// reasoning, forcing a concrete decision-IMPACT rationale immediately BEFORE
    /// each question (guided generation emits fields in declared order, so for slot
    /// k the model must state "answering this changes <concrete decision>" right
    /// before phrasing question k). Hypothesis: a per-emission justification gate is
    /// harder to satisfy with filler than a one-shot batch list — a model that must
    /// name the concrete decision a slot changes, at the moment it writes that slot,
    /// is less likely to spend it on "any other preferences?". Single call on the
    /// exp011 contrastive RAG base (best); the rationales are discarded from output.
    private func ragJustifiedQuestions(_ input: String) async throws -> DiscoveryResult {
        let session = LanguageModelSession(model: try resolveModel()) { ragSystemPrompt(input) + Self.contrastLesson + Self.justifiedGuidance }
        let prompt = """
        Task the user entered: "\(input)"

        Produce exactly 7 clarifying questions. For EACH, first state — in one short \
        phrase — the concrete decision that answering it would change for THIS task, \
        then write the question. A slot you can only justify with vague wording \
        ("to understand preferences", "to know more") is filler: replace it with a \
        sharper, decision-critical unknown instead.
        """
        let r = try await session.respond(to: prompt, generating: FMJustifiedPlan.self,
                                          options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    /// EXP-022: guidance appended after the contrastive lesson — explains the
    /// interleaved justify-then-ask discipline the schema enforces, reusing the
    /// "Organize my garage" task so the rationales line up with the STRONG set above.
    static let justifiedGuidance = """


        ── JUSTIFY EACH SLOT, THEN ASK (one at a time) ──
        For every question, FIRST name the concrete decision its answer would change, \
        THEN write the question — immediately, slot by slot. The rationale must point \
        to a real fork in the plan, never vague intent. For "Organize my garage":
        • rationale "decides storage vs workshop vs parking layout" → "What is your main goal for the garage?"
        • rationale "sets how much shelving to buy" → "What is your budget for storage systems?"
        • rationale "determines whether you need outside help or a dumpster" → "Roughly how much stuff needs removing?"
        If the only rationale you can write is generic ("to understand your preferences", \
        "to know more about it"), the slot is FILLER — discard it and ask a sharper \
        decision-critical unknown for THIS task instead. Never restate a fact the task gives.
        """

    /// EXP-021: prompt-diverse perspective ensemble. Every prior multi-sample
    /// config (best-of-N exp004, self-consistency exp010, tournament exp012,
    /// corpus-select exp020) drew its samples from ONE prompt at varying
    /// TEMPERATURES — and exp010's central datum is that those samples all collapse
    /// onto the SAME generic modal cluster, so aggregating/selecting over them
    /// cannot recover coverage the model never produces. This config attacks that
    /// diagnosed failure with the orthogonal, untried lever: PROMPT diversity.
    /// It generates three full 7-question sets from three systematically DIFFERENT
    /// generation FRAMES — an EXECUTION/logistics planner, a SCOPE/goals strategist,
    /// and a DOMAIN EXPERT for this task's field — each of which steers the model
    /// into a different region of decision-space, so their UNION spans dimensions
    /// no single modal draw covers (the domain-expert frame in particular targets
    /// the recurring domain-specificity gap: tax→residency/employment-type,
    /// therapist→presenting concern). The 7 are then assembled DETERMINISTICALLY
    /// (PerspectiveMerge): round-robin across the three sets in each frame's own
    /// emission order, skipping filler and near-duplicates — no 3B selection/
    /// ranking/critique pass, the move that compounded weak judgment in every prior
    /// multi-FM loser. Built on the exp011 contrastive RAG base for phrasing.
    private func ragPerspectiveEnsemble(_ input: String) async throws -> DiscoveryResult {
        let base = ragSystemPrompt(input) + Self.contrastLesson
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."

        var sets: [[DiscoveryQuestion]] = []
        var title = ""
        var summary = ""
        for (i, frame) in Self.perspectiveFrames.enumerated() {
            let session = LanguageModelSession(model: try resolveModel()) { base + frame }
            let plan = try await session.respond(
                to: prompt, generating: FMDiscoveryPlan.self,
                options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
            ).content
            if i == 0 { title = plan.title; summary = plan.summary }
            sets.append(plan.questions.map {
                DiscoveryQuestion(title: $0.question, description: $0.detail, requiresExternalAction: $0.requiresExternalAction)
            })
        }
        let merged = PerspectiveMerge.merge(sets, count: 7)
        return DiscoveryResult(taskTitle: title, taskDescription: summary, questions: merged)
    }

    /// EXP-021: the three distinct generation FRAMES, each appended to the exp011
    /// contrastive RAG system prompt. Unlike exp015's abstract dimension LABELS
    /// (which crowded out task-specific unknowns) and exp016's "ask something
    /// different" (which produced trivial surface variations), each frame is a full
    /// generative PERSONA that gives the model room to reason and produce a natural,
    /// task-specific 7-question set from one coherent vantage point.
    static let perspectiveFrames: [String] = [
        """


        ── YOUR LENS: EXECUTION & LOGISTICS ──
        Approach this as the planner who must actually CARRY OUT the task. Focus your \
        questions on the concrete logistics whose answers you'd need to start the work: \
        exact quantities and scale, who/what/where/when, the money and resources \
        required, and the practical constraints of getting it done. Ask the execution \
        details that would block or reshape a real plan if left unknown.
        """,
        """


        ── YOUR LENS: SCOPE & GOALS ──
        Approach this as the strategist who defines what SUCCESS looks like before any \
        work starts. Focus your questions on the user's underlying objective and \
        priorities: the outcome they actually want, who it is for, how big or ambitious \
        the effort is, what tradeoffs matter most, and where to focus first. Ask the \
        high-level scoping questions whose answers would most change WHICH plan is right.
        """,
        """


        ── YOUR LENS: DOMAIN EXPERT ──
        Approach this as a seasoned professional who specialises in exactly this kind of \
        task and has done it many times. Focus your questions on the specialised, \
        field-specific decision factors an expert always checks first but a novice would \
        overlook — the details particular to THIS domain (its typical categories, \
        requirements, common pitfalls, or context-specific facts) that determine the \
        right approach. Ask the expert-level questions that separate a knowledgeable \
        plan from a generic one.
        """,
    ]

    /// EXP-020: corpus-grounded selection over an over-generated candidate pool.
    /// Every prior SELECTION over the 3B's own samples failed because the selection
    /// SIGNAL was weak 3B judgment (self-rating exp002, pairwise exp012, frequency
    /// exp010) or a blunt heuristic (keyword coverage exp004, single-gold embedding
    /// gap exp009). Here the signal is EXTERNAL: how much a candidate resembles the
    /// questions Sonnet actually asks for the nearest corpus task types. Stage 1
    /// over-generates a DIVERSE pool by drawing the exp011 contrastive-RAG generator
    /// at several temperatures (so the task-specific TAIL questions exp010 identified
    /// actually land in the pool, not just the modal generic cluster). Stage 2 ranks
    /// every candidate by max embedding cosine to the Sonnet reference questions
    /// (retrieved from the 300+ `corpus/` bank) and greedily selects 7 with embedding
    /// redundancy suppression. The output questions are all 3B-generated fresh; the
    /// corpus is a RANKING prior only — never copied or templated. Falsifiable test:
    /// if the critical questions exist in the pool but get mis-ranked, this lifts
    /// coverage; if it plateaus, the critical questions are never generated (the wall
    /// is generation-side mode collapse, not ranking).
    private func ragCorpusSelect(_ input: String) async throws -> DiscoveryResult {
        let system = ragSystemPrompt(input) + Self.contrastLesson
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let temps = config.sampleTemps ?? [0.4, 0.7, 1.0]

        var candidates: [DiscoveryQuestion] = []
        var title = ""
        var summary = ""
        for (i, t) in temps.enumerated() {
            let session = LanguageModelSession(model: try resolveModel()) { system }
            let plan = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                                  options: config.options(temp: t, sampling: .modelDefault)).content
            if i == 0 { title = plan.title; summary = plan.summary }
            for q in plan.questions {
                candidates.append(DiscoveryQuestion(title: q.question, description: q.detail,
                                                    requiresExternalAction: q.requiresExternalAction))
            }
        }

        let references = CorpusBank.nearestSemantic(to: input, k: 3).flatMap { $0.questions }
        let selected = CorpusSelector.select(candidates: candidates, references: references, count: 7)
        return DiscoveryResult(taskTitle: title, taskDescription: summary, questions: selected)
    }

    /// EXP-018: in-schema chain-of-thought few-shot. The persistent coverage wall is
    /// that the 3B does not decide WHICH unknown is decision-critical — it defaults to
    /// generic catch-alls and drops the one slot that matters. Every prior config
    /// either emitted the 7 questions DIRECTLY (no explicit prioritisation step:
    /// exp003/011/014) or pushed the judgment into a SEPARATE FM pass (brainstorm→
    /// select exp001, plan→assumptions exp013, auditor exp005, tournament exp012) —
    /// the latter all compounded the 3B's weak judgment and lost. This is the untried
    /// middle path: a SINGLE call whose output SCHEMA forces the model to first commit
    /// to the 7 most decision-critical unknowns (short phrases), THEN write one natural
    /// question probing each, in order. Because guided generation fills fields in
    /// declared order, the leading `criticalUnknowns` list is in-schema CoT that
    /// conditions the subsequent questions — no extra weak-judgment FM pass. A worked
    /// reasoning demonstration (the unknowns for "Organize my garage") anchors what
    /// good critical-unknown identification looks like (classic CoT few-shot), atop the
    /// exp011 contrastive RAG base (current best).
    private func ragReasonedFewShot(_ input: String) async throws -> DiscoveryResult {
        let session = LanguageModelSession(model: try resolveModel()) { ragSystemPrompt(input) + Self.contrastLesson + Self.reasonedGuidance }
        let prompt = """
        Task the user entered: "\(input)"

        First identify the 7 most decision-critical unknowns for THIS task (short \
        phrases), then write exactly one clarifying question probing each, in the same \
        order.
        """
        let r = try await session.respond(to: prompt, generating: FMReasonedPlan.self,
                                          options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    /// EXP-018: appended after the contrastive lesson — a worked example of the
    /// reasoning step (identify decision-critical unknowns BEFORE phrasing questions),
    /// reusing the "Organize my garage" task so the unknowns line up with the STRONG
    /// set already shown above. Teaches the think-first format the schema enforces.
    static let reasonedGuidance = """


        ── THINK FIRST: name the decision-critical unknowns ──
        Before writing any questions, name the MOST decision-critical unknowns for the \
        task — the facts whose answers would most change the plan. For the example task \
        "Organize my garage", those unknowns are:
        main goal (storage vs workshop vs parking); garage size; how much stuff there \
        is; budget for storage systems; deadline; what to do with unwanted items; \
        whether anyone is helping.
        These are HIGH-LEVERAGE unknowns — never generic filler ("any preferences?") \
        and never a fact the task already states. Each then becomes exactly ONE natural \
        question, in the same order.

        Do this for the user's task: first list its 7 decision-critical unknowns as \
        short phrases, then write one question probing each.
        """

    /// EXP-023: scoped starting-point critique. Every prior 2nd-pass config lost
    /// because it ran a GENERAL audit (exp005 delete-given/delete-low-value/split-
    /// compound/fill-from-a-7-item-checklist; exp017 detect-and-refill all wasted
    /// slots) — a broad rewrite that compounds the 3B's weak judgment across many
    /// independent decisions and mangles strong slots. The rules' guidance for a
    /// SMARTER multi-FM pass is to "scope a critique to ONE named failure mode, not
    /// a general audit." The single dominant recurring miss across the dev set is
    /// the same one: the model ASSUMES the user's STARTING POINT and never asks it —
    /// trip (departure city), resume (current role / existing resume), learn_guitar
    /// (current skill level), tax (residency/employment situation), buy_used_car
    /// (whether a specific car is already chosen), wedding (whether the venue is
    /// booked). This is one well-defined dimension, not a checklist. Stage 1 is the
    /// exp011 contrastive RAG draft (current best). Stage 2 is ONE call that judges
    /// ONLY this: does any of the 7 questions establish the user's starting point
    /// for THIS task? If YES, the draft is returned verbatim (no rewrite, no risk).
    /// If NO, the model names the single WEAKEST slot and writes ONE task-specific
    /// starting-point question; Swift swaps exactly that one slot (the other 6 stay
    /// verbatim, defended by a filler/near-dup re-check). At most one slot changes —
    /// the minimal-surface 2nd pass, attacking the one gap that recurs everywhere.
    private func ragStartingPointCritique(_ input: String) async throws -> DiscoveryResult {
        // Stage 1: contrastive RAG draft (= exp011, the current best base).
        let draftSession = LanguageModelSession(model: try resolveModel()) { ragSystemPrompt(input) + Self.contrastLesson }
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let plan = try await draftSession.respond(
            to: prompt, generating: FMDiscoveryPlan.self,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
        ).content

        var questions = plan.questions.map {
            DiscoveryQuestion(title: $0.question, description: $0.detail, requiresExternalAction: $0.requiresExternalAction)
        }
        let titles = questions.map { $0.title }
        let numbered = titles.enumerated().map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        // Stage 2: ONE scoped critique — starting-point coverage ONLY.
        let critiqueSystem = """
        You are reviewing a set of 7 clarifying questions a coach will ask BEFORE \
        planning the user's task. Focus on ONE thing only: the user's STARTING POINT.

        Almost every plan depends on where the user is starting FROM — their current \
        situation, what they already have or have done, or the concrete thing they are \
        starting with. Examples: for a trip, the city they are departing from; for a \
        resume, their current role and whether a resume already exists; for learning an \
        instrument, their current skill level; for buying something used, whether they \
        have already picked a specific one; for an event, whether the venue is booked.

        Read the 7 draft questions. Decide: do ANY of them establish the user's \
        STARTING POINT for THIS task?
        • If YES, set startingPointCovered = true (everything else is ignored).
        • If NO, set startingPointCovered = false, give the 1-based position of the \
          single WEAKEST question (the most generic, premature, or least \
          decision-critical one), and write ONE natural, task-specific question that \
          establishes the starting point — 5-12 words, asking exactly ONE thing, \
          addressed to the user, never generic filler, never restating a fact the \
          task already gives.

        Judge ONLY starting-point coverage. Do not comment on anything else.
        """
        let critiqueSession = LanguageModelSession(model: try resolveModel()) { critiqueSystem }
        let critiquePrompt = """
        Task the user entered: "\(input)"

        Draft questions:
        \(numbered)

        Does any draft question establish the user's starting point for this task?
        """
        let fix = try await critiqueSession.respond(
            to: critiquePrompt, generating: FMStartingPointFix.self,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
        ).content

        // Covered → return the draft verbatim (no rewrite, no risk).
        if fix.startingPointCovered {
            return DiscoveryResult(taskTitle: plan.title, taskDescription: plan.summary, questions: questions)
        }

        // Not covered → swap exactly the named weakest slot, with defensive guards.
        let idx = fix.weakestIndex - 1
        let cand = fix.startingPointQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard questions.indices.contains(idx), !cand.isEmpty, !FillerDetector.isFiller(cand) else {
            return DiscoveryResult(taskTitle: plan.title, taskDescription: plan.summary, questions: questions)
        }
        // Don't introduce a near-duplicate of any slot we are KEEPING.
        let kept = titles.enumerated().filter { $0.offset != idx }.map { $0.element }
        if kept.contains(where: { FillerDetector.jaccard(cand, $0) >= 0.5 }) {
            return DiscoveryResult(taskTitle: plan.title, taskDescription: plan.summary, questions: questions)
        }
        questions[idx] = DiscoveryQuestion(title: cand, description: "",
                                           requiresExternalAction: fix.requiresExternalAction)
        return DiscoveryResult(taskTitle: plan.title, taskDescription: plan.summary, questions: questions)
    }

    /// EXP-017: filler/redundancy detect-and-repair on the contrastive RAG draft.
    /// The judge's recurring complaint on the best config (exp011) is that redundant
    /// near-duplicate clusters and vague catch-all questions "crowd out more valuable
    /// questions" — i.e. the model often KNOWS task-specific unknowns but WASTES slots
    /// on overlap/filler, so the critical ones never make the cut. Prior repair tries
    /// failed for opposite reasons: exp005's FM auditor injected a UNIVERSAL checklist
    /// (budget/timeline everywhere) and exp009's embedding gap-finder picked the wrong
    /// gold question and re-duplicated. Here detection is purely DETERMINISTIC
    /// (filler-phrase patterns + content-word Jaccard near-dupes), so it targets
    /// exactly the wasted slots; we then make ONE scoped call that refills ONLY those
    /// slots with concrete, task-specific questions — shown the kept set, told to be
    /// specific, given NO universal-dimension list. Strong slots are returned verbatim
    /// (atomicity/naturalness preserved); a defensive re-check keeps the original draft
    /// question for any refill that is itself filler or duplicates a kept slot.
    private func ragFillerRepair(_ input: String) async throws -> DiscoveryResult {
        // Stage 1: contrastive RAG draft (= exp011, the current best base).
        let draftSession = LanguageModelSession(model: try resolveModel()) { ragSystemPrompt(input) + Self.contrastLesson }
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let plan = try await draftSession.respond(
            to: prompt, generating: FMDiscoveryPlan.self,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
        ).content

        var questions = plan.questions.map {
            DiscoveryQuestion(title: $0.question, description: $0.detail, requiresExternalAction: $0.requiresExternalAction)
        }
        let titles = questions.map { $0.title }
        let weak = FillerDetector.weakIndices(titles)
        guard !weak.isEmpty else {
            return DiscoveryResult(taskTitle: plan.title, taskDescription: plan.summary, questions: questions)
        }

        // Stage 2: ONE scoped call to refill only the wasted slots.
        let kept = titles.enumerated().filter { !weak.contains($0.offset) }.map { $0.element }
        let keptList = kept.enumerated().map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let n = weak.count
        let plural = n == 1 ? "" : "s"
        let repairSystem = """
        You are a personal task coach refining a set of clarifying questions for the \
        user's task. The set already has \(kept.count) strong questions (below). It is \
        MISSING \(n) sharp, task-specific question\(plural): the slots being replaced \
        were generic catch-alls or near-duplicates that wasted space.

        ── STRONG QUESTIONS ALREADY IN THE SET (do NOT repeat or overlap with these) ──
        \(keptList)

        ── YOUR JOB ──
        Write exactly \(n) NEW clarifying question\(plural), each probing a CONCRETE, \
        decision-critical specific of THIS task that none of the strong questions above \
        cover — for example a concrete quantity or scale, who it is for, where or when, \
        budget if money matters here, or the user's current situation / starting point. \
        Be concrete and specific to THIS task. NEVER write a generic catch-all \
        ("any other...", "anything else?", "any specific preferences?"). Each asks exactly \
        ONE thing, 5-12 words, addressed to the user ("you"/"your"), no emojis.
        """
        let repairSession = LanguageModelSession(model: try resolveModel()) { repairSystem }
        let refilled = try await repairSession.respond(
            to: "Task the user entered: \"\(input)\"\n\nWrite the \(n) new clarifying question\(plural).",
            generating: FMQuestionList.self,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
        ).content.questions

        // Fill wasted slots in order. Defensive: skip any refill that is itself filler
        // or duplicates a kept slot — leave the original draft question in that case.
        for (k, idx) in weak.enumerated() where k < refilled.count {
            let cand = refilled[k].question
            if FillerDetector.isFiller(cand) { continue }
            if kept.contains(where: { FillerDetector.jaccard(cand, $0) >= 0.5 }) { continue }
            questions[idx] = DiscoveryQuestion(title: cand, description: "",
                                               requiresExternalAction: refilled[k].requiresExternalAction)
        }
        return DiscoveryResult(taskTitle: plan.title, taskDescription: plan.summary, questions: questions)
    }

    /// EXP-016: sequential, one-question-at-a-time generation. Every prior config
    /// generated all 7 questions in a SINGLE guided emission (one flat array, a
    /// scored pool, or 7 typed slots), and they all plateau at coverage 3. exp010's
    /// key datum: the 3B's MODAL output is the generic catch-all, and the sharp
    /// task-specific decision-critical unknowns appear only in the TAIL of its
    /// sampling distribution. Generating 7 at once lets the model collapse onto its
    /// modal cluster (7 generic-ish slots). This topology instead generates ONE
    /// question per call, each call shown the questions already chosen and told to
    /// probe a DIFFERENT unknown than all of them. Forced novelty pushes each
    /// successive emission OFF the modal cluster into the tail where the
    /// task-specific unknowns live — a different generation DYNAMIC than asking the
    /// 3B to select/rank/critique/aggregate (the absolute judgment it lacks). The
    /// exp003 RAG few-shot system prompt grounds phrasing/atomicity per step, and
    /// the explicit do-not-repeat list structurally maximises non-redundancy.
    private func ragSequential(_ input: String) async throws -> DiscoveryResult {
        let system = ragSystemPrompt(input)

        // Task framing (title + one-sentence summary) in one small call.
        let framingSession = LanguageModelSession(model: try resolveModel()) { system }
        let framing = try await framingSession.respond(
            to: "Task the user entered: \"\(input)\"\n\nRestate this task as a short specific title (4-9 words) and a one-sentence summary.",
            generating: FMTaskFraming.self,
            options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
        ).content

        // Generate 7 questions, one per call, each conditioned on the prior set.
        var asked: [DiscoveryQuestion] = []
        for i in 0..<7 {
            let priorBlock: String
            if asked.isEmpty {
                priorBlock = "No questions have been asked yet. Ask the SINGLE most decision-critical unknown for this task."
            } else {
                let list = asked.enumerated().map { "  \($0.offset + 1). \($0.element.title)" }.joined(separator: "\n")
                priorBlock = """
                Questions already asked (do NOT repeat or overlap with any of these):
                \(list)

                Ask the SINGLE next most decision-critical unknown that none of the \
                above already covers. It must probe a genuinely DIFFERENT unknown.
                """
            }
            let prompt = """
            Task the user entered: "\(input)"

            \(priorBlock)

            Write exactly ONE clarifying question (question \(i + 1) of 7). It must be \
            specific to THIS task, ask exactly one thing, and not restate a fact the \
            task already gives.
            """
            let session = LanguageModelSession(model: try resolveModel()) { system }
            let q = try await session.respond(
                to: prompt, generating: FMSingleQuestion.self,
                options: config.options(temp: config.selectTemp, sampling: config.selectSampling)
            ).content
            asked.append(DiscoveryQuestion(title: q.question, description: "",
                                           requiresExternalAction: q.requiresExternalAction))
        }

        return DiscoveryResult(taskTitle: framing.title, taskDescription: framing.summary, questions: asked)
    }

    /// EXP-015: structural coverage enforcement via a typed guided SCHEMA. Every
    /// coverage attempt to date has either SHOWN the 3B which unknowns matter
    /// (in-context demos exp003/007/008/014, checklists exp005/006) or asked it to
    /// SELECT/RANK/CRITIQUE its own samples (exp004/010/012) — all plateau at
    /// coverage 3 because the 3B can't decide which unknown is decision-critical and
    /// freely DROPS the critical slot for a generic one. This is a NEW lever: instead
    /// of one flat `questions: [FMQuestion]` array (used by every prior config), the
    /// output schema has SEVEN distinctly-named, individually-`@Guide`d slots, one per
    /// universal high-value planning dimension the judge keeps flagging as MISSING
    /// (goal, scope/scale, who-for, budget/resources, timeline, current-state,
    /// constraints/avoid). Guided generation ENFORCES every named field, so the model
    /// structurally cannot omit the budget/who-for/timeline/current-state slots — it
    /// must produce a task-specific question for each. Coverage breadth becomes a
    /// property of the SCHEMA, not of ranking judgment the 3B lacks. Each slot's guide
    /// allows graceful adaptation when a dimension is moot (ask the closest applicable
    /// unknown), and the exp011 RAG+contrastive system prompt anchors phrasing/atomicity.
    private func ragDimensionalSchema(_ input: String) async throws -> DiscoveryResult {
        let session = LanguageModelSession(model: try resolveModel()) { ragSystemPrompt(input) + Self.contrastLesson + Self.dimensionalGuidance }
        let prompt = """
        Task the user entered: "\(input)"

        Generate clarifying questions by filling each labelled slot below with ONE \
        natural question specific to THIS task. Each slot targets a different \
        decision-critical unknown so the set covers the task broadly.
        """
        let r = try await session.respond(to: prompt, generating: FMDimensionalPlan.self,
                                          options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    /// Extra guidance appended to the system prompt for EXP-015's dimensional schema:
    /// names the 7 slots and tells the model how to gracefully adapt a moot dimension.
    static let dimensionalGuidance = """


        ── DIMENSION SLOTS (fill each with ONE question) ──
        Your output has seven labelled slots. Fill each with a single natural question \
        that probes that slot's decision-critical unknown FOR THIS SPECIFIC TASK:
        1. GOAL — the user's specific goal, desired outcome, or what success looks like.
        2. SCOPE — the scope or scale: how much, how many, or which parts are involved.
        3. WHO-FOR — who the task is for or who else is involved (if it's solely for the \
           user, ask instead about their relevant experience or skill level).
        4. BUDGET — the budget or resources available (if money is clearly irrelevant to \
           this task, ask instead about the key material, tool, or resource it needs).
        5. TIMELINE — the deadline, target date, or how soon it must happen.
        6. CURRENT-STATE — what already exists, what they have done so far, or their \
           starting point (e.g. do they already own/have the core thing involved).
        7. CONSTRAINTS — preferences, requirements, or things they specifically want to avoid.
        Adapt each to be genuinely useful for THIS task; never ask about a fact the task \
        statement already gives. Keep every question to ONE thing, 5-15 words, natural.
        """

    /// EXP-014: corpus-backed RAG few-shot. The coverage wall has held against every
    /// in-context retrieval variant — but all of them retrieved from only the 12
    /// generic hardcoded `GoldExemplars`, where the "nearest" demo is frequently
    /// off-domain (exp007's lesson: semantically-nearest≠instructive WHEN the pool is
    /// tiny and generic). This swaps the retrieval BANK (not the mechanism) for the
    /// 100+ `corpus/` Sonnet sets — a far richer, more specific bank the rules
    /// explicitly encourage using — so semantic retrieval can surface genuinely
    /// close-DOMAIN demonstrations (baby-shower→dinner_party, 401k→retirement,
    /// visa/Portugal→trip_paris) that model the right decision-critical unknowns for
    /// THIS task type. k=3 (vs exp003's 2) because the richer bank has more close
    /// matches to draw coverage signal from. Keeps exp011's contrastive lesson (the
    /// current-best base) to suppress the off-task/compound/filler anti-patterns.
    private func ragCorpusFewShot(_ input: String) async throws -> DiscoveryResult {
        let examples = CorpusBank.nearestSemantic(to: input, k: 3)
        let session = LanguageModelSession(model: try resolveModel()) { ragSystemPrompt(input, examples: examples) + Self.contrastLesson }
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let r = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                          options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
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
            let session = LanguageModelSession(model: try resolveModel()) { system }
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
        let session = LanguageModelSession(model: try resolveModel()) { Prompts.setComparator }
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
        let session = LanguageModelSession(model: try resolveModel()) { ragSystemPrompt(input) + Self.contrastLesson }
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
            let session = LanguageModelSession(model: try resolveModel()) { system }
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
            let session = LanguageModelSession(model: try resolveModel()) { system }
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
        let session = LanguageModelSession(model: try resolveModel()) { Prompts.singleShot }
        let prompt = """
        Task the user entered: "\(input)"

        Generate exactly 7 clarifying questions. Each must ask about ONE thing only — never combine two asks with "and" or "or".
        """
        let r = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                          options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    private func brainstormSelect(_ input: String) async throws -> DiscoveryResult {
        let bs = LanguageModelSession(model: try resolveModel()) { Prompts.brainstorm }
        let unknowns = try await bs.respond(
            to: "The user wants to: \"\(input)\"\n\nList the candidate unknowns you'd want to learn before planning this. Do not ask about anything the task already states.",
            generating: FMUnknowns.self,
            options: config.options(temp: config.brainstormTemp, sampling: config.brainstormSampling)
        ).content.unknowns

        let sel = LanguageModelSession(model: try resolveModel()) { Prompts.select }
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
        let session = LanguageModelSession(model: try resolveModel()) { ragSystemPrompt(input) + scaffold }
        let prompt = "Task the user entered: \"\(input)\"\n\nGenerate exactly 7 clarifying questions."
        let r = try await session.respond(to: prompt, generating: FMDiscoveryPlan.self,
                                          options: config.options(temp: config.selectTemp, sampling: config.selectSampling))
        return r.content.toContract()
    }

    private func ragFewShot(_ input: String) async throws -> DiscoveryResult {
        let session = LanguageModelSession(model: try resolveModel()) { ragSystemPrompt(input) }
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
        let planner = LanguageModelSession(model: try resolveModel()) { Prompts.planAssumptions }
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
        let session = LanguageModelSession(model: try resolveModel()) { ragSystemPrompt(input) + scaffold }
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
        let session = LanguageModelSession(model: try resolveModel()) { ragSystemPrompt(input, examples: examples) }
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
        let session = LanguageModelSession(model: try resolveModel()) { system }
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
        let draftSession = LanguageModelSession(model: try resolveModel()) { ragSystemPrompt(input, examples: exemplars) }
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
        let repairSession = LanguageModelSession(model: try resolveModel()) { repairSystem }
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
            let session = LanguageModelSession(model: try resolveModel()) { system }
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
        let draftSession = LanguageModelSession(model: try resolveModel()) { ragSystemPrompt(input) }
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
        let editorSession = LanguageModelSession(model: try resolveModel()) { editorSystem }
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
        let session = LanguageModelSession(model: try resolveModel()) { Prompts.overGenerate }
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

/// EXP-018: a plan with in-schema chain-of-thought. The model fills
/// `criticalUnknowns` FIRST (guided generation emits fields in declared order), so
/// committing to which 7 unknowns matter conditions the questions it then writes.
@Generable
struct FMReasonedPlan {
    @Guide(description: "The user's task restated as a short specific title, 4-9 words, in their own words. Never a generic label like 'Clarifying Questions'.")
    var title: String
    @Guide(description: "One plain sentence summarising the task.")
    var summary: String
    @Guide(description: "The 7 MOST decision-critical unknowns for THIS task, each a short phrase (2-5 words) naming a fact whose answer would most change the plan (e.g. 'departure city', 'trip budget', 'who is travelling'). Specific to this task; never generic filler; never a fact the task already states.", .count(7))
    var criticalUnknowns: [String]
    @Guide(description: "Exactly 7 clarifying questions — one natural question probing each decision-critical unknown above, in the SAME order.", .count(7))
    var questions: [FMQuestion]

    func toContract() -> DiscoveryResult {
        DiscoveryResult(taskTitle: title, taskDescription: summary,
                        questions: questions.map { DiscoveryQuestion(title: $0.question, description: $0.detail, requiresExternalAction: $0.requiresExternalAction) })
    }
}

/// EXP-025: a plan with an in-schema GIVENS-extraction step. The model fills
/// `providedFacts` FIRST (guided generation emits fields in declared order) — an
/// easy reading task — so it commits to what the task already states before
/// writing questions, which must then avoid re-asking any given.
@Generable
struct FMGivensPlan {
    @Guide(description: "The user's task restated as a short specific title, 4-9 words, in their own words. Never a generic label like 'Clarifying Questions'.")
    var title: String
    @Guide(description: "One plain sentence summarising the task.")
    var summary: String
    @Guide(description: "The concrete facts the task statement ALREADY states — each a short phrase naming something the user has already told you, so you must NOT ask about it (e.g. 'destination is Paris', '8 guests', 'budget under $10k', 'instrument is guitar'). List ONLY facts actually present in the task text; if the task is very short, this may be just one or two facts.")
    var providedFacts: [String]
    @Guide(description: "Exactly 7 clarifying questions, each probing a genuine UNKNOWN. NEVER ask about, restate, or re-confirm any fact listed in providedFacts. Each is a complete question, 5-15 words, asking exactly ONE thing, addressed to the user.", .count(7))
    var questions: [FMQuestion]

    func toContract() -> DiscoveryResult {
        DiscoveryResult(taskTitle: title, taskDescription: summary,
                        questions: questions.map { DiscoveryQuestion(title: $0.question, description: $0.detail, requiresExternalAction: $0.requiresExternalAction) })
    }
}

/// EXP-022: a plan whose 7 slots each INTERLEAVE a decision-impact rationale
/// before the question. Because guided generation emits fields in declared order,
/// the model commits to "answering this changes <decision>" immediately before
/// phrasing each question — a per-slot CoT gate (vs exp018's batch-leading list).
/// The rationales are discarded; only the questions reach the contract.
@Generable
struct FMJustifiedQuestion {
    @Guide(description: "In 6-14 words, the CONCRETE decision in the plan that answering the question would change for THIS task (e.g. 'decides which city to book flights from'). Must name a real fork in the plan — never vague ('to understand preferences').")
    var rationale: String
    @Guide(description: "One complete clarifying question for the decision named above, 5-12 words, asking exactly ONE thing. Never combine two asks with 'and' or 'or'. Addressed to the user ('you'/'your'). Never restate a fact the task already gives.")
    var question: String
    @Guide(description: "True only if answering requires a real-world action outside the app (call, email, visit). False for in-app data entry.")
    var requiresExternalAction: Bool
}

@Generable
struct FMJustifiedPlan {
    @Guide(description: "The user's task restated as a short specific title, 4-9 words, in their own words. Never a generic label like 'Clarifying Questions'.")
    var title: String
    @Guide(description: "One plain sentence summarising the task.")
    var summary: String
    @Guide(description: "Exactly 7 slots, each a decision-impact rationale paired with one clarifying question probing that decision.", .count(7))
    var questions: [FMJustifiedQuestion]

    func toContract() -> DiscoveryResult {
        DiscoveryResult(taskTitle: title, taskDescription: summary,
                        questions: questions.map { DiscoveryQuestion(title: $0.question, description: "", requiresExternalAction: $0.requiresExternalAction) })
    }
}

/// EXP-015: a typed plan whose seven question slots each target a distinct
/// decision-critical planning dimension. Guided generation enforces every named
/// field, so coverage breadth is structural — the model cannot drop a slot.
@Generable
struct FMDimensionalPlan {
    @Guide(description: "The user's task restated as a short specific title, 4-9 words, in their own words. Never a generic label like 'Clarifying Questions'.")
    var title: String
    @Guide(description: "One plain sentence summarising the task.")
    var summary: String
    @Guide(description: "Question about the user's specific GOAL, desired outcome, or what success looks like for this task.")
    var goalQuestion: FMQuestion
    @Guide(description: "Question about the SCOPE or SCALE: how much, how many, or which parts are involved.")
    var scopeQuestion: FMQuestion
    @Guide(description: "Question about WHO the task is for or who else is involved. If it is solely for the user, ask about their relevant experience or skill level instead.")
    var whoForQuestion: FMQuestion
    @Guide(description: "Question about BUDGET or resources available. If money is clearly irrelevant, ask about the key material, tool, or resource the task needs instead.")
    var budgetQuestion: FMQuestion
    @Guide(description: "Question about the TIMELINE: deadline, target date, or how soon this must happen.")
    var timelineQuestion: FMQuestion
    @Guide(description: "Question about the CURRENT STATE: what already exists, progress so far, or whether they already own/have the core thing involved.")
    var currentStateQuestion: FMQuestion
    @Guide(description: "Question about CONSTRAINTS: preferences, requirements, or things they specifically want to avoid.")
    var constraintsQuestion: FMQuestion

    func toContract() -> DiscoveryResult {
        let qs = [goalQuestion, scopeQuestion, whoForQuestion, budgetQuestion,
                  timelineQuestion, currentStateQuestion, constraintsQuestion]
        return DiscoveryResult(taskTitle: title, taskDescription: summary,
                               questions: qs.map { DiscoveryQuestion(title: $0.question, description: $0.detail, requiresExternalAction: $0.requiresExternalAction) })
    }
}

/// EXP-023: the scoped starting-point critique verdict. The model first commits to
/// a single boolean (is the starting point covered?), then — only if not — names the
/// weakest slot and writes one replacement. Guided generation emits fields in order,
/// so the boolean gates whether the replacement is even considered downstream.
@Generable
struct FMStartingPointFix {
    @Guide(description: "True if at least one of the 7 draft questions already establishes the user's STARTING POINT for THIS task — where/what they are starting from, what they already have or have done, or their current situation. False if none of them do.")
    var startingPointCovered: Bool
    @Guide(description: "The 1-based position (1 to 7) of the SINGLE weakest draft question — the most generic, premature, or least decision-critical one. Only used when startingPointCovered is false.")
    var weakestIndex: Int
    @Guide(description: "One natural clarifying question, 5-12 words, asking exactly ONE thing, that establishes the user's STARTING POINT for THIS task. Specific to this task; never generic filler; never restate a fact the task already gives. Only used when startingPointCovered is false.")
    var startingPointQuestion: String
    @Guide(description: "True only if answering the new question requires a real-world action outside the app (call, email, visit). False for in-app data entry.")
    var requiresExternalAction: Bool
}

/// EXP-017: a variable-length list of refill questions (the wasted-slot count is
/// only known at runtime, so the count cannot be a static `@Guide` constraint).
@Generable
struct FMQuestionList {
    @Guide(description: "The requested new clarifying questions, each asking exactly one thing, specific to the task.")
    var questions: [FMSingleQuestion]
}

@Generable
struct FMSingleQuestion {
    @Guide(description: "One complete clarifying question, 5-12 words, asking exactly ONE thing. Never combine two asks with 'and' or 'or'. Addressed to the user ('you'/'your').")
    var question: String
    @Guide(description: "True only if answering requires a real-world action outside the app (call, email, visit). False for in-app data entry.")
    var requiresExternalAction: Bool
}

/// EXP-016: task framing (title + summary) for the sequential topology, which
/// emits questions one at a time and so needs a separate small framing emission.
@Generable
struct FMTaskFraming {
    @Guide(description: "The user's task restated as a short specific title, 4-9 words, in their own words. Never a generic label like 'Clarifying Questions'.")
    var title: String
    @Guide(description: "One plain sentence summarising the task.")
    var summary: String
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

/// EXP-030: a set of divergent competing scenarios — the materialised solution space
/// the questions must discriminate between (Lever C, solution-space information gain).
@Generable
struct FMScenarios {
    @Guide(description: "4 DIVERGENT, concrete, plausible interpretations of who this user is and what they specifically want for the task. Each is ONE vivid sentence committing to SPECIFIC, different answers (different goal, scale, budget, audience, starting point, or constraints) so the four together span the realistic range. They must genuinely DISAGREE on the decision-critical unknowns; never vague or interchangeable.", .count(4))
    var scenarios: [String]
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
