import Foundation
import Testing
@testable import Tada

// MARK: - KnowledgeBaseEntityLinker Tests

@Test func entitySlug_lowercases_and_hyphenates() {
    #expect(KnowledgeBaseFilesystem.entitySlug(from: "Tada.app") == "tada-app")
    #expect(KnowledgeBaseFilesystem.entitySlug(from: "Human Agency") == "human-agency")
    #expect(KnowledgeBaseFilesystem.entitySlug(from: "OpenAI") == "openai")
    #expect(KnowledgeBaseFilesystem.entitySlug(from: "June 1, 2026") == "june-1-2026")
}

@Test func entitySlug_collapses_multiple_separators() {
    #expect(KnowledgeBaseFilesystem.entitySlug(from: "AI / ML & Research") == "ai-ml-research")
}

@Test func entitySlug_truncates_to_48_chars() {
    let long = String(repeating: "a", count: 100)
    #expect(KnowledgeBaseFilesystem.entitySlug(from: long).count == 48)
}

@Test func canonicalize_rewrites_entity_links_to_relative_path() {
    let body = "Visit [[tada-app.md|Tada.app]] for more info."
    let newEntities = [ExtractedEntity(slug: "tada-app", displayName: "Tada.app", body: "An AI-native productivity app.")]
    let result = KnowledgeBaseEntityLinker.canonicalize(linkedBody: body, newEntities: newEntities, existingSlugs: [])

    #expect(result.body.contains("[[../_entities/tada-app.md|Tada.app]]"))
    #expect(result.finalNewEntities.count == 1)
    #expect(result.finalNewEntities[0].slug == "tada-app")
    #expect(result.finalNewEntities[0].displayName == "Tada.app")
}

@Test func canonicalize_preserves_subtask_links() {
    let body = "See [[02-some-step.md|Some Step]] for context."
    let result = KnowledgeBaseEntityLinker.canonicalize(linkedBody: body, newEntities: [], existingSlugs: [])

    #expect(result.body.contains("[[02-some-step.md|Some Step]]"))
    #expect(!result.body.contains("../_entities/"))
}

@Test func canonicalize_preserves_overview_back_link() {
    let body = "Back to [[_overview.md|Parent Task]]."
    let result = KnowledgeBaseEntityLinker.canonicalize(linkedBody: body, newEntities: [], existingSlugs: [])

    #expect(result.body.contains("[[_overview.md|Parent Task]]"))
}

@Test func canonicalize_corrects_ai_slug_variants_for_new_entities() {
    // AI used a non-canonical slug for the new entity; canonicalisation should snap it to display-derived form.
    let body = "We use [[TadaApp.md|Tada.app]] daily."
    let newEntities = [ExtractedEntity(slug: "TadaApp", displayName: "Tada.app", body: "An AI-native app.")]
    let result = KnowledgeBaseEntityLinker.canonicalize(linkedBody: body, newEntities: newEntities, existingSlugs: [])

    #expect(result.body.contains("[[../_entities/tada-app.md|Tada.app]]"))
    #expect(result.finalNewEntities[0].slug == "tada-app")
}

@Test func canonicalize_keeps_existing_entity_slug() {
    let body = "Targeting [[ai-labs.md|AI Labs]]."
    let result = KnowledgeBaseEntityLinker.canonicalize(linkedBody: body, newEntities: [], existingSlugs: ["ai-labs"])

    #expect(result.body.contains("[[../_entities/ai-labs.md|AI Labs]]"))
}

@Test func canonicalize_dedupes_new_entities_by_canonical_slug() {
    let body = "[[openai.md|OpenAI]] and [[OpenAI.md|OpenAI]]"
    let newEntities = [
        ExtractedEntity(slug: "openai", displayName: "OpenAI", body: "AI lab."),
        ExtractedEntity(slug: "OpenAI", displayName: "OpenAI", body: "Same lab.")
    ]
    let result = KnowledgeBaseEntityLinker.canonicalize(linkedBody: body, newEntities: newEntities, existingSlugs: [])

    #expect(result.finalNewEntities.count == 1)
    #expect(result.finalNewEntities[0].slug == "openai")
}

