import Foundation
import FoundationModels

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
    // The model only EXTRACTS entities; the wikilinks are inserted deterministically in code
    // (KnowledgeBaseEntityLinker.insertEntityLinks), because the on-device model won't rewrite
    // the body with [[...]] reliably — it returns the body verbatim.
    let newEntities: [ExtractedEntity]
}

struct ExistingEntityRef {
    let slug: String
    let title: String
}

// MARK: - Guided-generation mirrors

@Generable
private struct GenKnowledgeNote {
    @Guide(description: "Short noun-phrase title, 3-8 words, reflecting the durable insight.")
    var title: String
    @Guide(description: "1-3 short paragraphs of concise markdown. First person. No emojis.")
    var body: String
}

@Generable
private struct GenRelatedNote {
    @Guide(description: "The EXACT verbatim path string of a candidate from the list.")
    var targetPath: String
    var targetTitle: String
    @Guide(description: "One-sentence justification, an internal hint.")
    var reason: String
}

@Generable
private struct GenNoteLinks {
    var links: [GenRelatedNote]
}

@Generable
private struct GenExtractedEntity {
    @Guide(description: "Lowercase kebab-case slug, alphanumerics and hyphens only, max 48 chars.")
    var slug: String
    var displayName: String
    @Guide(description: "1-2 short sentences distilling the entity. First person, no emojis, no wikilinks.")
    var body: String
}

@Generable
private struct GenEntityExtraction {
    @Guide(description: "The high-signal entities mentioned in the note. Empty if none.")
    var newEntities: [GenExtractedEntity]
}

