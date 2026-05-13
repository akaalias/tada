import SwiftUI
import SwiftData

/// Renders the knowledge-base wiki as a stack of styled markdown blocks. Always starts at
/// `index.md`. Wikilinks `[[target.md|Label]]` and `[[target.md]]` are rewritten to clickable
/// `file://` links that navigate to the corresponding file on disk.
struct KnowledgeBaseView: View {
    @Environment(\.appServices) private var appServices
    @Query private var allTasks: [TodoTask]
    @State private var pageStack: [URL] = []
    @State private var refreshTick: Int = 0

    private var kb: KnowledgeBaseServiceProtocol? { appServices?.knowledgeBase }
    private var rootURL: URL { kb?.rootURL ?? KnowledgeBaseService.shared.rootURL }
    private var indexURL: URL { kb?.indexURL ?? KnowledgeBaseService.shared.indexURL }

    private var currentURL: URL { pageStack.last ?? indexURL }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 0) {
                        MarkdownPageBody(url: currentURL, rootURL: rootURL)
                        TaskContextFooter(url: currentURL, tasks: allTasks)
                        BacklinksFooter(url: currentURL, refreshTick: refreshTick)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 32)
                    .frame(maxWidth: 750, alignment: .leading)
                    .id("\(currentURL.absoluteString)-\(refreshTick)")
                    Spacer(minLength: 0)
                }
            }
        }
        .navigationTitle("Knowledge Base")
        .environment(\.openURL, OpenURLAction { url in
            handleLinkTap(url)
        })
        .onReceive(NotificationCenter.default.publisher(for: .knowledgeBaseUpdated)) { _ in
            refreshTick &+= 1
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                if !pageStack.isEmpty { pageStack.removeLast() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(pageStack.isEmpty)
            .help("Back")

            Button {
                pageStack.removeAll()
            } label: {
                Image(systemName: "house")
            }
            .disabled(pageStack.isEmpty)
            .help("Index")

            Spacer()

            Text(currentURL.lastPathComponent)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if kb?.isWorking == true {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 18)
                    .help("Working…")
            } else if isEntityExtractable(currentURL) {
                Button {
                    let url = currentURL
                    Task { await kb?.runEntityExtractionForCurrentNote(url) }
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .help("Extract entities from this note (uses AI)")
                .accessibilityIdentifier("kb.extractEntities")
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([rootURL])
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal knowledge base folder in Finder")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Whether the file at the given URL is a note that benefits from entity extraction.
    /// Excludes the index, `_overview.md` (planner-set description), and entity notes themselves.
    private func isEntityExtractable(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if url.path == indexURL.path { return false }
        if name == "_overview.md" { return false }
        if url.deletingLastPathComponent().lastPathComponent == KnowledgeBaseFilesystem.entitiesFolderName { return false }
        return name.hasSuffix(".md")
    }

    private func handleLinkTap(_ url: URL) -> OpenURLAction.Result {
        if url.isFileURL && url.path.hasPrefix(rootURL.path) {
            if url != currentURL {
                pageStack.append(url)
            }
            return .handled
        }
        return .systemAction
    }
}

// MARK: - Markdown rendering

private struct MarkdownPageBody: View {
    let url: URL
    let rootURL: URL

    var body: some View {
        let raw = (try? String(contentsOf: url, encoding: .utf8))
            ?? "_File not found: \(url.lastPathComponent)_"
        let body = stripFrontmatter(raw)
        let rewritten = rewriteWikilinks(body, currentFile: url, rootURL: rootURL)
        let blocks = MarkdownBlock.parse(rewritten)

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
    }

    private func stripFrontmatter(_ raw: String) -> String {
        guard raw.hasPrefix("---") else { return raw }
        let rest = raw.dropFirst(3)
        guard let end = rest.range(of: "\n---") else { return raw }
        return String(rest[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rewriteWikilinks(_ text: String, currentFile: URL, rootURL: URL) -> String {
        let baseDir = currentFile.deletingLastPathComponent()

        // First pass: rewrite ![alt](relative.png) to absolute file:// URLs.
        var stage = text
        if let imgRegex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) {
            let ns = stage as NSString
            var out = ""
            var cursor = 0
            imgRegex.enumerateMatches(in: stage, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match else { return }
                out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                let alt = ns.substring(with: match.range(at: 1))
                let path = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                let resolved = baseDir.appendingPathComponent(path).standardizedFileURL
                if resolved.path.hasPrefix(rootURL.path) {
                    out += "![\(alt)](\(resolved.absoluteString))"
                } else {
                    out += alt
                }
                cursor = match.range.location + match.range.length
            }
            out += ns.substring(from: cursor)
            stage = out
        }

        // Second pass: rewrite [[wikilinks]] to clickable file:// markdown links.
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return stage }
        let ns = stage as NSString
        var result = ""
        var cursor = 0

        regex.enumerateMatches(in: stage, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let inner = ns.substring(with: match.range(at: 1))
            let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let target = parts[0].trimmingCharacters(in: .whitespaces)
            let label = parts.count > 1
                ? parts[1].trimmingCharacters(in: .whitespaces)
                : (target.hasSuffix(".md") ? String(target.dropLast(3)) : target)
            let resolved = baseDir.appendingPathComponent(target).standardizedFileURL
            if resolved.path.hasPrefix(rootURL.path) {
                result += "[\(label)](\(resolved.absoluteString))"
            } else {
                result += label
            }
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }
}

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case unorderedListItem(text: String)
    case orderedListItem(number: Int, text: String)
    case blockquote(text: String)
    case codeBlock(text: String)
    case horizontalRule
    case image(alt: String, url: URL)
    case table(headers: [String], rows: [[String]])

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphBuffer: [String] = []
        var codeBuffer: [String] = []
        var inFence = false

        // Strip HTML comments so internal markers like <!-- tada:related:* --> are invisible.
        let withoutComments = markdown.replacingOccurrences(
            of: #"<!--[\s\S]*?-->"#,
            with: "",
            options: .regularExpression
        )

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            blocks.append(.paragraph(text: paragraphBuffer.joined(separator: " ")))
            paragraphBuffer.removeAll()
        }

        let rawLines = withoutComments.components(separatedBy: "\n")
        var i = 0

        func tableSeparator(_ s: String) -> Bool {
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") else { return false }
            let cells = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            return !cells.isEmpty && cells.allSatisfy { cell in
                let stripped = cell.replacingOccurrences(of: ":", with: "")
                return !stripped.isEmpty && stripped.allSatisfy { $0 == "-" }
            }
        }

        func parseTableRow(_ s: String) -> [String] {
            var line = s.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("|") { line.removeFirst() }
            if line.hasSuffix("|") { line.removeLast() }
            return line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }

        while i < rawLines.count {
            let rawLine = rawLines[i]
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Try table: current line starts with | and next line is a separator
            if !inFence && trimmed.hasPrefix("|") && i + 1 < rawLines.count && tableSeparator(rawLines[i + 1]) {
                flushParagraph()
                let headers = parseTableRow(trimmed)
                var rows: [[String]] = []
                var j = i + 2
                while j < rawLines.count {
                    let next = rawLines[j].trimmingCharacters(in: .whitespaces)
                    if !next.hasPrefix("|") { break }
                    rows.append(parseTableRow(next))
                    j += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                i = j
                continue
            }

            // For every non-table branch below, ensure `i` advances exactly once.
            defer { i += 1 }

            if inFence {
                if trimmed.hasPrefix("```") {
                    blocks.append(.codeBlock(text: codeBuffer.joined(separator: "\n")))
                    codeBuffer.removeAll()
                    inFence = false
                } else {
                    codeBuffer.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                inFence = true
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let r = trimmed.range(of: #"^#{1,6}\s"#, options: .regularExpression) {
                flushParagraph()
                let hashes = trimmed[..<r.upperBound].filter { $0 == "#" }
                let text = String(trimmed[r.upperBound...])
                blocks.append(.heading(level: hashes.count, text: text))
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.horizontalRule)
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.unorderedListItem(text: String(trimmed.dropFirst(2))))
                continue
            }

            if let r = trimmed.range(of: #"^(\d+)\.\s"#, options: .regularExpression) {
                flushParagraph()
                let prefix = trimmed[..<r.upperBound]
                let number = Int(prefix.filter(\.isNumber)) ?? 1
                let text = String(trimmed[r.upperBound...])
                blocks.append(.orderedListItem(number: number, text: text))
                continue
            }

            if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.blockquote(text: String(trimmed.dropFirst(2))))
                continue
            }
            if trimmed == ">" {
                flushParagraph()
                blocks.append(.blockquote(text: ""))
                continue
            }

            // Standalone image: a whole line consisting of ![alt](url)
            if trimmed.hasPrefix("![") {
                if let imgRegex = try? NSRegularExpression(pattern: #"^!\[([^\]]*)\]\((file://[^)]+)\)$"#),
                   let match = imgRegex.firstMatch(
                       in: trimmed,
                       range: NSRange(location: 0, length: (trimmed as NSString).length)
                   ) {
                    flushParagraph()
                    let alt = (trimmed as NSString).substring(with: match.range(at: 1))
                    let urlString = (trimmed as NSString).substring(with: match.range(at: 2))
                    if let url = URL(string: urlString) {
                        blocks.append(.image(alt: alt, url: url))
                        continue
                    }
                }
            }

            paragraphBuffer.append(trimmed)
        }

        flushParagraph()
        return blocks
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    private let lineSpacing: CGFloat = 6
    private let paragraphSpacing: CGFloat = 16
    private let listItemSpacing: CGFloat = 6

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(.system(size: headingSize(level), weight: .semibold))
                .lineSpacing(level <= 2 ? 4 : 3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, headingTopPadding(level))
                .padding(.bottom, headingBottomPadding(level))
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(let text):
            Text(inline(text))
                .font(.system(size: Theme.fontSize))
                .lineSpacing(lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, paragraphSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .unorderedListItem(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•")
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(.secondary)
                if let link = SingleLinkExtractor.extract(from: text) {
                    LinkButton(label: link.label, suffix: link.suffix, url: link.url)
                } else {
                    Text(inline(text))
                        .font(.system(size: Theme.fontSize))
                        .lineSpacing(lineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 4)
            .padding(.bottom, listItemSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)

        case .orderedListItem(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(number).")
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(.secondary)
                Text(inline(text))
                    .font(.system(size: Theme.fontSize))
                    .lineSpacing(lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)
            .padding(.bottom, listItemSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 3)
                Text(inline(text))
                    .font(.system(size: Theme.fontSize))
                    .lineSpacing(lineSpacing)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
            .padding(.bottom, paragraphSpacing - 8)
            .frame(maxWidth: .infinity, alignment: .leading)

        case .codeBlock(let text):
            Text(text)
                .font(.system(size: Theme.fontSize - 1, design: .monospaced))
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(6)
                .padding(.bottom, paragraphSpacing)

        case .horizontalRule:
            Divider().padding(.vertical, 12)

        case .image(let alt, let url):
            VStack(alignment: .leading, spacing: 6) {
                if let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(6)
                } else {
                    Text("(image not found: \(url.lastPathComponent))")
                        .font(.system(size: Theme.fontSize - 1))
                        .foregroundColor(.secondary)
                }
                if !alt.isEmpty {
                    Text(alt)
                        .font(.system(size: Theme.fontSize - 2))
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding(.vertical, 12)

        case .table(let headers, let rows):
            VStack(alignment: .leading, spacing: 0) {
                tableRow(cells: headers, isHeader: true)
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    tableRow(cells: row, isHeader: false)
                    if idx < rows.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
            .padding(8)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6).stroke(Color(.separatorColor), lineWidth: 1)
            )
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func tableRow(cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { idx, cell in
                Text(inline(cell))
                    .font(.system(size: Theme.fontSize, weight: isHeader ? .semibold : .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                if idx < cells.count - 1 {
                    Divider().opacity(0.4)
                }
            }
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 28
        case 2: return 22
        case 3: return 18
        case 4: return 16
        default: return 15
        }
    }

    private func headingTopPadding(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 4
        case 2: return 28
        case 3: return 20
        default: return 14
        }
    }

    private func headingBottomPadding(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 12
        case 2: return 10
        default: return 6
        }
    }

    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attr = try? AttributedString(markdown: text, options: options) {
            return attr
        }
        return AttributedString(text)
    }
}

// MARK: - List-item link button

/// Identifies a list item whose body is a single markdown link, optionally
/// followed by some trailing plain text (e.g. " — started 12. May · 2 notes").
/// Used by the wiki renderer to render those items as real, hit-testable
/// buttons rather than inline AttributedString links.
private enum SingleLinkExtractor {
    static func extract(from text: String) -> (label: String, suffix: String, url: URL)? {
        let pattern = #"^\[([^\]]+)\]\(([^)]+)\)(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.range(at: 1).location != NSNotFound else {
            return nil
        }
        let label = ns.substring(with: match.range(at: 1))
        let urlString = ns.substring(with: match.range(at: 2))
        let suffix = ns.substring(with: match.range(at: 3))
        guard let url = URL(string: urlString) else { return nil }
        return (label, suffix, url)
    }
}

private struct LinkButton: View {
    let label: String
    let suffix: String
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Button {
                openURL(url)
            } label: {
                Text(label)
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(.accentColor)
                    .underline()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("kb.link.\(url.lastPathComponent)")
            if !suffix.isEmpty {
                Text(suffix)
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Source task footer

/// Renders the parent task (and, where applicable, sub-task) that produced the current note as
/// real UI below the markdown body. Reads `taskId` + optional `subtaskTitle` from the note's
/// frontmatter and looks them up in SwiftData. Renders nothing if the file has no task
/// association (entity notes, the index) or if the referenced task / sub-task no longer exists.
private struct TaskContextFooter: View {
    let url: URL
    let tasks: [TodoTask]

    var body: some View {
        if let context = resolve() {
            VStack(alignment: .leading, spacing: 10) {
                Text("Source")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                VStack(alignment: .leading, spacing: 6) {
                    Text(context.task.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    if let subTask = context.subTask {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(subTask.phase == .discovery ? "Question" : "Step")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.15))
                                )
                            Text(subTask.title)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !subTask.subTaskDescription.isEmpty {
                            Text(subTask.subTaskDescription)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .padding(.top, 24)
        }
    }

    private struct ResolvedContext {
        let task: TodoTask
        let subTask: SubTask?
    }

    private func resolve() -> ResolvedContext? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let meta = KnowledgeBaseFilesystem.parseFrontmatter(raw)
        guard let taskIdStr = meta["taskId"],
              let taskId = UUID(uuidString: taskIdStr),
              let task = tasks.first(where: { $0.id == taskId }) else {
            return nil
        }
        // Entity notes set `kind: entity` and have no task association.
        if meta["kind"] == "entity" { return nil }

        // Sub-task notes carry `subtaskTitle`. Match against current sub-tasks by title.
        let subTask: SubTask? = meta["subtaskTitle"].flatMap { title in
            task.sortedSubTasks.first { $0.title == title }
        }
        return ResolvedContext(task: task, subTask: subTask)
    }
}

// MARK: - Backlinks footer

/// Lists the notes that link to the entity at the current URL. Only renders for entity notes
/// (files inside `notes/_entities/`). Loads asynchronously on appear so the wiki view doesn't
/// block while scanning. Re-runs when `refreshTick` changes so the list updates after
/// extraction / generation runs.
private struct BacklinksFooter: View {
    let url: URL
    let refreshTick: Int

    @Environment(\.appServices) private var appServices
    @Environment(\.openURL) private var openURL
    @State private var backlinks: [KnowledgeBaseEntityLinker.Backlink] = []
    @State private var hasLoaded = false

    private var slug: String? {
        guard url.deletingLastPathComponent().lastPathComponent == KnowledgeBaseFilesystem.entitiesFolderName else {
            return nil
        }
        return url.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        if let slug {
            content(for: slug)
                .task(id: "\(slug)-\(refreshTick)") {
                    backlinks = await appServices?.knowledgeBase.backlinks(toEntitySlug: slug) ?? []
                    hasLoaded = true
                }
        }
    }

    @ViewBuilder
    private func content(for slug: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Backlinks")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            if !hasLoaded {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning…").font(.system(size: 12)).foregroundColor(.secondary)
                }
                .padding(12)
            } else if backlinks.isEmpty {
                Text("No notes link to this entity yet.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(backlinks.enumerated()), id: \.element.id) { idx, link in
                        Button {
                            openURL(link.fileURL)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(link.noteTitle)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    if let taskTitle = link.taskTitle {
                                        Text(taskTitle)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < backlinks.count - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }
        }
        .padding(.top, 24)
    }
}

#Preview {
    KnowledgeBaseView()
}