@Test func canonicalize_skips_new_entity_if_canonical_already_exists() {
    let newEntities = [ExtractedEntity(slug: "openai", displayName: "OpenAI", body: "...")]
    let result = KnowledgeBaseEntityLinker.canonicalize(linkedBody: "", newEntities: newEntities, existingSlugs: ["openai"])

    #expect(result.finalNewEntities.isEmpty)
}

@Test func canonicalize_handles_multiple_entities_in_one_body() {
    let body = "Targeting [[ai-builders.md|AI Builders]] at [[openai.md|OpenAI]] and [[anthropic.md|Anthropic]]."
    let newEntities = [
        ExtractedEntity(slug: "ai-builders", displayName: "AI Builders", body: "..."),
        ExtractedEntity(slug: "openai", displayName: "OpenAI", body: "..."),
        ExtractedEntity(slug: "anthropic", displayName: "Anthropic", body: "...")
    ]
    let result = KnowledgeBaseEntityLinker.canonicalize(linkedBody: body, newEntities: newEntities, existingSlugs: [])

    #expect(result.body.contains("[[../_entities/ai-builders.md|AI Builders]]"))
    #expect(result.body.contains("[[../_entities/openai.md|OpenAI]]"))
    #expect(result.body.contains("[[../_entities/anthropic.md|Anthropic]]"))
    #expect(result.finalNewEntities.count == 3)
}

// MARK: - Filesystem Entity Helpers

@Test func writeEntityNote_creates_file() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ent-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let fs = KnowledgeBaseFilesystem(notesURL: tmp, rootURL: tmp)
    let created = await fs.writeEntityNote(slug: "tada-app", displayName: "Tada.app", body: "An AI-native app.")

    #expect(created == true)
    let written = try String(contentsOf: tmp.appendingPathComponent("_entities/tada-app.md"), encoding: .utf8)
    #expect(written.contains("# Tada.app"))
    #expect(written.contains("An AI-native app."))
    #expect(written.contains("kind: entity"))
}

@Test func writeEntityNote_skips_if_exists() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ent-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let fs = KnowledgeBaseFilesystem(notesURL: tmp, rootURL: tmp)
    _ = await fs.writeEntityNote(slug: "openai", displayName: "OpenAI", body: "First.")
    let secondAttempt = await fs.writeEntityNote(slug: "openai", displayName: "OpenAI", body: "Second.")

    #expect(secondAttempt == false)
    let written = try String(contentsOf: tmp.appendingPathComponent("_entities/openai.md"), encoding: .utf8)
    #expect(written.contains("First."))
    #expect(!written.contains("Second."))
}

@Test func listEntities_returns_slug_and_title() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ent-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let fs = KnowledgeBaseFilesystem(notesURL: tmp, rootURL: tmp)
    _ = await fs.writeEntityNote(slug: "openai", displayName: "OpenAI", body: "...")
    _ = await fs.writeEntityNote(slug: "anthropic", displayName: "Anthropic", body: "...")

    let entities = await fs.listEntities()
    let slugs = Set(entities.map { $0.slug })
    let titles = Set(entities.map { $0.title })

    #expect(slugs == ["openai", "anthropic"])
    #expect(titles == ["OpenAI", "Anthropic"])
}

@Test func listTaskFolders_skips_entities_folder() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ent-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let fs = KnowledgeBaseFilesystem(notesURL: tmp, rootURL: tmp)
    _ = await fs.writeEntityNote(slug: "openai", displayName: "OpenAI", body: "...")
    let taskFolder = await fs.ensureTaskFolder(taskId: UUID(), title: "Some Task")
    _ = taskFolder

    let folders = await fs.listTaskFolders()
    #expect(folders.count == 1)
    #expect(!folders.contains { $0.lastPathComponent == "_entities" })
}
