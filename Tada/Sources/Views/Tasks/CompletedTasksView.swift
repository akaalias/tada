import SwiftUI
import SwiftData

struct CompletedTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TodoTask> { $0.status == "completed" }, sort: \TodoTask.completedAt, order: .reverse)
    private var completedTasks: [TodoTask]

    var body: some View {
        Group {
            if completedTasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(completedTasks) { task in
                            TaskCard(task: task, defaultExpanded: false) {
                                SubTaskListContent(task: task)
                            }
                            .opacity(0.7)
                            .contextMenu {
                                    Button("Reopen Task") {
                                        reopenTask(task)
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
        .navigationTitle("Completed")
        .toolbar {
            if !completedTasks.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear All", role: .destructive) {
                        clearAll()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No completed tasks")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tasks you complete will appear here.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reopenTask(_ task: TodoTask) {
        task.status = "active"
        task.completedAt = nil
        try? modelContext.save()
    }

    private func deleteTask(_ task: TodoTask) {
        modelContext.delete(task)
        try? modelContext.save()
    }

    private func deleteTasks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(completedTasks[index])
        }
        try? modelContext.save()
    }

    private func clearAll() {
        for task in completedTasks {
            modelContext.delete(task)
        }
        try? modelContext.save()
    }
}

#Preview {
    CompletedTasksView()
        .modelContainer(for: [TodoTask.self, SubTask.self], inMemory: true)
}
