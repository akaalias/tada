import SwiftUI
import SwiftData

struct ExecutionPlanData {
    let taskId: UUID
}

struct InformationRequiredView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTasks: [TodoTask]
    private var activeTasks: [TodoTask] { allTasks.filter { $0.status == .active } }
    @State private var showingExecutionPlanSheet = false
    @State private var executionPlanData: ExecutionPlanData?

    var body: some View {
        Group {
            if discoveryTasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(Array(discoveryTasks.enumerated()), id: \.element.id) { index, task in
                            ActionCard(task: task, defaultExpanded: index == 0)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Tasks that require your information")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .newTask, object: nil)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showExecutionPlanSheet)) { notification in
            if let data = notification.object as? ExecutionPlanData {
                executionPlanData = data
                showingExecutionPlanSheet = true
            }
        }
        .sheet(isPresented: $showingExecutionPlanSheet) {
            if let data = executionPlanData,
               let task = activeTasks.first(where: { $0.id == data.taskId }) {
                ExecutionPlanSheetContent(
                    task: task,
                    onClose: {
                        showingExecutionPlanSheet = false
                    },
                    onContinue: {
                        showingExecutionPlanSheet = false
                        NotificationCenter.default.post(
                            name: .navigateToTaskInActionRequired,
                            object: data.taskId
                        )
                    }
                )
            }
        }
    }

    private var discoveryTasks: [TodoTask] {
        activeTasks.filter { task in
            if task.isPlanningDiscovery { return true }
            if task.subTasks.isEmpty { return true }
            if task.isDiscoveryPhase && task.currentSubTask != nil { return true }
            if task.isDiscoveryPhase && !task.discoverySubTasks.isEmpty &&
               task.discoverySubTasks.allSatisfy({ $0.isCompleted }) {
                return true
            }
            return false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 64))
                .foregroundColor(.orange.opacity(0.4))

            Text("No questions right now")
                .font(.title2)
                .fontWeight(.semibold)

            Text("When tasks need clarifying information, they'll appear here.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ActionRequiredView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTasks: [TodoTask]
    private var activeTasks: [TodoTask] { allTasks.filter { $0.status == .active } }
    @State private var focusedTaskId: UUID?

    var body: some View {
        Group {
            if executionTasks.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(Array(executionTasks.enumerated()), id: \.element.id) { index, task in
                                ActionCard(
                                    task: task,
                                    defaultExpanded: focusedTaskId == nil ? index == 0 : task.id == focusedTaskId
                                )
                                .id(task.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: focusedTaskId) { _, newValue in
                        if let taskId = newValue {
                            withAnimation {
                                proxy.scrollTo(taskId, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Tasks that require your action")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .newTask, object: nil)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTaskInActionRequired)) { notification in
            if let taskId = notification.object as? UUID {
                focusedTaskId = taskId
            }
        }
    }

    private var executionTasks: [TodoTask] {
        activeTasks.filter { task in
            if task.isPlanningExecution { return true }
            if task.isExecutionPhase && task.currentSubTask != nil { return true }
            return false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.circle")
                .font(.system(size: 64))
                .foregroundColor(.blue.opacity(0.4))

            Text("No actions right now")
                .font(.title2)
                .fontWeight(.semibold)

            Text("When tasks are ready for execution, their action steps will appear here.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum SubmissionState: Equatable {
    case idle
    case saving
    case revising
}

enum BlockerType: String, CaseIterable, Identifiable {
    case needsBreakingDown = "Needs breaking down"
    case overwhelming = "Feels overwhelming"
    case doesntMakeSense = "This doesn't make sense"
    case remember = "Remember something"
    case needInfo = "Need more information first"
    case badTiming = "Bad timing right now"
    case anxious = "Feeling anxious about it"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .needsBreakingDown: return "arrow.triangle.branch"
        case .overwhelming: return "rectangle.expand.vertical"
        case .doesntMakeSense: return "xmark.circle"
        case .remember: return "brain"
        case .needInfo: return "questionmark.circle"
        case .badTiming: return "clock"
        case .anxious: return "heart"
        }
    }
}

struct NudgeInputView: View {
    let initialText: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var nudgeText: String = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .foregroundColor(.purple)
                    Text("Nudges")
                        .font(.headline)
                }
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                Button("Save") {
                    onSave(nudgeText)
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Guide the AI for this task. What should it remember or avoid?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextEditor(text: $nudgeText)
                    .font(.system(size: 14))
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )

                Text("Example: Only use bamboo, roses, and daybed. Stop suggesting privacy screens or planters.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 450, height: 320)
        .onAppear {
            nudgeText = initialText
        }
    }
}

struct ActionCard: View {
    @Environment(\.modelContext) private var modelContext
    let task: TodoTask
    var defaultExpanded: Bool = true
    @State private var showingSubTaskSheet = false
    @State private var actionSchema: ActionSchema?
    @State private var actionResponse = ActionResponse()
    @State private var isLoadingSchema = false
    @State private var schemaError: String?
    @State private var submissionState: SubmissionState = .idle
    @State private var progressLog: [String] = []
    @State private var showingBlockerSelection = false
    @State private var selectedBlocker: BlockerType?
    @State private var pendingSubTask: SubTask?
    @State private var showingNudgeInput = false

    private var phaseColor: Color {
        task.isDiscoveryPhase ? .orange : .blue
    }

    private var isTransitioningToExecution: Bool {
        task.isDiscoveryPhase &&
        !task.discoverySubTasks.isEmpty &&
        task.discoverySubTasks.allSatisfy({ $0.isCompleted }) &&
        task.executionSubTasks.isEmpty
    }

    var body: some View {
        TaskCard(task: task, defaultExpanded: defaultExpanded) {
            Divider()

            if submissionState != .idle || isLoadingSchema {
                submissionProgressView
            } else if task.isPlanning {
                planningInProgressView
            } else if let subTask = task.currentSubTask {
                dynamicActionView(for: subTask)
            } else if task.subTasks.isEmpty {
                noSubTasksView
            } else if isTransitioningToExecution {
                transitioningView
            } else {
                allCompletedView
            }
        }
        .sheet(isPresented: $showingSubTaskSheet) {
            AddSubTasksSheet(task: task)
        }
        .sheet(isPresented: $showingBlockerSelection) {
            BlockerSelectionView(
                subTaskTitle: pendingSubTask?.title ?? "",
                onSelect: { blocker in
                    handleBlockerSelection(blocker)
                },
                onCancel: {
                    showingBlockerSelection = false
                    pendingSubTask = nil
                }
            )
        }
        .sheet(isPresented: $showingNudgeInput) {
            NudgeInputView(
                initialText: task.memory,
                onSave: { text in
                    task.memory = text
                    try? modelContext.save()
                    showingNudgeInput = false
                },
                onCancel: {
                    showingNudgeInput = false
                }
            )
        }
        .onChange(of: task.currentSubTask?.id) { oldId, newId in
            if oldId != newId {
                actionSchema = nil
                actionResponse = ActionResponse()
                schemaError = nil
            }
        }
    }

    private var submissionProgressView: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(progressLog.enumerated()), id: \.offset) { index, message in
                    HStack(spacing: 12) {
                        if index == 0 {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: Theme.circleSize))
                                .foregroundColor(phaseColor)
                        }
                        Text(message)
                            .font(.system(size: Theme.fontSize))
                            .foregroundColor(index == 0 ? .primary : .secondary)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.3), value: progressLog.count)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func addProgressMessage(_ message: String) {
        withAnimation(.easeInOut(duration: 0.3)) {
            progressLog.insert(message, at: 0)
        }
    }

    private func clearProgressLog() {
        progressLog.removeAll()
    }

    @ViewBuilder
    private func dynamicActionView(for subTask: SubTask) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Sub-task sub-header
            HStack(spacing: 10) {
                if task.isDiscoveryPhase {
                    Text("Question \(currentIndex + 1) of \(task.subTasks.count)")
                        .font(.system(size: Theme.fontSize, weight: .medium))
                        .foregroundColor(.orange)
                } else {
                    Text("Step \(currentIndex + 1) of \(task.subTasks.count)")
                        .font(.system(size: Theme.fontSize, weight: .medium))
                        .foregroundColor(.blue)
                }

                Text(subTask.title)
                    .font(.system(size: Theme.fontSize, weight: .semibold))

                if !task.isDiscoveryPhase && (subTask.effectiveRequiresExternalAction || actionSchema?.requiresExternalAction == true) {
                    Text("Outside Work")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.externalActionColor)
                        .cornerRadius(4)
                }

                Spacer()

                if APIKeyManager.hasAPIKey && !isLoadingSchema {
                    Button {
                        regenerateActionUI(for: subTask)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderless)
                    .help("Regenerate Activity")
                }
            }

            // Outside work alert
            if !task.isDiscoveryPhase && (subTask.effectiveRequiresExternalAction || actionSchema?.requiresExternalAction == true) {
                Text("This step requires action outside the app. It might feel uncomfortable, but completing it will move you closer to your goal.")
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.externalActionColor)
                    .cornerRadius(8)
            }

            // Action UI section
            if isLoadingSchema {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Creating a custom UI for")
                        .font(.system(size: Theme.fontSize))
                        .foregroundColor(.secondary)
                    Text(subTask.title)
                        .font(.system(size: Theme.fontSize, weight: .bold))
                        .foregroundColor(phaseColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
            } else if let schema = actionSchema {
                ActionUIRenderer(schema: schema, response: $actionResponse, isDiscovery: task.isDiscoveryPhase, showTitle: false) {
                    completeSubTaskWithResponse(subTask)
                } onHelp: {
                    pendingSubTask = subTask
                    showingBlockerSelection = true
                } onChangeFieldType: { newType, options in
                    changeFieldType(to: newType, options: options, for: subTask)
                }
            } else if let error = schemaError {
                VStack(alignment: .leading, spacing: 14) {
                    if !subTask.subTaskDescription.isEmpty {
                        Text(subTask.subTaskDescription)
                            .font(.system(size: Theme.fontSize))
                            .foregroundColor(.secondary)
                    }

                    Text("Could not generate UI: \(error)")
                        .font(.system(size: Theme.fontSize))
                        .foregroundColor(.orange)

                    HStack {
                        Button("Skip") {
                            skipSubTask(subTask)
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("Mark Complete") {
                            completeSubTask(subTask)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if !subTask.subTaskDescription.isEmpty {
                        Text(subTask.subTaskDescription)
                            .font(.system(size: Theme.fontSize))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        if APIKeyManager.hasAPIKey {
                            Button("Generate Action UI") {
                                loadOrGenerateActionUI(for: subTask)
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()

                        Button("Skip") {
                            skipSubTask(subTask)
                        }
                        .buttonStyle(.bordered)

                        Button("Mark Complete") {
                            completeSubTask(subTask)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                .task(id: subTask.id) {
                    if APIKeyManager.hasAPIKey && actionSchema == nil && !isLoadingSchema {
                        loadOrGenerateActionUI(for: subTask)
                    }
                }
            }
        }
    }

    private var noSubTasksView: some View {
        VStack(spacing: 12) {
            Text("This task needs a plan.")
                .foregroundColor(.secondary)

            HStack {
                Button("Add Sub-Tasks Manually") {
                    showingSubTaskSheet = true
                }

                if APIKeyManager.hasAPIKey {
                    Button("Plan with AI") {
                        planWithAI()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var planningInProgressView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(task.isPlanningDiscovery ? "Planning discovery questions..." : "Creating action plan...")
                    .font(.system(size: Theme.fontSize, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var allCompletedView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Theme.circleSize))
                .foregroundColor(phaseColor)
            if task.isDiscoveryPhase && task.executionSubTasks.isEmpty {
                Text("All questions answered!")
                Spacer()
                Button("Create Execution Plan") {
                    transitionToExecutionPhase()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("All steps completed!")
                Spacer()
                Button("Mark Task Complete") {
                    completeTask()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var transitioningView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Creating your action plan...")
                    .font(.system(size: Theme.fontSize, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text("All questions answered. Generating execution steps based on your responses.")
                .font(.system(size: Theme.fontSize))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            // Auto-trigger transition if we're in this state
            transitionToExecutionPhase()
        }
    }

    private var currentIndex: Int {
        task.sortedSubTasks.firstIndex(where: { $0.id == task.currentSubTask?.id }) ?? 0
    }

    private func loadOrGenerateActionUI(for subTask: SubTask) {
        // First check if we have a cached schema
        if let cachedData = subTask.actionSchemaData,
           let cachedSchema = try? JSONDecoder().decode(ActionSchema.self, from: cachedData) {
            self.actionSchema = cachedSchema
            self.isLoadingSchema = false
            return
        }

        // No cache - generate new schema
        generateActionUI(for: subTask)
    }

    private func regenerateActionUI(for subTask: SubTask) {
        // Clear cached schema and response
        subTask.actionSchemaData = nil
        actionSchema = nil
        actionResponse = ActionResponse()
        try? modelContext.save()

        // Generate fresh
        generateActionUI(for: subTask)
    }

    private func changeFieldType(to newType: ActionField.FieldType, options: [FieldOption]?, for subTask: SubTask) {
        // Extract current data to convert to new format
        var defaultValue: String? = nil
        var prefillRows: [[String: String]]? = nil

        // Try to extract text data from current response
        let currentText = actionResponse.values.compactMap { _, value -> String? in
            switch value {
            case .string(let s):
                // Skip image data
                if s.hasPrefix("data:image") { return nil }
                return s.isEmpty ? nil : s
            case .number(let n): return String(format: "%.0f", n)
            case .stringArray(let arr): return arr.joined(separator: "\n")
            default: return nil
            }
        }.joined(separator: "\n")

        // Convert data based on target type
        if newType == .textarea || newType == .text {
            if !currentText.isEmpty {
                // Parse table format "Item - €50; Item2 - €30" into lines
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
            // Parse text into rows for table
            if !currentText.isEmpty {
                let lines = currentText.components(separatedBy: "\n").filter { !$0.isEmpty }
                prefillRows = lines.map { ["item": $0] }
            }
        }

        // Create a new schema with the specified field type
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

        // Clear response and update schema
        actionResponse = ActionResponse()
        actionSchema = newSchema

        // Cache the new schema
        if let schemaData = try? JSONEncoder().encode(newSchema) {
            subTask.actionSchemaData = schemaData
            try? modelContext.save()
        }
    }

    private func generateActionUI(for subTask: SubTask) {
        guard let apiKey = APIKeyManager.getAPIKey() else { return }

        // Clear any previous progress log and start fresh
        clearProgressLog()
        addProgressMessage("Creating a custom UI for \(subTask.title)")
        isLoadingSchema = true
        schemaError = nil

        // Gather previous responses from completed sub-tasks
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

                    // Cache the schema for future use
                    if let schemaData = try? JSONEncoder().encode(schema) {
                        subTask.actionSchemaData = schemaData
                        try? modelContext.save()
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

    private func completeSubTaskWithResponse(_ subTask: SubTask) {
        // Check if this is an outside work step with a "No" answer
        if subTask.effectiveRequiresExternalAction || actionSchema?.requiresExternalAction == true {
            // Look for a yesNo field with a "No" response
            for (_, value) in actionResponse.values {
                if case .boolean(let answered) = value, answered == false {
                    // User said "No" - show blocker selection instead of completing
                    pendingSubTask = subTask
                    showingBlockerSelection = true
                    return
                }
            }
        }

        proceedWithCompletion(subTask)
    }

    private func proceedWithCompletion(_ subTask: SubTask) {
        // Start progress log
        clearProgressLog()
        submissionState = .saving
        addProgressMessage("Saving your response...")

        // Save response
        if let responseData = try? JSONEncoder().encode(actionResponse) {
            subTask.actionResponseData = responseData
        }

        subTask.markCompleted()
        try? modelContext.save()
        KnowledgeBaseService.shared.handleSubtaskCompleted(subTask)

        // Check if we're in discovery or execution phase
        if task.isDiscoveryPhase {
            // Discovery phase: no revision, just move to next question
            let remainingQuestions = task.sortedSubTasks.filter { $0.isPending }

            if remainingQuestions.isEmpty {
                // All discovery questions answered - transition to execution!
                addProgressMessage("All questions answered")
                transitionToExecutionPhase()
            } else {
                // More questions to ask
                addProgressMessage("Moving to next question...")
                if let next = remainingQuestions.first {
                    next.markCurrent()
                }
                try? modelContext.save()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    resetForNextAction()
                }
            }
        } else {
            // Execution phase: evaluate if plan needs revision after each step
            addProgressMessage("Step completed")
            let remainingSteps = task.sortedSubTasks.filter({ $0.phase == TaskPhase.execution && $0.isPending })

            if remainingSteps.count > 1 {
                // Always ask the planner if revision is needed based on new info
                addProgressMessage("Reviewing plan...")
                revisePlanIfNeeded(remainingSteps: remainingSteps)
            } else if let next = remainingSteps.first {
                next.markCurrent()
                addProgressMessage("Moving to next step...")
                try? modelContext.save()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    resetForNextAction()
                }
            } else {
                // All execution steps done - auto-complete the task
                addProgressMessage("All steps completed!")
                addProgressMessage("Task complete!")

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    task.markCompleted()
                    try? modelContext.save()
                    KnowledgeBaseService.shared.handleTaskCompleted(task)
                    resetForNextAction()
                }
            }
        }
    }

    private func handleBlockerSelection(_ blocker: BlockerType) {
        showingBlockerSelection = false

        guard let currentSubTask = pendingSubTask else { return }

        // Set state to show progress view
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                resetForNextAction()
            }

        case .badTiming:
            addProgressMessage("No problem, we'll come back to this later")
            pendingSubTask = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                resetForNextAction()
            }

        case .anxious:
            addProgressMessage("That's okay - let's think about what's making this feel hard")
            pendingSubTask = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                resetForNextAction()
            }
        }
    }

    private func deleteSubTask(_ subTask: SubTask) {
        // Capture context for learning before deleting
        let badStepTitle = subTask.title
        let taskContext = task.title

        // Build discovery context
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

        // Build execution progress
        let executionSteps = task.executionSubTasks
        let completedSteps = executionSteps.filter { $0.isCompleted }.map { "- [DONE] \($0.title)" }
        let currentStep = ["- [BAD STEP] \(badStepTitle)"]
        let remainingStepsList = executionSteps.filter { $0.isPending && $0.id != subTask.id }.map { "- [TODO] \($0.title)" }
        let executionProgress = (completedSteps + currentStep + remainingStepsList).joined(separator: "\n")

        // Generate learning in background
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

        // Find the next step before deleting
        let remainingSteps = task.executionSubTasks.filter { $0.id != subTask.id && $0.isPending }

        // Delete the subtask
        modelContext.delete(subTask)

        // Renumber remaining steps
        let remainingExecutionSteps = task.executionSubTasks.filter { $0.id != subTask.id }
        let discoveryCount = task.discoverySubTasks.count
        for (index, step) in remainingExecutionSteps.sorted(by: { $0.order < $1.order }).enumerated() {
            step.order = discoveryCount + index
        }

        // Mark next step as current
        if let next = remainingSteps.first {
            next.markCurrent()
            addProgressMessage("Moving to next step...")
        }

        try? modelContext.save()
        pendingSubTask = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            resetForNextAction()
        }
    }

    private func breakDownOverwhelmingStep(_ subTask: SubTask) {
        guard let apiKey = APIKeyManager.getAPIKey() else {
            addProgressMessage("Unable to generate steps")
            pendingSubTask = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                resetForNextAction()
            }
            return
        }

        // Build discovery context
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

        // Build execution progress
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

                    // Get the position of the overwhelming step in execution subtasks
                    let executionSteps = task.executionSubTasks
                    let position = executionSteps.firstIndex(where: { $0.id == subTask.id }) ?? 0

                    // Build new execution order: [steps before] + [micro-steps] + [steps after]
                    let stepsBefore = Array(executionSteps.prefix(position))
                    let stepsAfter = Array(executionSteps.dropFirst(position + 1))

                    // Delete the overwhelming step
                    modelContext.delete(subTask)

                    // Create micro-step SubTask objects
                    var newMicroSteps: [SubTask] = []
                    for microStep in microSteps {
                        let newSubTask = SubTask(
                            title: microStep.title,
                            description: microStep.description,
                            order: 0, // Will renumber below
                            phase: .execution,
                            requiresExternalAction: microStep.requiresExternalAction ?? false
                        )
                        task.addSubTask(newSubTask)
                        modelContext.insert(newSubTask)
                        newMicroSteps.append(newSubTask)
                    }

                    // Renumber all execution steps in correct order
                    let discoveryCount = task.discoverySubTasks.count
                    let newExecutionOrder = stepsBefore + newMicroSteps + stepsAfter
                    for (index, step) in newExecutionOrder.enumerated() {
                        step.order = discoveryCount + index
                        // Don't change status of existing steps - only new micro-steps need status set
                    }

                    // Mark first micro-step as current
                    if let firstMicroStep = newMicroSteps.first {
                        firstMicroStep.markCurrent()
                    }

                    try? modelContext.save()
                    pendingSubTask = nil

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        resetForNextAction()
                    }
                }
            } catch {
                await MainActor.run {
                    addProgressMessage("Couldn't break down step: \(error.localizedDescription)")
                    pendingSubTask = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        resetForNextAction()
                    }
                }
            }
        }
    }

    private func completeSubTask(_ subTask: SubTask) {
        subTask.markCompleted()

        // Activate next pending sub-task
        if let next = task.sortedSubTasks.first(where: { $0.isPending }) {
            next.markCurrent()
        }

        // Reset UI state for next sub-task
        actionSchema = nil
        actionResponse = ActionResponse()

        try? modelContext.save()
        KnowledgeBaseService.shared.handleSubtaskCompleted(subTask)
    }

    private func resetForNextAction() {
        submissionState = .idle
        actionSchema = nil
        actionResponse = ActionResponse()
        // Start loading next schema immediately to prevent flicker
        if let currentSubTask = task.sortedSubTasks.first(where: { $0.isCurrent }),
           APIKeyManager.hasAPIKey {
            loadOrGenerateActionUI(for: currentSubTask)
        }
    }

    private func skipSubTask(_ subTask: SubTask) {
        subTask.skip()

        if let next = task.sortedSubTasks.first(where: { $0.isPending }) {
            next.markCurrent()
        }

        actionSchema = nil
        actionResponse = ActionResponse()

        try? modelContext.save()
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

                        // Remove old remaining steps
                        for step in remainingSteps {
                            modelContext.delete(step)
                        }

                        // Add new steps after the last completed task
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
                            modelContext.insert(subTask)
                        }

                        try? modelContext.save()
                        addProgressMessage("Plan updated!")

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            resetForNextAction()
                        }
                    } else {
                        // No revision needed, continue normally
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
            try? modelContext.save()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                resetForNextAction()
            }
        }
    }

    private func completeTask() {
        task.markCompleted()
        try? modelContext.save()
        KnowledgeBaseService.shared.handleTaskCompleted(task)
    }

    private func planWithAI() {
        guard let apiKey = APIKeyManager.getAPIKey() else { return }

        task.planningStatus = .planningDiscovery
        try? modelContext.save()

        Task {
            do {
                let planner = PlannerAIService(apiKey: apiKey)

                // Start with discovery phase - generate clarifying questions
                let plan = try await planner.generateDiscoveryQuestions(for: task.originalInput)

                await MainActor.run {
                    task.title = plan.title
                    task.taskDescription = plan.description

                    // Cap at 7 discovery questions
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
                        modelContext.insert(subTask)
                    }

                    task.planningStatus = .idle
                    try? modelContext.save()
                }
            } catch {
                print("Failed to generate discovery questions: \(error)")
                await MainActor.run {
                    task.planningStatus = .idle
                    try? modelContext.save()
                }
            }
        }
    }

    private func transitionToExecutionPhase() {
        guard let apiKey = APIKeyManager.getAPIKey() else { return }

        task.planningStatus = PlanningStatus.planningExecution
        submissionState = .revising
        addProgressMessage("Creating your action plan...")
        try? modelContext.save()

        // Gather all discovery answers
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

                    // Keep discovery subtasks, update title/description based on discovery answers
                    task.transitionToExecution()
                    task.title = executionPlan.title
                    task.taskDescription = executionPlan.description

                    // Add execution steps (with order starting after discovery tasks)
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
                        modelContext.insert(subTask)
                    }

                    task.planningStatus = .idle
                    try? modelContext.save()
                    KnowledgeBaseService.shared.handleTaskCreatedOrUpdated(task)

                    // Post notification to show execution plan sheet from parent view
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        resetForNextAction()
                    }
                }
            }
        }
    }

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

