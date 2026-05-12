import Foundation

// MARK: - Cross-Link Discovery

/// Handles cross-link discovery between wiki notes using AI analysis.
final actor KnowledgeBaseLinkDiscovery {
    private let filesystem: KnowledgeBaseFilesystem

    init(filesystem: KnowledgeBaseFilesystem) {
        self.filesystem = filesystem
    }

    private var discoveryWorkItem: DispatchWorkItem?

    /// Schedule (debounced) a cross-link discovery pass. Multiple back-to-back note writes
    /// collapse into one AI call ~6s after the last write.
    func scheduleLinkDiscovery() {
        discoveryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { await self?.runLinkDiscovery() }
        }
        discoveryWorkItem = work
        DispatchQueue.global().asyncAfter(deadline: .now() + 6, execute: work)
    }

    /// Trigger cross-link discovery immediately, bypassing the debounce. Used by the toolbar
    /// button so the user gets immediate feedback (spinner in the sidebar).
    func runLinkDiscoveryNow() {
        discoveryWorkItem?.cancel()
        discoveryWorkItem = nil
        Task { await runLinkDiscovery() }
    }

    private func runLinkDiscovery() async {
        guard let apiKey = APIKeyManager.getAPIKey() else { return }
        let inputs = await collectNotesForDiscovery(rootURL: filesystem.rootURL)
        guard inputs.count >= 2 else { return }

        print("[KnowledgeBase] Running cross-link discovery across \(inputs.count) notes")

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let service = KnowledgeAIService(apiKey: apiKey)
                let result = try await service.discoverCrossLinks(
                    notes: inputs.map { ($0.relPath, $0.title, $0.body) }
                )
                print("[KnowledgeBase] AI returned \(result.pairs.count) cross-link pair(s)")
                await self.applyDiscoveredLinks(result.pairs, allNotes: inputs)
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

    private func collectNotesForDiscovery(rootURL: URL) async -> [NoteForDiscovery] {
        let folders = await filesystem.listTaskFolders()
        var result: [NoteForDiscovery] = []

        for folder in folders {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let files = await filesystem.listNoteFiles(in: folder)
            for file in files where file.pathExtension == "md" {
                guard let raw = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let meta = await filesystem.parseFrontmatter(raw)
                let title = meta["title"] ?? file.deletingPathExtension().lastPathComponent
                let stripped = await filesystem.stripFrontmatterAndMarkers(raw)
                // path relative to rootURL (e.g. "notes/<folder>/<file>.md")
                let rel = file.path.replacingOccurrences(of: rootURL.path + "/", with: "")
                result.append(NoteForDiscovery(relPath: rel, title: title, body: stripped, fileURL: file))
            }
        }
        return result
    }

    private func applyDiscoveredLinks(_ pairs: [CrossLinkPair], allNotes: [NoteForDiscovery]) async {
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
            let changed = await updateRelatedSection(in: note, links: entries)
            if changed && !entries.isEmpty { updatedSources += 1 }
        }
        print("[KnowledgeBase] Wrote Related section on \(updatedSources) note(s)")
    }

    @discardableResult
    private func updateRelatedSection(in note: NoteForDiscovery, links: [(target: NoteForDiscovery, title: String)]) async -> Bool {
        guard let original = try? String(contentsOf: note.fileURL, encoding: .utf8) else { return false }

        let startMarker = "<!-- tada:related:start -->"
        let endMarker = "<!-- tada:related:end -->"

        let sectionBody: String
        if links.isEmpty {
            sectionBody = ""
        } else {
            let sourceDir = note.fileURL.deletingLastPathComponent()
            var bullets: [String] = []
            for entry in links {
                let rel = await filesystem.relativePath(from: sourceDir, to: entry.target.fileURL)
                if !rel.isEmpty {
                    bullets.append("- [[\(rel)|\(entry.title)]]")
                }
            }
            sectionBody = "\n## Related\n\n\(bullets.joined(separator: "\n"))\n"
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
}
