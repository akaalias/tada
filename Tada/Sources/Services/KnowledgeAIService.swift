import Foundation

struct GeneratedKnowledgeNote: Codable {
    let title: String
    let body: String
}

struct DiscoveredCrossLinks: Codable {
    let pairs: [CrossLinkPair]
}

struct CrossLinkPair: Codable {
    let sourcePath: String
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
        self.client = ClaudeAPIClient(apiKey: apiKey, role: .knowledge)
    }

    func generateSubtaskNote(
        taskTitle: String,
        subtaskTitle: String,
        subtaskDescription: String,
        response: String,
        attachedImage: Data? = nil,
        tableMarkdown: String? = nil
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
            attachedImages: attachedImage.map { [$0] } ?? []
        )
    }

    func discoverCrossLinks(
        notes: [(path: String, title: String, body: String)]
    ) async throws -> DiscoveredCrossLinks {
        let formatted = notes.map { note in
            """
            ---
            path: \(note.path)
            title: \(note.title)
            ---
            \(note.body.prefix(1200))
            """
        }.joined(separator: "\n\n")

        let systemPrompt = """
        You analyse a personal knowledge wiki and suggest cross-links between related notes.

        INPUT: a list of notes. Each has a unique `path` (relative to the wiki root, e.g. "notes/<folder>/<file>.md"), a `title`, and a `body`.

        OUTPUT: a list of `pairs`. Each pair: { sourcePath, targetPath, targetTitle, reason }.

        STRICT RULES:
        - sourcePath and targetPath MUST be the EXACT verbatim strings from the input list — including the "notes/<folder>/" prefix. Do not abbreviate, rename, or invent paths.
        - Never link a note to itself.
        - Cross-links are directional: a pair {source, target} adds a link from source → target. If you want bidirectional, emit two pairs.

        WHAT TO LINK:
        - Notes from the SAME parent task folder are usually related — they describe one project. Always link them when there's a real semantic connection: the answer to one question informs another, a decision flows from a constraint, a budget feeds a shopping list, etc.
        - Notes across DIFFERENT task folders should also be linked when they share a concrete entity (same person, product, place, deadline, decision).
        - Aim for 1-5 outgoing links per note. Don't blanket-link everything; pick the most useful connections.

        Use `reason` to justify in one sentence why the link is useful — this is an internal hint, not shown to the user.
        """

        let userMessage = """
        Here are the notes:

        \(formatted)

        Identify cross-link opportunities between them.
        """

        return try await client.sendStructuredMessage(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            responseType: DiscoveredCrossLinks.self,
            maxTokens: 8192
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
        existingEntities: [ExistingEntityRef]
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
            maxTokens: 2048
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
            maxTokens: 1024
        )
    }
}
