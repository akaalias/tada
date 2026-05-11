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
        self.client = ClaudeAPIClient(apiKey: apiKey)
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