struct BlockerSelectionView: View {
    let subTaskTitle: String
    let onSelect: (BlockerType) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("What's making this hard?")
                    .font(.system(size: 20, weight: .semibold))

                Text("No judgment - understanding the blocker helps us help you")
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            VStack(spacing: 12) {
                ForEach(BlockerType.allCases) { blocker in
                    Button {
                        onSelect(blocker)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: blocker.icon)
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                                .frame(width: 24)

                            Text(blocker.rawValue)
                                .font(.system(size: Theme.fontSize))
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Go back") {
                onCancel()
            }
            .font(.system(size: Theme.fontSize))
            .foregroundColor(.secondary)
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 400)
    }
}

struct ExecutionPlanSheetContent: View {
    let task: TodoTask
    let onClose: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                TaskHeaderView(task: task, isExpanded: .constant(true))
                SubTaskListContent(task: task)
            }
            .padding(16)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )
            .padding(20)

            HStack(spacing: 16) {
                Button("Close") {
                    onClose()
                }
                .buttonStyle(.bordered)

                Button("Continue with Execution") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(minWidth: 500, maxWidth: 600)
    }
}

struct PreviousInputsSummary: View {
    let completedSubTasks: [SubTask]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    Text("Your inputs (\(completedSubTasks.count))")
                        .font(.system(size: Theme.fontSize, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(completedSubTasks) { subTask in
                        PreviousInputRow(subTask: subTask)
                    }
                }
                .padding(.leading, 24)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

struct PreviousInputRow: View {
    let subTask: SubTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(subTask.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            let extracted = extractResponse(from: subTask)

            if let image = extracted.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 80)
                    .cornerRadius(4)
            }

            if let yesNo = extracted.yesNo {
                HStack(spacing: 6) {
                    Image(systemName: yesNo ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(yesNo ? .green : .red)
                    Text(yesNo ? "Yes" : "No")
                        .font(.system(size: Theme.fontSize))
                        .foregroundColor(.primary)
                }
            }

            if !extracted.listItems.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(extracted.listItems, id: \.self) { item in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text(item)
                                .font(.system(size: Theme.fontSize))
                                .foregroundColor(.primary)
                        }
                    }
                }
            }

            if !extracted.tableItems.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(extracted.tableItems, id: \.self) { item in
                        Text(item)
                            .font(.system(size: Theme.fontSize))
                            .foregroundColor(.primary)
                    }
                }
            }

            if let date = extracted.date {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(date)
                        .font(.system(size: Theme.fontSize))
                        .foregroundColor(.primary)
                }
            }

            if let text = extracted.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(.primary)
            }
        }
    }

    struct ExtractedResponse {
        var text: String?
        var image: NSImage?
        var listItems: [String] = []
        var tableItems: [String] = []
        var yesNo: Bool?
        var date: String?
    }

    private func extractResponse(from subTask: SubTask) -> ExtractedResponse {
        guard let data = subTask.actionResponseData,
              let response = try? JSONDecoder().decode(ActionResponse.self, from: data) else {
            return ExtractedResponse()
        }

        var result = ExtractedResponse()
        var textParts: [String] = []

        for (_, value) in response.values {
            switch value {
            case .string(let s):
                if s.hasPrefix("data:image/png;base64,") {
                    let base64 = String(s.dropFirst("data:image/png;base64,".count))
                    if let imageData = Data(base64Encoded: base64) {
                        result.image = NSImage(data: imageData)
                    }
                } else if s.contains("; ") && (s.contains("€") || s.contains("$") || s.contains(" - ")) {
                    // Looks like table data: "Item - €50; Item2 - €30 (Total: €80)"
                    let items = s.components(separatedBy: "; ")
                        .map { $0.replacingOccurrences(of: " (Total:", with: "\n  Total:") }
                    result.tableItems = items
                } else if !s.isEmpty {
                    textParts.append(s)
                }
            case .number(let n):
                textParts.append(String(format: "%.0f", n))
            case .boolean(let b):
                result.yesNo = b
            case .stringArray(let arr):
                result.listItems = arr
            case .date(let d):
                result.date = d.formatted(date: .abbreviated, time: .omitted)
            }
        }

        result.text = textParts.isEmpty ? nil : textParts.joined(separator: ", ")
        return result
    }
}

#Preview {
    ActionRequiredView()
        .modelContainer(for: [TodoTask.self, SubTask.self], inMemory: true)
}
