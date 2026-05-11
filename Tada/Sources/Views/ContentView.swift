import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedView: SidebarItem = .allTasks
    @State private var showingNewTaskSheet = false
    @Query private var allTasks: [TodoTask]

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selectedView)
        } detail: {
            detailView
        }
        .sheet(isPresented: $showingNewTaskSheet) {
            NewTaskSheet()
        }
        .onAppear {
            // Back-fill wiki pages for tasks created before the wiki feature existed.
            KnowledgeBaseService.shared.reconcile(tasks: allTasks)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTask)) { _ in
            showingNewTaskSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToInformationRequired)) { _ in
            selectedView = .informationRequired
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToActionRequired)) { _ in
            selectedView = .actionRequired
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTaskInActionRequired)) { _ in
            selectedView = .actionRequired
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedView {
        case .allTasks:
            AllTasksView()
        case .informationRequired:
            InformationRequiredView()
        case .actionRequired:
            ActionRequiredView()
        case .completed:
            CompletedTasksView()
        case .knowledge:
            KnowledgeBaseView()
        case .settings:
            SettingsView()
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case allTasks = "All Tasks"
    case informationRequired = "Information Required"
    case actionRequired = "Action Required"
    case completed = "Completed"
    case knowledge = "Knowledge Base"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .allTasks: return "list.bullet"
        case .informationRequired: return "questionmark.circle.fill"
        case .actionRequired: return "bolt.fill"
        case .completed: return "checkmark.circle"
        case .knowledge: return "book"
        case .settings: return "gear"
        }
    }
}

struct Sidebar: View {
    @Binding var selection: SidebarItem
    @Query(filter: #Predicate<TodoTask> { $0.status == "active" })
    private var activeTasks: [TodoTask]
    @ObservedObject private var kb = KnowledgeBaseService.shared

    private var mainItems: [SidebarItem] {
        [.allTasks, .informationRequired, .actionRequired]
    }

    private var secondaryItems: [SidebarItem] {
        [.completed, .knowledge, .settings]
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
            .frame(height: 132)
        }
        .frame(minWidth: 200)
    }

    @ViewBuilder
    private func sidebarRow(for item: SidebarItem) -> some View {
        NavigationLink(value: item) {
            Label {
                HStack {
                    Text(item.rawValue)
                    Spacer()
                    if item == .informationRequired && informationRequiredCount > 0 {
                        Text("\(informationRequiredCount)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    if item == .actionRequired && actionRequiredCount > 0 {
                        Text("\(actionRequiredCount)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    if item == .knowledge && kb.isWorking {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            } icon: {
                Image(systemName: item.icon)
            }
        }
    }

    private var informationRequiredCount: Int {
        activeTasks.filter { task in
            if task.isPlanningDiscovery { return true }
            if task.subTasks.isEmpty { return true }
            if task.isDiscoveryPhase && task.currentSubTask != nil { return true }
            if task.isDiscoveryPhase && !task.discoverySubTasks.isEmpty &&
               task.discoverySubTasks.allSatisfy({ $0.isCompleted }) { return true }
            return false
        }.count
    }

    private var actionRequiredCount: Int {
        activeTasks.filter { task in
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
