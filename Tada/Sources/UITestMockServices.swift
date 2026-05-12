import Foundation

/// Deterministic stand-ins for the AI/knowledge services, used only under
/// `UITestSupport.isActive`. They emit a fixed, scripted plan so UI tests can
/// assert end-to-end flows without touching the network.
@MainActor
final class UITestPlannerAIService: PlannerAIServiceProtocol {

    static let discoveryQuestions: [String] = [
        "What dates are you traveling?"
    ]

    static let executionSteps: [String] = [
        "Book flights"
    ]

    func generateDiscoveryQuestions(for task: String) async throws -> TaskPlan {
        TaskPlan(
            title: task,
            description: "Test discovery plan",
            subTasks: Self.discoveryQuestions.map {
                SubTaskPlan(title: $0, description: "", requiresExternalAction: false)
            }
        )
    }

    func createExecutionPlan(
        originalTask: String,
        discoveryAnswers: [CompletedSubTaskInfo]
    ) async throws -> TaskPlan {
        // Real-world planning has perceptible latency; tests rely on this delay
        // to observe the "Planning Execution:" header before the first exec step
        // is current. XCUITest polls at ~1Hz, so the window must be >1s.
        try await Task.sleep(nanoseconds: 2_000_000_000)
        return TaskPlan(
            title: originalTask,
            description: "Test execution plan",
            subTasks: Self.executionSteps.map {
                SubTaskPlan(title: $0, description: "", requiresExternalAction: false)
            }
        )
    }

    func revisePlan(
        originalTask: String,
        completedSubTasks: [CompletedSubTaskInfo],
        remainingSubTasks: [String],
        latestResponse: [String: Any]
    ) async throws -> PlanRevision {
        PlanRevision(revised: false, reason: nil, subTasks: nil)
    }

    func breakDownStep(
        stepTitle: String,
        stepDescription: String,
        taskContext: String,
        discoveryContext: String,
        executionProgress: String
    ) async throws -> [SubTaskPlan] {
        [SubTaskPlan(title: "Sub-step", description: "", requiresExternalAction: false)]
    }

    func generateLearning(
        badStepTitle: String,
        taskContext: String,
        discoveryContext: String,
        executionProgress: String
    ) async throws -> String {
        "Test learning"
    }
}

/// Always returns a single text-field schema so every step is a simple form.
final class UITestExecutiveAIService: ExecutiveAIServiceProtocol {
    func generateActionUI(
        subTask: String,
        subTaskDescription: String,
        taskContext: String,
        previousResponses: [[String: String]],
        taskMemory: String
    ) async throws -> ActionSchema {
        let field = ActionField(
            id: "field_text",
            type: .text,
            label: subTask,
            placeholder: "Enter your response...",
            options: nil,
            defaultValue: nil,
            prefillRows: nil
        )
        return ActionSchema(
            type: .form,
            title: subTask,
            description: subTaskDescription,
            fields: [field],
            submitLabel: "Continue",
            requiresExternalAction: false
        )
    }
}

