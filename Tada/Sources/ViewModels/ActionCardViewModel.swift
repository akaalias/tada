import Foundation
import SwiftData
import SwiftUI
import Observation

@Observable
@MainActor
final class ActionCardViewModel {
    let task: TodoTask
    var modelContext: ModelContext?
    private let knowledgeBase: KnowledgeBaseServiceProtocol

    var actionSchema: ActionSchema?
    var actionResponse = ActionResponse()
    var isLoadingSchema = false
    var schemaError: String?
    var submissionState: SubmissionState = .idle
    var progressLog: [String] = []
    var pendingSubTask: SubTask?
    var selectedBlocker: BlockerType?
    var showingBlockerSelection = false
    var showingNudgeInput = false

    init(task: TodoTask, knowledgeBase: KnowledgeBaseServiceProtocol) {
        self.task = task
        self.knowledgeBase = knowledgeBase
    }

    // MARK: - Computed

    var phaseColor: Color {
        task.isDiscoveryPhase ? .orange : .blue
    }

    var isTransitioningToExecution: Bool {
        task.isDiscoveryPhase &&
        !task.discoverySubTasks.isEmpty &&
        task.discoverySubTasks.allSatisfy({ $0.isCompleted }) &&
        task.executionSubTasks.isEmpty
    }

    var currentIndex: Int {
        task.sortedSubTasks.firstIndex(where: { $0.id == task.currentSubTask?.id }) ?? 0
    }

    // MARK: - Schema loading

    func clearSchemaForNewSubTask() {
        actionSchema = nil
        actionResponse = ActionResponse()
        schemaError = nil
    }

    func loadOrGenerateActionUI(for subTask: SubTask) {
        if let cachedData = subTask.actionSchemaData,
           let cachedSchema = try? JSONDecoder().decode(ActionSchema.self, from: cachedData) {
            self.actionSchema = cachedSchema
            self.isLoadingSchema = false
            return
        }
        generateActionUI(for: subTask)
    }

    func regenerateActionUI(for subTask: SubTask) {
        subTask.actionSchemaData = nil
        actionSchema = nil
        actionResponse = ActionResponse()
        try? modelContext?.save()
        generateActionUI(for: subTask)
    }

    func changeFieldType(to newType: ActionField.FieldType, options: [FieldOption]?, for subTask: SubTask) {
        var defaultValue: String? = nil
        var prefillRows: [[String: String]]? = nil

        let currentText = actionResponse.values.compactMap { _, value -> String? in
            switch value {
            case .string(let s):
                if s.hasPrefix("data:image") { return nil }
                return s.isEmpty ? nil : s
            case .number(let n): return String(format: "%.0f", n)
            case .stringArray(let arr): return arr.joined(separator: "\n")
            default: return nil
            }
        }.joined(separator: "\n")

        if newType == .textarea || newType == .text {
            if !currentText.isEmpty {
                if currentText.contains("; ") {
                    let items = currentText
                        .replacingOccurrences(of: " (Total: €", with: "\n\nTotal: €")
                        .replacingOccurrences(of: " (Total: $", with: "\n\nTotal: $")
                        .replacingOccurrences(of: ")", with: "")
                        .components(separatedBy: "; ")
                        .joined(separator: "\n")
                    defaultValue = items
                } else {
                    defaultValue = currentText
                }
            }
        } else if newType == .itemTable {
            if !currentText.isEmpty {
                let lines = currentText.components(separatedBy: "\n").filter { !$0.isEmpty }
                prefillRows = lines.map { ["item": $0] }
            }
        }

        let newField = ActionField(
            id: "field_\(newType.rawValue)",
            type: newType,
            label: "",
            placeholder: newType == .textarea ? "Enter your response here..." : nil,
            options: options,
            defaultValue: defaultValue,
            prefillRows: prefillRows
        )

        let newSchema = ActionSchema(
            type: .form,
            title: actionSchema?.title ?? subTask.title,
            description: actionSchema?.description ?? subTask.subTaskDescription,
            fields: [newField],
            submitLabel: "Save",
            requiresExternalAction: subTask.effectiveRequiresExternalAction
        )

        actionResponse = ActionResponse()
        actionSchema = newSchema

        if let schemaData = try? JSONEncoder().encode(newSchema) {
            subTask.actionSchemaData = schemaData
            try? modelContext?.save()
        }
    }

