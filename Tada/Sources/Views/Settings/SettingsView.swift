import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var saveStatus: SaveStatus = .none
    @State private var learnings: [PlanningLearning] = []

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Claude API Key")
                        .font(.headline)

                    Text("Required for AI-powered task planning and action generation.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        if APIKeyManager.hasAPIKey && !showKey {
                            SecureField("", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            TextField("Enter your API key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        if APIKeyManager.hasAPIKey {
                            Button {
                                if showKey {
                                    // Hide: mask the key
                                    apiKey = String(repeating: "•", count: 20)
                                } else {
                                    // Show: read the real key from storage
                                    apiKey = APIKeyManager.getAPIKey() ?? ""
                                }
                                showKey.toggle()
                            } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    HStack {
                        Button("Save API Key") {
                            saveAPIKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if APIKeyManager.hasAPIKey {
                            Button("Remove", role: .destructive) {
                                removeAPIKey()
                            }
                        }

                        Spacer()

                        switch saveStatus {
                        case .none:
                            EmptyView()
                        case .saved:
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        case .removed:
                            Label("Removed", systemImage: "trash.fill")
                                .foregroundColor(.orange)
                        case .error(let message):
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                        }
                    }

                    Divider()

                    Text("Get your API key from [console.anthropic.com](https://console.anthropic.com/)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Planning Learnings")
                            .font(.headline)

                        Spacer()

                        if !learnings.isEmpty {
                            Button("Clear All", role: .destructive) {
                                PlanningMemoryService.shared.clearAllLearnings()
                                learnings = []
                            }
                            .font(.caption)
                        }
                    }

                    Text("Lessons learned from steps you marked as 'doesn't make sense'. These guide future AI planning.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if learnings.isEmpty {
                        Text("No learnings yet. When you mark steps as not making sense, the AI will learn from those mistakes.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(learnings) { learning in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(.yellow)
                                        .font(.system(size: 12))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(learning.lesson)
                                            .font(.system(size: 13))

                                        Text("From: \(learning.badStepTitle)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Button {
                                        PlanningMemoryService.shared.deleteLearning(id: learning.id)
                                        learnings = PlanningMemoryService.shared.loadLearnings()
                                    } label: {
                                        Image(systemName: "xmark.circle")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 4)

                                if learning.id != learnings.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About Tada")
                        .font(.headline)

                    Text("A task management app that uses AI to plan your tasks and generate custom interfaces to help you complete them.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Version 1.0")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 500)
        .onAppear {
            if let existingKey = APIKeyManager.getAPIKey() {
                // Show masked version
                apiKey = String(repeating: "•", count: min(existingKey.count, 20))
            }
            learnings = PlanningMemoryService.shared.loadLearnings()
        }
    }

    private func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedKey.contains("•") else { return }

        do {
            try APIKeyManager.setAPIKey(trimmedKey)
            saveStatus = .saved
            apiKey = String(repeating: "•", count: 20)

            // Clear status after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saveStatus = .none
            }
        } catch {
            saveStatus = .error(error.localizedDescription)
        }
    }

    private func removeAPIKey() {
        APIKeyManager.deleteAPIKey()
        apiKey = ""
        saveStatus = .removed

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            saveStatus = .none
        }
    }
}

enum SaveStatus {
    case none
    case saved
    case removed
    case error(String)
}

#Preview {
    SettingsView()
}
