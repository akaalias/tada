import SwiftUI
import SwiftData

struct AddSubTasksSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let task: TodoTask
    @State private var subTaskInputs: [SubTaskInput] = [SubTaskInput()]

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Sub-Tasks")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Break down \"\(task.title)\" into steps")
                .foregroundColor(.secondary)
                .lineLimit(2)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach($subTaskInputs) { $input in
                        HStack {
                            Text("\(subTaskInputs.firstIndex(where: { $0.id == input.id })! + 1).")
                                .foregroundColor(.secondary)
                                .frame(width: 24)

                            TextField("Step description", text: $input.title)
                                .textFieldStyle(.roundedBorder)

                            if subTaskInputs.count > 1 {
                                Button {
                                    subTaskInputs.removeAll { $0.id == input.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        subTaskInputs.append(SubTaskInput())
                    } label: {
                        Label("Add Step", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxHeight: 300)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Save Sub-Tasks") {
                    saveSubTasks()
                }
                .buttonStyle(.borderedProminent)
                .disabled(validInputs.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private var validInputs: [SubTaskInput] {
        subTaskInputs.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func saveSubTasks() {
        for (index, input) in validInputs.enumerated() {
            let subTask = SubTask(
                title: input.title.trimmingCharacters(in: .whitespacesAndNewlines),
                order: index
            )
            if index == 0 {
                subTask.markCurrent()
            }
            task.addSubTask(subTask)
            modelContext.insert(subTask)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save sub-tasks: \(error)")
        }
    }
}

struct SubTaskInput: Identifiable {
    let id = UUID()
    var title: String = ""
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TodoTask.self, SubTask.self, configurations: config)
    let task = TodoTask(title: "Test Task")

    return AddSubTasksSheet(task: task)
        .modelContainer(container)
}
