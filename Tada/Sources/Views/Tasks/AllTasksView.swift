import SwiftUI
import SwiftData

struct AllTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoTask.createdAt, order: .reverse) private var allTasks: [TodoTask]
    private var tasks: [TodoTask] { allTasks.filter { $0.status == .active } }

    @State private var selectedTask: TodoTask?

    var body: some View {
        Group {
            if tasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(tasks) { task in
                            TaskCard(task: task, defaultExpanded: true) {
                                SubTaskListContent(task: task)
                            }
                            .contextMenu {
                                    Button("Complete Task") {
                                        completeTask(task)
                                    }
                                    Divider()
                                    Button("Replan Discovery") {
                                        replanDiscovery(task)
                                    }
                                    if task.isExecutionPhase {
                                        Button("Replan Execution") {
                                            replanExecution(task)
                                        }
                                    }
                                    Divider()
                                    Button("Delete Task", role: .destructive) {
                                        deleteTask(task)
                                    }
                                }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("All Tasks")
        .onAppear {
            // Auto-complete any tasks that are 100% done but still marked active
            for task in tasks {
                if task.progress >= 1.0 && task.isExecutionPhase && !task.executionSubTasks.isEmpty {
                    let allExecutionDone = task.executionSubTasks.allSatisfy { $0.isCompleted }
                    if allExecutionDone {
                        task.markCompleted()
                        KnowledgeBaseService.shared.handleTaskCompleted(task)
                    }
                }
            }
            try? modelContext.save()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .newTask, object: nil)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No tasks yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add a task to get started.")
                .foregroundColor(.secondary)

            Button {
                NotificationCenter.default.post(name: .newTask, object: nil)
            } label: {
                Label("Add Task", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func completeTask(_ task: TodoTask) {
        task.markCompleted()
        try? modelContext.save()
        KnowledgeBaseService.shared.handleTaskCompleted(task)
    }

    private func deleteTask(_ task: TodoTask) {
        modelContext.delete(task)
        try? modelContext.save()
    }

    private func deleteTasks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tasks[index])
        }
        try? modelContext.save()
    }

    private func replanDiscovery(_ task: TodoTask) {
        guard let apiKey = APIKeyManager.getAPIKey() else { return }

        // Clear all subtasks and set planning status
        for subTask in task.subTasks {
            modelContext.delete(subTask)
        }
        task.phase = .discovery
        task.planningStatus = PlanningStatus.planningDiscovery
        try? modelContext.save()

        // Regenerate discovery
        Task {
            do {
                let planner = PlannerAIService(apiKey: apiKey)
                let plan = try await planner.generateDiscoveryQuestions(for: task.originalInput)

                await MainActor.run {
                    task.title = plan.title
                    task.taskDescription = plan.description

                    let cappedSubTasks = Array(plan.subTasks.prefix(5))
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
                    KnowledgeBaseService.shared.handleTaskCreatedOrUpdated(task)
                }
            } catch {
                print("Failed to replan discovery: \(error)")
                await MainActor.run {
                    task.planningStatus = .idle
                    try? modelContext.save()
                }
            }
        }
    }

    private func replanExecution(_ task: TodoTask) {
        guard let apiKey = APIKeyManager.getAPIKey() else { return }

        // Clear only execution subtasks and set planning status
        for subTask in task.executionSubTasks {
            modelContext.delete(subTask)
        }
        task.planningStatus = PlanningStatus.planningExecution
        try? modelContext.save()

        // Gather discovery answers
        let discoveryAnswers = task.discoverySubTasks
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

        // Regenerate execution
        Task {
            do {
                let planner = PlannerAIService(apiKey: apiKey)
                let executionPlan = try await planner.createExecutionPlan(
                    originalTask: task.originalInput,
                    discoveryAnswers: discoveryAnswers
                )

                await MainActor.run {
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
                    try? modelContext.save()
                    KnowledgeBaseService.shared.handleTaskCreatedOrUpdated(task)
                }
            } catch {
                print("Failed to replan execution: \(error)")
                await MainActor.run {
                    task.planningStatus = .idle
                    try? modelContext.save()
                }
            }
        }
    }
}

#Preview {
    AllTasksView()
        .modelContainer(for: [TodoTask.self, SubTask.self], inMemory: true)
}
