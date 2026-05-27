# Code Context

## Files Retrieved

### Core View Structure
1. `/Users/alexisrondeau/Workshop/tada/Tada/Sources/TadaApp.swift` - Main app entry point with swiftData model container
2. `/Users/alexisrondeau/Workshop/tada/Tada/Sources/Views/ContentView.swift` - Main shell with sidebar navigation and detail view router
3. `/Users/alexisrondeau/Workshop/tada/Tada/Sources/Views/NewTaskSheet.swift` - Task creation flow with AI planning

### ActionUI Renderer System
4. `/Users/alexisrondeau/Workshop/tada/Tada/Sources/Views/ActionUI/ActionUIRenderer.swift` - Dynamic form renderer with type selection menu
5. `/Users/alexisrondeau/Workshop/tada/Tada/Sources/Models/ActionSchema.swift` - Schema definitions for dynamic UI generation
6. `/Users/alexisrondeau/Workshop/tada/Tada/Sources/Views/ActionUI/Renderers/*.swift` - 15+ field renderers for different input types

### Task Views
7. `/Users/alexisrondeau/Workshop/tada/Tada/Sources/Views/Tasks/AllTasksView.swift` - Main task list with discovery/execution phases
8. `/Users/alexisrondeau/Workshop/tada/Tada/Sources/Views/Tasks/ActionRequiredView.swift` - Action Items view for tasks needing attention
9. `/Users/alexisrondeau/Workshop/tada/Tada/Sources/Views/Tasks/CompletedTasksView.swift` - Completed task archive
10. `/Users/alexisrondeau/Workshop/tada/Tada/Sources/Views/Tasks/FocusedTaskView.swift` - Single-task focused view
11. `/Users/alexisrondeau/Workshop/tada/Tada/Sources/Views/Tasks/TaskCardComponents.swift` - Reusable task card components
12. `/Users/alexisrondeau/Workshop/tada/Tada/Sources/Views/Tasks/AddSubTasksSheet.swift` - Add sub-tasks UI

### Settings & Knowledge Base
13. `/Users/alexisrondeau/Workshop/tada/Tada/Sources/Views/Settings/SettingsView.swift` - Settings with Engine, Learnings, About tabs
14. `/Users/alexisrondeau/Workshop/tada/Tada/Sources/Views/Tasks/KnowledgeBaseView.swift` - Wiki editor with markdown, graph view, backlinks

## Key Code

### Main App Entry Point
```swift
// TadaApp.swift (lines 1-40)
@main
struct TadaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appServices, appServices)
        }
        .modelContainer(for: [TodoTask.self, SubTask.self], inMemory: UITestSupport.isActive)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") { NotificationCenter.default.post(name: .newTask, object: nil) }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
```

### ContentView Navigation Structure
```swift
// ContentView.swift (lines 12-160)
struct ContentView: View {
    @State private var selectedView: SidebarItem = .allTasks
    @State private var showingNewTaskSheet = false
    
    enum SidebarItem: String, CaseIterable, Identifiable {
        case allTasks, actionItems, completed, knowledge, console, settings
    }
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedView {
        case .allTasks: AllTasksView(coachContext: coachContext)
        case .actionItems: ActionItemsView()
        case .completed: CompletedTasksView()
        case .knowledge: KnowledgeBaseView(coachContext: coachContext)
        case .settings: SettingsView()
        }
    }
}
```

### ActionUI Renderer Architecture
```swift
// ActionUIRenderer.swift (lines 17-150)
struct ActionUIRenderer: View {
    let schema: ActionSchema
    @Binding var response: ActionResponse
    
    var body: some View {
        ForEach(schema.fields) { field in
            renderField(field)
        }
    }
    
    @ViewBuilder
    private func renderField(_ field: ActionField) -> some View {
        switch field.type {
        case .text: TextFieldRenderer(field: field, response: $response)
        case .number: NumberFieldRenderer(field: field, response: $response)
        case .textarea: TextAreaRenderer(field: field, response: $response)
        case .singleSelect: SingleSelectRenderer(field: field, response: $response)
        case .multiSelect: MultiSelectRenderer(field: field, response: $response)
        case .yesNo: YesNoRenderer(field: field, response: $response)
        case .checklist: ChecklistRenderer(field: field, response: $response)
        case .itemTable: ItemTableRenderer(field: field, response: $response)
        // ... 7 more renderer types
        }
    }
}
```

### Task Model with Phases
```swift
// TodoTask.swift (lines 1-85)
@Model
final class TodoTask {
    var phase: TaskPhase = TaskPhase.discovery
    var planningStatus: PlanningStatus = PlanningStatus.idle
    
    var isDiscoveryPhase: Bool { phase == .discovery }
    var isExecutionPhase: Bool { phase == .execution }
    
    var currentSubTask: SubTask? {
        currentPhaseSubTasks.first { $0.status == .current || $0.status == .pending }
    }
    
    var progress: Double {
        let phaseTasks = currentPhaseSubTasks
        guard !phaseTasks.isEmpty else { return 0 }
        let completed = phaseTasks.filter { $0.status.isCompleted }.count
        return Double(completed) / Double(phaseTasks.count)
    }
    
    func markCompleted() {
        status = TaskStatus.completed
        completedAt = Date()
    }
}
```

