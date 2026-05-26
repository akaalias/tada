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
        guard FoundationModelsAvailability.isAvailable else { return }

        let all = await collectNotesForDiscovery(rootURL: filesystem.rootURL)
        guard let newNote = all.first(where: {
            $0.fileURL.standardizedFileURL == url.standardizedFileURL
        }) else {
            print("[KnowledgeBase] Link discovery: note not found on disk: \(url.lastPathComponent)")
            return
        }
        let newIsEntity = Self.entitySlug(of: newNote) != nil

        // Only consider notes that aren't already structurally close — siblings, entities the
        // note already links to, and notes already in its Related section are dropped, so the
        // AI spends its judgement on non-obvious, cross-context connections.
        let candidates = await filterCandidates(for: newNote, from: all)
        if candidates.isEmpty {
            print("[KnowledgeBase] Link discovery: no non-obvious candidates for '\(newNote.relPath)'")
        } else {
            print("[KnowledgeBase] Link discovery for '\(newNote.relPath)' against \(candidates.count) candidate(s)")

            // Co-occurrence context: which task notes mention each entity. Shared mentions are
            // a strong signal that two entities belong together.
            let mentions = Self.entityMentionMap(in: all)
            do {
                let service = KnowledgeAIService()
                let result = try await service.discoverLinksForNote(
                    note: (newNote.relPath, newNote.title, newNote.body, Self.mentionContext(for: newNote, mentions: mentions)),
                    candidates: candidates.map {
                        ($0.relPath, $0.title, $0.body, Self.mentionContext(for: $0, mentions: mentions))
                    },
                    newNoteIsEntity: newIsEntity
                )
                await applySuggestions(result.links, newNote: newNote, allNotes: all)
            } catch {
                print("[KnowledgeBase] Link discovery failed: \(AppError.userMessage(from: error))")
            }
        }

        // An entity's Related section only ever holds other entities — task notes that
        // reference it already surface under Backlinks. Normalise it here so stale task-note
        // links written by earlier runs get cleaned up.
        if newIsEntity { await pruneToEntityLinks(newNote) }
        NotificationCenter.default.post(name: .knowledgeBaseUpdated, object: nil)
    }

    // MARK: - Candidate filtering (proximity)

    /// Drops notes that are already close to `newNote`, so discovery targets only connections
    /// that aren't already obvious.
    ///
    /// When the new note is an **entity**, candidates are restricted to other entities — its
    /// Related section is for entity↔entity links; task notes that reference it already surface
    /// under Backlinks. When the new note is a **task note**, same-task-folder siblings are
    /// dropped (already connected through the shared overview).
    ///
    /// In both cases, entities the new note already wikilinks, and notes already in its Related
    /// section, are dropped.
    func filterCandidates(for newNote: NoteForDiscovery, from all: [NoteForDiscovery]) async -> [NoteForDiscovery] {
        let newDir = newNote.fileURL.deletingLastPathComponent().standardizedFileURL
        let newIsEntity = Self.entitySlug(of: newNote) != nil
        let linkedEntitySlugs = Self.entitySlugsLinked(inBody: newNote.body)
        let alreadyRelated = relatedTargetURLs(of: newNote)

        return all.filter { candidate in
            guard candidate.relPath != newNote.relPath else { return false }
            let candidateSlug = Self.entitySlug(of: candidate)

            if newIsEntity {
                // An entity links only to other entities.
                guard candidateSlug != nil else { return false }
            } else {
                // Same task folder — already connected through the shared overview.
                if candidate.fileURL.deletingLastPathComponent().standardizedFileURL == newDir { return false }
            }
            // Already linked from the new note's Related section.
            if alreadyRelated.contains(candidate.fileURL.standardizedFileURL) { return false }
            // An entity the new note already wikilinks in its body.
            if let candidateSlug, linkedEntitySlugs.contains(candidateSlug) { return false }
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
    /// any links already there. When `note` is an entity, the section is kept entity-only:
    /// non-entity targets are dropped and stale non-entity bullets are pruned.
    private func addRelatedLinks(
        to note: NoteForDiscovery,
        targets: [(target: NoteForDiscovery, title: String)]
    ) async {
        guard let raw = try? String(contentsOf: note.fileURL, encoding: .utf8) else { return }
        let sourceDir = note.fileURL.deletingLastPathComponent()
        let destIsEntity = Self.entitySlug(of: note) != nil

        // An entity links only to other entities.
        let effectiveTargets = destIsEntity
            ? targets.filter { Self.entitySlug(of: $0.target) != nil }
            : targets

        var newBullets: [String] = []
        for entry in effectiveTargets {
            let rel = await filesystem.relativePath(from: sourceDir, to: entry.target.fileURL)
            if !rel.isEmpty {
                newBullets.append("- [[\(rel)|\(entry.title)]]")
            }
        }

        // Existing bullets — for an entity destination, drop any that no longer point at an entity.
        var existing = Self.existingRelatedBullets(in: raw)
        if destIsEntity {
            existing = existing.filter { Self.bulletResolvesToEntity($0, sourceDir: sourceDir) }
        }

        let merged = Self.dedupedBullets(existing + newBullets)
        let updated = Self.writeRelatedSection(in: raw, bullets: merged)
        if updated != raw {
            try? updated.write(to: note.fileURL, atomically: true, encoding: .utf8)
        }
    }

    /// Rewrites `note`'s Related section to drop any bullet that does not resolve to an entity
    /// note. Used to normalise entity notes (their Related section is entity-only).
    private func pruneToEntityLinks(_ note: NoteForDiscovery) async {
        guard let raw = try? String(contentsOf: note.fileURL, encoding: .utf8) else { return }
        let sourceDir = note.fileURL.deletingLastPathComponent()
        let bullets = Self.existingRelatedBullets(in: raw)
        let entityBullets = bullets.filter { Self.bulletResolvesToEntity($0, sourceDir: sourceDir) }
        guard entityBullets.count != bullets.count else { return }
        let updated = Self.writeRelatedSection(in: raw, bullets: entityBullets)
        if updated != raw {
            try? updated.write(to: note.fileURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Co-occurrence

    /// Maps each entity slug to the titles of the task notes whose body wikilinks it. Two
    /// entities mentioned together in the same note are a strong candidate for a Related link.
    static func entityMentionMap(in notes: [NoteForDiscovery]) -> [String: [String]] {
        var map: [String: [String]] = [:]
        for note in notes where entitySlug(of: note) == nil {
            for slug in entitySlugsLinked(inBody: note.body) {
                map[slug, default: []].append(note.title)
            }
        }
        return map
    }

    /// A human-readable "mentioned in" line for an entity note, or "" for non-entities.
    private static func mentionContext(for note: NoteForDiscovery, mentions: [String: [String]]) -> String {
        guard let slug = entitySlug(of: note), let notes = mentions[slug], !notes.isEmpty else { return "" }
        return "mentioned in: \(notes.joined(separator: ", "))"
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

    /// Whether a `- [[path|title]]` bullet, resolved relative to `sourceDir`, points at an
    /// entity note — a file inside the `_entities/` folder. Resolution is required because a
    /// link to a sibling entity is a bare filename (`executives.md`) with no `_entities/` in it.
    static func bulletResolvesToEntity(_ bullet: String, sourceDir: URL) -> Bool {
        guard let target = bulletTarget(bullet) else { return false }
        let resolved = URL(fileURLWithPath: target, relativeTo: sourceDir).standardizedFileURL
        return resolved.deletingLastPathComponent().lastPathComponent == KnowledgeBaseFilesystem.entitiesFolderName
    }

    /// De-duplicates bullets by wikilink target path. The first occurrence of a path wins.
    static func dedupedBullets(_ bullets: [String]) -> [String] {
        var merged: [String] = []
        var seen: Set<String> = []
        for bullet in bullets {
            let key = bulletTarget(bullet) ?? bullet
            if seen.contains(key) { continue }
            seen.insert(key)
            merged.append(bullet)
        }
        return merged
    }

    /// Merges `newBullets` into `raw`'s Related section, preserving existing bullets and
    /// de-duplicating by wikilink target path. Existing bullets win on a path collision.
    static func addRelatedBullets(_ newBullets: [String], to raw: String) -> String {
        let merged = dedupedBullets(existingRelatedBullets(in: raw) + newBullets)
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
