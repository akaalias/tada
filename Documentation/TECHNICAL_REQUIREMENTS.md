# Technical Requirements Document: Tada

**Version:** 1.0  
**Date:** 2026-04-16  
**Related:** PRD.md

---

## 1. Overview

This document specifies the technical architecture and implementation requirements for Tada, a native macOS task management application with AI-powered planning and dynamic UI generation.

---

## 2. Technology Stack

### 2.1 Application Framework

| Layer | Technology | Rationale |
|-------|------------|-----------|
| Platform | macOS 14+ (Sonoma) | Native performance, system integration |
| UI Framework | SwiftUI | Modern declarative UI, native look and feel |
| Language | Swift 5.9+ | Type safety, performance, Apple ecosystem |
| Data Persistence | SwiftData | Native persistence, seamless SwiftUI integration |
| AI Integration | Claude API (Anthropic) | Best-in-class reasoning for planning and UI generation |

### 2.2 Dependencies

```swift
// Package.swift or Xcode dependencies
dependencies: [
    // HTTP client for API calls
    .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.19.0"),
    
    // JSON handling (built into Foundation, but consider for complex schemas)
    // SwiftUI built-in for UI components
]
```

---

## 3. Architecture

### 3.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      SwiftUI Views                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │   Task      │  │   Action    │  │   Dynamic       │  │
│  │   List      │  │   Required  │  │   Action UI     │  │
│  └─────────────┘  └─────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    View Models                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │   Task      │  │   Action    │  │   Action UI     │  │
│  │   ViewModel │  │   Dashboard │  │   Renderer      │  │
│  └─────────────┘  └─────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                      Services                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │   Task      │  │   Planner   │  │   Executive     │  │
│  │   Service   │  │   AI        │  │   AI            │  │
│  └─────────────┘  └─────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    Data Layer                            │
│  ┌─────────────────────┐  ┌───────────────────────────┐ │
│  │   SwiftData Models  │  │   Claude API Client       │ │
│  └─────────────────────┘  └───────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Component Responsibilities

| Component | Responsibility |
|-----------|----------------|
| **Views** | Pure UI rendering, user input capture |
| **ViewModels** | State management, view logic, service coordination |
| **TaskService** | CRUD operations, data validation |
| **PlannerAI** | Task structuring, sub-task generation, plan revision |
| **ExecutiveAI** | Action UI schema generation |
| **ActionUIRenderer** | Dynamic SwiftUI view construction from schema |

---

## 4. Data Models

### 4.1 SwiftData Models

```swift
import SwiftData

@Model
final class Task {
    @Attribute(.unique) var id: UUID
    var title: String
    var taskDescription: String
    var status: TaskStatus
    var createdAt: Date
    var completedAt: Date?
    var originalInput: String
    
    @Relationship(deleteRule: .cascade, inverse: \SubTask.task)
    var subTasks: [SubTask] = []
    
    init(originalInput: String) {
        self.id = UUID()
        self.title = originalInput // Will be refined by Planner AI
        self.taskDescription = ""
        self.status = .active
        self.createdAt = Date()
        self.originalInput = originalInput
    }
}

@Model
final class SubTask {
    @Attribute(.unique) var id: UUID
    var task: Task?
    var title: String
    var subTaskDescription: String
    var order: Int
    var status: SubTaskStatus
    var actionType: String?
    var actionSchema: Data? // JSON encoded ActionSchema
    var actionResponse: Data? // JSON encoded user response
    var completedAt: Date?
    
    init(title: String, order: Int) {
        self.id = UUID()
        self.title = title
        self.subTaskDescription = ""
        self.order = order
        self.status = .pending
    }
}

enum TaskStatus: String, Codable {
    case active
    case completed
    case archived
}

enum SubTaskStatus: String, Codable {
    case pending
    case current
    case completed
    case skipped
}
```

### 4.2 Action Schema Definition

