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
    /// The verbatim user input, rewritten with first-occurrence wikilinks. Nil when the note
    /// had no original-input block to link.
    let linkedOriginalInput: String?
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
    /// in the new note's Related section. Each note may carry a `context` line (e.g. which
    /// other notes mention an entity) that helps spot co-occurrence.
    func discoverLinksForNote(
        note: (path: String, title: String, body: String, context: String),
        candidates: [(path: String, title: String, body: String, context: String)],
        newNoteIsEntity: Bool
    ) async throws -> NoteLinkSuggestions {
        func block(path: String, title: String, body: String, context: String) -> String {
            let contextLine = context.isEmpty ? "" : "\n\(context)"
            return """
            ---
            path: \(path)
            title: \(title)\(contextLine)
            ---
            \(body.prefix(800))
            """
        }

        let candidateList = candidates
            .map { block(path: $0.path, title: $0.title, body: $0.body, context: $0.context) }
            .joined(separator: "\n\n")

        let systemPrompt = newNoteIsEntity ? Self.entityLinkPrompt : Self.taskNoteLinkPrompt

        let closingQuestion = newNoteIsEntity
            ? "Which candidate entities belong in the same theme as the new entity?"
            : "Which candidates share a real, non-obvious connection with the new note?"

        let userMessage = """
        NEW NOTE:
        \(block(path: note.path, title: note.title, body: note.body, context: note.context))

        CANDIDATE NOTES:

        \(candidateList)

        \(closingQuestion)
        """

        return try await client.sendStructuredMessage(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            responseType: NoteLinkSuggestions.self,
            maxTokens: AppConstants.kbLinkDiscoveryMaxTokens,
            taskTitle: note.title
        )
    }

    /// Discovery prompt when the new note is an ENTITY — favours generous thematic clustering
    /// so each topic forms a richly interlinked sub-graph.
    private static let entityLinkPrompt = """
    You maintain the entity graph of a personal knowledge wiki.

    The new note is an ENTITY — an atomic concept note: a person, company, lab, product, place, role, idea, movement, or deadline. The candidates are other entities.

    YOUR GOAL: connect this entity to other entities in the SAME DOMAIN OR THEME, so each topic forms a richly interlinked cluster the user can navigate. Link generously WITHIN a theme:
    - a person or role and the organisations, fields, or other roles they belong to (e.g. "Technical Leaders" ↔ "Anthropic", "SSI", "AI Researchers", "Executives");
    - companies, labs, products, or accelerators in the same industry (e.g. "Anthropic" ↔ "OpenAI" ↔ "SSI" ↔ "Y Combinator");
    - concepts, methods, movements, or topics within the same discipline (e.g. "RLHF" ↔ "RLHR" ↔ "Human Agency").

    DO NOT link across unrelated domains. The wiki spans several worlds (AI industry, balcony renovation, German tax filing, a cycling trip, …). An AI-industry entity has nothing to do with a balcony-furniture entity or a tax-form entity. Stay strictly within the new entity's theme.

    Some entities carry a `mentioned in:` line listing the notes that reference them. Entities mentioned by the same notes are an especially strong link — but a shared theme alone is enough; co-occurrence is a bonus, not a requirement.

    OUTPUT: a list of `links` — the candidate entities that belong in the new entity's "Related" section. Each link: { targetPath, targetTitle, reason }.

    RULES:
    - targetPath MUST be the EXACT verbatim `path` string of a candidate from the list. Never abbreviate, rename, or invent a path.
    - Only suggest candidates from the list. Never suggest the new note itself.
    - Aim for 3-8 links when the entity sits in a populated theme; return fewer (or none) only when its theme genuinely has few other entities.
    - Use `reason` to name the shared theme in one sentence — an internal hint, not shown to the user.
    """

    /// Discovery prompt when the new note is a TASK note — favours precise, non-obvious links.
    private static let taskNoteLinkPrompt = """
    You maintain the cross-links of a personal knowledge wiki.

    INPUT:
    - ONE new note that was just created: its `path`, `title`, and full `body`.
    - A list of CANDIDATE notes, each with a `path`, `title`, and `body`.
    - Some notes also carry a `mentioned in:` line listing the other notes that reference them. When the new note and a candidate are mentioned by the same notes, that is a STRONG signal they belong together.

    IMPORTANT — the candidate list has already been pruned. Notes that are ALREADY connected to the new note (its task-folder siblings, entities it already links to, notes already in its Related section) were removed on purpose. Every candidate is a note the new note is NOT yet connected to.

    YOUR GOAL: surface the NON-OBVIOUS connections. Link the new note to candidates that share a genuine conceptual thread — the same underlying theme or argument, a decision in one project that informs another, the same person / product / place / idea resurfacing across the user's work.

    OUTPUT: a list of `links` — the candidates that belong in the new note's "Related" section. Each link: { targetPath, targetTitle, reason }.

    STRICT RULES:
    - targetPath MUST be the EXACT verbatim `path` string of a candidate from the list — including the "notes/<folder>/" prefix. Never abbreviate, rename, or invent a path.
    - Only suggest candidates from the list. Never suggest the new note itself.
    - Quality over quantity. Return 0-5 links. An empty list is a fine answer when nothing is genuinely related — do NOT pad.
    - Do NOT link on weak or generic overlap (both notes mention "decisions", both involve "writing"). Require a concrete shared entity, a specific shared idea, or genuine co-occurrence.

    Use `reason` to name, in one sentence, the specific shared thread — this is an internal hint, not shown to the user.
    """

    private let entityExtractionPrompt = """
    You analyse a wiki note and identify high-signal entities to extract into atomic sub-notes.

    INPUT:
    - The note's title and body.
    - Optionally, the ORIGINAL USER INPUT — the user's own verbatim words for this sub-task.
    - A list of entities that already exist in the wiki: { slug, title }.

    OUTPUT:
    - `linkedBody`: the note body rewritten as Obsidian-style wikilinks around entity mentions. For every entity (existing OR new), wrap its FIRST occurrence as [[<slug>.md|<Display Name>]]. Leave subsequent occurrences as plain text. Preserve all other text verbatim — same line breaks, same paragraphs, same punctuation.
    - `linkedOriginalInput`: ONLY if ORIGINAL USER INPUT was given, return it rewritten with first-occurrence wikilinks the SAME way. Treat it as its own independent block: link an entity's first occurrence within this block even if that entity was already linked in the body. Preserve the user's exact wording, line breaks, and punctuation otherwise. Omit this field entirely when no original input was provided.
    - `newEntities`: entities that are NOT in the existing list, each with { slug, displayName, body }. Body: 1-2 short sentences distilling the durable concept, written first person, no emojis, no filler.

    RULES:
    - Prefer linking to EXISTING entities. Only create a new entity when the mention is high-signal AND not already covered.
    - High-signal = a proper noun, named concept/movement, specific company/person/place, calendar date that anchors a deadline, or domain-specific term. SKIP generic verbs, adjectives, and common nouns.
    - The ORIGINAL USER INPUT is a prime entity source — proper nouns the user typed themselves are high-signal. Mine entities from it as thoroughly as from the body, even concepts the body's paraphrase dropped.
    - Slug format: lowercase ASCII, hyphenated separator, alphanumerics only, max 48 chars. Examples: "tada-app", "human-agency", "openai", "june-1-2026".
    - For an existing entity, use its existing slug verbatim — do not invent a new variant.
    - Never invent entities the input doesn't mention.
    - Aim for 3-10 entities per note; quality over quantity.
    - The new entity's `body` should NOT itself contain wikilinks. Entity bodies are leaf nodes.
    """

    func extractEntitiesAndLink(
        noteTitle: String,
        noteBody: String,
        originalInput: String? = nil,
        existingEntities: [ExistingEntityRef],
        phase: APIRequestPhase = .knowledge
    ) async throws -> EntityExtractionResult {
        let existingList = existingEntities.isEmpty
            ? "(none yet)"
            : existingEntities.map { "- slug: \($0.slug) | title: \($0.title)" }.joined(separator: "\n")

        let trimmedInput = originalInput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let originalSection = trimmedInput.isEmpty
            ? ""
            : "\n\nORIGINAL USER INPUT:\n\(trimmedInput)"
        let closingInstruction = trimmedInput.isEmpty
            ? "Rewrite the body with first-occurrence wikilinks and emit any new high-signal entities."
            : "Rewrite both the body and the original user input with first-occurrence wikilinks, and emit any new high-signal entities found in either."

        let userMessage = """
        NOTE TITLE: \(noteTitle)

        NOTE BODY:
        \(noteBody)\(originalSection)

        EXISTING ENTITIES:
        \(existingList)

        \(closingInstruction)
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
