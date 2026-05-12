import Foundation

// MARK: - Filesystem Operations

/// Handles all file system operations for the knowledge base.
final actor KnowledgeBaseFilesystem {
    let rootURL: URL
    private let notesURL: URL

    init(notesURL: URL, rootURL: URL) {
        self.notesURL = notesURL
        self.rootURL = rootURL
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
        (try? FileManager.default.contentsOfDirectory(at: notesURL, includingPropertiesForKeys: nil))
            ?? []
    }

    // MARK: - Note writing

    func writeNote(
        _ note: GeneratedKnowledgeNote,
        filename: String,
        taskId: UUID,
        parentTitle: String,
        folderURL: URL,
        sourceSubtaskTitle: String?
    ) {
        let subtaskField = sourceSubtaskTitle.map { "subtaskTitle: \(escapeFrontmatter($0))\n" } ?? ""
        let content = """
        ---
        title: \(escapeFrontmatter(note.title))
        taskId: \(taskId.uuidString)
        \(subtaskField)---

        # \(note.title)

        \(note.body)

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
        let slug = slugify(title)
        return "\(taskId.uuidString)__\(slug.isEmpty ? "task" : slug)"
    }

    private func subtaskFilename(_ order: Int, _ title: String) -> String {
        // order is 0-based across both phases; +1 keeps "00-" reserved for the task overview note.
        return String(format: "%02d-%@.md", order + 1, slugify(title))
    }

    private func imageFilename(for order: Int, _ title: String) -> String {
        return String(format: "%02d-%@.png", order + 1, slugify(title))
    }

    private func slugify(_ s: String) -> String {
        let lowered = s.lowercased()
        let allowed = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "-"
        }
        let collapsed = String(allowed).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return String(collapsed.prefix(48))
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
}
