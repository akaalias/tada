import SwiftUI
import SwiftData

struct ActionItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var appServices
    @Query(sort: \TodoTask.createdAt, order: .reverse) private var allTasks: [TodoTask]
    private var activeTasks: [TodoTask] { allTasks.filter { $0.status == .active } }
    @State private var focusedTaskId: UUID?

    var body: some View {
        Group {
            if actionableTasks.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(actionableTasks, id: \.id) { task in
                                ActionCard(
                                    task: task,
                                    defaultExpanded: task.id == focusedTaskId,
                                    accessory: .takeAction,
                                    knowledgeBase: appServices?.knowledgeBase,
                                    executiveAI: appServices?.executiveAI,
                                    plannerAI: appServices?.plannerAI
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
        .navigationTitle("Action Items")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .newTask, object: nil)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTaskInActionItems)) { notification in
            if let taskId = notification.object as? UUID {
                focusedTaskId = taskId
            }
        }
    }

    private var actionableTasks: [TodoTask] {
        activeTasks.filter { task in
            if task.isPlanningDiscovery { return true }
            if task.subTasks.isEmpty { return true }
            if task.isDiscoveryPhase && task.currentSubTask != nil { return true }
            if task.isDiscoveryPhase && !task.discoverySubTasks.isEmpty &&
               task.discoverySubTasks.allSatisfy({ $0.isCompleted }) { return true }
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

            Text("No action items right now")
                .font(.title2)
                .fontWeight(.semibold)

            Text("When tasks need a question answered or a step completed, they'll appear here.")
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
    var accessory: TaskCardAccessory = .expandChevron
    private let knowledgeBase: KnowledgeBaseServiceProtocol
    private let executiveAI: ExecutiveAIServiceProtocol
    private let plannerAI: PlannerAIServiceProtocol
    @State private var viewModel: ActionCardViewModel
    @State private var showingSubTaskSheet = false

    init(
        task: TodoTask,
        defaultExpanded: Bool = true,
        accessory: TaskCardAccessory = .expandChevron,
        knowledgeBase: KnowledgeBaseServiceProtocol? = nil,
        executiveAI: ExecutiveAIServiceProtocol? = nil,
        plannerAI: PlannerAIServiceProtocol? = nil
    ) {
        self.task = task
        self.defaultExpanded = defaultExpanded
        self.accessory = accessory
        // Use injected services when available, fall back to defaults
        self.knowledgeBase = knowledgeBase ?? KnowledgeBaseServiceAdapter()
        self.executiveAI = executiveAI ?? ExecutiveAIServiceAdapter()
        self.plannerAI = plannerAI ?? PlannerAIServiceAdapter()
        self._viewModel = State(initialValue: ActionCardViewModel(
            task: task,
            knowledgeBase: self.knowledgeBase,
            executiveAI: self.executiveAI,
            plannerAI: self.plannerAI
        ))
    }

    var body: some View {
        @Bindable var vm = viewModel
        return TaskCard(task: task, defaultExpanded: defaultExpanded, accessory: accessory) {
            Divider()

            if viewModel.submissionState != .idle || viewModel.isLoadingSchema {
                submissionProgressView
            } else if task.isPlanning {
                planningInProgressView
            } else if let subTask = task.currentSubTask {
                dynamicActionView(for: subTask)
            } else if task.subTasks.isEmpty {
                noSubTasksView
            } else if viewModel.isTransitioningToExecution {
                transitioningView
            } else {
                allCompletedView
            }
        }
        .task {
            if viewModel.modelContext == nil {
                viewModel.modelContext = modelContext
            }
        }
        .sheet(isPresented: $showingSubTaskSheet) {
            AddSubTasksSheet(task: task)
        }
        .sheet(isPresented: $vm.showingBlockerSelection) {
            BlockerSelectionView(
                subTaskTitle: viewModel.pendingSubTask?.title ?? "",
                onSelect: { blocker in
                    viewModel.handleBlockerSelection(blocker)
                },
                onCancel: {
                    viewModel.showingBlockerSelection = false
                    viewModel.pendingSubTask = nil
                }
            )
        }
        .sheet(isPresented: $vm.showingNudgeInput) {
            NudgeInputView(
                initialText: task.memory,
                onSave: { text in
                    viewModel.saveMemory(text)
                    viewModel.showingNudgeInput = false
                },
                onCancel: {
                    viewModel.showingNudgeInput = false
                }
            )
        }
        .onChange(of: task.currentSubTask?.id) { oldId, newId in
            if oldId != newId {
                viewModel.clearSchemaForNewSubTask()
            }
        }
    }

    private var submissionProgressView: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(viewModel.progressLog.enumerated()), id: \.offset) { index, message in
                    HStack(spacing: 12) {
                        if index == 0 {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: Theme.circleSize))
                                .foregroundColor(viewModel.phaseColor)
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
            .animation(.easeInOut(duration: 0.3), value: viewModel.progressLog.count)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    @ViewBuilder
    private func dynamicActionView(for subTask: SubTask) -> some View {
        @Bindable var vm = viewModel
        VStack(alignment: .leading, spacing: 16) {
            // Sub-task sub-header
            HStack(spacing: 10) {
                if task.isDiscoveryPhase {
                    Text("Question \(viewModel.currentIndex + 1) of \(task.subTasks.count)")
                        .font(.system(size: Theme.fontSize, weight: .medium))
                        .foregroundColor(.orange)
                } else {
                    Text("Step \(viewModel.currentIndex + 1) of \(task.subTasks.count)")
                        .font(.system(size: Theme.fontSize, weight: .medium))
                        .foregroundColor(.blue)
                }

                Text(subTask.title)
                    .font(.system(size: Theme.fontSize, weight: .semibold))

                if !task.isDiscoveryPhase && (subTask.effectiveRequiresExternalAction || viewModel.actionSchema?.requiresExternalAction == true) {
                    Text("Outside Work")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.externalActionColor)
                        .cornerRadius(4)
                }

                Spacer()

                if FoundationModelsAvailability.isAvailable && !viewModel.isLoadingSchema {
                    Button {
                        viewModel.regenerateActionUI(for: subTask)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderless)
                    .help("Regenerate Activity")
                }
            }

            // Outside work alert
            if !task.isDiscoveryPhase && (subTask.effectiveRequiresExternalAction || viewModel.actionSchema?.requiresExternalAction == true) {
                Text("This step requires action outside the app. It might feel uncomfortable, but completing it will move you closer to your goal.")
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.externalActionColor)
                    .cornerRadius(8)
            }

            // Action UI section
            if viewModel.isLoadingSchema {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Creating a custom UI for")
                        .font(.system(size: Theme.fontSize))
                        .foregroundColor(.secondary)
                    Text(subTask.title)
                        .font(.system(size: Theme.fontSize, weight: .bold))
                        .foregroundColor(viewModel.phaseColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
            } else if let schema = viewModel.actionSchema {
                ActionUIRenderer(schema: schema, response: $vm.actionResponse, isDiscovery: task.isDiscoveryPhase, showTitle: false) {
                    viewModel.completeSubTaskWithResponse(subTask)
                } onHelp: {
                    NotificationCenter.default.post(name: .revealCoach, object: nil)
                } onChangeFieldType: { newType, options in
                    viewModel.changeFieldType(to: newType, options: options, for: subTask)
                }
            } else if let error = viewModel.schemaError {
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
                            viewModel.skipSubTask(subTask)
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("Mark Complete") {
                            viewModel.completeSubTask(subTask)
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
                        if FoundationModelsAvailability.isAvailable {
                            Button("Generate Action UI") {
                                viewModel.loadOrGenerateActionUI(for: subTask)
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()

                        Button("Skip") {
                            viewModel.skipSubTask(subTask)
                        }
                        .buttonStyle(.bordered)

                        Button("Mark Complete") {
                            viewModel.completeSubTask(subTask)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                .task(id: subTask.id) {
                    if FoundationModelsAvailability.isAvailable && viewModel.actionSchema == nil && !viewModel.isLoadingSchema {
                        viewModel.loadOrGenerateActionUI(for: subTask)
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

                if FoundationModelsAvailability.isAvailable {
                    Button("Plan with AI") {
                        viewModel.planWithAI()
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
                .foregroundColor(viewModel.phaseColor)
            if task.isDiscoveryPhase && task.executionSubTasks.isEmpty {
                Text("All questions answered!")
                Spacer()
                Button("Create Execution Plan") {
                    viewModel.transitionToExecutionPhase()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("All steps completed!")
                Spacer()
                Button("Mark Task Complete") {
                    viewModel.completeTask()
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
            viewModel.transitionToExecutionPhase()
        }
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

#Preview {
    ActionItemsView()
        .modelContainer(for: [TodoTask.self, SubTask.self], inMemory: true)
}
