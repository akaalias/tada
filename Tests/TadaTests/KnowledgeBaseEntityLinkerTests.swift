import Foundation
import Testing
@testable import Tada

// MARK: - KnowledgeBaseEntityLinker Tests

@Test func entitySlug_lowercases_and_hyphenates() {
    #expect(KnowledgeBaseFilesystem.slug(from: "Tada.app") == "tada-app")
    #expect(KnowledgeBaseFilesystem.slug(from: "Human Agency") == "human-agency")
    #expect(KnowledgeBaseFilesystem.slug(from: "OpenAI") == "openai")
    #expect(KnowledgeBaseFilesystem.slug(from: "June 1, 2026") == "june-1-2026")
}

@Test func entitySlug_collapses_multiple_separators() {
    #expect(KnowledgeBaseFilesystem.slug(from: "AI / ML & Research") == "ai-ml-research")
}

@Test func entitySlug_truncates_to_48_chars() {
    let long = String(repeating: "a", count: 100)
    #expect(KnowledgeBaseFilesystem.slug(from: long).count == 48)
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

@Test func canonicalize_rewrites_links_in_original_input() {
    let body = "The note body mentions [[openai.md|OpenAI]]."
    let original = "I emailed [[openai.md|OpenAI]] about the role yesterday."
    let newEntities = [ExtractedEntity(slug: "openai", displayName: "OpenAI", body: "An AI lab.")]
    let result = KnowledgeBaseEntityLinker.canonicalize(
        linkedBody: body,
        linkedOriginalInput: original,
        newEntities: newEntities,
        existingSlugs: []
    )

    #expect(result.body.contains("[[../_entities/openai.md|OpenAI]]"))
    #expect(result.originalInput?.contains("[[../_entities/openai.md|OpenAI]]") == true)
}

@Test func canonicalize_original_input_nil_when_not_provided() {
    let result = KnowledgeBaseEntityLinker.canonicalize(
        linkedBody: "Body text.",
        newEntities: [],
        existingSlugs: []
    )

    #expect(result.originalInput == nil)
}

@Test func canonicalize_original_input_corrects_ai_slug_variant() {
    let original = "We ship with [[TadaApp.md|Tada.app]] every day."
    let newEntities = [ExtractedEntity(slug: "TadaApp", displayName: "Tada.app", body: "An AI-native app.")]
    let result = KnowledgeBaseEntityLinker.canonicalize(
        linkedBody: "",
        linkedOriginalInput: original,
        newEntities: newEntities,
        existingSlugs: []
    )

    #expect(result.originalInput?.contains("[[../_entities/tada-app.md|Tada.app]]") == true)
}

@Test func canonicalize_original_input_preserves_structural_links() {
    let original = "Back to [[_overview.md|Parent Task]] and [[02-step.md|Step Two]]."
    let result = KnowledgeBaseEntityLinker.canonicalize(
        linkedBody: "",
        linkedOriginalInput: original,
        newEntities: [],
        existingSlugs: []
    )

    #expect(result.originalInput?.contains("[[_overview.md|Parent Task]]") == true)
    #expect(result.originalInput?.contains("[[02-step.md|Step Two]]") == true)
    #expect(result.originalInput?.contains("../_entities/") == false)
}

// MARK: - Backlink Detection

@Test func bodyContainsEntityLink_matches_canonical_link() {
    let body = "We use [[../_entities/tada-app.md|Tada.app]] daily."
    #expect(KnowledgeBaseEntityLinker.bodyContainsEntityLink(body, entitySlug: "tada-app"))
}

@Test func bodyContainsEntityLink_no_display_name_still_matches() {
    let body = "See [[../_entities/openai.md]] for context."
    #expect(KnowledgeBaseEntityLinker.bodyContainsEntityLink(body, entitySlug: "openai"))
}

@Test func bodyContainsEntityLink_does_not_match_different_slug() {
    let body = "[[../_entities/openai.md|OpenAI]]"
    #expect(!KnowledgeBaseEntityLinker.bodyContainsEntityLink(body, entitySlug: "anthropic"))
}

@Test func bodyContainsEntityLink_ignores_subtask_links() {
    let body = "See [[02-some-step.md|Some Step]]."
    #expect(!KnowledgeBaseEntityLinker.bodyContainsEntityLink(body, entitySlug: "some-step"))
}

// MARK: - Body Region Extraction

@Test func extractBodyRegion_finds_body_before_original_input() {
    let raw = """
    ---
    title: "Some Note"
    taskId: 123
    ---

    # Some Note

    This is the body of the note across one line.

    ## Original input

    raw user text

    <!-- tada:related:start -->
    <!-- tada:related:end -->

    ---
    Back to [[_overview.md|Parent]]
    """

    let region = KnowledgeBaseEntityLinker.extractBodyRegion(from: raw)
    #expect(region?.body == "This is the body of the note across one line.")
}

@Test func extractBodyRegion_finds_body_before_related_marker_when_no_original_input() {
    let raw = """
    ---
    title: "X"
    ---

    # X

    Body line.

    <!-- tada:related:start -->
    <!-- tada:related:end -->
    """

    let region = KnowledgeBaseEntityLinker.extractBodyRegion(from: raw)
    #expect(region?.body == "Body line.")
}

@Test func extractBodyRegion_returns_nil_when_no_heading() {
    let raw = "Just some text without a heading."
    #expect(KnowledgeBaseEntityLinker.extractBodyRegion(from: raw) == nil)
}

@Test func extractBodyRegion_returns_nil_when_body_empty() {
    let raw = """
    # Heading

    ## Original input

    foo
    """
    #expect(KnowledgeBaseEntityLinker.extractBodyRegion(from: raw) == nil)
}

@Test func extractBodyRegion_splice_replaces_body_only() {
    let raw = """
    ---
    title: "X"
    ---

    # X

    Original body.

    ## Original input

    foo

    <!-- tada:related:start -->
    <!-- tada:related:end -->

    ---
    Back to [[_overview.md|P]]
    """
    let region = KnowledgeBaseEntityLinker.extractBodyRegion(from: raw)!
    var updated = raw
    updated.replaceSubrange(region.range, with: "\nLINKED BODY\n")

    #expect(updated.contains("LINKED BODY"))
    #expect(!updated.contains("Original body."))
    #expect(updated.contains("## Original input"))
    #expect(updated.contains("Back to [[_overview.md|P]]"))
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

// MARK: - insertEntityLinks (deterministic linking)

@Test func insertEntityLinks_wraps_first_occurrence() {
    let body = "I work at FELS Family Office GmbH and Tobi helps me. FELS Family Office GmbH is fine."
    let out = KnowledgeBaseEntityLinker.insertEntityLinks(into: body, entities: [
        ("fels-family-office-gmbh", "FELS Family Office GmbH"),
        ("tobi", "Tobi"),
    ])
    #expect(out.contains("[[../_entities/fels-family-office-gmbh.md|FELS Family Office GmbH]]"))
    #expect(out.contains("[[../_entities/tobi.md|Tobi]]"))
    // Only the FIRST occurrence is linked.
    #expect(out.components(separatedBy: "fels-family-office-gmbh.md").count == 2)
}

@Test func insertEntityLinks_longest_name_wins_over_substring() {
    let body = "FELS Family Office GmbH is the company."
    let out = KnowledgeBaseEntityLinker.insertEntityLinks(into: body, entities: [
        ("fels", "FELS"),
        ("fels-family-office-gmbh", "FELS Family Office GmbH"),
    ])
    #expect(out.contains("[[../_entities/fels-family-office-gmbh.md|FELS Family Office GmbH]]"))
    #expect(!out.contains("|FELS]]"))  // the short "FELS" did not grab the prefix
}

@Test func insertEntityLinks_skips_already_linked_slug() {
    let body = "See [[../_entities/tobi.md|Tobi]] and Tobi again."
    let out = KnowledgeBaseEntityLinker.insertEntityLinks(into: body, entities: [("tobi", "Tobi")])
    #expect(out == body)  // already linked -> unchanged
}

@Test func insertEntityLinks_word_boundary_no_partial_match() {
    let body = "Tobias is not Tobi."
    let out = KnowledgeBaseEntityLinker.insertEntityLinks(into: body, entities: [("tobi", "Tobi")])
    #expect(out.contains("Tobias is not [[../_entities/tobi.md|Tobi]]."))
    #expect(out.hasPrefix("Tobias is not"))  // "Tobias" untouched
}

@Test func insertEntityLinks_no_match_leaves_text_unchanged() {
    let body = "Nothing relevant here."
    let out = KnowledgeBaseEntityLinker.insertEntityLinks(into: body, entities: [("openai", "OpenAI")])
    #expect(out == body)
}