```swift
/// Defines the structure of a dynamically generated action UI
struct ActionSchema: Codable {
    let type: ActionType
    let title: String
    let description: String?
    let fields: [ActionField]
    let submitLabel: String
    
    enum ActionType: String, Codable {
        case form
        case multiSelect
        case singleSelect
        case confirmation
        case freeform
    }
}

struct ActionField: Codable, Identifiable {
    let id: String
    let type: FieldType
    let label: String
    let placeholder: String?
    let required: Bool
    let options: [FieldOption]? // For select types
    let validation: FieldValidation?
    
    enum FieldType: String, Codable {
        case text
        case number
        case multiSelect
        case singleSelect
        case yesNo
        case date
        case textarea
        case checklist
    }
}

struct FieldOption: Codable, Identifiable {
    let id: String
    let label: String
    let description: String?
}

struct FieldValidation: Codable {
    let minLength: Int?
    let maxLength: Int?
    let minValue: Double?
    let maxValue: Double?
    let pattern: String?
}
```

---

## 5. AI Integration

### 5.1 Claude API Client

```swift
actor ClaudeAPIClient {
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-sonnet-4-6"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func sendMessage(
        systemPrompt: String,
        userMessage: String
    ) async throws -> String {
        // Implementation using URLSession or AsyncHTTPClient
        // Returns the assistant's text response
    }
    
    func sendStructuredMessage<T: Decodable>(
        systemPrompt: String,
        userMessage: String,
        responseType: T.Type
    ) async throws -> T {
        // Requests JSON response, parses into expected type
    }
}
```

### 5.2 Planner AI Service

```swift
actor PlannerAIService {
    private let client: ClaudeAPIClient
    
    private let systemPrompt = """
    You are a task planning assistant. When given a user's task input, you will:
    
    1. Create a clear, actionable title (imperative mood, specific outcome)
    2. Write a brief description explaining the goal
    3. Generate 3-7 sub-tasks that form a logical plan
    
    Each sub-task should be:
    - Actionable (something the user can do)
    - Sequential (order matters)
    - Completable (has a clear done state)
    
    Respond in JSON format:
    {
        "title": "...",
        "description": "...",
        "subTasks": [
            {"title": "...", "description": "..."},
            ...
        ]
    }
    """
    
    func planTask(input: String) async throws -> TaskPlan {
        // Send to Claude, parse response
    }
    
    func revisePlan(
        task: Task,
        completedSubTask: SubTask,
        userResponse: [String: Any]
    ) async throws -> PlanRevision {
        // Evaluate if remaining sub-tasks need changes
    }
}

struct TaskPlan: Codable {
    let title: String
    let description: String
    let subTasks: [SubTaskPlan]
}

struct SubTaskPlan: Codable {
    let title: String
    let description: String
}

struct PlanRevision: Codable {
    let revised: Bool
    let reason: String?
    let newSubTasks: [SubTaskPlan]? // If revised
}
```

### 5.3 Executive AI Service

```swift
actor ExecutiveAIService {
    private let client: ClaudeAPIClient
    
    private let systemPrompt = """
    You are a UI designer that creates simple action interfaces. Given a sub-task, 
    design the easiest possible way for a user to complete it.
    
    Available field types:
    - text: Single line text input
    - number: Numeric input with optional min/max
    - textarea: Multi-line text
    - singleSelect: Choose one option
    - multiSelect: Choose multiple options
    - yesNo: Boolean toggle
    - date: Date picker
    - checklist: Multiple items to confirm
    
    Design principles:
    - Minimize typing (prefer selections when options are obvious)
    - One screen, one action
    - Clear submit button label
    - Only ask what's necessary
    
    Respond in JSON matching the ActionSchema format.
    """
    
    func generateActionUI(
        subTask: SubTask,
        taskContext: Task,
        previousResponses: [[String: Any]]
    ) async throws -> ActionSchema {
        // Generate appropriate UI schema for this sub-task
    }
}
```

---

## 6. Dynamic UI Rendering

### 6.1 ActionUIRenderer

The core component that transforms `ActionSchema` into SwiftUI views:

