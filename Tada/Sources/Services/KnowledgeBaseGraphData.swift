import Foundation

// MARK: - Graph data model

/// JSON-serialisable graph payload that drives the wiki's force-directed graph view.
/// Three node kinds:
///   - `topLevelTask` — `_overview.md` of a task folder (the root of one project)
///   - `subTask`      — sub-task notes (`XX-*.md`) and AI task-overview notes (`00-*.md`)
///   - `entity`       — atomic notes under `_entities/`
/// Three link kinds:
///   - `parent`   — task overview ↔ its constituent sub-task notes
///   - `entity`   — sub-task note → entity it wikilinks
///   - `related`  — cross-task related links (from cross-link discovery)
struct KnowledgeGraphData: Codable, Equatable {
    struct Node: Codable, Equatable, Hashable {
        let id: String           // relative path from the wiki root, e.g. "notes/<folder>/01-foo.md"
        let title: String
        let kind: String         // "topLevelTask" | "subTask" | "entity"
        let taskId: String?      // owning task's UUID string — set on task & sub-task nodes, nil otherwise
        let subtaskTitle: String?  // originating sub-task's title (from frontmatter); used to resolve phase
    }

    struct Link: Codable, Equatable, Hashable {
        let source: String
        let target: String
        let kind: String         // "parent" | "entity" | "related"
    }

    var nodes: [Node]
    var links: [Link]

    /// Returns a copy keeping only nodes that belong to a task in `allowedTaskIds`,
    /// plus entity nodes (which carry no `taskId`). Links to dropped nodes are
    /// removed. Used to hide wiki folders whose task was deleted or archived.
    func keepingTasks(in allowedTaskIds: Set<String>) -> KnowledgeGraphData {
        let keptNodes = nodes.filter { node in
            guard let taskId = node.taskId else { return true }   // entities are always kept
            return allowedTaskIds.contains(taskId)
        }
        let keptIds = Set(keptNodes.map(\.id))
        let keptLinks = links.filter { keptIds.contains($0.source) && keptIds.contains($0.target) }
        return KnowledgeGraphData(nodes: keptNodes, links: keptLinks)
    }
}

// MARK: - Task state → graph colour

/// Maps a top-level task's live state to the colour bucket the graph node uses.
/// Planning status takes precedence over phase; a completed (or archived) task
/// is `completed` regardless of phase.
enum GraphTaskState: String {
    case discovery
    case execution
    case completed

    init(task: TodoTask) {
        if task.status == .completed || task.status == .archived {
            self = .completed
            return
        }
        switch task.planningStatus {
        case .planningDiscovery:
            self = .discovery
        case .planningExecution:
            self = .execution
        case .idle:
            self = task.phase == .execution ? .execution : .discovery
        }
    }
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
        let isUserNote: Bool       // inside `_notes/` - user-created notes
        let folderRelativePath: String  // e.g. "notes/<folder>" or "notes/_entities"
        let body: String           // raw file content (frontmatter+body), used to find wikilinks
        let taskId: String?        // owning task's UUID string, from the `taskId` frontmatter field
        var subtaskTitle: String? = nil  // sub-task notes only, from the `subtaskTitle` frontmatter field
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
            if input.isUserNote { kind = "userNote" }
            else if input.isOverview { kind = "topLevelTask" }
            else if input.isEntity { kind = "entity" }
            else { kind = "subTask" }
            let node = KnowledgeGraphData.Node(
                id: input.relativePath.precomposedStringWithCanonicalMapping,
                title: input.title, kind: kind, taskId: input.taskId,
                subtaskTitle: input.subtaskTitle)
            if nodeIds.insert(node.id).inserted {
                nodes.append(node)
            }
        }

        for input in inputs {
            // Parent link: every non-overview, non-entity, non-userNote note → its folder's overview.
            if !input.isOverview && !input.isEntity && !input.isUserNote {
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

            // Entity-to-entity links: within entity notes, links are just `[[slug.md|...]]`.
            if input.isEntity {
                for slug in entityToEntitySlugs(in: input.body) {
                    let target = "notes/_entities/\(slug).md"
                    if nodeIds.contains(target) && target != input.relativePath {
                        addLink(source: input.relativePath, target: target, kind: "entity",
                                links: &links, keys: &linkKeys)
                    }
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
        // Normalise to NFC so link endpoints byte-match node ids in the emitted JSON.
        // macOS filenames are NFD; wikilinks in note bodies are NFC. Swift's String
        // compares them equal (canonical equivalence) so the builder's `nodeIds.contains`
        // check passes — but JavaScript string equality is byte-exact, so a mismatched
        // pair would leave the link's node unresolvable and force-graph would drop it.
        let source = source.precomposedStringWithCanonicalMapping
        let target = target.precomposedStringWithCanonicalMapping
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

    private static func entityToEntitySlugs(in body: String) -> [String] {
        // Matches `[[<slug>.md|...]]` for links within entity notes to other entities.
        // Excludes links with path separators and special files like index.md.
        let pattern = #"\[\[([a-z0-9-]+)\.md(?:\|[^\]]+)?\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match in
            guard match.range(at: 1).location != NSNotFound else { return nil }
            let slug = ns.substring(with: match.range(at: 1))
            // Exclude index and other special files
            if slug == "index" { return nil }
            return slug
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
