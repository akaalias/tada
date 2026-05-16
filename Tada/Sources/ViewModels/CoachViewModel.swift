import Foundation
import SwiftData

/// ViewModel for the productivity coach chat panel.
@Observable
@MainActor
final class CoachViewModel {
    var messages: [CoachMessage] = []
    var inputText: String = ""
    var isLoading: Bool = false
    var error: String?

    private var coachService: CoachService?
    let context: CoachContext
    var modelContext: ModelContext?
    var knowledgeBase: KnowledgeBaseServiceProtocol?
    var plannerAI: PlannerAIServiceProtocol?

    init(context: CoachContext) {
        self.context = context
        if let apiKey = APIKeyManager.getAPIKey() {
            self.coachService = CoachService(apiKey: apiKey)
        }
        addWelcomeMessage()
    }

    private func addWelcomeMessage() {
        let welcome = CoachMessage(
            role: .coach,
            content: "Hi, I'm your productivity coach. I can help you manage tasks, answer questions about your work, and take actions on your behalf. What would you like to do?"
        )
        messages.append(welcome)
    }

    func sendMessage() async {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }
        guard let service = coachService else {
            error = "API key not configured"
            return
        }

        let userMessage = CoachMessage(role: .user, content: trimmedInput)
        messages.append(userMessage)
        inputText = ""
        isLoading = true
        error = nil

