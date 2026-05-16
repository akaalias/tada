import Foundation
import SwiftUI

// MARK: - Knowledge Base Coordinator

/// Thin coordinator that wires together filesystem, generation, indexing, and link discovery.
/// Exposes the public trigger API used by views and view models.
final class KnowledgeBaseService: ObservableObject {
    static let shared = KnowledgeBaseService()

    @MainActor @Published private(set) var isWorking: Bool = false
    @MainActor private var inFlightCount: Int = 0

    private let filesystem: KnowledgeBaseFilesystem
    private let generator: KnowledgeBaseGenerator
    private let indexer: KnowledgeBaseIndexer
    private let linkDiscovery: KnowledgeBaseLinkDiscovery

    // Exposed for read-only access (e.g. views, tests)
    let rootURL: URL
    let indexURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Tada", isDirectory: true)
        rootURL = appFolder.appendingPathComponent("knowledge", isDirectory: true)
        let notesURL = rootURL.appendingPathComponent("notes", isDirectory: true)
        indexURL = rootURL.appendingPathComponent("index.md")

        try? FileManager.default.createDirectory(at: notesURL, withIntermediateDirectories: true)

        self.filesystem = KnowledgeBaseFilesystem(notesURL: notesURL, rootURL: rootURL)
        self.generator = KnowledgeBaseGenerator(filesystem: filesystem)
        self.indexer = KnowledgeBaseIndexer(notesURL: notesURL, indexURL: indexURL, filesystem: filesystem)
        self.linkDiscovery = KnowledgeBaseLinkDiscovery(filesystem: filesystem)
    }

    // MARK: - Work tracking

    private func beginWork() {
        Task { @MainActor in
            inFlightCount += 1
            isWorking = inFlightCount > 0
        }
    }

    private func endWork() {
        Task { @MainActor in
            inFlightCount = max(0, inFlightCount - 1)
            isWorking = inFlightCount > 0
        }
    }

    // MARK: - Triggers

    /// Called right after a new task is created (or its title/description is refined by the planner).
    /// Writes a stub `_overview.md` page for the task so the wiki has an entry from day one.
    /// No AI call — this is purely structural.
    func handleTaskCreatedOrUpdated(_ task: TodoTask) {
        Task {
            let folder = await filesystem.ensureTaskFolder(taskId: task.id, title: task.title)
            await filesystem.writeOverview(
                taskId: task.id,
                title: task.title,
                description: task.taskDescription,
                originalInput: task.originalInput,
                createdAt: task.createdAt,
                completedAt: task.completedAt,
                status: task.status,
                folderURL: folder
            )
            await indexer.regenerateGlobalIndex()
            NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
        }
    }

    /// Ensures every supplied task has a wiki folder + overview file. Used on app launch to back-fill
    /// tasks that existed before the wiki feature.
    func reconcile(tasks: [TodoTask]) {
        for task in tasks {
            handleTaskCreatedOrUpdated(task)
        }
    }

    /// Called right after a sub-task is marked completed. Generates the atomic note for that
    /// sub-task (and back-fills any earlier completed sub-tasks that are missing a note file).
    /// No-op if no API key is configured.
    func handleSubtaskCompleted(_ subTask: SubTask) {
        guard let parent = subTask.task else {
            print("[KnowledgeBase] Skipping sub-task note: no parent task")
            return
        }

        Task {
            // Always refresh the parent overview to pick up any title/structural changes, even if no
            // AI is available or no new notes are needed.
            let folder = await filesystem.ensureTaskFolder(taskId: parent.id, title: parent.title)
            await filesystem.writeOverview(
                taskId: parent.id,
                title: parent.title,
                description: parent.taskDescription,
                originalInput: parent.originalInput,
                createdAt: parent.createdAt,
                completedAt: parent.completedAt,
                status: parent.status,
                folderURL: folder
            )
            await indexer.regenerateGlobalIndex()
            NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
        }

        guard APIKeyManager.hasAPIKey else { return }

        Task {
            let folder = await filesystem.ensureTaskFolder(taskId: parent.id, title: parent.title)

            // Generate notes for every completed sub-task that doesn't yet have one on disk.
            var pending: [SubtaskSnapshot] = []
            for st in parent.sortedSubTasks where st.isCompleted {
                let snap = SubtaskSnapshot(from: st)
                let filename = await filesystem.subtaskFilename(for: (snap.id, snap.order, snap.title))
                let fileURL = folder.appendingPathComponent(filename)
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    pending.append(snap)
                }
            }

            guard !pending.isEmpty else { return }

            let taskId = parent.id
            let taskTitle = parent.title
            let description = parent.taskDescription
            let originalInput = parent.originalInput
            let createdAt = parent.createdAt
            let completedAt = parent.completedAt
            let status = parent.status

            print("[KnowledgeBase] Generating \(pending.count) sub-task note(s) for '\(taskTitle)'")

            beginWork()
            defer { endWork() }

            let writtenURLs = await generator.generateSubtaskNotes(pending, taskId: taskId, taskTitle: taskTitle, folderURL: folder)

            await filesystem.writeOverview(
                taskId: taskId,
                title: taskTitle,
                description: description,
                originalInput: originalInput,
                createdAt: createdAt,
                completedAt: completedAt,
                status: status,
                folderURL: folder
            )
            await indexer.regenerateGlobalIndex()
            NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)

            // Discover related notes for each freshly generated note. Runs after generation
            // (and its inline entity-extraction pass) so there is no race.
            await linkDiscovery.discoverLinks(forNotesAt: writtenURLs)
        }
    }

    /// Called right after a task is marked completed. Ensures any outstanding sub-task notes are
    /// generated, then generates the task-level overview note.
    func handleTaskCompleted(_ task: TodoTask) {
        let taskId = task.id
        let taskTitle = task.title
        let originalInput = task.originalInput
        let taskDescription = task.taskDescription
        let createdAt = task.createdAt
        let completedAt = task.completedAt ?? Date()
        let status = task.status

        let allCompletedSnapshots: [SubtaskSnapshot] = task.sortedSubTasks
            .filter { $0.isCompleted }
            .map { SubtaskSnapshot(from: $0) }

        // Always update overview to reflect completion even if AI is unavailable.
        Task {
            let folder = await filesystem.ensureTaskFolder(taskId: taskId, title: taskTitle)
            await filesystem.writeOverview(
                taskId: taskId,
                title: taskTitle,
                description: taskDescription,
                originalInput: originalInput,
                createdAt: createdAt,
                completedAt: completedAt,
                status: status,
                folderURL: folder
            )
            await indexer.regenerateGlobalIndex()
            NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
        }

        guard APIKeyManager.hasAPIKey else { return }

        Task {
            let folder = await filesystem.ensureTaskFolder(taskId: taskId, title: taskTitle)

            var pending: [SubtaskSnapshot] = []
            for snap in allCompletedSnapshots {
                let filename = await filesystem.subtaskFilename(for: (snap.id, snap.order, snap.title))
                let fileURL = folder.appendingPathComponent(filename)
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    pending.append(snap)
                }
            }

            print("[KnowledgeBase] Task completed: '\(taskTitle)' — \(pending.count) sub-task notes pending + 1 overview")

            let writtenSubtaskURLs = await generator.generateSubtaskNotes(pending, taskId: taskId, taskTitle: taskTitle, folderURL: folder)

            var subtaskSummaries: [(title: String, response: String, filename: String)] = []
            for snap in allCompletedSnapshots {
                let filename = await filesystem.subtaskFilename(for: (snap.id, snap.order, snap.title))
                subtaskSummaries.append((snap.title, KnowledgeResponseExtractor.responseString(for: snap.subTask), filename))
            }
            let overviewURL = await generator.generateTaskOverviewNote(
                taskId: taskId,
                taskTitle: taskTitle,
                originalInput: originalInput,
                taskDescription: taskDescription,
                subtaskSummaries: subtaskSummaries,
                folderURL: folder
            )

            await filesystem.writeOverview(
                taskId: taskId,
                title: taskTitle,
                description: taskDescription,
                originalInput: originalInput,
                createdAt: createdAt,
                completedAt: completedAt,
                status: status,
                folderURL: folder
            )
            await indexer.regenerateGlobalIndex()
            NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)

            // Discover related notes for each freshly generated note. Runs after generation
            // (and its inline entity-extraction pass) so there is no race.
            await linkDiscovery.discoverLinks(forNotesAt: writtenSubtaskURLs + (overviewURL.map { [$0] } ?? []))
        }
    }

    // MARK: - Reading

    func loadAllEntries() async -> [KnowledgeEntry] {
        await indexer.loadAllEntries()
    }

    func loadNoteContent(at url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - Link discovery

    /// Runs single-note link discovery for one note on demand (the "Discover Related Notes"
    /// toolbar button). Drives the `isWorking` indicator.
    func runLinkDiscoveryForNote(_ url: URL) async {
        beginWork()
        defer { endWork() }
        await linkDiscovery.discoverLinks(forNoteAt: url)
    }

    // MARK: - Graph data

    /// Builds the JSON payload that drives the force-directed graph view. Walks every note +
    /// entity on disk and emits `{nodes, links}`.
    func buildGraphData() async -> KnowledgeGraphData {
        let inputs = await filesystem.collectGraphInputs()
        return KnowledgeGraphBuilder.build(from: inputs)
    }

    // MARK: - Backlinks

    /// Returns the list of notes that link to the entity at `slug`, used by the wiki view to
    /// render a Backlinks section under entity notes.
    func backlinks(toEntitySlug slug: String) async -> [KnowledgeBaseEntityLinker.Backlink] {
        await filesystem.backlinks(toEntitySlug: slug)
    }

    // MARK: - Manual extraction

    /// Runs the entity-extraction pass on a single note (the one currently being viewed).
    /// Idempotent: notes already containing entity wikilinks are skipped. Drives the
    /// `isWorking` indicator and regenerates the index so new entities appear immediately.
    func runEntityExtractionForCurrentNote(_ url: URL) async {
        beginWork()
        defer { endWork() }
        let rewritten = await generator.runEntityExtraction(for: url)
        await indexer.regenerateGlobalIndex()
        NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
        // Chain link discovery off the extraction so the discovery AI sees the linked note.
        if rewritten {
            await linkDiscovery.discoverLinks(forNoteAt: url)
        }
    }

    // MARK: - Cleanup

    /// Removes orphaned notes from the knowledge base:
    /// - Task folders whose task no longer exists in SwiftData
    /// - Entity notes that have no backlinks from any task note
    /// Returns the count of deleted items.
    func cleanupOrphanedNotes(existingTaskIds: Set<UUID>) async -> (taskFolders: Int, entities: Int) {
        beginWork()
        defer { endWork() }

        var deletedFolders = 0
        var deletedEntities = 0

        // Clean up orphaned task folders
        let taskFolders = await filesystem.listTaskFolders()
        for folder in taskFolders {
            let folderName = folder.lastPathComponent
            guard let taskId = KnowledgeBaseFilesystem.taskId(fromFolderName: folderName) else { continue }
            if !existingTaskIds.contains(taskId) {
                await filesystem.deleteTaskFolder(folder)
                deletedFolders += 1
                print("[KnowledgeBase] Deleted orphaned task folder: \(folderName)")
            }
        }

        // Clean up orphaned entity notes
        let entityFiles = await filesystem.listEntityFiles()
        for entityURL in entityFiles {
            let slug = entityURL.deletingPathExtension().lastPathComponent
            let hasLinks = await filesystem.hasBacklinks(toEntitySlug: slug)
            if !hasLinks {
                await filesystem.deleteEntityNote(entityURL)
                deletedEntities += 1
                print("[KnowledgeBase] Deleted orphaned entity: \(slug)")
            }
        }

        if deletedFolders > 0 || deletedEntities > 0 {
            await indexer.regenerateGlobalIndex()
            NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
        }

        return (deletedFolders, deletedEntities)
    }

    // MARK: - Coach Actions

    /// Creates a new entity note in the knowledge base with the given name and body.
    func createEntity(name: String, body: String) async throws {
        beginWork()
        defer { endWork() }

        let slug = KnowledgeBaseFilesystem.entitySlug(from: name)
        let created = await filesystem.writeEntityNote(slug: slug, displayName: name, body: body)

        if created {
            await indexer.regenerateGlobalIndex()
        }
        NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
    }

    /// Adds a wikilink to the target entity at the end of a note.
    func addLinkToNote(at url: URL, targetEntity: String) async throws {
        beginWork()
        defer { endWork() }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw KnowledgeBaseError.noteNotFound
        }

        var content = try String(contentsOf: url, encoding: .utf8)

        let slug = targetEntity.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        let isInEntitiesFolder = url.deletingLastPathComponent().lastPathComponent == KnowledgeBaseFilesystem.entitiesFolderName
        let linkPath = isInEntitiesFolder ? "\(slug).md" : "_entities/\(slug).md"
        let wikilink = "[[\(linkPath)|\(targetEntity)]]"

        if content.contains(wikilink) {
            return
        }

        if content.contains("## Related") {
            content = content.replacingOccurrences(of: "## Related", with: "## Related\n\n- \(wikilink)")
        } else {
            content += "\n\n## Related\n\n- \(wikilink)"
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
    }

    /// Finds text in a note and replaces it with a wikilink to the target entity.
    func replaceTextWithLink(at url: URL, textToFind: String, targetEntity: String) async throws {
        beginWork()
        defer { endWork() }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw KnowledgeBaseError.noteNotFound
        }

        var content = try String(contentsOf: url, encoding: .utf8)

        guard content.contains(textToFind) else {
            throw KnowledgeBaseError.textNotFound
        }

        let slug = targetEntity.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        let isInEntitiesFolder = url.deletingLastPathComponent().lastPathComponent == KnowledgeBaseFilesystem.entitiesFolderName
        let linkPath = isInEntitiesFolder ? "\(slug).md" : "_entities/\(slug).md"
        let wikilink = "[[\(linkPath)|\(targetEntity)]]"

        content = content.replacingOccurrences(of: textToFind, with: wikilink)

        try content.write(to: url, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
    }

    /// Edits the body content of a note, preserving frontmatter and structural sections.
    func editNoteBody(at url: URL, newBody: String) async throws {
        beginWork()
        defer { endWork() }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw KnowledgeBaseError.noteNotFound
        }

        let raw = try String(contentsOf: url, encoding: .utf8)

        guard let (_, bodyRange) = KnowledgeBaseEntityLinker.extractBodyRegion(from: raw) else {
            throw KnowledgeBaseError.bodyNotFound
        }

        var content = raw
        content.replaceSubrange(bodyRange, with: "\n\(newBody)\n\n")

        try content.write(to: url, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
    }

    /// Generates a summary of the knowledge base by reading the index and summarizing entries.
    func generateSummary() async throws -> String {
        beginWork()
        defer { endWork() }

        let entries = await loadAllEntries()
        let entityFiles = await filesystem.listEntityFiles()

        if entries.isEmpty && entityFiles.isEmpty {
            return "Your knowledge base is empty. Complete some tasks to start building your personal wiki."
        }

        var summary = "Your knowledge base contains:\n\n"

        if !entries.isEmpty {
            summary += "Tasks (\(entries.count)):\n"
            for entry in entries.prefix(5) {
                summary += "- \(entry.title)\n"
            }
            if entries.count > 5 {
                summary += "- ... and \(entries.count - 5) more\n"
            }
            summary += "\n"
        }

        if !entityFiles.isEmpty {
            summary += "Entities (\(entityFiles.count)):\n"
            for entityURL in entityFiles.prefix(5) {
                let name = entityURL.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "-", with: " ")
                    .capitalized
                summary += "- \(name)\n"
            }
            if entityFiles.count > 5 {
                summary += "- ... and \(entityFiles.count - 5) more\n"
            }
        }

        return summary
    }

    // MARK: - User Notes

    func createUserNote(title: String, body: String) async -> URL {
        beginWork()
        defer { endWork() }

        let slug = title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .prefix(48)

        let url = await filesystem.writeUserNote(slug: String(slug), title: title, body: body)
        await indexer.regenerateGlobalIndex()
        NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
        return url
    }

    func listUserNotes() async -> [(slug: String, title: String)] {
        await filesystem.listUserNotes()
    }

    /// Searches for notes by name across entities and user notes. Returns matching note info.
    func searchNotes(query: String) async -> [(name: String, path: String, kind: String)] {
        let lowercaseQuery = query.lowercased()
        let queryWords = lowercaseQuery.split(separator: " ").map(String.init)

        var results: [(name: String, path: String, kind: String)] = []

        let entities = await filesystem.listEntities()
        for entity in entities {
            let nameLower = entity.title.lowercased()
            let slugLower = entity.slug.lowercased()
            if nameLower.contains(lowercaseQuery) || slugLower.contains(lowercaseQuery) ||
               queryWords.contains(where: { nameLower.contains($0) || slugLower.contains($0) }) {
                let path = "Knowledge/Entities/\(entity.title).md"
                results.append((name: entity.title, path: path, kind: "entity"))
            }
        }

        let userNotes = await filesystem.listUserNotes()
        for note in userNotes {
            let nameLower = note.title.lowercased()
            let slugLower = note.slug.lowercased()
            if nameLower.contains(lowercaseQuery) || slugLower.contains(lowercaseQuery) ||
               queryWords.contains(where: { nameLower.contains($0) || slugLower.contains($0) }) {
                let path = "Knowledge/Notes/\(note.title).md"
                results.append((name: note.title, path: path, kind: "userNote"))
            }
        }

        return results
    }
}

enum KnowledgeBaseError: LocalizedError {
    case noteNotFound
    case textNotFound
    case bodyNotFound

    var errorDescription: String? {
        switch self {
        case .noteNotFound:
            return "Note not found"
        case .textNotFound:
            return "Text not found in note"
        case .bodyNotFound:
            return "Could not find body section in note"
        }
    }
}

// MARK: - Subtask Snapshot (used by generator)

struct SubtaskSnapshot {
    let id: UUID
    let order: Int
    let phase: TaskPhase
    let title: String
    let description: String
    let response: String
    let imagePNG: Data?
    let tableMarkdown: String?
    var subTask: SubTask

    init(from subTask: SubTask) {
        self.id = subTask.id
        self.order = subTask.order
        self.phase = subTask.phase
        self.title = subTask.title
        self.description = subTask.subTaskDescription
        self.response = KnowledgeResponseExtractor.responseString(for: subTask)
        self.imagePNG = KnowledgeResponseExtractor.extractPNG(from: subTask)
        self.tableMarkdown = KnowledgeResponseExtractor.extractTableMarkdown(from: subTask)
        self.subTask = subTask
    }
}

extension Notification.Name {
    static let knowledgeBaseUpdated = Notification.Name("knowledgeBaseUpdated")
}