/// Test-mode knowledge base. Writes structural notes synchronously to a stable
/// path so the UI-test process can verify the expected files exist after a
/// task journey. The file/folder layout and on-disk format mirror the real
/// `KnowledgeBaseFilesystem` / `KnowledgeBaseIndexer` output so UI rendering
/// is identical to production.
///
/// The test process is responsible for wiping `rootURL` in `setUp` before each
/// run.
@MainActor
final class UITestKnowledgeBaseService: KnowledgeBaseServiceProtocol {
    /// The UI test process passes its own temp path via the
    /// `TADA_UI_TEST_KB_PATH` env var. We use it directly so writes here are
    /// visible to the (sandboxed) test process when it polls for note files.
    /// Falls back to NSTemporaryDirectory if the env var isn't set.
    static let stableRootURL: URL = {
        if let path = ProcessInfo.processInfo.environment["TADA_UI_TEST_KB_PATH"] {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TadaUITestKnowledgeBase", isDirectory: true)
    }()

    let rootURL: URL = stableRootURL
    var indexURL: URL { rootURL.appendingPathComponent("index.md") }
    let isWorking: Bool = false

    private var notesURL: URL { rootURL.appendingPathComponent("notes", isDirectory: true) }

    init() {
        try? FileManager.default.createDirectory(at: notesURL, withIntermediateDirectories: true)
    }

    func handleTaskCreatedOrUpdated(_ task: TodoTask) {
        let folder = ensureFolder(for: task)
        writeOverview(in: folder, for: task)
        writeIndex()
    }

    func handleSubtaskCompleted(_ subTask: SubTask) {
        guard let parent = subTask.task else { return }
        let folder = ensureFolder(for: parent)
        // Write a note for every completed subtask that doesn't have one yet.
        for (index, st) in parent.sortedSubTasks.enumerated() where st.isCompleted {
            let filename = String(format: "%02d-%@.md", index + 1, Self.slugify(st.title))
            let url = folder.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: url.path) {
                let body = """
                ---
                title: \(escapeFrontmatter(st.title))
                ---

                # \(st.title)

                \(KnowledgeResponseExtractor.responseString(for: st))
                """
                try? body.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        writeOverview(in: folder, for: parent)
        writeIndex()
    }

    func handleTaskCompleted(_ task: TodoTask) {
        // The real app also writes an AI-generated `00-<title>.md` task
        // summary here, but that requires Claude and would be a stub in test
        // mode. We skip it so the overview's "Sub-task notes" list contains
        // only the user's actual sub-tasks, in order.
        let folder = ensureFolder(for: task)
        writeOverview(in: folder, for: task)
        writeIndex()
    }

    func reconcile(tasks: [TodoTask]) {
        for task in tasks { handleTaskCreatedOrUpdated(task) }
    }

    func runLinkDiscoveryNow() async {}

    // MARK: - Helpers (mirror KnowledgeBaseFilesystem / KnowledgeBaseIndexer formats)

    private func ensureFolder(for task: TodoTask) -> URL {
        let name = "\(task.id.uuidString)__\(Self.slugify(task.title))"
        let folder = notesURL.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func writeOverview(in folder: URL, for task: TodoTask) {
        let iso = ISO8601DateFormatter()
        let noteURLs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let noteLines = noteURLs
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "_overview.md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url -> String in
                let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                let title = parseTitleFromFrontmatter(raw) ?? url.deletingPathExtension().lastPathComponent
                return "- [[\(url.lastPathComponent)|\(title)]]"
            }
            .joined(separator: "\n")

        let completedLine = task.completedAt.map { "completedAt: \(iso.string(from: $0))\n" } ?? ""
        let description = task.taskDescription.isEmpty ? task.originalInput : task.taskDescription
        let body = """
        ---
        taskId: \(task.id.uuidString)
        title: \(escapeFrontmatter(task.title))
        status: \(task.status)
        createdAt: \(iso.string(from: task.createdAt))
        \(completedLine)---

        # \(task.title)

        \(description.isEmpty ? "" : description + "\n")
        > Original request: \(task.originalInput)

        ## Sub-task notes

        \(noteLines.isEmpty ? "_None yet — sub-task notes will appear here as you answer questions and complete steps._" : noteLines)

        ## Back

        [[../../index.md|Knowledge Base index]]
        """
        try? body.write(to: folder.appendingPathComponent("_overview.md"), atomically: true, encoding: .utf8)
    }

    private func writeIndex() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: notesURL, includingPropertiesForKeys: nil)) ?? []
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var lines: [String] = [
            "# Knowledge Base",
            "",
            "An auto-growing wiki of every task and sub-task captured in Tada.",
            ""
        ]

        var active: [(folderName: String, title: String, date: Date, noteCount: Int)] = []
        var completed: [(folderName: String, title: String, date: Date, noteCount: Int)] = []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let overviewURL = folder.appendingPathComponent("_overview.md")
            guard let raw = try? String(contentsOf: overviewURL, encoding: .utf8) else { continue }
            let meta = parseFrontmatter(raw)
            let title = meta["title"] ?? folder.lastPathComponent
            let status = meta["status"] ?? "active"
            let iso = ISO8601DateFormatter()
            let date = meta["completedAt"].flatMap { iso.date(from: $0) }
                ?? meta["createdAt"].flatMap { iso.date(from: $0) }
                ?? Date()
            let noteCount = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "md" && $0.lastPathComponent != "_overview.md" }.count ?? 0
            let entry = (folder.lastPathComponent, title, date, noteCount)
            if status == "completed" {
                completed.append(entry)
            } else {
                active.append(entry)
            }
        }

        if !active.isEmpty {
            lines.append("## In progress")
            lines.append("")
            for e in active {
                lines.append("- [[notes/\(e.folderName)/_overview.md|\(e.title)]] — started \(dateFormatter.string(from: e.date)) · \(e.noteCount) note\(e.noteCount == 1 ? "" : "s")")
            }
            lines.append("")
        }

        if !completed.isEmpty {
            lines.append("## Completed")
            lines.append("")
            for e in completed {
                lines.append("- [[notes/\(e.folderName)/_overview.md|\(e.title)]] — completed \(dateFormatter.string(from: e.date)) · \(e.noteCount) note\(e.noteCount == 1 ? "" : "s")")
            }
            lines.append("")
        }

        if active.isEmpty && completed.isEmpty {
            lines.append("_No tasks yet. Create one and it will appear here._")
        }

        try? lines.joined(separator: "\n").write(to: indexURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Frontmatter helpers

    private func parseFrontmatter(_ raw: String) -> [String: String] {
        guard raw.hasPrefix("---") else { return [:] }
        let rest = raw.dropFirst(3)
        guard let end = rest.range(of: "\n---") else { return [:] }
        let block = rest[rest.startIndex..<end.lowerBound]
        var dict: [String: String] = [:]
        for line in block.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            var value = parts[1]
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            dict[parts[0]] = value
        }
        return dict
    }

    private func parseTitleFromFrontmatter(_ raw: String) -> String? {
        parseFrontmatter(raw)["title"]
    }

    private func escapeFrontmatter(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func slugify(_ s: String) -> String {
        let lowered = s.lowercased()
        let mapped = lowered.map { (c: Character) -> Character in
            (c.isLetter || c.isNumber) ? c : "-"
        }
        let collapsed = String(mapped).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return String(collapsed.prefix(48))
    }
}
