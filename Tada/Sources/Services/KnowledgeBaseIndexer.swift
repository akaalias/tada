import Foundation

// MARK: - Knowledge Entry Model

struct KnowledgeEntry: Identifiable {
    let taskId: UUID
    let title: String
    let completedAt: Date
    let summary: String
    let folderURL: URL
    let notes: [KnowledgeNoteFile]

    var id: UUID { taskId }
}

struct KnowledgeNoteFile: Identifiable {
    let title: String
    let fileURL: URL

    var id: String { fileURL.path }
}

// MARK: - Indexer

/// Manages loading knowledge entries and regenerating the global index.
final actor KnowledgeBaseIndexer {
    private let notesURL: URL
    private let indexURL: URL
    private let filesystem: KnowledgeBaseFilesystem

    init(notesURL: URL, indexURL: URL, filesystem: KnowledgeBaseFilesystem) {
        self.notesURL = notesURL
        self.indexURL = indexURL
        self.filesystem = filesystem
    }

    func loadAllEntries() async -> [KnowledgeEntry] {
        let folders = await filesystem.listTaskFolders()
        var entries: [KnowledgeEntry] = []

        for url in folders {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if let entry = await loadEntry(at: url) {
                entries.append(entry)
            }
        }

        return entries.sorted { $0.completedAt > $1.completedAt }
    }

    func regenerateGlobalIndex() async {
        let entries = await loadAllEntries()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var lines: [String] = [
            "# Knowledge Base",
            "",
            "An auto-growing wiki of every task and sub-task captured in Tada.",
            ""
        ]

        let activeEntries = entries.filter { $0.summary == "In progress" }
        let completedEntries = entries.filter { $0.summary != "In progress" }

        if !activeEntries.isEmpty {
            lines.append("## In progress")
            lines.append("")
            for entry in activeEntries {
                let folderName = entry.folderURL.lastPathComponent
                let overviewPath = "notes/\(folderName)/_overview.md"
                lines.append("- [[\(overviewPath)|\(entry.title)]] — started \(dateFormatter.string(from: entry.completedAt)) · \(entry.notes.count) note\(entry.notes.count == 1 ? "" : "s")")
            }
            lines.append("")
        }

        if !completedEntries.isEmpty {
            lines.append("## Completed")
            lines.append("")
            for entry in completedEntries {
                let folderName = entry.folderURL.lastPathComponent
                let overviewPath = "notes/\(folderName)/_overview.md"
                lines.append("- [[\(overviewPath)|\(entry.title)]] — completed \(dateFormatter.string(from: entry.completedAt)) · \(entry.notes.count) note\(entry.notes.count == 1 ? "" : "s")")
            }
            lines.append("")
        }

        let entities = await filesystem.listEntities()
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        if !entities.isEmpty {
            lines.append("## Entities")
            lines.append("")
            for entity in entities {
                let entityPath = "notes/\(KnowledgeBaseFilesystem.entitiesFolderName)/\(entity.slug).md"
                lines.append("- [[\(entityPath)|\(entity.title)]]")
            }
            lines.append("")
        }

        if entries.isEmpty && entities.isEmpty {
            lines.append("_No tasks yet. Create one and it will appear here._")
        }

        await filesystem.writeIndex(lines: lines, to: indexURL)
    }

    // MARK: - Private

    private func loadEntry(at folderURL: URL) async -> KnowledgeEntry? {
        let overviewURL = folderURL.appendingPathComponent("_overview.md")
        guard let raw = try? String(contentsOf: overviewURL, encoding: .utf8) else { return nil }

        let meta = await filesystem.parseFrontmatter(raw)
        guard let taskIdString = meta["taskId"],
              let taskId = UUID(uuidString: taskIdString),
              let title = meta["title"] else {
            return nil
        }
        let iso = ISO8601DateFormatter()
        let createdAt: Date = meta["createdAt"].flatMap { iso.date(from: $0) } ?? Date()
        let completedAt: Date? = meta["completedAt"].flatMap { iso.date(from: $0) }
        let sortDate = completedAt ?? createdAt

        let noteURLs = await filesystem.listNoteFiles(in: folderURL)
        var notes: [KnowledgeNoteFile] = []

        for url in noteURLs where url.pathExtension == "md" && url.lastPathComponent != "_overview.md" {
            let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let noteMeta = await filesystem.parseFrontmatter(body)
            let noteTitle = noteMeta["title"] ?? url.deletingPathExtension().lastPathComponent
            notes.append(KnowledgeNoteFile(title: noteTitle, fileURL: url))
        }

        notes.sort { $0.fileURL.lastPathComponent < $1.fileURL.lastPathComponent }

        return KnowledgeEntry(
            taskId: taskId,
            title: title,
            completedAt: sortDate,
            summary: meta["status"] == "completed" ? "Completed" : "In progress",
            folderURL: folderURL,
            notes: notes
        )
    }
}
