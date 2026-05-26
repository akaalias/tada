import SwiftUI
import SwiftData

struct NewTaskSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var appServices

    @State private var taskInput = ""
    @State private var promptQuestion: String

    private static let kickOffPrompts = [
        "What do you want to accomplish today?",
        "What's the problem you're trying to solve?",
        "What's this task about?",
        "What needs to get done?",
        "What's on your mind?",
        "What would you like to tackle?",
        "What are you working on?",
        "What do you need help with?"
    ]

    init() {
        _promptQuestion = State(initialValue: Self.kickOffPrompts.randomElement() ?? "What do you want to accomplish?")
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(promptQuestion)
                .font(.system(size: Theme.fontSize, weight: .semibold))
                .multilineTextAlignment(.center)

            ZStack(alignment: .topLeading) {
                if taskInput.isEmpty {
                    Text("Describe what you want to accomplish...")
                        .font(.system(size: Theme.fontSize))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }

                TextEditor(text: $taskInput)
                    .font(.system(size: Theme.fontSize))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("newTaskSheet.input")
            }
            .frame(minHeight: 100)
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )

            if !FoundationModelsAvailability.isAvailable {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("On-device model unavailable. Enable Apple Intelligence to use AI planning.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier("newTaskSheet.cancel")

                Spacer()

                Button("Create Task", action: createTask)
                    .buttonStyle(.borderedProminent)
                    .disabled(taskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("newTaskSheet.create")
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func createTask() {
        let trimmedInput = taskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        // Create task immediately with planning status
        let task = TodoTask(title: trimmedInput, originalInput: trimmedInput)

        if FoundationModelsAvailability.isAvailable {
            task.planningStatus = PlanningStatus.planningDiscovery
        }

        modelContext.insert(task)
        try? modelContext.save()
        appServices?.knowledgeBase.handleTaskCreatedOrUpdated(task)
        dismiss()

        // Plan in background if API key available
        if FoundationModelsAvailability.isAvailable {
            let plannerAI = appServices?.plannerAI ?? PlannerAIServiceAdapter()
            Task {
                do {
                    let discoveryPlan = try await plannerAI.generateDiscoveryQuestions(for: trimmedInput)

                    await MainActor.run {
                        task.title = discoveryPlan.title
                        task.taskDescription = discoveryPlan.description

                        let cappedQuestions = Array(discoveryPlan.subTasks.prefix(AppConstants.maxDiscoveryQuestions))
                        for (index, questionPlan) in cappedQuestions.enumerated() {
                            let subTask = SubTask(
                                title: questionPlan.title,
                                description: questionPlan.description,
                                order: index
                            )
                            if index == 0 {
                                subTask.markCurrent()
                            }
                            task.addSubTask(subTask)
                            modelContext.insert(subTask)
                        }

                        task.planningStatus = PlanningStatus.idle
                        try? modelContext.save()
                        appServices?.knowledgeBase.handleTaskCreatedOrUpdated(task)
                    }
                } catch {
                    await MainActor.run {
                        task.planningStatus = PlanningStatus.idle
                        try? modelContext.save()
                    }
                }
            }
        }
    }
}

#Preview {
    NewTaskSheet()
        .modelContainer(for: [TodoTask.self, SubTask.self], inMemory: true)
}
