import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            EngineSettingsView()
                .tabItem {
                    Label("Engine", systemImage: "cpu")
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

// MARK: - Engine Tab

/// Shows on-device model status. Tada runs entirely on Apple's foundation model;
/// there is no remote API and no key to configure.
private struct EngineSettingsView: View {
    private let available = FoundationModelsAvailability.isAvailable
    private let unavailableReason = FoundationModelsAvailability.unavailableReason

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("AI Engine")
                        .font(.headline)

                    Text("Tada plans your tasks and generates action UIs entirely on-device using Apple's foundation model. Nothing is sent to a server, and no API key is required.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Image(systemName: available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(available ? .green : .orange)
                        Text(available ? "On-device model ready" : (unavailableReason ?? "On-device model unavailable"))
                            .font(.system(size: 13))
                    }
                }
                .padding()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Learnings Tab

private struct LearningsSettingsView: View {
    @State private var learnings: [PlanningLearning] = []

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Planning Learnings")
                        .font(.headline)

                    Text("Lessons the AI has learned from your feedback.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if learnings.isEmpty {
                        Text("None yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(learnings) { learning in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(learning.lesson.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Button {
                                        PlanningMemoryService.shared.deleteLearning(id: learning.id)
                                        learnings = PlanningMemoryService.shared.loadLearnings()
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.secondary.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(10)
                                .background(Color(.controlBackgroundColor))
                                .cornerRadius(6)
                            }
                        }

                        Button("Clear All", role: .destructive) {
                            PlanningMemoryService.shared.clearAllLearnings()
                            learnings = []
                        }
                        .font(.caption)
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

                    Text("A task management app that uses on-device AI to plan your tasks and generate custom interfaces to help you complete them.")
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

#Preview {
    SettingsView()
}
