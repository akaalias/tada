import Foundation
import Testing
@testable import Tada

// MARK: - KnowledgeBaseLinkDiscovery Tests

/// Builds a temp wiki on disk: one task folder with a note, plus one entity note.
/// Returns the root URL; caller is responsible for cleanup.
private func makeWikiFixture() throws -> URL {
    // macOS reports the temp dir under /var, a symlink to /private/var. FileManager's
    // directory listing returns the resolved /private form, so anchor the fixture there
    // to keep computed relative paths consistent.
    var tmpPath = NSTemporaryDirectory()
    if tmpPath.hasPrefix("/var/") { tmpPath = "/private" + tmpPath }
    let root = URL(fileURLWithPath: tmpPath)
        .appendingPathComponent("kb-linkdisc-\(UUID().uuidString)", isDirectory: true)
    let notes = root.appendingPathComponent("notes", isDirectory: true)
    let taskFolder = notes.appendingPathComponent("ABC123__revamp-balcony", isDirectory: true)
    let entities = notes.appendingPathComponent("_entities", isDirectory: true)
    try FileManager.default.createDirectory(at: taskFolder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: entities, withIntermediateDirectories: true)

    let taskNote = """
    ---
    title: "Balcony Privacy Solution Preference"
    taskId: ABC123
    ---

    # Balcony Privacy Solution Preference

    For my balcony revamp I chose plants and greenery as the privacy solution.

    <!-- tada:related:start -->
    <!-- tada:related:end -->

    ---
    Back to [[_overview.md|Revamp Balcony]]
    """
    try taskNote.write(
        to: taskFolder.appendingPathComponent("01-privacy-solution.md"),
        atomically: true, encoding: .utf8
    )

    let entityNote = """
    ---
    title: "Plants as Privacy Solution"
    kind: entity
    slug: plants-as-privacy-solution
    ---

    # Plants as Privacy Solution

    I chose living plants and greenery as my primary balcony privacy approach.

    <!-- tada:related:start -->
    <!-- tada:related:end -->

    ---
    Back to [[../../index.md|Knowledge Base index]]
    """
    try entityNote.write(
        to: entities.appendingPathComponent("plants-as-privacy-solution.md"),
        atomically: true, encoding: .utf8
    )

    return root
}

@Test func collectNotesForDiscovery_includes_entity_notes() async throws {
    let root = try makeWikiFixture()
    defer { try? FileManager.default.removeItem(at: root) }

    let fs = KnowledgeBaseFilesystem(
        notesURL: root.appendingPathComponent("notes", isDirectory: true),
        rootURL: root
    )
    let discovery = KnowledgeBaseLinkDiscovery(filesystem: fs)

    let collected = await discovery.collectNotesForDiscovery(rootURL: root)
    let relPaths = Set(collected.map { $0.relPath })

    #expect(relPaths.contains("notes/ABC123__revamp-balcony/01-privacy-solution.md"))
    #expect(relPaths.contains("notes/_entities/plants-as-privacy-solution.md"))
}

@Test func collectNotesForDiscovery_entity_note_carries_title_and_body() async throws {
    let root = try makeWikiFixture()
    defer { try? FileManager.default.removeItem(at: root) }

    let fs = KnowledgeBaseFilesystem(
        notesURL: root.appendingPathComponent("notes", isDirectory: true),
        rootURL: root
    )
    let discovery = KnowledgeBaseLinkDiscovery(filesystem: fs)

    let collected = await discovery.collectNotesForDiscovery(rootURL: root)
    let entity = collected.first { $0.relPath == "notes/_entities/plants-as-privacy-solution.md" }

    #expect(entity?.title == "Plants as Privacy Solution")
    #expect(entity?.body.contains("living plants and greenery") == true)
}

// MARK: - Related-section additive merge

private let noteWithEmptyMarkers = """
---
title: "T"
---

# T

Body text.

<!-- tada:related:start -->
<!-- tada:related:end -->

---
Back to [[_overview.md|X]]
"""

@Test func addRelatedBullets_fills_an_empty_section() {
    let out = KnowledgeBaseLinkDiscovery.addRelatedBullets(
        ["- [[../foo/02-x.md|X Note]]"], to: noteWithEmptyMarkers
    )
    #expect(out.contains("## Related"))
    #expect(out.contains("- [[../foo/02-x.md|X Note]]"))
    // Markers and trailing structure preserved.
    #expect(out.contains("<!-- tada:related:start -->"))
    #expect(out.contains("<!-- tada:related:end -->"))
    #expect(out.contains("Back to [[_overview.md|X]]"))
}

@Test func addRelatedBullets_preserves_existing_bullets_and_appends() {
    let withOne = KnowledgeBaseLinkDiscovery.addRelatedBullets(
        ["- [[a.md|A]]"], to: noteWithEmptyMarkers
    )
    let withTwo = KnowledgeBaseLinkDiscovery.addRelatedBullets(
        ["- [[b.md|B]]"], to: withOne
    )
    #expect(withTwo.contains("- [[a.md|A]]"))
    #expect(withTwo.contains("- [[b.md|B]]"))
}