### SubTask with Action Schema Support
```swift
// SubTask.swift (lines 1-60)
@Model
final class SubTask {
    var actionSchemaData: Data?
    var actionResponseData: Data?
    var requiresExternalAction: Bool = false
    
    var effectiveRequiresExternalAction: Bool {
        if requiresExternalAction { return true }
        guard let data = actionSchemaData,
              let schema = try? JSONDecoder().decode(ActionSchema.self, from: data) else {
            return false
        }
        return schema.requiresExternalAction
    }
}
```

### Knowledge Base View with Markdown Rendering
```swift
// KnowledgeBaseView.swift (lines 17-80)
struct KnowledgeBaseView: View {
    @State private var pageStack: [URL] = []
    
    var body: some View {
        MarkdownPageBody(url: currentURL, rootURL: rootURL)
        TaskContextFooter(url: currentURL, tasks: allTasks)
        BacklinksFooter(url: currentURL, refreshTick: refreshTick)
    }
    
    private func rewriteWikilinks(_ text: String, ...) -> String {
        // Rewrites [[wikilinks]] to clickable file:// links
    }
}

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case unorderedListItem(text: String)
    case orderedListItem(number: Int, text: String)
    case table(headers: [String], rows: [[String]])
}
```

## Architecture

### View Hierarchy
```
TadaApp
└── ContentView (main shell)
    ├── Sidebar (NavigationSplitView leading)
    │   └── List with 6 navigation items
    └── Detail View (NavigationSplitView detail)
        └── switch(selectedView)
            ├── AllTasksView
            │   └── TaskCard components for each active task
            ├── ActionItemsView (tasks needing attention)
            │   └── ActionCard components with "Take Action"
            ├── CompletedTasksView
            ├── KnowledgeBaseView (Wiki)
            │   ├── MarkdownPageBody
            │   ├── TaskContextFooter
            │   └── BacklinksFooter
            └── SettingsView (TabView)
                ├── EngineSettingsView
                ├── LearningsSettingsView
                └── AboutSettingsView
```

### Dynamic Form Generation Flow
1. **Task Creation** (`NewTaskSheet.swift`) - User enters task description
2. **Planning Trigger** - `planningStatus = .planningDiscovery`
3. **Planner AI** (`PlannerAIServiceAdapter`) generates discovery questions
4. **Discovery Phase** creates SubTasks with `phase = .discovery`
5. **Answer Collection** - ActionSchema generated for each discovery subtask
6. **ActionUIRenderer** renders dynamic form based on schema fields
7. **Response Storage** - `subTask.actionResponseData` stores JSON response
8. **Execution Transition** - User triggers `transitionToExecution()`
9. **Execution Planning** - Planner generates execution steps from discovery answers
10. **Execution Phase** - SubTasks with `phase = .execution` for completion

### ActionSchema Field Types (16 total)
- Text/Number/Textarea - Simple input fields
- SingleSelect/MultiSelect - Choice selection
- YesNo - Boolean toggle
- Date - Calendar picker
- Checklist - Multi-select with completion tracking
- Drawing/Brainstorm - Visual inputs
- Slider/RangeSlider - Numeric range selection
- CountSelector - 1-4+ counter
- ItemTable - Grid with currency/category options
- OrderedList/HierarchicalList - Drag-to-reorder trees

### Coach Context System
```swift
enum CoachViewContext {
    case allTasks, actionItems, completed
    case knowledgeBase(currentNote: URL?)
    case focusedTask(taskId: UUID)
    case console, settings
}

class CoachContext {
    var currentView: CoachViewContext = .allTasks
    var selectedTaskId: UUID?
    var allSubTasks: [(id: UUID, title: String, isCurrent: Bool)]?
}
```

## Start Here

**First file to open**: `/Users/alexisrondeau/Workshop/tada/Tada/Sources/Views/ContentView.swift`

**Why**: This is the central navigation hub that ties together all views. Understanding this file explains how users move between All Tasks, Action Items, Completed tasks, Knowledge Base, Settings, and Console.

**Next files to understand**:
1. `ActionUI/ActionUIRenderer.swift` - How dynamic forms are generated
2. `Models/TodoTask.swift` - Task phases and progression logic
3. `Services/PlannerAIServiceAdapter.swift` - AI planning integration

## Supervisor coordination

No blocking issues identified. The Views folder structure is well-organized with clear separation between:
- Navigation (ContentView)
- Task management (Tasks folder)
- Dynamic UI rendering (ActionUI folder)
- Settings/Knowledge Base

All tasks are read-only reconnaissance - no runtime intervention needed.
