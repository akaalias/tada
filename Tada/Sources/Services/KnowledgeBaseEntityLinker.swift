import Foundation

// MARK: - Entity Link Canonicalization

/// Pure logic that turns an AI-produced entity-extraction result into:
///   - a body where every entity wikilink uses the canonical relative path `../_entities/<slug>.md`
///   - a final list of new entities keyed by canonical slug (display-name-derived)
/// Existing sub-task wikilinks (`[[XX-foo.md|...]]`) and overview back-links (`[[_overview.md|...]]`)
/// are left untouched.
enum KnowledgeBaseEntityLinker {

    struct FinalEntity: Equatable {
        let slug: String
        let displayName: String
        let body: String
    }

    static func canonicalize(
        linkedBody: String,
        newEntities: [ExtractedEntity],
        existingSlugs: Set<String>
    ) -> (body: String, finalNewEntities: [FinalEntity]) {
        // 1. Compute canonical slug for each newEntity (display-name-derived).
        //    Map AI's emitted slug → canonical slug so we can rewrite links that used the AI's slug.
        var aiSlugToCanonical: [String: String] = [:]
        var finalNew: [FinalEntity] = []
        var seenCanonical: Set<String> = []
        for e in newEntities {
            let canonical = KnowledgeBaseFilesystem.entitySlug(from: e.displayName)
            guard !canonical.isEmpty else { continue }
            aiSlugToCanonical[e.slug] = canonical
            if !seenCanonical.contains(canonical) && !existingSlugs.contains(canonical) {
                finalNew.append(FinalEntity(slug: canonical, displayName: e.displayName, body: e.body))
                seenCanonical.insert(canonical)
            }
        }

        // 2. Rewrite [[X.md|Y]] in the body — skip sub-task (^\d{2}-) and _overview links.
        let pattern = #"\[\[([^\[\]\|]+)\.md\|([^\[\]]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (linkedBody, finalNew)
        }
        let nsBody = linkedBody as NSString
        let matches = regex.matches(in: linkedBody, range: NSRange(location: 0, length: nsBody.length))
        var result = linkedBody as NSString
        // Apply in reverse so ranges stay valid.
        for m in matches.reversed() {
            let slug = nsBody.substring(with: m.range(at: 1))
            let display = nsBody.substring(with: m.range(at: 2))

            if isStructuralSlug(slug) { continue }

            let finalSlug = resolveFinalSlug(
                aiSlug: slug,
                display: display,
                aiSlugMap: aiSlugToCanonical,
                existingSlugs: existingSlugs
            )

            let replacement = "[[\(KnowledgeBaseFilesystem.entityLinkPrefix)\(finalSlug).md|\(display)]]"
            result = result.replacingCharacters(in: m.range, with: replacement) as NSString
        }
        return (result as String, finalNew)
    }

    private static func isStructuralSlug(_ slug: String) -> Bool {
        // Sub-task notes are named `XX-...` where XX is a 2-digit order prefix.
        if slug.range(of: "^\\d{2}-", options: .regularExpression) != nil { return true }
        if slug == "_overview" { return true }
        // Anything containing path separators is already a relative link — leave it.
        if slug.contains("/") { return true }
        return false
    }

    /// A note that links to an entity.
    struct Backlink: Identifiable, Equatable {
        let fileURL: URL
        let noteTitle: String
        let taskTitle: String?
        var id: String { fileURL.path }
    }

    /// Returns true if `body` contains a wikilink to the entity with the given slug.
    static func bodyContainsEntityLink(_ body: String, entitySlug slug: String) -> Bool {
        // Match the canonical path-prefixed form from task notes: `[[../_entities/<slug>.md|...`
        let taskNoteFormat = "[[\(KnowledgeBaseFilesystem.entityLinkPrefix)\(slug).md"
        if body.contains(taskNoteFormat) { return true }
        // Also match entity-to-entity links (same folder): `[[<slug>.md|...`
        let entityFormat = "[[\(slug).md"
        if body.contains(entityFormat) { return true }
        // And links with _entities/ prefix (from notes not in task folders)
        let prefixedFormat = "[[_entities/\(slug).md"
        return body.contains(prefixedFormat)
    }

    /// Locates the body slice inside a written note file. The body lives between the `# Title`
    /// heading and the first trailing structural section (`## Original input`, `## Related`,
    /// or the `<!-- tada:related:start -->` marker). Returns the body text and the range that
    /// can be used to splice an updated body back into the file.
    static func extractBodyRegion(from raw: String) -> (body: String, range: Range<String.Index>)? {
        guard let titleRegex = try? NSRegularExpression(pattern: #"(?m)^# [^\n]+\n+"#) else {
            return nil
        }
        let nsRaw = raw as NSString
        guard let titleMatch = titleRegex.firstMatch(in: raw, range: NSRange(location: 0, length: nsRaw.length)),
              let titleEndStringIdx = Range(titleMatch.range, in: raw)?.upperBound else {
            return nil
        }

        // Find the earliest trailing marker after the heading. Markers may sit right at the
        // body start (empty body) or further down preceded by a newline.
        let markers = ["## Original input", "## Related", "<!-- tada:related:start -->"]
        var bodyEnd: String.Index = raw.endIndex
        for marker in markers {
            if let r = raw.range(of: marker, range: titleEndStringIdx..<raw.endIndex) {
                if r.lowerBound < bodyEnd { bodyEnd = r.lowerBound }
            }
        }
        let bodySlice = raw[titleEndStringIdx..<bodyEnd]
        let trimmed = bodySlice.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed, titleEndStringIdx..<bodyEnd)
    }

    private static func resolveFinalSlug(
        aiSlug: String,
        display: String,
        aiSlugMap: [String: String],
        existingSlugs: Set<String>
    ) -> String {
        // If the AI used the slug of an existing entity, keep it.
        if existingSlugs.contains(aiSlug) { return aiSlug }
        // If the AI's slug maps to one of our canonical new entities, use canonical.
        if let canonical = aiSlugMap[aiSlug] { return canonical }
        // Otherwise compute canonical from the display name as a fallback.
        let fromDisplay = KnowledgeBaseFilesystem.entitySlug(from: display)
        return fromDisplay.isEmpty ? aiSlug : fromDisplay
    }
}