    func generateActionUI(for subTask: SubTask) {
        guard let apiKey = APIKeyManager.getAPIKey() else { return }

        clearProgressLog()
        addProgressMessage("Creating a custom UI for \(subTask.title)")
        isLoadingSchema = true
        schemaError = nil

        let previousResponses = gatherPreviousResponses()

        Task {
            do {
                let executive = ExecutiveAIService(apiKey: apiKey)
                let schema = try await executive.generateActionUI(
                    subTask: subTask.title,
                    subTaskDescription: subTask.subTaskDescription,
                    taskContext: task.title,
                    previousResponses: previousResponses,
                    taskMemory: task.memory
                )

                await MainActor.run {
                    self.actionSchema = schema
                    self.isLoadingSchema = false
                    clearProgressLog()

                    if let schemaData = try? JSONEncoder().encode(schema) {
                        subTask.actionSchemaData = schemaData
                        try? modelContext?.save()
                    }
                }
            } catch {
                await MainActor.run {
                    self.schemaError = error.localizedDescription
                    self.isLoadingSchema = false
                    clearProgressLog()
                }
            }
        }
    }

    // MARK: - Completion flow

    func completeSubTaskWithResponse(_ subTask: SubTask) {
        if subTask.effectiveRequiresExternalAction || actionSchema?.requiresExternalAction == true {
            for (_, value) in actionResponse.values {
                if case .boolean(let answered) = value, answered == false {
                    pendingSubTask = subTask
                    showingBlockerSelection = true
                    return
                }
            }
        }
        proceedWithCompletion(subTask)
    }

