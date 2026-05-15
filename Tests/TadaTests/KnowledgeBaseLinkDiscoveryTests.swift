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
