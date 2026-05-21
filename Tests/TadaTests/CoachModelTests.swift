import Foundation
import Testing

@testable import Tada

// MARK: - CoachTool Tests

@Test func coachTool_all_cases_have_nonempty_description() {
    for tool in CoachTool.allCases {
        #expect(!tool.description.isEmpty, "\(tool.rawValue) has empty description")
    }
}

@Test func coachTool_rawValues_are_snake_case_identifiers() {
    // Every tool must map to the snake_case name the API expects.
    #expect(CoachTool.captureInboxItem.rawValue == "capture_inbox_item")
    #expect(CoachTool.createTask.rawValue == "create_task")
    #expect(CoachTool.splitSubTask.rawValue == "split_subtask")
    #expect(CoachTool.updateSubTask.rawValue == "update_subtask")
}

@Test func coachTool_generateKnowledgeSummary_has_no_parameters() {
    #expect(CoachTool.generateKnowledgeSummary.parameters.isEmpty)
}

@Test func coachTool_captureInboxItem_has_required_content_param() {
    let params = CoachTool.captureInboxItem.parameters
    #expect(params.count == 1)
    let content = try? #require(params.first)
    #expect(content?.name == "content")
    #expect(content?.type == .string)
    #expect(content?.required == true)
}

@Test func coachTool_replanExecution_marks_guidance_optional() {
    let params = CoachTool.replanExecution.parameters
    #expect(params.contains { $0.name == "task_id" && $0.required })
    #expect(params.contains { $0.name == "guidance" && !$0.required })
}

@Test func coachTool_updateSubTask_has_optional_title_and_description() {
    let params = CoachTool.updateSubTask.parameters
    #expect(params.first(where: { $0.name == "title" })?.required == false)
    #expect(params.first(where: { $0.name == "description" })?.required == false)
    #expect(params.first(where: { $0.name == "task_id" })?.required == true)
    #expect(params.first(where: { $0.name == "subtask_id" })?.required == true)
}

@Test func coachTool_toAPISchema_includes_name_description_and_input_schema() {
    let schema = CoachTool.createTask.toAPISchema()

    #expect(schema["name"] as? String == "create_task")
    #expect((schema["description"] as? String)?.isEmpty == false)

    let input = try? #require(schema["input_schema"] as? [String: Any])
    #expect(input?["type"] as? String == "object")

    let properties = try? #require(input?["properties"] as? [String: Any])
    #expect(properties?["description"] != nil)

    let required = try? #require(input?["required"] as? [String])
    #expect(required?.contains("description") == true)
}

@Test func coachTool_toAPISchema_omits_optional_params_from_required() {
    let schema = CoachTool.replanExecution.toAPISchema()
    let input = schema["input_schema"] as! [String: Any]
    let required = input["required"] as! [String]

    #expect(required.contains("task_id"))
    #expect(!required.contains("guidance"))

    // Optional params still appear under properties.
    let properties = input["properties"] as! [String: Any]
    #expect(properties["guidance"] != nil)
}

@Test func coachTool_toAPISchema_empty_params_yields_empty_required() {
    let schema = CoachTool.generateKnowledgeSummary.toAPISchema()
    let input = schema["input_schema"] as! [String: Any]
    let required = input["required"] as! [String]
    let properties = input["properties"] as! [String: Any]

    #expect(required.isEmpty)
    #expect(properties.isEmpty)
}

@Test func coachTool_every_case_produces_valid_apischema() {
    for tool in CoachTool.allCases {
        let schema = tool.toAPISchema()
        #expect(schema["name"] as? String == tool.rawValue)
        let input = schema["input_schema"] as? [String: Any]
        #expect(input?["properties"] is [String: Any])
        #expect(input?["required"] is [String])
    }
}

@Test func toolParameter_parameterType_rawValues() {
    #expect(ToolParameter.ParameterType.string.rawValue == "string")
    #expect(ToolParameter.ParameterType.number.rawValue == "number")
    #expect(ToolParameter.ParameterType.boolean.rawValue == "boolean")
}

@Test func toolCall_codable_roundtrip() throws {
    let call = ToolCall(id: "tool_1", name: "create_task", arguments: ["description": "Buy milk"])
    let data = try JSONEncoder().encode(call)
    let decoded = try JSONDecoder().decode(ToolCall.self, from: data)
    #expect(decoded == call)
}

// MARK: - CoachMessage Tests

@Test func coachMessage_init_defaults() {
    let message = CoachMessage(role: .user, content: "Hello")

    #expect(message.role == .user)
    #expect(message.content == "Hello")
    #expect(message.toolCalls == nil)
    #expect(message.toolResults == nil)
    #expect(message.timestamp <= Date())
}

@Test func coachMessage_distinct_ids() {
    let a = CoachMessage(role: .coach, content: "A")
    let b = CoachMessage(role: .coach, content: "A")
    #expect(a.id != b.id)
    #expect(a != b) // Equatable differs by id/timestamp
}

