import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var appServices
    @State private var selectedView: SidebarItem = .allTasks
    @State private var showingNewTaskSheet = false
    @State private var apiKeyValid: Bool = APIKeyManager.hasValidAPIKey
    @Query private var allTasks: [TodoTask]

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selectedView, appServices: appServices)
        } detail: {
            detailView
        }
        .sheet(isPresented: $showingNewTaskSheet) {
            NewTaskSheet()
        }
        .onAppear {
            // Back-fill wiki pages for tasks created before the wiki feature existed.
            appServices?.knowledgeBase.reconcile(tasks: allTasks)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTask)) { _ in
            showingNewTaskSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToActionItems)) { _ in
            selectedView = .actionItems
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTaskInActionItems)) { _ in
            selectedView = .actionItems
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiKeyChanged)) { _ in
            apiKeyValid = APIKeyManager.hasValidAPIKey
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    @ViewBuilder
    private var detailView: some View {
        VStack(spacing: 16) {
            if !apiKeyValid {
                APIKeyBanner()
                    .padding(.horizontal)
                    .padding(.top, 16)
            }

            switch selectedView {
            case .allTasks:
                AllTasksView()
            case .actionItems:
                ActionItemsView()
            case .completed:
                CompletedTasksView()
            case .knowledge:
                KnowledgeBaseView()
            case .console:
                ConsoleView()
            case .settings:
                SettingsView()
            }
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case allTasks = "All Tasks"
    case actionItems = "Action Items"
    case completed = "Completed"
    case knowledge = "Knowledge Base"
    case console = "Console"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .allTasks: return "list.bullet"
        case .actionItems: return "bolt.fill"
        case .completed: return "checkmark.circle"
        case .knowledge: return "book"
        case .console: return "terminal"
        case .settings: return "gear"
        }
    }
}

struct Sidebar: View {
    @Binding var selection: SidebarItem
    let appServices: AppServices?
    @Query private var allTasks: [TodoTask]
    private var activeTasks: [TodoTask] { allTasks.filter { $0.status == .active } }
    private var kb: KnowledgeBaseServiceProtocol? { appServices?.knowledgeBase }

    private var mainItems: [SidebarItem] {
        [.allTasks, .actionItems]
    }

    private var secondaryItems: [SidebarItem] {
        [.completed, .knowledge, .console, .settings]
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(mainItems) { item in
                    sidebarRow(for: item)
                }
            }
            .listStyle(.sidebar)

            Spacer()

            List(selection: $selection) {
                ForEach(secondaryItems) { item in
                    sidebarRow(for: item)
                }
            }
            .listStyle(.sidebar)
            .frame(height: 176)
        }
        .frame(minWidth: 200)
    }

    @ViewBuilder
    private func sidebarRow(for item: SidebarItem) -> some View {
        NavigationLink(value: item) {
            Label {
                HStack {
                    Text(item.rawValue)
                        .accessibilityIdentifier("sidebar.\(item.id)")
                    Spacer()
                    if item == .actionItems && actionItemsCount > 0 {
                        Text("\(actionItemsCount)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    if item == .knowledge, let kb = kb, kb.isWorking {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            } icon: {
                Image(systemName: item.icon)
            }
        }
    }

    private var actionItemsCount: Int {
        activeTasks.filter { task in
            if task.isPlanningDiscovery { return true }
            if task.subTasks.isEmpty { return true }
            if task.isDiscoveryPhase && task.currentSubTask != nil { return true }
            if task.isDiscoveryPhase && !task.discoverySubTasks.isEmpty &&
               task.discoverySubTasks.allSatisfy({ $0.isCompleted }) { return true }
            if task.isPlanningExecution { return true }
            if task.isExecutionPhase && task.currentSubTask != nil { return true }
            return false
        }.count
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [TodoTask.self, SubTask.self], inMemory: true)
}
