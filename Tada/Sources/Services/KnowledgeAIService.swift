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
    @Guide(description: "The note body with first-occurrence wikilinks of the form [[<slug>.md|<Name>]] around each entity. All other text preserved verbatim.")
    var linkedBody: String
    @Guide(description: "The original user input rewritten with first-occurrence wikilinks the same way. Empty string if no original input was provided.")
    var linkedOriginalInput: String
    @Guide(description: "Entities not already in the existing list. Empty if none.")
    var newEntities: [GenExtractedEntity]
}

/// On-device knowledge service: distils completed work into wiki notes, discovers
/// cross-links, and extracts entities — all via guided generation. `phase` and
/// `attachedImage` parameters are retained for call-site compatibility but the
/// on-device model is text-only, so images are ignored (the PNG is still embedded
/// on disk by the caller).
actor KnowledgeAIService {
    init() {}

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
            You distil a single completed sub-task into ONE atomic markdown note for a personal \
            wiki. Capture concrete details from the user's answer (names, numbers, dates, places, \
            preferences); don't restate the question. The title reflects the durable insight, not \
            the question. First person, no emojis.
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

        let instructions = newNoteIsEntity
            ? "You maintain the entity graph of a personal wiki. Link the new entity to candidate entities in the SAME domain or theme. Never link across unrelated domains. Each link's targetPath MUST be the exact verbatim path of a candidate."
            : "You maintain the cross-links of a personal wiki. Surface NON-OBVIOUS connections: candidates sharing a genuine conceptual thread with the new note. Quality over quantity; an empty list is fine. Each link's targetPath MUST be the exact verbatim path of a candidate."

        let session = LanguageModelSession { instructions }
        let userMessage = """
        NEW NOTE:
        \(block(path: note.path, title: note.title, body: note.body, context: note.context))

        CANDIDATE NOTES:

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
            You identify high-signal entities (proper nouns, named concepts, companies, people, \
            places, dates anchoring deadlines, domain terms) in a wiki note and rewrite the body \
            with first-occurrence Obsidian wikilinks [[<slug>.md|<Name>]]. Prefer existing \
            entities; only create a new entity when the mention is high-signal and not already \
            covered. Preserve all other text verbatim. Entity bodies contain no wikilinks. No emojis.
            """
        let session = LanguageModelSession { instructions }
        let userMessage = """
        NOTE TITLE: \(noteTitle)

        NOTE BODY:
        \(noteBody)\(originalSection)

        EXISTING ENTITIES:
        \(existingList)

        Rewrite with first-occurrence wikilinks and emit any new high-signal entities.
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
            let content = result.content
            let extraction = EntityExtractionResult(
                linkedBody: content.linkedBody,
                linkedOriginalInput: content.linkedOriginalInput.isEmpty ? nil : content.linkedOriginalInput,
                newEntities: content.newEntities.map {
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
            You distil a completed task into ONE atomic overview note. Synthesise the goal, the \
            key decisions, and how it concluded — do not regurgitate every sub-task. You may \
            reference per-sub-task notes by filename as [[02-some-slug.md|Some Title]]. First \
            person, no emojis.
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
