import Foundation

// MARK: - Cross-Link Discovery

/// Discovers which existing wiki notes belong in a *single* note's "Related" section.
///
/// Triggered per-note right after that note's entity-extraction pass completes — so the
/// discovery AI sees a stable, fully-linked note set and there is no race with extraction.
/// The pass is single-source: "here is new note X, here is every other note — which ones
/// belong in X's Related section?" Links are written two-way (X gains the targets, each
/// target gains X), and writes are additive so existing Related links are preserved.
final actor KnowledgeBaseLinkDiscovery {
    private let filesystem: KnowledgeBaseFilesystem

    init(filesystem: KnowledgeBaseFilesystem) {
        self.filesystem = filesystem
    }

    /// Runs link discovery for each note in turn. Sequential so two notes in the same batch
    /// never write each other's Related section concurrently.
    func discoverLinks(forNotesAt urls: [URL]) async {
        for url in urls {
            await discoverLinks(forNoteAt: url)
        }
    }

    /// Runs link discovery for one note: asks the AI which existing notes belong in this
    /// note's Related section, then writes the links two-way.
    func discoverLinks(forNoteAt url: URL) async {
        guard let apiKey = APIKeyManager.getAPIKey() else { return }

        let all = await collectNotesForDiscovery(rootURL: filesystem.rootURL)
        guard let newNote = all.first(where: {
            $0.fileURL.standardizedFileURL == url.standardizedFileURL
        }) else {
            print("[KnowledgeBase] Link discovery: note not found on disk: \(url.lastPathComponent)")
            return
        }

        // Only consider notes that aren't already structurally close — siblings, entities the
        // note already links to, and notes already in its Related section are dropped, so the
        // AI spends its judgement on non-obvious, cross-context connections.
        let candidates = await filterCandidates(for: newNote, from: all)
        guard !candidates.isEmpty else {
            print("[KnowledgeBase] Link discovery: no non-obvious candidates for '\(newNote.relPath)'")
            return
        }

        print("[KnowledgeBase] Link discovery for '\(newNote.relPath)' against \(candidates.count) candidate(s)")

        do {
            let service = KnowledgeAIService(apiKey: apiKey)
            let result = try await service.discoverLinksForNote(
                note: (newNote.relPath, newNote.title, newNote.body),
                candidates: candidates.map { ($0.relPath, $0.title, $0.body) }
            )
            await applySuggestions(result.links, newNote: newNote, allNotes: all)
            NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
        } catch {
            print("[KnowledgeBase] Link discovery failed: \(AppError.userMessage(from: error))")
        }
    }

    // MARK: - Candidate filtering (proximity)

    /// Drops notes that are already close to `newNote`, so discovery targets only connections
    /// that aren't already obvious:
    ///   - notes in the same task folder (siblings + that task's `_overview`, all linked via
    ///     the overview already);
    ///   - entity notes the new note already wikilinks in its body;
    ///   - notes already present in the new note's Related section.
    func filterCandidates(for newNote: NoteForDiscovery, from all: [NoteForDiscovery]) async -> [NoteForDiscovery] {
        let newDir = newNote.fileURL.deletingLastPathComponent().standardizedFileURL
        let linkedEntitySlugs = Self.entitySlugsLinked(inBody: newNote.body)
        let alreadyRelated = relatedTargetURLs(of: newNote)

        return all.filter { candidate in
            guard candidate.relPath != newNote.relPath else { return false }
            // Same task folder — already connected through the shared overview.
            if candidate.fileURL.deletingLastPathComponent().standardizedFileURL == newDir { return false }
            // Already linked from the new note's Related section.
            if alreadyRelated.contains(candidate.fileURL.standardizedFileURL) { return false }
            // An entity the new note already wikilinks in its body.
            if let slug = Self.entitySlug(of: candidate), linkedEntitySlugs.contains(slug) { return false }
            return true
        }
    }

    /// Absolute URLs already listed in `note`'s Related section.
    private func relatedTargetURLs(of note: NoteForDiscovery) -> Set<URL> {
        guard let raw = try? String(contentsOf: note.fileURL, encoding: .utf8) else { return [] }
        let dir = note.fileURL.deletingLastPathComponent()
        var urls: Set<URL> = []
        for bullet in Self.existingRelatedBullets(in: raw) {
            guard let target = Self.bulletTarget(bullet) else { continue }
            urls.insert(URL(fileURLWithPath: target, relativeTo: dir).standardizedFileURL)
        }
        return urls
    }

    /// Entity slugs wikilinked anywhere in `body` (matches `[[..._entities/<slug>.md`).
    private static func entitySlugsLinked(inBody body: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[[^\[\]]*_entities/([^\[\]/|]+)\.md"#) else {
            return []
        }
        let ns = body as NSString
        var slugs: Set<String> = []
        for m in regex.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            slugs.insert(ns.substring(with: m.range(at: 1)))
        }
        return slugs
    }

    /// The slug of `note` if it is an entity note, else nil.
    private static func entitySlug(of note: NoteForDiscovery) -> String? {
        let parent = note.fileURL.deletingLastPathComponent().lastPathComponent
        guard parent == KnowledgeBaseFilesystem.entitiesFolderName else { return nil }
        return note.fileURL.deletingPathExtension().lastPathComponent
    }

    struct NoteForDiscovery {
        let relPath: String       // e.g. "notes/<folder>/01-slug.md"
        let title: String
        let body: String          // body without frontmatter or related markers
        let fileURL: URL
    }

    func collectNotesForDiscovery(rootURL: URL) async -> [NoteForDiscovery] {
        let folders = await filesystem.listTaskFolders()
        var result: [NoteForDiscovery] = []

        for folder in folders {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let files = await filesystem.listNoteFiles(in: folder)
            for file in files where file.pathExtension == "md" {
                if let note = await makeNote(from: file, rootURL: rootURL) {
                    result.append(note)
                }
            }
        }

        // Entity notes (`_entities/<slug>.md`) participate in discovery too, so the Related
        // section can connect task notes to the entities they're about — and surface other
        // notes that reference the same entity.
        for file in await filesystem.listEntityFiles() {
            if let note = await makeNote(from: file, rootURL: rootURL) {
                result.append(note)
            }
        }
        return result
    }

    private func makeNote(from file: URL, rootURL: URL) async -> NoteForDiscovery? {
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let meta = await filesystem.parseFrontmatter(raw)
        let title = meta["title"] ?? file.deletingPathExtension().lastPathComponent
        let stripped = await filesystem.stripFrontmatterAndMarkers(raw)
        // path relative to rootURL (e.g. "notes/<folder>/<file>.md")
        let rel = file.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        return NoteForDiscovery(relPath: rel, title: title, body: stripped, fileURL: file)
    }

    // MARK: - Applying suggestions

    private func applySuggestions(
        _ links: [SuggestedRelatedNote],
        newNote: NoteForDiscovery,
        allNotes: [NoteForDiscovery]
    ) async {
        let resolve = Self.makeResolver(allNotes)

        var targets: [NoteForDiscovery] = []
        var seen: Set<String> = [newNote.relPath]
        for link in links {
            guard let target = resolve(link.targetPath) else {
                print("[KnowledgeBase] Link discovery: unmatched target \(link.targetPath)")
                continue
            }
            if seen.contains(target.relPath) { continue }
            seen.insert(target.relPath)
            targets.append(target)
        }

        guard !targets.isEmpty else {
            print("[KnowledgeBase] Link discovery: no related notes for '\(newNote.relPath)'")
            return
        }

        // Outgoing: the new note gains links to every suggested target.
        await addRelatedLinks(to: newNote, targets: targets.map { ($0, $0.title) })
        // Backlinks: each target gains a link back to the new note.
        for target in targets {
            await addRelatedLinks(to: target, targets: [(newNote, newNote.title)])
        }
        print("[KnowledgeBase] Link discovery: linked '\(newNote.relPath)' with \(targets.count) note(s)")
    }

    /// Resolves an AI-supplied path string to a known note. Tolerates a leading slash, a
    /// missing "notes/" prefix, and unambiguous basename matches.
    private static func makeResolver(_ notes: [NoteForDiscovery]) -> (String) -> NoteForDiscovery? {
        var byPath: [String: NoteForDiscovery] = [:]
        var byBasename: [String: [NoteForDiscovery]] = [:]
        for note in notes {
            byPath[note.relPath] = note
            byBasename[note.fileURL.lastPathComponent, default: []].append(note)
        }
        return { aiPath in
            if let n = byPath[aiPath] { return n }
            let normalized = aiPath
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let n = byPath[normalized] { return n }
            let basename = (aiPath as NSString).lastPathComponent
            if let matches = byBasename[basename], matches.count == 1 {
                return matches.first
            }
            return nil
        }
    }

    /// Additively merges the given targets into `note`'s Related section on disk, preserving
    /// any links already there.
    private func addRelatedLinks(
        to note: NoteForDiscovery,
        targets: [(target: NoteForDiscovery, title: String)]
    ) async {
        guard let raw = try? String(contentsOf: note.fileURL, encoding: .utf8) else { return }
        let sourceDir = note.fileURL.deletingLastPathComponent()

        var bullets: [String] = []
        for entry in targets {
            let rel = await filesystem.relativePath(from: sourceDir, to: entry.target.fileURL)
            if !rel.isEmpty {
                bullets.append("- [[\(rel)|\(entry.title)]]")
            }
        }
        guard !bullets.isEmpty else { return }

        let updated = Self.addRelatedBullets(bullets, to: raw)
        if updated != raw {
            try? updated.write(to: note.fileURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Related-section editing (pure)

    private static let relatedStartMarker = "<!-- tada:related:start -->"
    private static let relatedEndMarker = "<!-- tada:related:end -->"

    /// The bullet lines (`- [[...]]`) currently inside the related-section markers.
    static func existingRelatedBullets(in raw: String) -> [String] {
        guard let startRange = raw.range(of: relatedStartMarker),
              let endRange = raw.range(of: relatedEndMarker),
              startRange.upperBound <= endRange.lowerBound else { return [] }
        return raw[startRange.upperBound..<endRange.lowerBound]
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- [[") }
    }

    /// The wikilink target path inside a `- [[path|title]]` bullet, used to de-duplicate.
    private static func bulletTarget(_ bullet: String) -> String? {
        guard let open = bullet.range(of: "[[") else { return nil }
        let after = bullet[open.upperBound...]
        guard let end = after.firstIndex(where: { $0 == "|" || $0 == "]" }) else { return nil }
        return String(after[..<end])
    }

    /// Merges `newBullets` into `raw`'s Related section, preserving existing bullets and
    /// de-duplicating by wikilink target path. Existing bullets win on a path collision.
    static func addRelatedBullets(_ newBullets: [String], to raw: String) -> String {
        var merged: [String] = []
        var seen: Set<String> = []
        for bullet in existingRelatedBullets(in: raw) + newBullets {
            let key = bulletTarget(bullet) ?? bullet
            if seen.contains(key) { continue }
            seen.insert(key)
            merged.append(bullet)
        }
        return writeRelatedSection(in: raw, bullets: merged)
    }

    /// Splices a complete Related section (built from `bullets`) into `raw`, replacing whatever
    /// sits between the markers. For legacy notes without markers, inserts the section just
    /// before the trailing "Back to ..." line.
    static func writeRelatedSection(in raw: String, bullets: [String]) -> String {
        let sectionBody = bullets.isEmpty
            ? ""
            : "\n## Related\n\n\(bullets.joined(separator: "\n"))\n"
        let replacement = "\(relatedStartMarker)\(sectionBody)\(relatedEndMarker)"

        if let startRange = raw.range(of: relatedStartMarker),
           let endRange = raw.range(of: relatedEndMarker),
           startRange.lowerBound < endRange.upperBound {
            return raw.replacingCharacters(
                in: startRange.lowerBound..<endRange.upperBound,
                with: replacement
            )
        }

        // Markers missing (legacy note) — append them right before the trailing "Back to ..." line.
        let lines = raw.components(separatedBy: "\n")
        if let backIdx = lines.lastIndex(where: { $0.hasPrefix("Back to ") }) {
            var newLines = lines
            let insertIdx = backIdx > 0 && newLines[backIdx - 1] == "---" ? backIdx - 1 : backIdx
            newLines.insert(replacement, at: insertIdx)
            return newLines.joined(separator: "\n")
        }
        return raw + "\n\n" + replacement + "\n"
    }
}
