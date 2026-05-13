import Foundation

// MARK: - Graph data model

/// JSON-serialisable graph payload that drives the wiki's force-directed graph view.
/// Three node kinds:
///   - `task`     — `_overview.md` of a task folder (the root of one project)
///   - `note`     — sub-task notes (`XX-*.md`) and AI task-overview notes (`00-*.md`)
///   - `entity`   — atomic notes under `_entities/`
/// Three link kinds:
///   - `parent`   — task overview ↔ its constituent notes
///   - `entity`   — note → entity it wikilinks
///   - `related`  — cross-task related links (from cross-link discovery)
struct KnowledgeGraphData: Codable, Equatable {
    struct Node: Codable, Equatable, Hashable {
        let id: String           // relative path from the wiki root, e.g. "notes/<folder>/01-foo.md"
        let title: String
        let kind: String         // "task" | "note" | "entity"
    }

    struct Link: Codable, Equatable, Hashable {
        let source: String
        let target: String
        let kind: String         // "parent" | "entity" | "related"
    }

    var nodes: [Node]
    var links: [Link]
}

// MARK: - Builder

/// Pure function that takes raw note metadata and produces the graph payload. Kept separate
/// from the actor-bound filesystem so it's testable with synthetic input.
enum KnowledgeGraphBuilder {

    /// Input for a single note file.
    struct NoteInput {
        let relativePath: String   // e.g. "notes/<folder>/01-foo.md" or "notes/_entities/openai.md"
        let title: String
        let isOverview: Bool       // `_overview.md`
        let isEntity: Bool         // inside `_entities/`
        let folderRelativePath: String  // e.g. "notes/<folder>" or "notes/_entities"
        let body: String           // raw file content (frontmatter+body), used to find wikilinks
    }

    static func build(from inputs: [NoteInput]) -> KnowledgeGraphData {
        var nodes: [KnowledgeGraphData.Node] = []
        var nodeIds = Set<String>()
        var links: [KnowledgeGraphData.Link] = []
        var linkKeys = Set<String>()

        // Index overviews by folder so we can attach parent links.
        var overviewByFolder: [String: String] = [:]   // folderRelativePath -> overview path
        for input in inputs where input.isOverview {
            overviewByFolder[input.folderRelativePath] = input.relativePath
        }

        for input in inputs {
            let kind: String
            if input.isOverview { kind = "task" }
            else if input.isEntity { kind = "entity" }
            else { kind = "note" }
            let node = KnowledgeGraphData.Node(id: input.relativePath, title: input.title, kind: kind)
            if nodeIds.insert(node.id).inserted {
                nodes.append(node)
            }
        }

        for input in inputs {
            // Parent link: every non-overview, non-entity note → its folder's overview.
            if !input.isOverview && !input.isEntity {
                if let overview = overviewByFolder[input.folderRelativePath] {
                    addLink(source: overview, target: input.relativePath, kind: "parent",
                            links: &links, keys: &linkKeys)
                }
            }

            // Entity links: scan body for `[[../_entities/<slug>.md|...]]`.
            for slug in entitySlugs(in: input.body) {
                let target = "notes/_entities/\(slug).md"
                if nodeIds.contains(target) {
                    addLink(source: input.relativePath, target: target, kind: "entity",
                            links: &links, keys: &linkKeys)
                }
            }

            // Related links: pulled from the `## Related` section's wikilinks (cross-link discovery).
            for relative in relatedTargets(in: input.body) {
                let resolved = resolve(relativeLink: relative, from: input.folderRelativePath)
                if nodeIds.contains(resolved) && resolved != input.relativePath {
                    addLink(source: input.relativePath, target: resolved, kind: "related",
                            links: &links, keys: &linkKeys)
                }
            }
        }

        return KnowledgeGraphData(nodes: nodes, links: links)
    }

    // MARK: - Private parsing helpers

    private static func addLink(
        source: String,
        target: String,
        kind: String,
        links: inout [KnowledgeGraphData.Link],
        keys: inout Set<String>
    ) {
        let key = "\(source)→\(target)|\(kind)"
        if keys.insert(key).inserted {
            links.append(.init(source: source, target: target, kind: kind))
        }
    }

    private static func entitySlugs(in body: String) -> [String] {
        // Matches `[[../_entities/<slug>.md` (display name optional).
        let pattern = #"\[\[\.\./_entities/([^/\]\|]+)\.md"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match in
            guard match.range(at: 1).location != NSNotFound else { return nil }
            return ns.substring(with: match.range(at: 1))
        }
    }

    private static func relatedTargets(in body: String) -> [String] {
        // Pull every wikilink inside the `## Related` section.
        guard let startRange = body.range(of: "## Related") else { return [] }
        let after = body[startRange.upperBound...]
        // Related section ends at the next "##" heading, the related-end comment, or end of body.
        let endMarkers = ["\n## ", "\n<!-- tada:related:end -->", "\n---\nBack to"]
        var end = after.endIndex
        for marker in endMarkers {
            if let r = after.range(of: marker) {
                if r.lowerBound < end { end = r.lowerBound }
            }
        }
        let section = after[..<end]
        let pattern = #"\[\[([^\[\]\|]+)(?:\|[^\[\]]+)?\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let str = String(section)
        let ns = str as NSString
        let matches = regex.matches(in: str, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { m in
            guard m.range(at: 1).location != NSNotFound else { return nil }
            return ns.substring(with: m.range(at: 1))
        }
    }

    /// Resolves a wikilink relative path against the source note's folder.
    /// Example: source folder "notes/<folder-a>", link "../<folder-b>/01-foo.md" → "notes/<folder-b>/01-foo.md".
    private static func resolve(relativeLink: String, from folder: String) -> String {
        var components = folder.split(separator: "/").map(String.init)
        for part in relativeLink.split(separator: "/").map(String.init) {
            if part == ".." {
                if !components.isEmpty { components.removeLast() }
            } else if part != "." {
                components.append(part)
            }
        }
        return components.joined(separator: "/")
    }
}
