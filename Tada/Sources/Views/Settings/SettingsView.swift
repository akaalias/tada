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

                    if APIKeyManager.hasValidAPIKey {
                        Divider()
                        ModelPickerView()
                    }
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

// MARK: - Model Picker

/// A searchable dropdown of Claude models available to the configured API key.
private struct ModelPickerView: View {
    @State private var models: [ClaudeModel] = []
    @State private var selectedModel: String = ModelPreference.selectedModel
    @State private var search = ""
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model")
                .font(.headline)

            Text("Choose which Claude model handles task planning and action generation.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Button {
                    showPicker.toggle()
                } label: {
                    HStack {
                        Text(currentDisplayName)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(width: 300)
                    .background(Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoading || models.isEmpty)
                .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                    modelList
                }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    Task { await loadModels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
                .help("Refresh model list")
            }

            if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .task {
            await loadModels()
        }
    }

    private var currentDisplayName: String {
        models.first { $0.id == selectedModel }?.displayName ?? selectedModel
    }

    private var filteredModels: [ClaudeModel] {
        guard !search.isEmpty else { return models }
        return models.filter {
            $0.displayName.localizedCaseInsensitiveContains(search)
                || $0.id.localizedCaseInsensitiveContains(search)
        }
    }

    private var modelList: some View {
        VStack(spacing: 0) {
            TextField("Search models", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(8)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(filteredModels) { model in
                        Button {
                            selectedModel = model.id
                            ModelPreference.selectedModel = model.id
                            search = ""
                            showPicker = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(model.displayName)
                                    Text(model.id)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.id == selectedModel {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if filteredModels.isEmpty {
                        Text("No models match.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .frame(width: 320)
    }

    private func loadModels() async {
        guard let key = APIKeyManager.getAPIKey(), !key.isEmpty else { return }
        isLoading = true
        loadError = nil
        do {
            models = try await ModelCatalog.fetchModels(apiKey: key)
        } catch {
            loadError = AppError.userMessage(from: error)
        }
        isLoading = false
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