@Test func coachMessage_carries_tool_calls_and_results() {
    let call = ToolCall(id: "t1", name: "search_tasks", arguments: ["query": "tax"])
    let result = CoachMessage.ToolResult(toolUseId: "t1", toolName: "search_tasks", success: true, message: "Found 2")
    let message = CoachMessage(role: .coach, content: "", toolCalls: [call], toolResults: [result])

    #expect(message.toolCalls?.count == 1)
    #expect(message.toolResults?.count == 1)
    #expect(message.toolResults?.first?.success == true)
    #expect(message.toolResults?.first?.toolName == "search_tasks")
}

@Test func coachMessage_toolResult_assigns_unique_id() {
    let r1 = CoachMessage.ToolResult(toolUseId: "t1", toolName: "x", success: false, message: "err")
    let r2 = CoachMessage.ToolResult(toolUseId: "t1", toolName: "x", success: false, message: "err")
    #expect(r1.id != r2.id)
}

@Test func coachMessage_roles_are_distinct() {
    #expect(CoachMessage.Role.user != CoachMessage.Role.coach)
    #expect(CoachMessage.Role.coach != CoachMessage.Role.system)
}

// MARK: - CoachContext Tests

@MainActor
@Test func coachContext_default_view_is_allTasks() {
    let context = CoachContext()
    #expect(context.currentView == .allTasks)
    #expect(context.contextDescription.contains("All Tasks list"))
}

@MainActor
@Test func coachContext_allTasks_with_selected_task_lists_subtasks() {
    let context = CoachContext()
    let taskId = UUID()
    let subId = UUID()
    context.currentView = .allTasks
    context.selectedTaskId = taskId
    context.allSubTasks = [(id: subId, title: "Step one", isCurrent: true)]

    let desc = context.contextDescription
    #expect(desc.contains(taskId.uuidString))
    #expect(desc.contains("SELECTED TASK STEPS"))
    #expect(desc.contains(subId.uuidString))
    #expect(desc.contains("Step one"))
    #expect(desc.contains("(current)"))
}

@MainActor
@Test func coachContext_actionItems_description() {
    let context = CoachContext()
    context.currentView = .actionItems
    #expect(context.contextDescription.contains("Action Items"))
}

@MainActor
@Test func coachContext_completed_description() {
    let context = CoachContext()
    context.currentView = .completed
    #expect(context.contextDescription.contains("Completed Tasks"))
}

@MainActor
@Test func coachContext_knowledgeBase_with_and_without_note() {
    let context = CoachContext()

    context.currentView = .knowledgeBase(currentNote: nil)
    #expect(context.contextDescription.contains("Knowledge Base index"))

    let url = URL(fileURLWithPath: "/tmp/kb/note.md")
    context.currentView = .knowledgeBase(currentNote: url)
    #expect(context.contextDescription.contains("/tmp/kb/note.md"))
}

@MainActor
@Test func coachContext_console_and_settings_descriptions() {
    let context = CoachContext()
    context.currentView = .console
    #expect(context.contextDescription.contains("Console"))
    context.currentView = .settings
    #expect(context.contextDescription.contains("Settings"))
}

@MainActor
@Test func coachContext_focusedTask_includes_current_step_and_all_steps() {
    let context = CoachContext()
    let taskId = UUID()
    let subId = UUID()
    context.currentView = .focusedTask(taskId: taskId)
    context.selectedSubTaskId = subId
    context.currentSubTaskTitle = "Call the clinic"
    context.currentSubTaskDescription = "Phone (555) 1234"
    context.allSubTasks = [(id: subId, title: "Call the clinic", isCurrent: true)]

    let desc = context.contextDescription
    #expect(desc.contains("focused on a specific task"))
    #expect(desc.contains("CURRENT STEP"))
    #expect(desc.contains("Call the clinic"))
    #expect(desc.contains("Phone (555) 1234"))
    #expect(desc.contains("ALL STEPS IN THIS TASK"))
    #expect(desc.contains("split_subtask"))
}

@MainActor
@Test func coachContext_focusedTask_without_selected_subtask_omits_current_step() {
    let context = CoachContext()
    let taskId = UUID()
    context.currentView = .focusedTask(taskId: taskId)

    let desc = context.contextDescription
    #expect(desc.contains("focused on a specific task"))
    #expect(!desc.contains("CURRENT STEP"))
}

@Test func coachViewContext_equatable() {
    #expect(CoachViewContext.allTasks == .allTasks)
    #expect(CoachViewContext.knowledgeBase(currentNote: nil) == .knowledgeBase(currentNote: nil))
    let id = UUID()
    #expect(CoachViewContext.focusedTask(taskId: id) == .focusedTask(taskId: id))
    #expect(CoachViewContext.focusedTask(taskId: id) != .focusedTask(taskId: UUID()))
}
