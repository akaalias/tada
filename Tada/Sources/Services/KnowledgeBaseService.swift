import Foundation

struct KnowledgeEntry: Identifiable {
    let taskId: UUID
    let title: String
    let completedAt: Date
    let summary: String
    let folderURL: URL
    let overviewURL: URL
    let notes: [KnowledgeNoteFile]

    var id: UUID { taskId }
}

struct KnowledgeNoteFile: Identifiable {
    let title: String
    let fileURL: URL

    var id: String { fileURL.path }
}

final class KnowledgeBaseService: ObservableObject {
    static let shared = KnowledgeBaseService()

    let rootURL: URL
    private let notesURL: URL
    let indexURL: URL

    @MainActor @Published private(set) var isWorking: Bool = false
    @MainActor private var inFlightCount: Int = 0

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

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Tada", isDirectory: true)
        rootURL = appFolder.appendingPathComponent("knowledge", isDirectory: true)
        notesURL = rootURL.appendingPathComponent("notes", isDirectory: true)
        indexURL = rootURL.appendingPathComponent("index.md")

        try? FileManager.default.createDirectory(at: notesURL, withIntermediateDirectories: true)
    }

    // MARK: - Triggers

    /// Called right after a new task is created (or its title/description is refined by the planner).
    /// Writes a stub `_overview.md` page for the task so the wiki has an entry from day one.
    /// No AI call — this is purely structural.
    func handleTaskCreatedOrUpdated(_ task: TodoTask) {
        let folder = ensureTaskFolder(taskId: task.id, title: task.title)
        rewriteOverview(
            taskId: task.id,
            title: task.title,
            description: task.taskDescription,
            originalInput: task.originalInput,
            createdAt: task.createdAt,
            completedAt: task.completedAt,
            status: task.status,
            folder: folder
        )
        regenerateGlobalIndex()
        NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
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

        // Always refresh the parent overview to pick up any title/structural changes, even if no
        // AI is available or no new notes are needed.
        let folder = ensureTaskFolder(taskId: parent.id, title: parent.title)
        let snapshotParent = parent
        rewriteOverview(
            taskId: snapshotParent.id,
            title: snapshotParent.title,
            description: snapshotParent.taskDescription,
            originalInput: snapshotParent.originalInput,
            createdAt: snapshotParent.createdAt,
            completedAt: snapshotParent.completedAt,
            status: snapshotParent.status,
            folder: folder
        )
        regenerateGlobalIndex()
        NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)

        guard APIKeyManager.hasAPIKey else {
            print("[KnowledgeBase] Skipping sub-task note generation: no API key")
            return
        }

        // Generate notes for every completed sub-task that doesn't yet have one on disk.
        let pending: [SubtaskSnapshot] = parent.sortedSubTasks
            .filter { $0.isCompleted }
            .compactMap { st -> SubtaskSnapshot? in
                let snap = SubtaskSnapshot(from: st)
                let fileURL = folder.appendingPathComponent(subtaskFilename(snap))
                if FileManager.default.fileExists(atPath: fileURL.path) { return nil }
                return snap
            }

        guard !pending.isEmpty else { return }

        let taskId = snapshotParent.id
        let taskTitle = snapshotParent.title
        let description = snapshotParent.taskDescription
        let originalInput = snapshotParent.originalInput
        let createdAt = snapshotParent.createdAt
        let completedAt = snapshotParent.completedAt
        let status = snapshotParent.status

        print("[KnowledgeBase] Generating \(pending.count) sub-task note(s) for '\(taskTitle)'")

        beginWork()
        Task.detached { [weak self] in
            guard let self else { return }
            defer { self.endWork() }
            await self.generateSubtaskNotes(pending, taskId: taskId, taskTitle: taskTitle, folder: folder)
            self.rewriteOverview(
                taskId: taskId,
                title: taskTitle,
                description: description,
                originalInput: originalInput,
                createdAt: createdAt,
                completedAt: completedAt,
                status: status,
                folder: folder
            )
            self.regenerateGlobalIndex()
            NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
            self.scheduleLinkDiscovery()
        }
    }

    /// Called right after a task is marked completed. Ensures any outstanding sub-task notes are
    /// generated, then generates the task-level overview note.
    func handleTaskCompleted(_ task: TodoTask) {
        let folder = ensureTaskFolder(taskId: task.id, title: task.title)
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
        rewriteOverview(
            taskId: taskId,
            title: taskTitle,
            description: taskDescription,
            originalInput: originalInput,
            createdAt: createdAt,
            completedAt: completedAt,
            status: status,
            folder: folder
        )
        regenerateGlobalIndex()
        NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)

        guard APIKeyManager.hasAPIKey else {
            print("[KnowledgeBase] Skipping task overview note: no API key")
            return
        }

        let pending: [SubtaskSnapshot] = allCompletedSnapshots.filter { snap in
            !FileManager.default.fileExists(atPath: folder.appendingPathComponent(subtaskFilename(snap)).path)
        }

        print("[KnowledgeBase] Task completed: '\(taskTitle)' — \(pending.count) sub-task notes pending + 1 overview")

        Task.detached { [weak self] in
            guard let self else { return }
            await self.generateSubtaskNotes(pending, taskId: taskId, taskTitle: taskTitle, folder: folder)

            let subtaskSummaries = allCompletedSnapshots.map { snap -> (title: String, response: String, filename: String) in
                (snap.title, snap.response, self.subtaskFilename(snap))
            }
            await self.generateTaskOverviewNote(
                taskId: taskId,
                taskTitle: taskTitle,
                originalInput: originalInput,
                taskDescription: taskDescription,
                subtaskSummaries: subtaskSummaries,
                folder: folder
            )

            self.rewriteOverview(
                taskId: taskId,
                title: taskTitle,
                description: taskDescription,
                originalInput: originalInput,
                createdAt: createdAt,
                completedAt: completedAt,
                status: status,
                folder: folder
            )
            self.regenerateGlobalIndex()
            NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
            self.scheduleLinkDiscovery()
        }
    }

    // MARK: - Reading

    func loadAllEntries() -> [KnowledgeEntry] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: notesURL, includingPropertiesForKeys: nil) else {
            return []
        }
        let entries = folders.compactMap { url -> KnowledgeEntry? in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return loadEntry(at: url)
        }
        return entries.sorted { $0.completedAt > $1.completedAt }
    }

    func loadNoteContent(at url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func loadEntry(at folderURL: URL) -> KnowledgeEntry? {
        let overviewURL = folderURL.appendingPathComponent("_overview.md")
        guard let raw = try? String(contentsOf: overviewURL, encoding: .utf8) else { return nil }

        let meta = parseFrontmatter(raw)
        guard let taskIdString = meta["taskId"],
              let taskId = UUID(uuidString: taskIdString),
              let title = meta["title"] else {
            return nil
        }
        let iso = ISO8601DateFormatter()
        let createdAt: Date = meta["createdAt"].flatMap { iso.date(from: $0) } ?? Date()
        let completedAt: Date? = meta["completedAt"].flatMap { iso.date(from: $0) }
        let sortDate = completedAt ?? createdAt

        let fm = FileManager.default
        let noteURLs = (try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []
        let notes: [KnowledgeNoteFile] = noteURLs
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "_overview.md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                let noteMeta = parseFrontmatter(body)
                let noteTitle = noteMeta["title"] ?? url.deletingPathExtension().lastPathComponent
                return KnowledgeNoteFile(title: noteTitle, fileURL: url)
            }

        return KnowledgeEntry(
            taskId: taskId,
            title: title,
            completedAt: sortDate,
            summary: meta["status"] == "completed" ? "Completed" : "In progress",
            folderURL: folderURL,
            overviewURL: overviewURL,
            notes: notes
        )
    }

    // MARK: - Generation helpers

    private struct SubtaskSnapshot {
        let id: UUID
        let order: Int
        let phase: String
        let title: String
        let description: String
        let response: String
        let imagePNG: Data?
        let tableMarkdown: String?

        init(from subTask: SubTask) {
            self.id = subTask.id
            self.order = subTask.order
            self.phase = subTask.phase
            self.title = subTask.title
            self.description = subTask.subTaskDescription
            self.response = KnowledgeBaseService.responseString(for: subTask)
            self.imagePNG = KnowledgeBaseService.extractPNG(from: subTask)
            self.tableMarkdown = KnowledgeBaseService.extractTableMarkdown(from: subTask)
        }
    }

    private static func extractPNG(from subTask: SubTask) -> Data? {
        guard let data = subTask.actionResponseData,
              let response = try? JSONDecoder().decode(ActionResponse.self, from: data) else {
            return nil
        }
        for (_, value) in response.values {
            if case .string(let s) = value, s.hasPrefix("data:image/png;base64,") {
                let base64 = String(s.dropFirst("data:image/png;base64,".count))
                return Data(base64Encoded: base64)
            }
        }
        return nil
    }

    private static func extractTableMarkdown(from subTask: SubTask) -> String? {
        guard let data = subTask.actionResponseData,
              let response = try? JSONDecoder().decode(ActionResponse.self, from: data) else {
            return nil
        }
        for (_, value) in response.values {
            if case .string(let s) = value, s.hasPrefix("__tada_table__") {
                let json = String(s.dropFirst("__tada_table__".count))
                guard let jsonData = json.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let columns = dict["columns"] as? [[String: String]],
                      let rows = dict["rows"] as? [[String: String]],
                      !columns.isEmpty else { return nil }

                let header = "| " + columns.map { $0["label"] ?? "" }.joined(separator: " | ") + " |"
                let separator = "| " + columns.map { _ in "---" }.joined(separator: " | ") + " |"
                let rowLines = rows.map { row -> String in
                    let cells = columns.map { col -> String in
                        let id = col["id"] ?? ""
                        let raw = row[id] ?? ""
                        if col["type"] == "currency" && !raw.isEmpty {
                            return "€\(raw)"
                        }
                        return raw
                    }
                    return "| " + cells.joined(separator: " | ") + " |"
                }
                var table = ([header, separator] + rowLines).joined(separator: "\n")
                if let total = dict["total"] as? Int,
                   let hasCurrency = dict["hasCurrency"] as? Bool,
                   hasCurrency && total > 0 {
                    table += "\n\n_Total: €\(total)_"
                }
                return table
            }
        }
        return nil
    }

    private func generateSubtaskNotes(
        _ snapshots: [SubtaskSnapshot],
        taskId: UUID,
        taskTitle: String,
        folder: URL
    ) async {
        guard !snapshots.isEmpty, let apiKey = APIKeyManager.getAPIKey() else { return }
        let service = KnowledgeAIService(apiKey: apiKey)

        // Run notes in parallel for speed.
        await withTaskGroup(of: Void.self) { group in
            for snap in snapshots {
                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
                        // If the sub-task captured a sketch, save it next to the note as PNG so the
                        // wiki can embed it and the AI can see it for richer descriptions.
                        var imageMarkdown: String? = nil
                        if let pngData = snap.imagePNG {
                            let imageFilename = self.imageFilename(for: snap)
                            try? pngData.write(to: folder.appendingPathComponent(imageFilename))
                            imageMarkdown = "![\(snap.title) sketch](./\(imageFilename))"
                        }

                        let note = try await service.generateSubtaskNote(
                            taskTitle: taskTitle,
                            subtaskTitle: snap.title,
                            subtaskDescription: snap.description,
                            response: snap.response,
                            attachedImage: snap.imagePNG,
                            tableMarkdown: snap.tableMarkdown
                        )

                        // Append the image and/or table to the body so they render on the wiki page.
                        var body = note.body
                        if let imageMarkdown {
                            body += "\n\n\(imageMarkdown)"
                        }
                        if let table = snap.tableMarkdown {
                            body += "\n\n\(table)"
                        }
                        let augmented = GeneratedKnowledgeNote(title: note.title, body: body)

                        self.writeNote(
                            augmented,
                            filename: self.subtaskFilename(snap),
                            taskId: taskId,
                            parentTitle: taskTitle,
                            folder: folder,
                            sourceSubtaskTitle: snap.title
                        )
                        print("[KnowledgeBase] Wrote sub-task note: \(self.subtaskFilename(snap))")
                    } catch {
                        print("[KnowledgeBase] Failed to generate sub-task note for '\(snap.title)': \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func imageFilename(for snap: SubtaskSnapshot) -> String {
        return String(format: "%02d-%@.png", snap.order + 1, slugify(snap.title))
    }

    private func generateTaskOverviewNote(
        taskId: UUID,
        taskTitle: String,
        originalInput: String,
        taskDescription: String,
        subtaskSummaries: [(title: String, response: String, filename: String)],
        folder: URL
    ) async {
        guard let apiKey = APIKeyManager.getAPIKey() else { return }
        do {
            let service = KnowledgeAIService(apiKey: apiKey)
            let note = try await service.generateTaskOverviewNote(
                taskTitle: taskTitle,
                originalInput: originalInput,
                taskDescription: taskDescription,
                subtaskSummaries: subtaskSummaries
            )
            writeNote(
                note,
                filename: "00-\(slugify(note.title)).md",
                taskId: taskId,
                parentTitle: taskTitle,
                folder: folder,
                sourceSubtaskTitle: nil
            )
            print("[KnowledgeBase] Wrote task overview note")
        } catch {
            print("[KnowledgeBase] Failed to generate task overview note: \(error.localizedDescription)")
        }
    }

    private func writeNote(
        _ note: GeneratedKnowledgeNote,
        filename: String,
        taskId: UUID,
        parentTitle: String,
        folder: URL,
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
        try? content.write(to: folder.appendingPathComponent(filename), atomically: true, encoding: .utf8)
    }

    // MARK: - Cross-link discovery

    private var discoveryWorkItem: DispatchWorkItem?

    /// Schedule (debounced) a cross-link discovery pass. Multiple back-to-back note writes
    /// collapse into one AI call ~6s after the last write.
    func scheduleLinkDiscovery() {
        discoveryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.runLinkDiscovery()
        }
        discoveryWorkItem = work
        DispatchQueue.global().asyncAfter(deadline: .now() + 6, execute: work)
    }

    /// Trigger cross-link discovery immediately, bypassing the debounce. Used by the toolbar
    /// button so the user gets immediate feedback (spinner in the sidebar).
    func runLinkDiscoveryNow() {
        discoveryWorkItem?.cancel()
        discoveryWorkItem = nil
        runLinkDiscovery()
    }

    private func runLinkDiscovery() {
        guard let apiKey = APIKeyManager.getAPIKey() else { return }
        let inputs = collectNotesForDiscovery()
        guard inputs.count >= 2 else { return }

        print("[KnowledgeBase] Running cross-link discovery across \(inputs.count) notes")
        beginWork()

        Task.detached { [weak self] in
            guard let self else { return }
            defer { self.endWork() }
            do {
                let service = KnowledgeAIService(apiKey: apiKey)
                let result = try await service.discoverCrossLinks(
                    notes: inputs.map { ($0.relPath, $0.title, $0.body) }
                )
                print("[KnowledgeBase] AI returned \(result.pairs.count) cross-link pair(s)")
                self.applyDiscoveredLinks(result.pairs, allNotes: inputs)
                NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
            } catch {
                print("[KnowledgeBase] Cross-link discovery failed: \(error.localizedDescription)")
            }
        }
    }

    private struct NoteForDiscovery {
        let relPath: String       // e.g. "notes/<folder>/01-slug.md"
        let title: String
        let body: String          // body without frontmatter or related markers
        let fileURL: URL
    }

    private func collectNotesForDiscovery() -> [NoteForDiscovery] {
        let fm = FileManager.default
        var result: [NoteForDiscovery] = []
        guard let folders = try? fm.contentsOfDirectory(at: notesURL, includingPropertiesForKeys: nil) else {
            return result
        }
        for folder in folders {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "md" {
                guard let raw = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let meta = parseFrontmatter(raw)
                let title = meta["title"] ?? file.deletingPathExtension().lastPathComponent
                let stripped = stripFrontmatterAndMarkers(raw)
                // path relative to rootURL (e.g. "notes/<folder>/<file>.md")
                let rel = file.path.replacingOccurrences(of: rootURL.path + "/", with: "")
                result.append(NoteForDiscovery(relPath: rel, title: title, body: stripped, fileURL: file))
            }
        }
        return result
    }

    private func applyDiscoveredLinks(_ pairs: [CrossLinkPair], allNotes: [NoteForDiscovery]) {
        var byPath: [String: NoteForDiscovery] = [:]
        var byBasename: [String: [NoteForDiscovery]] = [:]
        for note in allNotes {
            byPath[note.relPath] = note
            byBasename[note.fileURL.lastPathComponent, default: []].append(note)
        }

        func resolve(_ aiPath: String) -> NoteForDiscovery? {
            // 1. Try exact match.
            if let n = byPath[aiPath] { return n }
            // 2. The AI sometimes prepends a leading slash or strips the "notes/" prefix.
            let normalized = aiPath
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let n = byPath[normalized] { return n }
            // 3. Try basename match. Only safe when unambiguous.
            let basename = (aiPath as NSString).lastPathComponent
            if let matches = byBasename[basename], matches.count == 1 {
                return matches.first
            }
            return nil
        }

        // Group valid pairs by source.
        var grouped: [String: [(target: NoteForDiscovery, title: String)]] = [:]
        var unmatched = 0
        for pair in pairs {
            guard pair.sourcePath != pair.targetPath else { continue }
            guard let source = resolve(pair.sourcePath), let target = resolve(pair.targetPath) else {
                unmatched += 1
                print("[KnowledgeBase] Unmatched pair: source=\(pair.sourcePath) target=\(pair.targetPath)")
                continue
            }
            grouped[source.relPath, default: []].append((target, pair.targetTitle))
        }

        if unmatched > 0 {
            print("[KnowledgeBase] \(unmatched) of \(pairs.count) suggested pair(s) could not be resolved to known notes")
        }

        // Update every source note's related-section markers. Also clear the section on notes that
        // are no longer suggested as a source so removed links don't linger.
        var updatedSources = 0
        for note in allNotes {
            let entries = grouped[note.relPath] ?? []
            let changed = updateRelatedSection(in: note, links: entries)
            if changed && !entries.isEmpty { updatedSources += 1 }
        }
        print("[KnowledgeBase] Wrote Related section on \(updatedSources) note(s)")
    }

    @discardableResult
    private func updateRelatedSection(in note: NoteForDiscovery, links: [(target: NoteForDiscovery, title: String)]) -> Bool {
        guard let original = try? String(contentsOf: note.fileURL, encoding: .utf8) else { return false }

        let startMarker = "<!-- tada:related:start -->"
        let endMarker = "<!-- tada:related:end -->"

        let sectionBody: String
        if links.isEmpty {
            sectionBody = ""
        } else {
            let sourceDir = note.fileURL.deletingLastPathComponent()
            let bullets = links.compactMap { (entry: (target: NoteForDiscovery, title: String)) -> String? in
                let rel = relativePath(from: sourceDir, to: entry.target.fileURL)
                guard !rel.isEmpty else { return nil }
                return "- [[\(rel)|\(entry.title)]]"
            }.joined(separator: "\n")
            sectionBody = "\n## Related\n\n\(bullets)\n"
        }

        let replacement = "\(startMarker)\(sectionBody)\(endMarker)"

        let updated: String
        if let startRange = original.range(of: startMarker),
           let endRange = original.range(of: endMarker),
           startRange.lowerBound < endRange.upperBound {
            updated = original.replacingCharacters(
                in: startRange.lowerBound..<endRange.upperBound,
                with: replacement
            )
        } else {
            // Markers missing (legacy note) — append them right before the trailing "Back to ..." line.
            let lines = original.components(separatedBy: "\n")
            if let backIdx = lines.lastIndex(where: { $0.hasPrefix("Back to ") }) {
                var newLines = lines
                let separatorIdx = backIdx > 0 && newLines[backIdx - 1] == "---" ? backIdx - 1 : backIdx
                newLines.insert(replacement, at: separatorIdx)
                updated = newLines.joined(separator: "\n")
            } else {
                updated = original + "\n\n" + replacement + "\n"
            }
        }

        if updated != original {
            try? updated.write(to: note.fileURL, atomically: true, encoding: .utf8)
            return true
        }
        return false
    }

    private func stripFrontmatterAndMarkers(_ raw: String) -> String {
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

    private func relativePath(from sourceDir: URL, to target: URL) -> String {
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

    private func rewriteOverview(
        taskId: UUID,
        title: String,
        description: String,
        originalInput: String,
        createdAt: Date,
        completedAt: Date?,
        status: String,
        folder: URL
    ) {
        let fm = FileManager.default
        let iso = ISO8601DateFormatter()

        // List all note files currently on disk for this task, sorted.
        let noteURLs = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
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

        try? overview.write(to: folder.appendingPathComponent("_overview.md"), atomically: true, encoding: .utf8)
    }

    private func regenerateGlobalIndex() {
        let entries = loadAllEntries()
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

        if entries.isEmpty {
            lines.append("_No tasks yet. Create one and it will appear here._")
        }

        try? lines.joined(separator: "\n").write(to: indexURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Filesystem helpers

    private func ensureTaskFolder(taskId: UUID, title: String) -> URL {
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

    private func folderName(taskId: UUID, title: String) -> String {
        let slug = slugify(title)
        return "\(taskId.uuidString)__\(slug.isEmpty ? "task" : slug)"
    }

    private func subtaskFilename(_ snap: SubtaskSnapshot) -> String {
        // order is 0-based across both phases; +1 keeps "00-" reserved for the task overview note.
        return String(format: "%02d-%@.md", snap.order + 1, slugify(snap.title))
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

    private func parseFrontmatter(_ raw: String) -> [String: String] {
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

    private static func responseString(for subTask: SubTask) -> String {
        guard let data = subTask.actionResponseData,
              let response = try? JSONDecoder().decode(ActionResponse.self, from: data) else {
            return "(no response recorded)"
        }
        let parts = response.values.compactMap { _, value -> String? in
            switch value {
            case .string(let s):
                if s.hasPrefix("data:image") { return "(drawing)" }
                return s.isEmpty ? nil : s
            case .number(let n):
                return String(format: "%g", n)
            case .boolean(let b):
                return b ? "Yes" : "No"
            case .stringArray(let arr):
                return arr.isEmpty ? nil : arr.joined(separator: ", ")
            case .date(let d):
                return d.formatted(date: .abbreviated, time: .omitted)
            }
        }
        return parts.isEmpty ? "(no response recorded)" : parts.joined(separator: "; ")
    }
}

extension Notification.Name {
    static let knowledgeBaseUpdated = Notification.Name("knowledgeBaseUpdated")
}