```swift
struct ActionUIRenderer: View {
    let schema: ActionSchema
    @Binding var responses: [String: Any]
    let onSubmit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(schema.title)
                .font(.headline)
            
            // Description
            if let description = schema.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Dynamic fields
            ForEach(schema.fields) { field in
                renderField(field)
            }
            
            // Submit button
            Button(action: onSubmit) {
                Text(schema.submitLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValid)
        }
        .padding()
    }
    
    @ViewBuilder
    private func renderField(_ field: ActionField) -> some View {
        switch field.type {
        case .text:
            TextFieldView(field: field, value: binding(for: field.id))
        case .number:
            NumberFieldView(field: field, value: binding(for: field.id))
        case .singleSelect:
            SingleSelectView(field: field, value: binding(for: field.id))
        case .multiSelect:
            MultiSelectView(field: field, value: binding(for: field.id))
        case .yesNo:
            YesNoView(field: field, value: binding(for: field.id))
        case .date:
            DateFieldView(field: field, value: binding(for: field.id))
        case .textarea:
            TextAreaView(field: field, value: binding(for: field.id))
        case .checklist:
            ChecklistView(field: field, value: binding(for: field.id))
        }
    }
}
```

### 6.2 Field Component Examples

```swift
struct MultiSelectView: View {
    let field: ActionField
    @Binding var value: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.label)
                .font(.subheadline)
                .fontWeight(.medium)
            
            ForEach(field.options ?? []) { option in
                HStack {
                    Image(systemName: value.contains(option.id) 
                        ? "checkmark.square.fill" 
                        : "square")
                        .foregroundColor(value.contains(option.id) ? .accentColor : .secondary)
                    
                    VStack(alignment: .leading) {
                        Text(option.label)
                        if let description = option.description {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if value.contains(option.id) {
                        value.remove(option.id)
                    } else {
                        value.insert(option.id)
                    }
                }
            }
        }
    }
}
```

---

## 7. View Architecture

### 7.1 Main Views

```swift
// App entry point
@main
struct TadaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Task.self, SubTask.self])
    }
}

// Main navigation
struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            Sidebar()
        } detail: {
            // Detail view based on selection
        }
    }
}

struct Sidebar: View {
    var body: some View {
        List {
            NavigationLink(destination: ActionRequiredView()) {
                Label("Action Required", systemImage: "bolt.fill")
            }
            
            NavigationLink(destination: AllTasksView()) {
                Label("All Tasks", systemImage: "list.bullet")
            }
            
            NavigationLink(destination: CompletedView()) {
                Label("Completed", systemImage: "checkmark.circle")
            }
        }
        .listStyle(.sidebar)
    }
}
```

### 7.2 Action Required View

```swift
struct ActionRequiredView: View {
    @Query(filter: #Predicate<Task> { $0.status == .active })
    private var activeTasks: [Task]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(activeTasks) { task in
                    if let currentSubTask = task.currentSubTask {
                        ActionCard(task: task, subTask: currentSubTask)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Action Required")
    }
}

struct ActionCard: View {
    let task: Task
    let subTask: SubTask
    @State private var responses: [String: Any] = [:]
    @State private var schema: ActionSchema?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Context header
            Text(task.title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(subTask.title)
                .font(.title3)
                .fontWeight(.semibold)
            
            Divider()
            
            // Dynamic UI
            if let schema = schema {
                ActionUIRenderer(
                    schema: schema,
                    responses: $responses,
                    onSubmit: handleSubmit
                )
            } else {
                ProgressView()
                    .task { await loadActionUI() }
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private func loadActionUI() async {
        // Load schema from subTask.actionSchema or generate new one
    }
    
    private func handleSubmit() {
        // 1. Save response
        // 2. Mark sub-task complete
        // 3. Trigger plan revision
        // 4. Load next action
    }
}
```

---

## 8. API Key Management

```swift
enum APIKeyManager {
    private static let keychainService = "com.tada.apikey"
    
    static func getAPIKey() throws -> String {
        // Read from Keychain
    }
    
    static func setAPIKey(_ key: String) throws {
        // Store in Keychain securely
    }
    
    static var hasAPIKey: Bool {
        (try? getAPIKey()) != nil
    }
}
```

Settings view for API key configuration:

```swift
struct SettingsView: View {
    @State private var apiKey: String = ""
    
    var body: some View {
        Form {
            Section("Claude API") {
                SecureField("API Key", text: $apiKey)
                Button("Save") {
                    try? APIKeyManager.setAPIKey(apiKey)
                }
            }
        }
        .padding()
    }
}
```

---

## 9. Error Handling