        do {
            let taskSummary = buildTaskSummary()
            var continueLoop = true
            var pendingToolResults: [CoachMessage.ToolResult]? = nil

            while continueLoop {
                let response = try await service.chat(
                    userMessage: trimmedInput,
                    context: context.contextDescription,
                    conversationHistory: messages,
                    taskSummary: taskSummary,
                    toolResults: pendingToolResults
                )

                if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                    let toolResults = await executeToolCalls(toolCalls)
                    let coachMessage = CoachMessage(
                        role: .coach,
                        content: response.message,
                        toolCalls: toolCalls,
                        toolResults: toolResults
                    )
                    messages.append(coachMessage)
                    pendingToolResults = toolResults
                } else {
                    if !response.message.isEmpty {
                        let coachMessage = CoachMessage(role: .coach, content: response.message)
                        messages.append(coachMessage)
                    }
                    continueLoop = false
                }
            }
        } catch {
            self.error = error.localizedDescription
            let errorMessage = CoachMessage(
                role: .system,
                content: "Something went wrong: \(error.localizedDescription)"
            )
            messages.append(errorMessage)
        }

        isLoading = false
    }

    private func buildTaskSummary() -> String? {
        guard let modelContext else { return nil }

        let descriptor = FetchDescriptor<TodoTask>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let allTasks = try? modelContext.fetch(descriptor) else {
            return nil
        }

        let activeTasks = allTasks.filter { $0.status == .active }
        guard !activeTasks.isEmpty else { return nil }

        return activeTasks.prefix(5).map { task in
            let phase = task.isDiscoveryPhase ? "discovery" : "execution"
            let progress = Int(task.progress * 100)
            return "- \(task.title) [\(phase), \(progress)% done]"
        }.joined(separator: "\n")
    }

    private func executeToolCalls(_ toolCalls: [ToolCall]) async -> [CoachMessage.ToolResult] {
        var results: [CoachMessage.ToolResult] = []

        for call in toolCalls {
            guard let tool = CoachTool(rawValue: call.name) else {
                results.append(CoachMessage.ToolResult(
                    toolUseId: call.id,
                    toolName: call.name,
                    success: false,
                    message: "Unknown tool"
                ))
                continue
            }

            let (success, message) = await executeTool(tool, arguments: call.arguments)
            results.append(CoachMessage.ToolResult(
                toolUseId: call.id,
                toolName: call.name,
                success: success,
                message: message
            ))
        }

        return results
    }

    private func executeTool(_ tool: CoachTool, arguments: [String: String]) async -> (success: Bool, message: String) {
        switch tool {
        case .captureInboxItem:
            return await captureInboxItem(content: arguments["content"] ?? "")

        case .createTask:
            return await createTask(description: arguments["description"] ?? "")

        case .searchTasks:
            return await searchTasks(query: arguments["query"] ?? "")

        case .updateDiscoveryQuestions:
            return await updateDiscoveryQuestions(
                taskIdString: arguments["task_id"] ?? "",
                newFraming: arguments["new_framing"] ?? ""
            )

        case .replanExecution:
            return await replanExecution(
                taskIdString: arguments["task_id"] ?? "",
                guidance: arguments["guidance"]
            )

        case .readNote:
            return await readNote(notePath: arguments["note_path"] ?? "")

        case .createKnowledgeEntity:
            return await createKnowledgeEntity(
                name: arguments["name"] ?? "",
                content: arguments["content"]
            )

        case .linkKnowledgeEntities:
            return await linkKnowledgeEntities(
                sourceNote: arguments["source_note"] ?? "",
                targetEntity: arguments["target_entity"] ?? ""
            )

        case .replaceTextWithLink:
            return await replaceTextWithLink(
                notePath: arguments["note_path"] ?? "",
                textToFind: arguments["text_to_find"] ?? "",
                targetEntity: arguments["target_entity"] ?? ""
            )

        case .editNote:
            return await editNote(
                notePath: arguments["note_path"] ?? "",
                newBody: arguments["new_body"] ?? ""
            )

        case .generateKnowledgeSummary:
            return await generateKnowledgeSummary()

        case .completeSubTask:
            return await completeSubTask(
                taskIdString: arguments["task_id"] ?? "",
                subtaskIdString: arguments["subtask_id"] ?? ""
            )

        case .skipSubTask:
            return await skipSubTask(
                taskIdString: arguments["task_id"] ?? "",
                subtaskIdString: arguments["subtask_id"] ?? ""
            )
        }
    }

    // MARK: - Tool Implementations

    private func captureInboxItem(content: String) async -> (success: Bool, message: String) {
        guard let modelContext else {
            return (false, "No model context")
        }

        let task = TodoTask(title: content, originalInput: content)
        modelContext.insert(task)

        do {
            try modelContext.save()
            return (true, "Captured: \(content)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func createTask(description: String) async -> (success: Bool, message: String) {
        guard let modelContext else {
            return (false, "No model context")
        }

        let task = TodoTask(title: description, originalInput: description)

        if APIKeyManager.hasAPIKey {
            task.planningStatus = .planningDiscovery
        }

        modelContext.insert(task)

        do {
            try modelContext.save()
            knowledgeBase?.handleTaskCreatedOrUpdated(task)

            if APIKeyManager.hasAPIKey, let plannerAI {
                Task {
                    do {
                        let plan = try await plannerAI.generateDiscoveryQuestions(for: description)

                        await MainActor.run {
                            task.title = plan.title
                            task.taskDescription = plan.description

                            for (index, subTaskPlan) in plan.subTasks.prefix(AppConstants.maxDiscoveryQuestions).enumerated() {
                                let subTask = SubTask(
                                    title: subTaskPlan.title,
                                    description: subTaskPlan.description,
                                    order: index
                                )
                                if index == 0 {
                                    subTask.markCurrent()
                                }
                                task.addSubTask(subTask)
                                modelContext.insert(subTask)
                            }

                            task.planningStatus = .idle
                            try? modelContext.save()
                            knowledgeBase?.handleTaskCreatedOrUpdated(task)
                        }
                    } catch {
                        await MainActor.run {
                            task.planningStatus = .idle
                            try? modelContext.save()
                        }
                    }
                }
            }

            return (true, "Created task: \(description)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func searchTasks(query: String) async -> (success: Bool, message: String) {
        guard let modelContext else {
            return (false, "No model context")
        }

        let descriptor = FetchDescriptor<TodoTask>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let allTasks = try? modelContext.fetch(descriptor) else {
            return (false, "Failed to fetch tasks")
        }

        let lowercaseQuery = query.lowercased()
        let matchingTasks = allTasks.filter { task in
            task.title.lowercased().contains(lowercaseQuery) ||
            task.taskDescription.lowercased().contains(lowercaseQuery) ||
            task.originalInput.lowercased().contains(lowercaseQuery)
        }

        if matchingTasks.isEmpty {
            return (true, "No tasks found matching '\(query)'")
        }

        let results = matchingTasks.prefix(5).map { task in
            let phase = task.isDiscoveryPhase ? "discovery" : "execution"
            let status = task.status == .completed ? "completed" : "active"
            return "- ID: \(task.id.uuidString)\n  Title: \(task.title)\n  Phase: \(phase), Status: \(status)"
        }.joined(separator: "\n")

        return (true, "Found \(matchingTasks.count) task(s):\n\(results)")
    }

    private func updateDiscoveryQuestions(taskIdString: String, newFraming: String) async -> (success: Bool, message: String) {
        guard let taskId = UUID(uuidString: taskIdString) else {
            return (false, "Invalid task ID")
        }

        guard let modelContext else {
            return (false, "No model context")
        }

        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.id == taskId }
        )

        guard let task = try? modelContext.fetch(descriptor).first else {
            return (false, "Task not found")
        }

        guard let plannerAI else {
            return (false, "Planner AI not available")
        }

        for subTask in task.subTasks {
            modelContext.delete(subTask)
        }
        task.phase = .discovery
        task.planningStatus = .planningDiscovery
        try? modelContext.save()

        do {
            let newInput = "\(task.originalInput)\n\nAdditional context: \(newFraming)"
            let plan = try await plannerAI.generateDiscoveryQuestions(for: newInput)

            task.title = plan.title
            task.taskDescription = plan.description

            for (index, subTaskPlan) in plan.subTasks.prefix(AppConstants.maxDiscoveryQuestions).enumerated() {
                let subTask = SubTask(
                    title: subTaskPlan.title,
                    description: subTaskPlan.description,
                    order: index
                )
                if index == 0 {
                    subTask.markCurrent()
                }
                task.addSubTask(subTask)
                modelContext.insert(subTask)
            }

            task.planningStatus = .idle
            try modelContext.save()
            knowledgeBase?.handleTaskCreatedOrUpdated(task)

            return (true, "Regenerated discovery questions for \(task.title)")
        } catch {
            task.planningStatus = .idle
            try? modelContext.save()
            return (false, error.localizedDescription)
        }
    }

    private func replanExecution(taskIdString: String, guidance: String?) async -> (success: Bool, message: String) {
        guard let taskId = UUID(uuidString: taskIdString) else {
            return (false, "Invalid task ID")
        }

        guard let modelContext else {
            return (false, "No model context")
        }

        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.id == taskId }
        )

        guard let task = try? modelContext.fetch(descriptor).first else {
            return (false, "Task not found")
        }

        guard let plannerAI else {
            return (false, "Planner AI not available")
        }

        for subTask in task.executionSubTasks {
            modelContext.delete(subTask)
        }
        task.planningStatus = .planningExecution
        try? modelContext.save()

        do {
            let discoveryAnswers = task.discoverySubTasks
                .filter { $0.isCompleted }
                .map { subTask -> CompletedSubTaskInfo in
                    var responseStr = ""
                    if let data = subTask.actionResponseData,
                       let response = try? JSONDecoder().decode(ActionResponse.self, from: data) {
                        responseStr = formatResponseValues(response)
                    }
                    return CompletedSubTaskInfo(title: subTask.title, response: responseStr)
                }

            var modifiedAnswers = discoveryAnswers
            if let guidance, !guidance.isEmpty {
                modifiedAnswers.append(CompletedSubTaskInfo(title: "Additional guidance", response: guidance))
            }

            let executionPlan = try await plannerAI.createExecutionPlan(
                originalTask: task.originalInput,
                discoveryAnswers: modifiedAnswers
            )

            task.title = executionPlan.title
            task.taskDescription = executionPlan.description

            let startOrder = task.discoverySubTasks.count
            for (index, subTaskPlan) in executionPlan.subTasks.enumerated() {
                let subTask = SubTask(
                    title: subTaskPlan.title,
                    description: subTaskPlan.description,
                    order: startOrder + index,
                    phase: .execution,
                    requiresExternalAction: subTaskPlan.requiresExternalAction ?? false
                )
                if index == 0 {
                    subTask.markCurrent()
                }
                task.addSubTask(subTask)
                modelContext.insert(subTask)
            }

            task.planningStatus = .idle
            try modelContext.save()
            knowledgeBase?.handleTaskCreatedOrUpdated(task)

            return (true, "Regenerated execution plan for \(task.title)")
        } catch {
            task.planningStatus = .idle
            try? modelContext.save()
            return (false, error.localizedDescription)
        }
    }

    private func readNote(notePath: String) async -> (success: Bool, message: String) {
        let noteURL = URL(fileURLWithPath: notePath)

        guard FileManager.default.fileExists(atPath: noteURL.path) else {
            return (false, "Note not found: \(notePath)")
        }

        do {
            let content = try String(contentsOf: noteURL, encoding: .utf8)
            return (true, content)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func createKnowledgeEntity(name: String, content: String?) async -> (success: Bool, message: String) {
        guard let knowledgeBase else {
            return (false, "Knowledge base not available")
        }

        let body = content?.isEmpty == false ? content! : "Knowledge base entry for \(name)."

        do {
            try await knowledgeBase.createEntity(name: name, body: body)
            return (true, "Created entity: \(name)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func linkKnowledgeEntities(sourceNote: String, targetEntity: String) async -> (success: Bool, message: String) {
        guard let knowledgeBase else {
            return (false, "Knowledge base not available")
        }

        var sourceURL: URL
        if sourceNote.hasPrefix("/") {
            sourceURL = URL(fileURLWithPath: sourceNote)
        } else {
            sourceURL = knowledgeBase.rootURL.appendingPathComponent(sourceNote)
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return (false, "Source note not found: \(sourceNote)")
        }

        do {
            try await knowledgeBase.addLinkToNote(at: sourceURL, targetEntity: targetEntity)
            return (true, "Linked \(sourceNote) to \(targetEntity)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func replaceTextWithLink(notePath: String, textToFind: String, targetEntity: String) async -> (success: Bool, message: String) {
        guard let knowledgeBase else {
            return (false, "Knowledge base not available")
        }

        let noteURL = URL(fileURLWithPath: notePath)

        guard FileManager.default.fileExists(atPath: noteURL.path) else {
            return (false, "Note not found: \(notePath)")
        }

        do {
            try await knowledgeBase.replaceTextWithLink(at: noteURL, textToFind: textToFind, targetEntity: targetEntity)
            return (true, "Replaced '\(textToFind)' with link to \(targetEntity)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func editNote(notePath: String, newBody: String) async -> (success: Bool, message: String) {
        guard let knowledgeBase else {
            return (false, "Knowledge base not available")
        }

        let noteURL = URL(fileURLWithPath: notePath)

        guard FileManager.default.fileExists(atPath: noteURL.path) else {
            return (false, "Note not found: \(notePath)")
        }

        do {
            try await knowledgeBase.editNoteBody(at: noteURL, newBody: newBody)
            return (true, "Updated note content")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func generateKnowledgeSummary() async -> (success: Bool, message: String) {
        guard let knowledgeBase else {
            return (false, "Knowledge base not available")
        }

        do {
            let summary = try await knowledgeBase.generateSummary()
            return (true, summary)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func completeSubTask(taskIdString: String, subtaskIdString: String) async -> (success: Bool, message: String) {
        guard let taskId = UUID(uuidString: taskIdString),
              let subtaskId = UUID(uuidString: subtaskIdString) else {
            return (false, "Invalid ID")
        }

        guard let modelContext else {
            return (false, "No model context")
        }

        let taskDescriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.id == taskId }
        )

        guard let task = try? modelContext.fetch(taskDescriptor).first,
              let subTask = task.subTasks.first(where: { $0.id == subtaskId }) else {
            return (false, "Task or subtask not found")
        }

        subTask.markCompleted()
        if let nextSubTask = task.subTasks.first(where: { !$0.isCompleted && $0.status != .skipped }) {
            nextSubTask.markCurrent()
        }

        do {
            try modelContext.save()
            return (true, "Completed: \(subTask.title)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func skipSubTask(taskIdString: String, subtaskIdString: String) async -> (success: Bool, message: String) {
        guard let taskId = UUID(uuidString: taskIdString),
              let subtaskId = UUID(uuidString: subtaskIdString) else {
            return (false, "Invalid ID")
        }

        guard let modelContext else {
            return (false, "No model context")
        }

        let taskDescriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.id == taskId }
        )

        guard let task = try? modelContext.fetch(taskDescriptor).first,
              let subTask = task.subTasks.first(where: { $0.id == subtaskId }) else {
            return (false, "Task or subtask not found")
        }

        subTask.skip()
        if let nextSubTask = task.subTasks.first(where: { !$0.isCompleted && $0.status != .skipped }) {
            nextSubTask.markCurrent()
        }

        do {
            try modelContext.save()
            return (true, "Skipped: \(subTask.title)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func clearChat() {
        messages.removeAll()
        addWelcomeMessage()
        error = nil
    }
}