/// On-device knowledge service: distils completed work into wiki notes, discovers
/// cross-links, and extracts entities — all via guided generation. `phase` and
/// `attachedImage` parameters are retained for call-site compatibility but the
/// on-device model is text-only, so images are ignored (the PNG is still embedded
/// on disk by the caller).
actor KnowledgeAIService {
    init() {}

    /// Safety cap on candidate notes fed to link discovery. Candidates are title-only, so
    /// this is rarely binding; it just bounds the 4,096-token window for very large wikis.
    private static let maxLinkCandidates = 40

    /// Link-discovery prompt when the new note is an ENTITY — generous thematic clustering.
    private static let entityLinkPrompt = """
    You maintain the entity graph of a personal knowledge wiki. The new note is an ENTITY (a person, company, lab, product, place, role, idea, movement, or deadline) shown with its body; the candidate entities are given by title only.

    GOAL: connect this entity to other entities in the SAME DOMAIN OR THEME so each topic forms a richly interlinked cluster. Link generously WITHIN a theme — a person and the organisations/fields/roles they belong to; companies, labs, or products in the same industry; concepts, methods, or movements within the same discipline.

    DO NOT link across unrelated domains. The wiki spans several worlds (e.g. AI industry, a balcony renovation, tax filing, a cycling trip). An entity from one world has nothing to do with another. Stay strictly within the new entity's theme.

    A `mentioned in:` line lists notes that reference an entity — shared mentions are a strong signal, but a shared theme alone is enough.

    OUTPUT: `links` — the candidate entities that belong in the new entity's "Related" section, each { targetPath, targetTitle, reason }.
    RULES: targetPath MUST be the EXACT verbatim `path` of a candidate from the list. Only suggest candidates from the list; never the new note itself. Aim for 3-8 links in a populated theme; fewer (or none) when the theme genuinely has few entities. `reason` names the shared theme in one sentence (internal hint, not shown to the user).
    """

    /// Link-discovery prompt when the new note is a TASK note — precise, non-obvious links.
    private static let taskNoteLinkPrompt = """
    You maintain the cross-links of a personal knowledge wiki.

    INPUT: ONE new note with its full body, and a list of CANDIDATE notes given by `path` and `title` only (judge relevance from the title against the new note's content). Some carry a `mentioned in:` line; when the new note and a candidate are mentioned by the same notes, that is a STRONG signal. The candidate list is already pruned of notes the new note is ALREADY connected to.

    GOAL: surface NON-OBVIOUS connections — candidates sharing a genuine conceptual thread: the same theme or argument, a decision in one project that informs another, the same person/product/place/idea resurfacing across the user's work.

    OUTPUT: `links` — the candidates that belong in the new note's "Related" section, each { targetPath, targetTitle, reason }.
    RULES: targetPath MUST be the EXACT verbatim `path` of a candidate (including the "notes/<folder>/" prefix). Only suggest candidates from the list; never the new note itself. Quality over quantity — return 0-5 links; an empty list is fine, do NOT pad. Don't link on weak/generic overlap (both mention "decisions"); require a concrete shared entity, a specific shared idea, or genuine co-occurrence. `reason` names the specific shared thread in one sentence (internal hint).
    """

    func generateSubtaskNote(
        taskTitle: String,
        subtaskTitle: String,
        subtaskDescription: String,
        response: String,
        attachedImage: Data? = nil,
        tableMarkdown: String? = nil,
        phase: APIRequestPhase
    ) async throws -> GeneratedKnowledgeNote {
        let tableSection = tableMarkdown.map { "\n\nSTRUCTURED TABLE DATA:\n\($0)" } ?? ""
        let instructions = """
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
        let session = LanguageModelSession { instructions }
        let userMessage = """
        PARENT TASK: \(taskTitle)

        SUB-TASK: \(subtaskTitle)
        \(subtaskDescription.isEmpty ? "" : "Details: \(subtaskDescription)\n")
        USER RESPONSE: \(response)\(tableSection)
        """
        let temperature = 0.4

        return try await APILog.shared.record(
            role: .knowledge,
            operation: "Knowledge note",
            instructions: instructions,
            prompt: userMessage,
            temperature: temperature,
            outputType: "GeneratedKnowledgeNote",
            phase: phase,
            taskTitle: taskTitle
        ) {
            let result = try await session.respond(
                to: userMessage,
                generating: GenKnowledgeNote.self,
                options: GenerationOptions(temperature: temperature)
            )
            let note = GeneratedKnowledgeNote(title: result.content.title, body: result.content.body)
            return (note, APILog.describe(note))
        }
    }

    func discoverLinksForNote(
        note: (path: String, title: String, body: String, context: String),
        candidates: [(path: String, title: String, body: String, context: String)],
        newNoteIsEntity: Bool
    ) async throws -> NoteLinkSuggestions {
        // The new note keeps its full body — it's the single source we're linking FROM.
        let newContext = note.context.isEmpty ? "" : "\n\(note.context)"
        let newNoteBlock = """
        path: \(note.path)
        title: \(note.title)\(newContext)
        ---
        \(note.body.prefix(500))
        """

        // Candidates are given by TITLE only (plus path and any "mentioned in" line). Feeding
        // full candidate bodies made the weak model link unrelated notes; titles give a clean
        // topical signal, and being tiny they all fit the 4,096-token window. (On-device
        // embedding similarity was evaluated and ranked unrelated notes as high as related
        // ones, so titles + the model's judgment is the more accurate path here.)
        let candidateList = candidates.prefix(Self.maxLinkCandidates).map { c -> String in
            let ctx = c.context.isEmpty ? "" : "  (\(c.context))"
            return "- path: \(c.path) | title: \(c.title)\(ctx)"
        }.joined(separator: "\n")

        let instructions = newNoteIsEntity ? Self.entityLinkPrompt : Self.taskNoteLinkPrompt

        let session = LanguageModelSession { instructions }
        let userMessage = """
        NEW NOTE:
        \(newNoteBlock)

        CANDIDATE NOTES (path | title):
        \(candidateList)

        Which candidates belong in the new note's Related section?
        """
        let temperature = 0.3

        return try await APILog.shared.record(
            role: .knowledge,
            operation: "Discover related notes",
            instructions: instructions,
            prompt: userMessage,
            temperature: temperature,
            outputType: "NoteLinkSuggestions",
            phase: .knowledge,
            taskTitle: note.title
        ) {
            let result = try await session.respond(
                to: userMessage,
                generating: GenNoteLinks.self,
                options: GenerationOptions(temperature: temperature)
            )
            let suggestions = NoteLinkSuggestions(links: result.content.links.map {
                SuggestedRelatedNote(targetPath: $0.targetPath, targetTitle: $0.targetTitle, reason: $0.reason)
            })
            return (suggestions, APILog.describe(suggestions))
        }
    }

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
        let originalSection = trimmedInput.isEmpty ? "" : "\n\nORIGINAL USER INPUT:\n\(trimmedInput)"

        let instructions = """
        You analyse a wiki note and identify the high-signal entities it mentions. You ONLY list
        entities — you do NOT rewrite the note (the wikilinks are inserted automatically afterwards).

        INPUT: the note's title and body; optionally the ORIGINAL USER INPUT (the user's verbatim words); and a list of entities that already exist: { slug, title }.

        OUTPUT: newEntities — entities NOT already in the existing list, each { slug, displayName, body }.
        - displayName: the entity's name EXACTLY as it appears in the text (e.g. "FELS Family Office GmbH", "Tobi"), so it can be matched and linked.
        - body: 1-2 short sentences distilling the durable concept. First person, no emojis, no filler, no wikilinks.

        RULES:
        - Only emit entities NOT already in the existing list (those are already linked).
        - High-signal = a proper noun, named concept/movement, specific company/person/place, a calendar date anchoring a deadline, or a domain-specific term. SKIP generic verbs, adjectives, common nouns.
        - The ORIGINAL USER INPUT is a prime entity source — mine the proper nouns the user typed as thoroughly as the body.
        - Slug: lowercase ASCII, hyphenated, alphanumerics only, max 48 chars (e.g. "tada-app", "human-agency", "june-1-2026").
        - Never invent entities the input doesn't mention. Aim for 3-10 per note; quality over quantity.
        """
        let session = LanguageModelSession { instructions }
        let userMessage = """
        NOTE TITLE: \(noteTitle)

        NOTE BODY:
        \(noteBody)\(originalSection)

        EXISTING ENTITIES:
        \(existingList)

        List the high-signal entities (new ones only).
        """
        let temperature = 0.3

        return try await APILog.shared.record(
            role: .knowledge,
            operation: "Extract entities and wikilinks",
            instructions: instructions,
            prompt: userMessage,
            temperature: temperature,
            outputType: "EntityExtractionResult",
            phase: phase,
            taskTitle: noteTitle
        ) {
            let result = try await session.respond(
                to: userMessage,
                generating: GenEntityExtraction.self,
                options: GenerationOptions(temperature: temperature)
            )
            let extraction = EntityExtractionResult(
                newEntities: result.content.newEntities.map {
                    ExtractedEntity(slug: $0.slug, displayName: $0.displayName, body: $0.body)
                }
            )
            return (extraction, APILog.describe(extraction))
        }
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

        let instructions = """
        You distill a fully completed task into ONE atomic markdown note that serves as the entry's overview.

        INPUT: the task, every sub-task that was completed, and a brief view of how each was answered.

        OUTPUT: one note with:
        - title: short noun phrase (3-8 words) summarising the task as a whole.
        - body: 1-3 short paragraphs of concise markdown. First person. Synthesise the goal, the key decisions, and how the task concluded — do not regurgitate every sub-task; the per-sub-task notes already cover those.

        CROSS-REFERENCES (optional): if natural, reference per-sub-task notes by their on-disk filename using Obsidian wikilinks, e.g. [[02-some-slug.md|Some Title]]. The filenames are provided.

        No emojis.
        """
        let session = LanguageModelSession { instructions }
        let userMessage = """
        TASK TITLE: \(taskTitle)

        ORIGINAL REQUEST: \(originalInput)
        \(taskDescription.isEmpty ? "" : "\nTASK DESCRIPTION: \(taskDescription)")

        COMPLETED SUB-TASKS (with their on-disk filenames):
        \(formatted)
        """
        let temperature = 0.4

        return try await APILog.shared.record(
            role: .knowledge,
            operation: "Task overview note",
            instructions: instructions,
            prompt: userMessage,
            temperature: temperature,
            outputType: "GeneratedKnowledgeNote",
            phase: .knowledge,
            taskTitle: taskTitle
        ) {
            let result = try await session.respond(
                to: userMessage,
                generating: GenKnowledgeNote.self,
                options: GenerationOptions(temperature: temperature)
            )
            let note = GeneratedKnowledgeNote(title: result.content.title, body: result.content.body)
            return (note, APILog.describe(note))
        }
    }
}