    private func proceedWithCompletion(_ subTask: SubTask) {
        clearProgressLog()
        submissionState = .saving
        addProgressMessage("Saving your response...")

        if let responseData = try? JSONEncoder().encode(actionResponse) {
            subTask.actionResponseData = responseData
        }

        subTask.markCompleted()
        try? modelContext?.save()
        knowledgeBase.handleSubtaskCompleted(subTask)

        if task.isDiscoveryPhase {
            let remainingQuestions = task.sortedSubTasks.filter { $0.isPending }

            if remainingQuestions.isEmpty {
                addProgressMessage("All questions answered")
                transitionToExecutionPhase()
            } else {
                addProgressMessage("Moving to next question...")
                if let next = remainingQuestions.first {
                    next.markCurrent()
                }
                try? modelContext?.save()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.resetForNextAction()
                }
            }
        } else {
            addProgressMessage("Step completed")
            let remainingSteps = task.sortedSubTasks.filter({ $0.phase == TaskPhase.execution && $0.isPending })

            if remainingSteps.count > 1 {
                addProgressMessage("Reviewing plan...")
                revisePlanIfNeeded(remainingSteps: remainingSteps)
            } else if let next = remainingSteps.first {
                next.markCurrent()
                addProgressMessage("Moving to next step...")
                try? modelContext?.save()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.resetForNextAction()
                }
            } else {
                addProgressMessage("All steps completed!")
                addProgressMessage("Task complete!")

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    guard let self else { return }
                    self.task.markCompleted()
                    try? self.modelContext?.save()
                    knowledgeBase.handleTaskCompleted(self.task)
                    self.resetForNextAction()
                }
            }
        }
    }

    // MARK: - Blocker handling

    func handleBlockerSelection(_ blocker: BlockerType) {
        showingBlockerSelection = false

        guard let currentSubTask = pendingSubTask else { return }

        clearProgressLog()
        submissionState = .saving

        switch blocker {
        case .needsBreakingDown:
            addProgressMessage("Splitting this into separate steps...")
            breakDownOverwhelmingStep(currentSubTask)

        case .overwhelming:
            addProgressMessage("Let's break this into smaller steps...")
            breakDownOverwhelmingStep(currentSubTask)

        case .doesntMakeSense:
            addProgressMessage("Removing this step...")
            deleteSubTask(currentSubTask)

        case .remember:
            pendingSubTask = nil
            submissionState = .idle
            showingNudgeInput = true

        case .needInfo:
            addProgressMessage("What information do you need?")
            pendingSubTask = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.resetForNextAction()
            }

        case .badTiming:
            addProgressMessage("No problem, we'll come back to this later")
            pendingSubTask = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.resetForNextAction()
            }

        case .anxious:
            addProgressMessage("That's okay - let's think about what's making this feel hard")
            pendingSubTask = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.resetForNextAction()
            }
        }
    }

    private func deleteSubTask(_ subTask: SubTask) {
        let badStepTitle = subTask.title
        let taskContext = task.title

        let discoveryContext = task.discoverySubTasks
            .filter { $0.isCompleted }
            .map { ds -> String in
                var responseStr = "(no response)"
                if let data = ds.actionResponseData,
                   let response = try? JSONDecoder().decode(ActionResponse.self, from: data) {
                    responseStr = response.values.map { _, value in
                        switch value {
                        case .string(let s): return s
                        case .number(let n): return String(n)
                        case .boolean(let b): return b ? "Yes" : "No"
                        case .stringArray(let arr): return arr.joined(separator: ", ")
                        case .date(let d): return d.formatted()
                        }
                    }.joined(separator: "; ")
                }
                return "Q: \(ds.title)\nA: \(responseStr)"
            }
            .joined(separator: "\n\n")

        let executionSteps = task.executionSubTasks
        let completedSteps = executionSteps.filter { $0.isCompleted }.map { "- [DONE] \($0.title)" }
        let currentStep = ["- [BAD STEP] \(badStepTitle)"]
        let remainingStepsList = executionSteps.filter { $0.isPending && $0.id != subTask.id }.map { "- [TODO] \($0.title)" }
        let executionProgress = (completedSteps + currentStep + remainingStepsList).joined(separator: "\n")

        if let apiKey = APIKeyManager.getAPIKey() {
            Task {
                do {
                    let planner = PlannerAIService(apiKey: apiKey)
                    let lesson = try await planner.generateLearning(
                        badStepTitle: badStepTitle,
                        taskContext: taskContext,
                        discoveryContext: discoveryContext.isEmpty ? "No discovery" : discoveryContext,
                        executionProgress: executionProgress
                    )

                    let learning = PlanningLearning(
                        taskContext: taskContext,
                        badStepTitle: badStepTitle,
                        lesson: lesson
                    )
                    PlanningMemoryService.shared.saveLearning(learning)
                } catch {
                    print("Failed to generate learning: \(error)")
                }
            }
        }

        let remainingSteps = task.executionSubTasks.filter { $0.id != subTask.id && $0.isPending }

        modelContext?.delete(subTask)

        let remainingExecutionSteps = task.executionSubTasks.filter { $0.id != subTask.id }
        let discoveryCount = task.discoverySubTasks.count
        for (index, step) in remainingExecutionSteps.sorted(by: { $0.order < $1.order }).enumerated() {
            step.order = discoveryCount + index
        }

        if let next = remainingSteps.first {
            next.markCurrent()
            addProgressMessage("Moving to next step...")
        }

        try? modelContext?.save()
        pendingSubTask = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.resetForNextAction()
        }
    }

    private func breakDownOverwhelmingStep(_ subTask: SubTask) {
        guard let apiKey = APIKeyManager.getAPIKey() else {
            addProgressMessage("Unable to generate steps")
            pendingSubTask = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.resetForNextAction()
            }
            return
        }

        let discoveryContext = task.discoverySubTasks
            .filter { $0.isCompleted }
            .map { discoverySubTask -> String in
                var responseStr = "(no response recorded)"
                if let data = discoverySubTask.actionResponseData,
                   let response = try? JSONDecoder().decode(ActionResponse.self, from: data) {
                    responseStr = response.values.map { _, value in
                        switch value {
                        case .string(let s): return s
                        case .number(let n): return String(n)
                        case .boolean(let b): return b ? "Yes" : "No"
                        case .stringArray(let arr): return arr.joined(separator: ", ")
                        case .date(let d): return d.formatted()
                        }
                    }.joined(separator: "; ")
                }
                return "Q: \(discoverySubTask.title)\nA: \(responseStr)"
            }
            .joined(separator: "\n\n")

        let executionSteps = task.executionSubTasks
        let completedSteps = executionSteps.filter { $0.isCompleted }.map { "- [DONE] \($0.title)" }
        let currentStep = executionSteps.filter { $0.isCurrent }.map { "- [CURRENT - OVERWHELMING] \($0.title)" }
        let remainingSteps = executionSteps.filter { $0.isPending && !$0.isCurrent }.map { "- [TODO] \($0.title)" }
        let executionProgress = (completedSteps + currentStep + remainingSteps).joined(separator: "\n")

        Task {
            do {
                let planner = PlannerAIService(apiKey: apiKey)
                let microSteps = try await planner.breakDownStep(
                    stepTitle: subTask.title,
                    stepDescription: subTask.subTaskDescription,
                    taskContext: task.title,
                    discoveryContext: discoveryContext.isEmpty ? "No discovery questions were asked" : discoveryContext,
                    executionProgress: executionProgress.isEmpty ? "This is the first step" : executionProgress
                )

                await MainActor.run {
                    addProgressMessage("Created \(microSteps.count) smaller steps")

                    let executionSteps = task.executionSubTasks
                    let position = executionSteps.firstIndex(where: { $0.id == subTask.id }) ?? 0
                    let stepsBefore = Array(executionSteps.prefix(position))
                    let stepsAfter = Array(executionSteps.dropFirst(position + 1))

                    modelContext?.delete(subTask)

                    var newMicroSteps: [SubTask] = []
                    for microStep in microSteps {
                        let newSubTask = SubTask(
                            title: microStep.title,
                            description: microStep.description,
                            order: 0,
                            phase: .execution,
                            requiresExternalAction: microStep.requiresExternalAction ?? false
                        )
                        task.addSubTask(newSubTask)
                        modelContext?.insert(newSubTask)
                        newMicroSteps.append(newSubTask)
                    }

                    let discoveryCount = task.discoverySubTasks.count
                    let newExecutionOrder = stepsBefore + newMicroSteps + stepsAfter
                    for (index, step) in newExecutionOrder.enumerated() {
                        step.order = discoveryCount + index
                    }

                    if let firstMicroStep = newMicroSteps.first {
                        firstMicroStep.markCurrent()
                    }

                    try? modelContext?.save()
                    pendingSubTask = nil

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        self?.resetForNextAction()
                    }
                }
            } catch {
                await MainActor.run {
                    addProgressMessage("Couldn't break down step: \(error.localizedDescription)")
                    pendingSubTask = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.resetForNextAction()
                    }
                }
            }
        }
    }

    // MARK: - Step navigation

    func completeSubTask(_ subTask: SubTask) {
        subTask.markCompleted()

        if let next = task.sortedSubTasks.first(where: { $0.isPending }) {
            next.markCurrent()
        }

        actionSchema = nil
        actionResponse = ActionResponse()

        try? modelContext?.save()
        KnowledgeBaseService.shared.handleSubtaskCompleted(subTask)
    }

    func resetForNextAction() {
        submissionState = .idle
        actionSchema = nil
        actionResponse = ActionResponse()
        if let currentSubTask = task.sortedSubTasks.first(where: { $0.isCurrent }),
           APIKeyManager.hasAPIKey {
            loadOrGenerateActionUI(for: currentSubTask)
        }
    }

    func skipSubTask(_ subTask: SubTask) {
        subTask.skip()

        if let next = task.sortedSubTasks.first(where: { $0.isPending }) {
            next.markCurrent()
        }

        actionSchema = nil
        actionResponse = ActionResponse()

        try? modelContext?.save()
    }

    private func revisePlanIfNeeded(remainingSteps: [SubTask]) {
        guard let apiKey = APIKeyManager.getAPIKey() else {
            moveToNextStep(remainingSteps)
            return
        }

        Task {
            do {
                let planner = PlannerAIService(apiKey: apiKey)
                let previousResponses = gatherPreviousResponses()

                let completedInfo = previousResponses.map { dict -> CompletedSubTaskInfo in
                    let title = dict["subTask"] ?? ""
                    let response = dict.filter { $0.key != "subTask" }
                        .map { "\($0.key): \($0.value)" }
                        .joined(separator: ", ")
                    return CompletedSubTaskInfo(title: title, response: response)
                }

                let remainingTitles = remainingSteps.map { $0.title }

                let revision = try await planner.revisePlan(
                    originalTask: task.title,
                    completedSubTasks: completedInfo,
                    remainingSubTasks: remainingTitles,
                    latestResponse: [:]
                )

                await MainActor.run {
                    if revision.revised, let newSubTasks = revision.subTasks {
                        addProgressMessage("Updating plan based on your input...")

                        for step in remainingSteps {
                            modelContext?.delete(step)
                        }

                        let maxCompletedOrder = task.sortedSubTasks
                            .filter { $0.isCompleted }
                            .map { $0.order }
                            .max() ?? 0
                        for (index, subTaskPlan) in newSubTasks.prefix(7).enumerated() {
                            let subTask = SubTask(
                                title: subTaskPlan.title,
                                description: subTaskPlan.description,
                                order: maxCompletedOrder + 1 + index
                            )
                            subTask.phase = .execution
                            subTask.requiresExternalAction = subTaskPlan.requiresExternalAction ?? false
                            if index == 0 {
                                subTask.markCurrent()
                            }
                            task.addSubTask(subTask)
                            modelContext?.insert(subTask)
                        }

                        try? modelContext?.save()
                        addProgressMessage("Plan updated!")

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                            self?.resetForNextAction()
                        }
                    } else {
                        moveToNextStep(remainingSteps)
                    }
                }
            } catch {
                await MainActor.run {
                    addProgressMessage("Continuing with current plan...")
                    moveToNextStep(remainingSteps)
                }
            }
        }
    }

    private func moveToNextStep(_ remainingSteps: [SubTask]) {
        if let next = remainingSteps.first {
            next.markCurrent()
            addProgressMessage("Moving to next step...")
            try? modelContext?.save()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.resetForNextAction()
            }
        }
    }

    func completeTask() {
        task.markCompleted()
        try? modelContext?.save()
        knowledgeBase.handleTaskCompleted(task)
    }

    // MARK: - Planning

    func planWithAI() {
        guard let apiKey = APIKeyManager.getAPIKey() else { return }

        task.planningStatus = .planningDiscovery
        try? modelContext?.save()

        Task {
            do {
                let planner = PlannerAIService(apiKey: apiKey)
                let plan = try await planner.generateDiscoveryQuestions(for: task.originalInput)

                await MainActor.run {
                    task.title = plan.title
                    task.taskDescription = plan.description

                    let cappedSubTasks = Array(plan.subTasks.prefix(7))
                    for (index, subTaskPlan) in cappedSubTasks.enumerated() {
                        let subTask = SubTask(
                            title: subTaskPlan.title,
                            description: subTaskPlan.description,
                            order: index
                        )
                        if index == 0 {
                            subTask.markCurrent()
                        }
                        task.addSubTask(subTask)
                        modelContext?.insert(subTask)
                    }

                    task.planningStatus = .idle
                    try? modelContext?.save()
                }
            } catch {
                print("Failed to generate discovery questions: \(error)")
                await MainActor.run {
                    task.planningStatus = .idle
                    try? modelContext?.save()
                }
            }
        }
    }

    func transitionToExecutionPhase() {
        guard let apiKey = APIKeyManager.getAPIKey() else { return }

        task.planningStatus = .planningExecution
        submissionState = .revising
        addProgressMessage("Creating your action plan...")
        try? modelContext?.save()

        let discoveryAnswers = task.sortedSubTasks
            .filter { $0.isCompleted }
            .map { subTask -> CompletedSubTaskInfo in
                var responseStr = ""
                if let data = subTask.actionResponseData,
                   let response = try? JSONDecoder().decode(ActionResponse.self, from: data) {
                    responseStr = response.values.map { _, value in
                        switch value {
                        case .string(let s): return s
                        case .number(let n): return String(n)
                        case .boolean(let b): return b ? "Yes" : "No"
                        case .stringArray(let arr): return arr.joined(separator: ", ")
                        case .date(let d): return d.formatted()
                        }
                    }.joined(separator: "; ")
                }
                return CompletedSubTaskInfo(title: subTask.title, response: responseStr)
            }

        Task {
            do {
                let planner = PlannerAIService(apiKey: apiKey)
                let executionPlan = try await planner.createExecutionPlan(
                    originalTask: task.originalInput,
                    discoveryAnswers: discoveryAnswers
                )

                await MainActor.run {
                    addProgressMessage("Plan created with \(executionPlan.subTasks.count) steps")

                    task.transitionToExecution()
                    task.title = executionPlan.title
                    task.taskDescription = executionPlan.description

                    let startOrder = task.subTasks.count
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
                        modelContext?.insert(subTask)
                    }

                    task.planningStatus = .idle
                    try? modelContext?.save()
                    knowledgeBase.handleTaskCreatedOrUpdated(task)

                    let planData = ExecutionPlanData(taskId: task.id)
                    submissionState = .idle
                    clearProgressLog()
                    NotificationCenter.default.post(name: .showExecutionPlanSheet, object: planData)
                }
            } catch {
                print("Failed to create execution plan: \(error)")
                await MainActor.run {
                    task.planningStatus = .idle
                    addProgressMessage("Error creating plan")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.resetForNextAction()
                    }
                }
            }
        }
    }

    // MARK: - Memory

    func saveMemory(_ text: String) {
        task.memory = text
        try? modelContext?.save()
    }

    // MARK: - Progress log

    private func addProgressMessage(_ message: String) {
        withAnimation(.easeInOut(duration: 0.3)) {
            progressLog.insert(message, at: 0)
        }
    }

    private func clearProgressLog() {
        progressLog.removeAll()
    }

    // MARK: - Helpers

    private func gatherPreviousResponses() -> [[String: String]] {
        var responses: [[String: String]] = []

        for subTask in task.sortedSubTasks where subTask.isCompleted {
            var responseDict: [String: String] = ["subTask": subTask.title]

            if let responseData = subTask.actionResponseData,
               let actionResponse = try? JSONDecoder().decode(ActionResponse.self, from: responseData) {
                for (key, value) in actionResponse.values {
                    switch value {
                    case .string(let s):
                        responseDict[key] = s
                    case .number(let n):
                        responseDict[key] = String(n)
                    case .boolean(let b):
                        responseDict[key] = b ? "Yes" : "No"
                    case .date(let d):
                        responseDict[key] = d.formatted(date: .abbreviated, time: .omitted)
                    case .stringArray(let arr):
                        responseDict[key] = arr.joined(separator: ", ")
                    }
                }
            }

            responses.append(responseDict)
        }

        return responses
    }
}
