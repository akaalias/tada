import Foundation
import Testing
@testable import Tada

// MARK: - Helpers

private func makeService() -> (svc: KnowledgeBaseService, root: URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("KBServiceTests")
        .appendingPathComponent(UUID().uuidString)
    let svc = KnowledgeBaseService(rootURL: root)
    return (svc, root)
}

private func waitForFile(_ url: URL, timeout: TimeInterval = 5) async -> Bool {
    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return false
}

// MARK: - KnowledgeBaseError

@Test func knowledgeBaseError_descriptions() {
    #expect(KnowledgeBaseError.noteNotFound.errorDescription == "Note not found")
    #expect(KnowledgeBaseError.textNotFound.errorDescription == "Text not found in note")
    #expect(KnowledgeBaseError.bodyNotFound.errorDescription == "Could not find body section in note")
}

// MARK: - handleTaskCreatedOrUpdated (non-AI structural)

@MainActor
@Test func kbservice_handleTaskCreatedOrUpdated_writes_overview_and_index() async {
    let (svc, root) = makeService()
    defer { try? FileManager.default.removeItem(at: root) }

    let task = TodoTask(title: "Build Shed", originalInput: "build a shed")
    svc.handleTaskCreatedOrUpdated(task)

    #expect(await waitForFile(svc.indexURL))
    let index = try? String(contentsOf: svc.indexURL, encoding: .utf8)
    #expect(index?.contains("Build Shed") == true)
}

// MARK: - createEntity / createUserNote / listUserNotes / searchNotes

@Test func kbservice_createEntity_writes_entity_note() async {
    let (svc, root) = makeService()
    defer { try? FileManager.default.removeItem(at: root) }

    try? await svc.createEntity(name: "Dr. Smith", body: "A trusted GP.")

    let entityURL = root.appendingPathComponent("notes/_entities/dr-smith.md")
    #expect(FileManager.default.fileExists(atPath: entityURL.path))
    let content = try? String(contentsOf: entityURL, encoding: .utf8)
    #expect(content?.contains("Dr. Smith") == true)
    #expect(content?.contains("A trusted GP.") == true)
}

@Test func kbservice_createUserNote_and_list() async {
    let (svc, root) = makeService()
    defer { try? FileManager.default.removeItem(at: root) }

    let url = await svc.createUserNote(title: "Weekend Ideas", body: "Go hiking")
    #expect(FileManager.default.fileExists(atPath: url.path))

    let notes = await svc.listUserNotes()
    #expect(notes.contains { $0.title == "Weekend Ideas" })
}

@Test func kbservice_searchNotes_matches_entities_and_user_notes() async {
    let (svc, root) = makeService()
    defer { try? FileManager.default.removeItem(at: root) }

    try? await svc.createEntity(name: "Bamboo Plant", body: "A privacy screen.")
    _ = await svc.createUserNote(title: "Balcony Plan", body: "Add bamboo")

    let results = await svc.searchNotes(query: "bamboo")
    #expect(results.contains { $0.kind == "entity" && $0.name == "Bamboo Plant" })

    let none = await svc.searchNotes(query: "zzz-nothing")
    #expect(none.isEmpty)
}

// MARK: - addLinkToNote / replaceTextWithLink / editNoteBody

@Test func kbservice_addLinkToNote_appends_related_section() async throws {
    let (svc, root) = makeService()
    defer { try? FileManager.default.removeItem(at: root) }

    let noteURL = root.appendingPathComponent("note.md")
    try "# Note\n\nSome body".write(to: noteURL, atomically: true, encoding: .utf8)

    try await svc.addLinkToNote(at: noteURL, targetEntity: "Dr. Smith")
    let content = try String(contentsOf: noteURL, encoding: .utf8)
    #expect(content.contains("## Related"))
    #expect(content.contains("Dr. Smith"))

    // Idempotent: adding the same link again does not duplicate it.
    try await svc.addLinkToNote(at: noteURL, targetEntity: "Dr. Smith")
    let after = try String(contentsOf: noteURL, encoding: .utf8)
    let occurrences = after.components(separatedBy: "Dr. Smith").count - 1
    #expect(occurrences == 1)
}

@Test func kbservice_replaceTextWithLink_replaces_or_throws() async throws {
    let (svc, root) = makeService()
    defer { try? FileManager.default.removeItem(at: root) }

    let noteURL = root.appendingPathComponent("note.md")
    try "I called the clinic today".write(to: noteURL, atomically: true, encoding: .utf8)

    try await svc.replaceTextWithLink(at: noteURL, textToFind: "clinic", targetEntity: "City Clinic")
    let content = try String(contentsOf: noteURL, encoding: .utf8)
    #expect(content.contains("[[") && content.contains("City Clinic"))

    // Missing text → textNotFound.
    await #expect(throws: KnowledgeBaseError.self) {
        try await svc.replaceTextWithLink(at: noteURL, textToFind: "nonexistent", targetEntity: "X")
    }
}

@Test func kbservice_replaceTextWithLink_missing_note_throws() async {
    let (svc, root) = makeService()
    defer { try? FileManager.default.removeItem(at: root) }
    let missing = root.appendingPathComponent("nope.md")
    await #expect(throws: KnowledgeBaseError.self) {
        try await svc.replaceTextWithLink(at: missing, textToFind: "x", targetEntity: "Y")
    }
}

@Test func kbservice_editNoteBody_missing_note_throws() async {
    let (svc, root) = makeService()
    defer { try? FileManager.default.removeItem(at: root) }
    await #expect(throws: KnowledgeBaseError.self) {
        try await svc.editNoteBody(at: root.appendingPathComponent("nope.md"), newBody: "x")
    }
}