```swift
enum TadaError: LocalizedError {
    case networkError(underlying: Error)
    case apiError(message: String)
    case invalidResponse
    case missingAPIKey
    case schemaParsingError
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let message):
            return "API error: \(message)"
        case .invalidResponse:
            return "Invalid response from AI"
        case .missingAPIKey:
            return "Please configure your Claude API key in Settings"
        case .schemaParsingError:
            return "Failed to parse action UI schema"
        }
    }
}
```

---

## 10. Testing Strategy

### 10.1 Unit Tests

| Component | Test Focus |
|-----------|------------|
| ActionSchema | JSON encoding/decoding |
| ActionUIRenderer | Field rendering for each type |
| TaskService | CRUD operations |
| PlannerAI | Response parsing |

### 10.2 Integration Tests

- End-to-end task creation with AI planning
- Action submission and plan revision flow
- Persistence across app restarts

### 10.3 UI Tests

- Navigation flows
- Action form submission
- Error state handling

---

## 11. Performance Considerations

| Area | Approach |
|------|----------|
| AI Response Time | Show loading states, stream responses if possible |
| Data Loading | Use SwiftData's lazy loading |
| UI Rendering | Lazy stacks for large task lists |
| Caching | Cache generated action schemas locally |

---

## 12. Security

- API keys stored in Keychain (not UserDefaults)
- No sensitive data in logs
- HTTPS for all API calls
- No analytics/tracking in V1

---

## 13. Build & Distribution

| Setting | Value |
|---------|-------|
| Minimum macOS | 14.0 (Sonoma) |
| Architecture | Universal (Apple Silicon + Intel) |
| Signing | Developer ID (for notarization) |
| Distribution | Direct download (V1), Mac App Store (future) |

---

## 14. File Structure

```
Tada/
├── TadaApp.swift
├── Models/
│   ├── Task.swift
│   ├── SubTask.swift
│   └── ActionSchema.swift
├── Views/
│   ├── ContentView.swift
│   ├── Sidebar.swift
│   ├── ActionRequired/
│   │   ├── ActionRequiredView.swift
│   │   └── ActionCard.swift
│   ├── Tasks/
│   │   ├── AllTasksView.swift
│   │   ├── TaskRow.swift
│   │   └── TaskDetailView.swift
│   ├── ActionUI/
│   │   ├── ActionUIRenderer.swift
│   │   ├── TextFieldView.swift
│   │   ├── NumberFieldView.swift
│   │   ├── SingleSelectView.swift
│   │   ├── MultiSelectView.swift
│   │   ├── YesNoView.swift
│   │   ├── DateFieldView.swift
│   │   ├── TextAreaView.swift
│   │   └── ChecklistView.swift
│   └── Settings/
│       └── SettingsView.swift
├── ViewModels/
│   ├── TaskViewModel.swift
│   └── ActionDashboardViewModel.swift
├── Services/
│   ├── TaskService.swift
│   ├── ClaudeAPIClient.swift
│   ├── PlannerAIService.swift
│   └── ExecutiveAIService.swift
├── Utilities/
│   ├── APIKeyManager.swift
│   └── TadaError.swift
└── Resources/
    └── Assets.xcassets
```

---

## 15. Implementation Phases

### Phase 1: Foundation (Week 1)
- [ ] Project setup with SwiftUI + SwiftData
- [ ] Task and SubTask models
- [ ] Basic CRUD UI (no AI)
- [ ] Navigation structure

### Phase 2: AI Integration (Week 2)
- [ ] Claude API client
- [ ] Planner AI service
- [ ] Task creation with AI planning
- [ ] API key management

### Phase 3: Dynamic UI (Week 3)
- [ ] ActionSchema model
- [ ] Executive AI service
- [ ] ActionUIRenderer + field components
- [ ] Action Required dashboard

### Phase 4: Polish (Week 4)
- [ ] Plan revision after action completion
- [ ] Error handling and edge cases
- [ ] Loading states and animations
- [ ] Testing

---

## 16. Open Technical Questions

1. **Streaming**: Should AI responses stream to show progress, or wait for complete response?
2. **Offline**: Cache AI responses? Allow manual task management offline?
3. **Rate Limiting**: How to handle Claude API rate limits gracefully?
4. **Schema Evolution**: How to handle schema changes across app versions?
