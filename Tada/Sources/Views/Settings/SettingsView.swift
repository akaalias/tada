import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            APIKeySettingsView()
                .tabItem {
                    Label("API Key", systemImage: "key.fill")
                }

            LearningsSettingsView()
                .tabItem {
                    Label("Learnings", systemImage: "lightbulb.fill")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 650, height: 520)
    }
}

// MARK: - API Key Tab

private struct APIKeySettingsView: View {
    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var saveStatus: SaveStatus = .none

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
                                    apiKey = String(repeating: "•", count: 20)
                                } else {
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
        }
        .formStyle(.grouped)
        .onAppear {
            if let existingKey = APIKeyManager.getAPIKey() {
                apiKey = String(repeating: "•", count: min(existingKey.count, 20))
            }
        }
    }

    private func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedKey.contains("•") else { return }

        do {
            try APIKeyManager.setAPIKey(trimmedKey)
            saveStatus = .saved
            apiKey = String(repeating: "•", count: 20)

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saveStatus = .none
            }
        } catch {
            saveStatus = .error(AppError.userMessage(from: error))
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

// MARK: - Learnings Tab

private struct LearningsSettingsView: View {
    @State private var learnings: [PlanningLearning] = []

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
        .onAppear {
            learnings = PlanningMemoryService.shared.loadLearnings()
        }
    }
}

// MARK: - About Tab

private struct AboutSettingsView: View {
    var body: some View {
        Form {
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