@Test func addRelatedBullets_dedups_by_target_path() {
    let withOne = KnowledgeBaseLinkDiscovery.addRelatedBullets(
        ["- [[a.md|A]]"], to: noteWithEmptyMarkers
    )
    // Re-adding the same target (even with a different display title) must not duplicate.
    let again = KnowledgeBaseLinkDiscovery.addRelatedBullets(
        ["- [[a.md|A renamed]]"], to: withOne
    )
    let occurrences = again.components(separatedBy: "[[a.md").count - 1
    #expect(occurrences == 1)
}

// MARK: - Candidate filtering (proximity)

/// A wiki with two task folders (A has two sibling notes, B has one) plus a shared entity.
/// "A Two" already links the entity in its body.
private func makeMultiTaskFixture() throws -> URL {
    var tmpPath = NSTemporaryDirectory()
    if tmpPath.hasPrefix("/var/") { tmpPath = "/private" + tmpPath }
    let root = URL(fileURLWithPath: tmpPath)
        .appendingPathComponent("kb-filter-\(UUID().uuidString)", isDirectory: true)
    let notes = root.appendingPathComponent("notes", isDirectory: true)
    let taskA = notes.appendingPathComponent("AAA__task-a", isDirectory: true)
    let taskB = notes.appendingPathComponent("BBB__task-b", isDirectory: true)
    let entities = notes.appendingPathComponent("_entities", isDirectory: true)
    try FileManager.default.createDirectory(at: taskA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: taskB, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: entities, withIntermediateDirectories: true)

    func note(_ title: String, body: String) -> String {
        """
        ---
        title: "\(title)"
        ---

        # \(title)

        \(body)

        <!-- tada:related:start -->
        <!-- tada:related:end -->

        ---
        Back to [[_overview.md|X]]
        """
    }

    try note("A One", body: "First note in task A.")
        .write(to: taskA.appendingPathComponent("01-a-one.md"), atomically: true, encoding: .utf8)
    try note("A Two", body: "Second note. Links [[../_entities/shared-idea.md|Shared Idea]] already.")
        .write(to: taskA.appendingPathComponent("02-a-two.md"), atomically: true, encoding: .utf8)
    try note("B One", body: "First note in task B.")
        .write(to: taskB.appendingPathComponent("01-b-one.md"), atomically: true, encoding: .utf8)

    let entity = """
    ---
    title: "Shared Idea"
    kind: entity
    slug: shared-idea
    ---

    # Shared Idea

    A concept shared across tasks.

    <!-- tada:related:start -->
    <!-- tada:related:end -->
    """
    try entity.write(to: entities.appendingPathComponent("shared-idea.md"), atomically: true, encoding: .utf8)
    return root
}

@Test func filterCandidates_excludes_same_folder_siblings_but_keeps_cross_task() async throws {
    let root = try makeMultiTaskFixture()
    defer { try? FileManager.default.removeItem(at: root) }

    let fs = KnowledgeBaseFilesystem(
        notesURL: root.appendingPathComponent("notes", isDirectory: true),
        rootURL: root
    )
    let discovery = KnowledgeBaseLinkDiscovery(filesystem: fs)

    let all = await discovery.collectNotesForDiscovery(rootURL: root)
    let aOne = all.first { $0.relPath.hasSuffix("01-a-one.md") }!
    let candidates = await discovery.filterCandidates(for: aOne, from: all)
    let paths = Set(candidates.map { $0.relPath })

    #expect(!paths.contains("notes/AAA__task-a/02-a-two.md"))  // sibling — already close
    #expect(paths.contains("notes/BBB__task-b/01-b-one.md"))   // cross-task — kept
}

@Test func filterCandidates_excludes_entities_already_linked_in_body() async throws {
    let root = try makeMultiTaskFixture()
    defer { try? FileManager.default.removeItem(at: root) }

    let fs = KnowledgeBaseFilesystem(
        notesURL: root.appendingPathComponent("notes", isDirectory: true),
        rootURL: root
    )
    let discovery = KnowledgeBaseLinkDiscovery(filesystem: fs)

    let all = await discovery.collectNotesForDiscovery(rootURL: root)
    let aTwo = all.first { $0.relPath.hasSuffix("02-a-two.md") }!
    let candidates = await discovery.filterCandidates(for: aTwo, from: all)
    let paths = Set(candidates.map { $0.relPath })

    #expect(!paths.contains("notes/_entities/shared-idea.md"))  // already body-linked
}

@Test func addRelatedBullets_legacy_note_without_markers_inserts_section() {
    let legacy = """
    # Legacy

    Body.

    ---
    Back to [[_overview.md|X]]
    """
    let out = KnowledgeBaseLinkDiscovery.addRelatedBullets(["- [[a.md|A]]"], to: legacy)
    #expect(out.contains("## Related"))
    #expect(out.contains("- [[a.md|A]]"))
    // The Related section lands before the trailing "Back to" line.
    let relatedIdx = out.range(of: "## Related")!.lowerBound
    let backIdx = out.range(of: "Back to")!.lowerBound
    #expect(relatedIdx < backIdx)
}
