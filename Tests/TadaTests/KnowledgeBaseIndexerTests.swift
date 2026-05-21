import Foundation
import Testing
@testable import Tada

// MARK: - Helpers

@MainActor
private func makeIndexerEnv() -> (fs: KnowledgeBaseFilesystem, indexer: KnowledgeBaseIndexer, root: URL, notes: URL, index: URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("KBIndexerTests")
        .appendingPathComponent(UUID().uuidString)
    let notes = root.appendingPathComponent("notes", isDirectory: true)
    let index = root.appendingPathComponent("index.md")
    try? FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
    let fs = KnowledgeBaseFilesystem(notesURL: notes, rootURL: root)
    let indexer = KnowledgeBaseIndexer(notesURL: notes, indexURL: index, filesystem: fs)
    return (fs, indexer, root, notes, index)
}

// MARK: - loadAllEntries

@Test func indexer_loadAllEntries_empty_when_no_folders() async {
    let env = await makeIndexerEnv()
    defer { try? FileManager.default.removeItem(at: env.root) }
    let entries = await env.indexer.loadAllEntries()
    #expect(entries.isEmpty)
}

@Test func indexer_loadAllEntries_reads_overview_metadata() async {
    let env = await makeIndexerEnv()
    defer { try? FileManager.default.removeItem(at: env.root) }

    let taskId = UUID()
    let folder = await env.fs.ensureTaskFolder(taskId: taskId, title: "Plan Trip")
    await env.fs.writeOverview(
        taskId: taskId, title: "Plan Trip", description: "A trip", originalInput: "plan trip",
        createdAt: Date(timeIntervalSince1970: 1_000_000), completedAt: nil,
        status: .active, folderURL: folder
    )

    let entries = await env.indexer.loadAllEntries()
    #expect(entries.count == 1)
    #expect(entries.first?.title == "Plan Trip")
    #expect(entries.first?.summary == "In progress")
    #expect(entries.first?.taskId == taskId)
}

@Test func indexer_loadAllEntries_marks_completed_and_counts_notes() async {
    let env = await makeIndexerEnv()
    defer { try? FileManager.default.removeItem(at: env.root) }

    let taskId = UUID()
    let folder = await env.fs.ensureTaskFolder(taskId: taskId, title: "Done Task")
    // Write a sub-task note so the entry has a note count > 0.
    await env.fs.writeNote(
        GeneratedKnowledgeNote(title: "Step note", body: "did the thing"),
        filename: "01-step-note.md", taskId: taskId, parentTitle: "Done Task",
        folderURL: folder, sourceSubtaskTitle: "Step"
    )
    await env.fs.writeOverview(
        taskId: taskId, title: "Done Task", description: "", originalInput: "do task",
        createdAt: Date(timeIntervalSince1970: 2_000_000),
        completedAt: Date(timeIntervalSince1970: 2_500_000),
        status: .completed, folderURL: folder
    )

    let entries = await env.indexer.loadAllEntries()
    #expect(entries.first?.summary == "Completed")
    #expect(entries.first?.notes.count == 1)
    #expect(entries.first?.notes.first?.title == "Step note")
}

@Test func indexer_loadEntry_skips_folder_without_overview() async {
    let env = await makeIndexerEnv()
    defer { try? FileManager.default.removeItem(at: env.root) }
    // Create a task folder but no _overview.md.
    _ = await env.fs.ensureTaskFolder(taskId: UUID(), title: "No Overview")
    let entries = await env.indexer.loadAllEntries()
    #expect(entries.isEmpty)
}

// MARK: - regenerateGlobalIndex

@Test func indexer_regenerate_empty_index_has_placeholder() async {
    let env = await makeIndexerEnv()
    defer { try? FileManager.default.removeItem(at: env.root) }

    await env.indexer.regenerateGlobalIndex()
    let content = try? String(contentsOf: env.index, encoding: .utf8)
    #expect(content?.contains("# Knowledge Base") == true)
    #expect(content?.contains("_No tasks yet.") == true)
}

@Test func indexer_regenerate_lists_in_progress_completed_and_entities() async throws {
    let env = await makeIndexerEnv()
    defer { try? FileManager.default.removeItem(at: env.root) }

    // One in-progress task.
    let activeId = UUID()
    let activeFolder = await env.fs.ensureTaskFolder(taskId: activeId, title: "Active Task")
    await env.fs.writeOverview(
        taskId: activeId, title: "Active Task", description: "", originalInput: "x",
        createdAt: Date(), completedAt: nil, status: .active, folderURL: activeFolder
    )

    // One completed task.
    let doneId = UUID()
    let doneFolder = await env.fs.ensureTaskFolder(taskId: doneId, title: "Completed Task")
    await env.fs.writeOverview(
        taskId: doneId, title: "Completed Task", description: "", originalInput: "y",
        createdAt: Date(), completedAt: Date(), status: .completed, folderURL: doneFolder
    )

    // One entity.
    await env.fs.writeEntityNote(slug: "dr-smith", displayName: "Dr. Smith", body: "A doctor")

    await env.indexer.regenerateGlobalIndex()
    let content = try #require(try? String(contentsOf: env.index, encoding: .utf8))

    #expect(content.contains("## In progress"))
    #expect(content.contains("Active Task"))
    #expect(content.contains("## Completed"))
    #expect(content.contains("Completed Task"))
    #expect(content.contains("## Entities"))
    #expect(content.contains("Dr. Smith"))
    #expect(content.contains("notes/\(KnowledgeBaseFilesystem.entitiesFolderName)/dr-smith.md"))
}