@Test func kbservice_editNoteBody_rewrites_body_of_real_note() async throws {
    let (svc, root) = makeService()
    defer { try? FileManager.default.removeItem(at: root) }

    // Build a note in the canonical format so the body region is detectable.
    let fs = KnowledgeBaseFilesystem(notesURL: root.appendingPathComponent("notes"), rootURL: root)
    let taskId = UUID()
    let folder = await fs.ensureTaskFolder(taskId: taskId, title: "T")
    await fs.writeNote(
        GeneratedKnowledgeNote(title: "Note", body: "old body text"),
        filename: "01-note.md", taskId: taskId, parentTitle: "T",
        folderURL: folder, sourceSubtaskTitle: "Step"
    )
    let noteURL = folder.appendingPathComponent("01-note.md")

    try await svc.editNoteBody(at: noteURL, newBody: "brand new body")
    let content = try String(contentsOf: noteURL, encoding: .utf8)
    #expect(content.contains("brand new body"))
    #expect(!content.contains("old body text"))
}

// MARK: - generateSummary

@Test func kbservice_generateSummary_empty() async throws {
    let (svc, root) = makeService()
    defer { try? FileManager.default.removeItem(at: root) }
    let summary = try await svc.generateSummary()
    #expect(summary.contains("empty"))
}

@Test func kbservice_generateSummary_lists_tasks_and_entities() async throws {
    let (svc, root) = makeService()
    defer { try? FileManager.default.removeItem(at: root) }

    let task = TodoTask(title: "Garden Project", originalInput: "garden")
    svc.handleTaskCreatedOrUpdated(task)
    _ = await waitForFile(svc.indexURL)
    try? await svc.createEntity(name: "Compost Bin", body: "A bin.")

    let summary = try await svc.generateSummary()
    #expect(summary.contains("Garden Project"))
    #expect(summary.contains("Compost Bin"))
}

// MARK: - cleanupOrphanedNotes

@Test func kbservice_cleanup_removes_orphan_folders_and_unlinked_entities() async {
    let (svc, root) = makeService()
    defer { try? FileManager.default.removeItem(at: root) }

    let liveTask = TodoTask(title: "Keep Me", originalInput: "keep")
    let orphanTask = TodoTask(title: "Delete Me", originalInput: "delete")
    svc.handleTaskCreatedOrUpdated(liveTask)
    svc.handleTaskCreatedOrUpdated(orphanTask)
    _ = await waitForFile(svc.indexURL)
    // Wait until both task folders exist.
    let notesDir = root.appendingPathComponent("notes")
    _ = await waitForFile(notesDir.appendingPathComponent("\(orphanTask.id.uuidString)__delete-me"))

    try? await svc.createEntity(name: "Lonely Entity", body: "no backlinks")

    let (folders, entities) = await svc.cleanupOrphanedNotes(existingTaskIds: [liveTask.id])
    #expect(folders == 1)      // orphanTask folder deleted
    #expect(entities == 1)     // unlinked entity deleted

    // The kept task survives.
    #expect(FileManager.default.fileExists(atPath: notesDir.appendingPathComponent("\(liveTask.id.uuidString)__keep-me").path))
}

// MARK: - buildGraphData / backlinks / loadAllEntries

@Test func kbservice_buildGraphData_returns_nodes_for_existing_notes() async {
    let (svc, root) = makeService()
    defer { try? FileManager.default.removeItem(at: root) }

    let task = TodoTask(title: "Graph Task", originalInput: "graph")
    svc.handleTaskCreatedOrUpdated(task)
    _ = await waitForFile(svc.indexURL)

    let graph = await svc.buildGraphData()
    #expect(graph.nodes.contains { $0.title == "Graph Task" && $0.kind == "topLevelTask" })
}

@Test func kbservice_loadAllEntries_returns_created_tasks() async {
    let (svc, root) = makeService()
    defer { try? FileManager.default.removeItem(at: root) }

    let task = TodoTask(title: "Loaded Task", originalInput: "load")
    svc.handleTaskCreatedOrUpdated(task)
    _ = await waitForFile(svc.indexURL)

    let entries = await svc.loadAllEntries()
    #expect(entries.contains { $0.title == "Loaded Task" })
}

@Test func kbservice_backlinks_finds_linking_notes() async throws {
    let (svc, root) = makeService()
    defer { try? FileManager.default.removeItem(at: root) }

    // Create an entity and a note that links to it.
    try? await svc.createEntity(name: "Linked Entity", body: "x")
    let fs = KnowledgeBaseFilesystem(notesURL: root.appendingPathComponent("notes"), rootURL: root)
    let taskId = UUID()
    let folder = await fs.ensureTaskFolder(taskId: taskId, title: "T")
    let slug = KnowledgeBaseFilesystem.slug(from: "Linked Entity")
    let wikilink = KnowledgeBaseFilesystem.entityWikilink(targetEntity: "Linked Entity", noteIsInEntitiesFolder: false)
    await fs.writeNote(
        GeneratedKnowledgeNote(title: "Note", body: "I mention \(wikilink) here"),
        filename: "01-note.md", taskId: taskId, parentTitle: "T",
        folderURL: folder, sourceSubtaskTitle: "Step"
    )

    let backlinks = await svc.backlinks(toEntitySlug: slug)
    #expect(backlinks.contains { $0.noteTitle == "Note" })
}
