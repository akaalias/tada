import Foundation

// MARK: - Filesystem Operations

/// Handles all file system operations for the knowledge base.
final actor KnowledgeBaseFilesystem {
    let rootURL: URL
    private let notesURL: URL
    private let entitiesURL: URL

    static let entitiesFolderName = "_entities"
    static let userNotesFolderName = "_notes"

    private let userNotesURL: URL

    init(notesURL: URL, rootURL: URL) {
        self.notesURL = notesURL
        self.rootURL = rootURL
        self.entitiesURL = notesURL.appendingPathComponent(Self.entitiesFolderName, isDirectory: true)
        self.userNotesURL = notesURL.appendingPathComponent(Self.userNotesFolderName, isDirectory: true)
    }

    // MARK: - Folder management

    func ensureTaskFolder(taskId: UUID, title: String) -> URL {
        let fm = FileManager.default
        let desiredName = folderName(taskId: taskId, title: title)
        let desired = notesURL.appendingPathComponent(desiredName, isDirectory: true)

        // Look for any existing folder for this task (the slug may have changed if the title changed).
        let existing = (try? fm.contentsOfDirectory(at: notesURL, includingPropertiesForKeys: nil))?
            .first { $0.lastPathComponent.hasPrefix("\(taskId.uuidString)__") }

        if let existing {
            if existing.lastPathComponent != desiredName {
                try? fm.moveItem(at: existing, to: desired)
                return desired
            }
            return existing
        }

        try? fm.createDirectory(at: desired, withIntermediateDirectories: true)
        return desired
    }

    func listNoteFiles(in folderURL: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil))
            ?? []
    }

    func listTaskFolders() -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: notesURL, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.lastPathComponent != Self.entitiesFolderName && $0.lastPathComponent != Self.userNotesFolderName }
    }

    // MARK: - User Notes

    func ensureUserNotesFolder() -> URL {
        try? FileManager.default.createDirectory(at: userNotesURL, withIntermediateDirectories: true)
        return userNotesURL
    }

    func listUserNoteFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: userNotesURL, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }
    }

    func listUserNotes() -> [(slug: String, title: String)] {
        let files = listUserNoteFiles()
        return files.compactMap { url -> (String, String)? in
            let slug = url.deletingPathExtension().lastPathComponent
            let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let title = parseFrontmatter(body)["title"] ?? slug
            return (slug, title)
        }
    }

    @discardableResult
    func writeUserNote(slug: String, title: String, body: String) -> URL {
        _ = ensureUserNotesFolder()
        let fileURL = userNotesURL.appendingPathComponent("\(slug).md")
        let content = """
        ---
        title: \(escapeFrontmatter(title))
        kind: userNote
        slug: \(slug)
        created: \(ISO8601DateFormatter().string(from: Date()))
        ---

        # \(title)

        \(body)

        <!-- tada:related:start -->
        <!-- tada:related:end -->

        ---
        Back to [[../../index.md|Knowledge Base index]]
        """
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - Entities

    func ensureEntitiesFolder() -> URL {
        try? FileManager.default.createDirectory(at: entitiesURL, withIntermediateDirectories: true)
        return entitiesURL
    }

    /// Canonical slug for a title or display name: lowercase, alphanumeric, hyphen-separated, max 48 chars.
    nonisolated static func slug(from displayName: String) -> String {
        let lowered = displayName.lowercased()
        let allowed = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "-"
        }
        let collapsed = String(allowed).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return String(collapsed.prefix(48))
    }

    /// Returns existing entity refs (slug + title) for prompting the AI.
    func listEntities() -> [(slug: String, title: String)] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: entitiesURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.compactMap { url -> (String, String)? in
            guard url.pathExtension == "md" else { return nil }
            let slug = url.deletingPathExtension().lastPathComponent
            let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let title = parseFrontmatter(body)["title"] ?? slug
            return (slug, title)
        }
    }

    /// Returns the URLs of every entity note file (`_entities/<slug>.md`).
    func listEntityFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: entitiesURL, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }
    }

    /// Writes an entity note. Returns true if a new file was created, false if the slug already existed.
    @discardableResult
    func writeEntityNote(slug: String, displayName: String, body: String) -> Bool {
        _ = ensureEntitiesFolder()
        let fileURL = entitiesURL.appendingPathComponent("\(slug).md")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return false
        }
        let content = """
        ---
        title: \(escapeFrontmatter(displayName))
        kind: entity
        slug: \(slug)
        ---

        # \(displayName)

        \(body)

        <!-- tada:related:start -->
        <!-- tada:related:end -->

        ---
        Back to [[../../index.md|Knowledge Base index]]
        """
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        return true
    }

    /// Path prefix for entity links from notes inside a task folder.
    /// Task notes live at `notes/<taskFolder>/<file>.md`; entities live at `notes/_entities/<slug>.md`.
    nonisolated static let entityLinkPrefix = "../\(KnowledgeBaseFilesystem.entitiesFolderName)/"

    /// Builds a wikilink to an entity note. Every non-entity note (task notes, overviews, user
    /// notes) lives one folder deep under `notes/`, so the link climbs one level with
    /// `entityLinkPrefix`. From a sibling entity note it's just the bare filename.
    nonisolated static func entityWikilink(targetEntity: String, noteIsInEntitiesFolder: Bool) -> String {
        let prefix = noteIsInEntitiesFolder ? "" : entityLinkPrefix
        return "[[\(prefix)\(slug(from: targetEntity)).md|\(targetEntity)]]"
    }

    /// Walks every note in the wiki and returns the inputs needed to build the graph payload.
    /// One pass over the disk: cheaper than iterating per-folder from outside the actor.
    func collectGraphInputs() -> [KnowledgeGraphBuilder.NoteInput] {
        var inputs: [KnowledgeGraphBuilder.NoteInput] = []

        // Task folders + their notes.
        for folder in listTaskFolders() {
            let folderRel = relativePath(from: rootURL, to: folder)
            let files = listNoteFiles(in: folder)
            for url in files where url.pathExtension == "md" {
                guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let meta = Self.parseFrontmatter(raw)
                let title = meta["title"] ?? url.deletingPathExtension().lastPathComponent
                let isOverview = url.lastPathComponent == "_overview.md"
                inputs.append(.init(
                    relativePath: relativePath(from: rootURL, to: url),
                    title: title,
                    isOverview: isOverview,
                    isEntity: false,
                    isUserNote: false,
                    folderRelativePath: folderRel,
                    body: raw,
                    taskId: meta["taskId"]
                ))
            }
        }

        // Entity notes.
        let entitiesFolderRel = "notes/\(Self.entitiesFolderName)"
        let entityFiles = (try? FileManager.default.contentsOfDirectory(at: entitiesURL, includingPropertiesForKeys: nil)) ?? []
        for url in entityFiles where url.pathExtension == "md" {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let meta = Self.parseFrontmatter(raw)
            let title = meta["title"] ?? url.deletingPathExtension().lastPathComponent
            inputs.append(.init(
                relativePath: relativePath(from: rootURL, to: url),
                title: title,
                isOverview: false,
                isEntity: true,
                isUserNote: false,
                folderRelativePath: entitiesFolderRel,
                body: raw,
                taskId: meta["taskId"]
            ))
        }

        // User notes.
        let userNotesFolderRel = "notes/\(Self.userNotesFolderName)"
        let userNoteFiles = listUserNoteFiles()
        for url in userNoteFiles {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let meta = Self.parseFrontmatter(raw)
            let title = meta["title"] ?? url.deletingPathExtension().lastPathComponent
            inputs.append(.init(
                relativePath: relativePath(from: rootURL, to: url),
                title: title,
                isOverview: false,
                isEntity: false,
                isUserNote: true,
                folderRelativePath: userNotesFolderRel,
                body: raw,
                taskId: nil
            ))
        }

        return inputs
    }

    /// Scans every task-folder note and entity file for wikilinks to the entity at `slug` and returns the backlinks
    /// in title-sorted order. Used by the wiki view to render an entity note's "Backlinks" section.
    func backlinks(toEntitySlug slug: String) -> [KnowledgeBaseEntityLinker.Backlink] {
        var results: [KnowledgeBaseEntityLinker.Backlink] = []

        // Scan task folders
        let folders = listTaskFolders()
        for folder in folders {
            let files = listNoteFiles(in: folder)
            let overviewURL = folder.appendingPathComponent("_overview.md")
            let overviewBody = (try? String(contentsOf: overviewURL, encoding: .utf8)) ?? ""
            let taskTitle = Self.parseFrontmatter(overviewBody)["title"]

            for url in files where url.pathExtension == "md" && url.lastPathComponent != "_overview.md" {
                guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
                if !KnowledgeBaseEntityLinker.bodyContainsEntityLink(raw, entitySlug: slug) { continue }
                let meta = Self.parseFrontmatter(raw)
                let noteTitle = meta["title"] ?? url.deletingPathExtension().lastPathComponent
                results.append(.init(fileURL: url, noteTitle: noteTitle, taskTitle: taskTitle))
            }
        }

        // Scan entity files (for entity-to-entity links)
        let entityFiles = listEntityFiles()
        for url in entityFiles {
            // Skip the entity itself
            if url.deletingPathExtension().lastPathComponent == slug { continue }
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if !KnowledgeBaseEntityLinker.bodyContainsEntityLink(raw, entitySlug: slug) { continue }
            let meta = Self.parseFrontmatter(raw)
            let noteTitle = meta["title"] ?? url.deletingPathExtension().lastPathComponent
            results.append(.init(fileURL: url, noteTitle: noteTitle, taskTitle: nil))
        }

        return results.sorted { $0.noteTitle.localizedCaseInsensitiveCompare($1.noteTitle) == .orderedAscending }
    }

    // MARK: - Note writing

    func writeNote(
        _ note: GeneratedKnowledgeNote,
        filename: String,
        taskId: UUID,
        parentTitle: String,
        folderURL: URL,
        sourceSubtaskTitle: String?,
        originalInput: String? = nil
    ) {
        let subtaskField = sourceSubtaskTitle.map { "subtaskTitle: \(escapeFrontmatter($0))\n" } ?? ""
        let trimmedOriginal = originalInput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let originalSection = trimmedOriginal.isEmpty
            ? ""
            : "\n## Original input\n\n\(trimmedOriginal)\n"
        let content = """
        ---
        title: \(escapeFrontmatter(note.title))
        taskId: \(taskId.uuidString)
        \(subtaskField)---

        # \(note.title)

        \(note.body)
        \(originalSection)
        <!-- tada:related:start -->
        <!-- tada:related:end -->

        ---
        Back to [[_overview.md|\(parentTitle)]]
        """
        try? content.write(to: folderURL.appendingPathComponent(filename), atomically: true, encoding: .utf8)
    }

    func writeOverview(
        taskId: UUID,
        title: String,
        description: String,
        originalInput: String,
        createdAt: Date,
        completedAt: Date?,
        status: TaskStatus,
        folderURL: URL
    ) {
        let iso = ISO8601DateFormatter()

        // List all note files currently on disk for this task, sorted.
        let noteURLs = listNoteFiles(in: folderURL)
        let notes = noteURLs
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "_overview.md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url -> (title: String, filename: String) in
                let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                let meta = parseFrontmatter(body)
                let noteTitle = meta["title"] ?? url.deletingPathExtension().lastPathComponent
                return (noteTitle, url.lastPathComponent)
            }

        let noteListLines = notes.map { entry in
            "- [[\(entry.filename)|\(entry.title)]]"
        }.joined(separator: "\n")

        let completedLine = completedAt.map { "completedAt: \(iso.string(from: $0))\n" } ?? ""

        let bodyDescription = description.isEmpty
            ? originalInput
            : description

        let overview = """
        ---
        taskId: \(taskId.uuidString)
        title: \(escapeFrontmatter(title))
        status: \(status)
        createdAt: \(iso.string(from: createdAt))
        \(completedLine)---

        # \(title)

        \(bodyDescription.isEmpty ? "" : bodyDescription + "\n")
        > Original request: \(originalInput)

        ## Sub-task notes

        \(noteListLines.isEmpty ? "_None yet — sub-task notes will appear here as you answer questions and complete steps._" : noteListLines)

        ## Back

        [[../../index.md|Knowledge Base index]]
        """

        try? overview.write(to: folderURL.appendingPathComponent("_overview.md"), atomically: true, encoding: .utf8)
    }

    func writeIndex(lines: [String], to url: URL) {
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Frontmatter parsing

    func parseFrontmatter(_ raw: String) -> [String: String] {
        Self.parseFrontmatter(raw)
    }

    /// Nonisolated static parser so callers outside the actor (e.g. views) can read frontmatter
    /// without bouncing through actor isolation.
    nonisolated static func parseFrontmatter(_ raw: String) -> [String: String] {
        guard raw.hasPrefix("---") else { return [:] }
        let trimmed = raw.dropFirst(3)
        guard let endRange = trimmed.range(of: "\n---") else { return [:] }
        let block = trimmed[..<endRange.lowerBound]
        var result: [String: String] = [:]
        for rawLine in block.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
                value = value.replacingOccurrences(of: "\\\"", with: "\"")
            }
            result[key] = value
        }
        return result
    }

    func stripFrontmatterAndMarkers(_ raw: String) -> String {
        var text = raw
        // Strip frontmatter
        if text.hasPrefix("---") {
            let rest = text.dropFirst(3)
            if let endRange = rest.range(of: "\n---") {
                text = String(rest[endRange.upperBound...])
            }
        }
        // Strip everything between related markers (don't feed our own suggestions back to the AI).
        if let regex = try? NSRegularExpression(
            pattern: "<!-- tada:related:start -->[\\s\\S]*?<!-- tada:related:end -->",
            options: []
        ) {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(location: 0, length: (text as NSString).length),
                withTemplate: ""
            )
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Path utilities

    func relativePath(from sourceDir: URL, to target: URL) -> String {
        let srcParts = sourceDir.standardizedFileURL.pathComponents
        let tgtParts = target.standardizedFileURL.pathComponents
        var common = 0
        while common < srcParts.count && common < tgtParts.count && srcParts[common] == tgtParts[common] {
            common += 1
        }
        let upCount = srcParts.count - common
        let downParts = tgtParts.dropFirst(common)
        let ups = Array(repeating: "..", count: upCount)
        return (ups + Array(downParts)).joined(separator: "/")
    }

    // MARK: - Private helpers

    private func folderName(taskId: UUID, title: String) -> String {
        let slug = Self.slug(from: title)
        return "\(taskId.uuidString)__\(slug.isEmpty ? "task" : slug)"
    }

    private func subtaskFilename(_ order: Int, _ title: String) -> String {
        // order is 0-based across both phases; +1 keeps "00-" reserved for the task overview note.
        return String(format: "%02d-%@.md", order + 1, Self.slug(from: title))
    }

    private func imageFilename(for order: Int, _ title: String) -> String {
        return String(format: "%02d-%@.png", order + 1, Self.slug(from: title))
    }

    private func escapeFrontmatter(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    func subtaskFilename(for snap: (id: UUID, order: Int, title: String)) -> String {
        subtaskFilename(snap.order, snap.title)
    }

    func imageFilename(for order: Int, title: String) -> String {
        imageFilename(for: order, title)
    }

    // MARK: - Cleanup

    /// Extracts the taskId UUID from a task folder name (format: `<UUID>__<slug>`).
    nonisolated static func taskId(fromFolderName name: String) -> UUID? {
        let parts = name.split(separator: "_", maxSplits: 2)
        guard let first = parts.first else { return nil }
        return UUID(uuidString: String(first))
    }

    /// Deletes a task folder and all its contents.
    func deleteTaskFolder(_ folderURL: URL) {
        try? FileManager.default.removeItem(at: folderURL)
    }

    /// Deletes an entity note file.
    func deleteEntityNote(_ fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Checks if any task-folder note links to the given entity slug.
    func hasBacklinks(toEntitySlug slug: String) -> Bool {
        let folders = listTaskFolders()
        for folder in folders {
            let files = listNoteFiles(in: folder)
            for url in files where url.pathExtension == "md" {
                guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
                if KnowledgeBaseEntityLinker.bodyContainsEntityLink(raw, entitySlug: slug) {
                    return true
                }
            }
        }
        return false
    }
}
