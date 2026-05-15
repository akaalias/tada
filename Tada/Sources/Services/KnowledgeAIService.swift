import Foundation

struct GeneratedKnowledgeNote: Codable {
    let title: String
    let body: String
}

struct NoteLinkSuggestions: Codable {
    let links: [SuggestedRelatedNote]
}

struct SuggestedRelatedNote: Codable {
    let targetPath: String
    let targetTitle: String
    let reason: String
}

struct ExtractedEntity: Codable {
    let slug: String
    let displayName: String
    let body: String
}

struct EntityExtractionResult: Codable {
    let linkedBody: String
    let newEntities: [ExtractedEntity]
}

struct ExistingEntityRef {
    let slug: String
    let title: String
}

actor KnowledgeAIService {
    private let client: ClaudeAPIClient

    private let subtaskPrompt = """
    You distill a SINGLE completed sub-task into ONE atomic markdown note for a personal wiki.

    INPUT: the parent task's title, the sub-task that was completed (its title is usually a question or a step), and the user's response.

    OUTPUT: exactly one note with:
    - title: short noun phrase (3-8 words), match-on-search friendly. Reflects the durable insight, NOT the question.
    - body: 1-3 short paragraphs of concise markdown. First person.

    RULES:
    - Capture concrete details from the user's answer (names, numbers, dates, places, preferences). Don't restate the question.
    - If the response is trivially "Yes/No" or empty, still produce a useful note about what was confirmed/denied and why it matters in context.
    - No emojis. No filler. Tight.
    """

    private let taskOverviewPrompt = """
    You distill a fully completed task into ONE atomic markdown note that serves as the entry's overview.

    INPUT: the task, every sub-task that was completed, and a brief view of how each was answered.

    OUTPUT: one note with:
    - title: short noun phrase (3-8 words) summarising the task as a whole.
    - body: 1-3 short paragraphs of concise markdown. First person. Synthesise the goal, the key decisions, and how the task concluded — do not regurgitate every sub-task; the per-sub-task notes already cover those.

    CROSS-REFERENCES (optional):
    If it's natural, reference per-sub-task notes by their on-disk filename using Obsidian wikilinks: [[02-some-slug.md|Some Title]]. The list of filenames is provided.

    No emojis.
    """

    init(apiKey: String) {
        self.client = ClaudeAPIClient(apiKey: apiKey, role: .knowledge, phase: .knowledge)
    }

    func generateSubtaskNote(
        taskTitle: String,
        subtaskTitle: String,
        subtaskDescription: String,
        response: String,
        attachedImage: Data? = nil,
        tableMarkdown: String? = nil,
        phase: APIRequestPhase
    ) async throws -> GeneratedKnowledgeNote {
        let imageHint = attachedImage == nil ? "" : "\nAn image of the user's sketch is attached — describe what it shows in concrete spatial/architectural terms in the note body.\n"
        let tableSection = tableMarkdown.map { "\n\nSTRUCTURED TABLE DATA:\n\($0)\n" } ?? ""

        let userMessage = """
        PARENT TASK: \(taskTitle)

        SUB-TASK: \(subtaskTitle)
        \(subtaskDescription.isEmpty ? "" : "Details: \(subtaskDescription)\n")
        USER RESPONSE: \(response)\(tableSection)\(imageHint)

        Produce exactly one atomic note distilling the durable insight from this sub-task.
        """

        return try await client.sendStructuredMessage(
            systemPrompt: subtaskPrompt,
            userMessage: userMessage,
            responseType: GeneratedKnowledgeNote.self,
            maxTokens: 1024,
            attachedImages: attachedImage.map { [$0] } ?? [],
            phase: phase,
            taskTitle: subtaskTitle
        )
    }

    /// Single-source cross-link discovery: given ONE new note and a list of CANDIDATE notes
    /// (everything not already structurally close to it), returns the candidates that belong
    /// in the new note's Related section.
    func discoverLinksForNote(
        note: (path: String, title: String, body: String),
        candidates: [(path: String, title: String, body: String)]
    ) async throws -> NoteLinkSuggestions {
        let candidateList = candidates.map { n in
            """
            ---
            path: \(n.path)
            title: \(n.title)
            ---
            \(n.body.prefix(800))
            """
        }.joined(separator: "\n\n")

        let systemPrompt = """
        You maintain the cross-links of a personal knowledge wiki.

        INPUT:
        - ONE new note that was just created: its `path`, `title`, and full `body`.
        - A list of CANDIDATE notes, each with a `path`, `title`, and `body`.

        IMPORTANT — the candidate list has already been pruned. Notes that are ALREADY connected to the new note (its task-folder siblings, entities it already links to, notes already in its Related section) were removed on purpose. Every candidate is a note the new note is NOT yet connected to.

        YOUR GOAL: surface the NON-OBVIOUS connections. Link the new note to candidates that share a genuine conceptual thread but live in a different task or context — the kind of link the user would not stumble on by browsing the same project. Think: the same underlying theme or argument, a decision in one project that informs another, the same person / product / place / idea resurfacing in unrelated work.

        OUTPUT: a list of `links` — the candidates that belong in the new note's "Related" section. Each link: { targetPath, targetTitle, reason }.

        STRICT RULES:
        - targetPath MUST be the EXACT verbatim `path` string of a candidate from the list — including the "notes/<folder>/" prefix. Never abbreviate, rename, or invent a path.
        - Only suggest candidates from the list. Never suggest the new note itself.
        - Quality over quantity. Return 0-4 links. An empty list is a perfectly good answer when nothing is genuinely related — do NOT pad.
        - Do NOT link on weak or generic overlap (both notes mention "decisions", both involve "writing"). Require a concrete shared entity or a specific shared idea.

        Use `reason` to name, in one sentence, the specific shared thread — this is an internal hint, not shown to the user.
        """

        let userMessage = """
        NEW NOTE:
        ---
        path: \(note.path)
        title: \(note.title)
        ---
        \(note.body)

        CANDIDATE NOTES:

        \(candidateList)

        Which candidates share a real, non-obvious connection with the new note?
        """

        return try await client.sendStructuredMessage(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            responseType: NoteLinkSuggestions.self,
            maxTokens: AppConstants.kbLinkDiscoveryMaxTokens
        )
    }

    private let entityExtractionPrompt = """
    You analyse a wiki note and identify high-signal entities to extract into atomic sub-notes.

    INPUT:
    - The note's title and body.
    - A list of entities that already exist in the wiki: { slug, title }.

    OUTPUT:
    - `linkedBody`: the note body rewritten as Obsidian-style wikilinks around entity mentions. For every entity (existing OR new), wrap its FIRST occurrence as [[<slug>.md|<Display Name>]]. Leave subsequent occurrences as plain text. Preserve all other text verbatim — same line breaks, same paragraphs, same punctuation.
    - `newEntities`: entities that are NOT in the existing list, each with { slug, displayName, body }. Body: 1-2 short sentences distilling the durable concept, written first person, no emojis, no filler.

    RULES:
    - Prefer linking to EXISTING entities. Only create a new entity when the mention is high-signal AND not already covered.
    - High-signal = a proper noun, named concept/movement, specific company/person/place, calendar date that anchors a deadline, or domain-specific term. SKIP generic verbs, adjectives, and common nouns.
    - Slug format: lowercase ASCII, hyphenated separator, alphanumerics only, max 48 chars. Examples: "tada-app", "human-agency", "openai", "june-1-2026".
    - For an existing entity, use its existing slug verbatim — do not invent a new variant.
    - Never invent entities the body doesn't mention.
    - Aim for 3-10 entities per note; quality over quantity.
    - The new entity's `body` should NOT itself contain wikilinks. Entity bodies are leaf nodes.
    """

    func extractEntitiesAndLink(
        noteTitle: String,
        noteBody: String,
        existingEntities: [ExistingEntityRef],
        phase: APIRequestPhase = .knowledge
    ) async throws -> EntityExtractionResult {
        let existingList = existingEntities.isEmpty
            ? "(none yet)"
            : existingEntities.map { "- slug: \($0.slug) | title: \($0.title)" }.joined(separator: "\n")

        let userMessage = """
        NOTE TITLE: \(noteTitle)

        NOTE BODY:
        \(noteBody)

        EXISTING ENTITIES:
        \(existingList)

        Rewrite the body with first-occurrence wikilinks and emit any new high-signal entities.
        """

        return try await client.sendStructuredMessage(
            systemPrompt: entityExtractionPrompt,
            userMessage: userMessage,
            responseType: EntityExtractionResult.self,
            maxTokens: 2048,
            phase: phase,
            taskTitle: noteTitle
        )
    }

    func generateTaskOverviewNote(
        taskTitle: String,
        originalInput: String,
        taskDescription: String,
        subtaskSummaries: [(title: String, response: String, filename: String)]
    ) async throws -> GeneratedKnowledgeNote {
        let formatted = subtaskSummaries.enumerated().map { idx, st in
            "\(idx + 1). [[\(st.filename)|\(st.title)]] — \(st.response)"
        }.joined(separator: "\n")

        let userMessage = """
        TASK TITLE: \(taskTitle)

        ORIGINAL REQUEST: \(originalInput)

        \(taskDescription.isEmpty ? "" : "TASK DESCRIPTION: \(taskDescription)\n")

        COMPLETED SUB-TASKS (with their on-disk filenames):
        \(formatted)

        Produce exactly one atomic overview note for this task.
        """

        return try await client.sendStructuredMessage(
            systemPrompt: taskOverviewPrompt,
            userMessage: userMessage,
            responseType: GeneratedKnowledgeNote.self,
            maxTokens: 1024,
            taskTitle: taskTitle
        )
    }
}
