import Foundation

/// Tools available to the productivity coach.
enum CoachTool: String, CaseIterable, Codable {
    case captureInboxItem = "capture_inbox_item"
    case createTask = "create_task"
    case searchTasks = "search_tasks"
    case getSubtasks = "get_subtasks"
    case updateDiscoveryQuestions = "update_discovery_questions"
    case replanExecution = "replan_execution"
    case readNote = "read_note"
    case createKnowledgeEntity = "create_knowledge_entity"
    case linkKnowledgeEntities = "link_knowledge_entities"
    case replaceTextWithLink = "replace_text_with_link"
    case editNote = "edit_note"
    case generateKnowledgeSummary = "generate_knowledge_summary"
    case searchNotes = "search_notes"
    case completeSubTask = "complete_subtask"
    case skipSubTask = "skip_subtask"
    case splitSubTask = "split_subtask"
    case updateSubTask = "update_subtask"

    var description: String {
        switch self {
        case .captureInboxItem:
            return "Quickly capture a thought or item to the inbox for later processing"
        case .createTask:
            return "Create a new task with AI-generated discovery questions"
        case .searchTasks:
            return "Search for tasks by name or description. Returns matching task IDs and titles."
        case .getSubtasks:
            return "Get all subtasks for a task. Returns subtask IDs and titles so you can update or split them."
        case .updateDiscoveryQuestions:
            return "Regenerate discovery questions for a task with new framing"
        case .replanExecution:
            return "Regenerate execution steps based on discovery answers"
        case .readNote:
            return "Read the content of the current note to see what text it contains"
        case .createKnowledgeEntity:
            return "Create a new entity note in the knowledge base"
        case .linkKnowledgeEntities:
            return "Add an entity to the Related section of a note"
        case .replaceTextWithLink:
            return "Find text in the current note and replace it with a wiki link to an entity"
        case .editNote:
            return "Edit the body content of the current note based on user instructions"
        case .generateKnowledgeSummary:
            return "Generate a summary of the knowledge base"
        case .searchNotes:
            return "Search for notes in the knowledge base by name. Returns note paths that can be used with link_knowledge_entities."
        case .completeSubTask:
            return "Mark the current subtask as complete"
        case .skipSubTask:
            return "Skip the current subtask"
        case .splitSubTask:
            return "Replace a subtask with multiple smaller subtasks. Use when the user is stuck and needs the step broken down into more manageable pieces."
        case .updateSubTask:
            return "Update a subtask's title or description. Use when the user wants to rename or clarify a step."
        }
    }

    var parameters: [ToolParameter] {
        switch self {
        case .captureInboxItem:
            return [
                ToolParameter(name: "content", type: .string, description: "The content to capture", required: true)
            ]
        case .createTask:
            return [
                ToolParameter(name: "description", type: .string, description: "Description of the task to create", required: true)
            ]
        case .searchTasks:
            return [
                ToolParameter(name: "query", type: .string, description: "Search query to match against task titles and descriptions", required: true)
            ]
        case .getSubtasks:
            return [
                ToolParameter(name: "task_id", type: .string, description: "ID of the task to get subtasks for", required: true)
            ]
        case .updateDiscoveryQuestions:
            return [
                ToolParameter(name: "task_id", type: .string, description: "ID of the task to update", required: true),
                ToolParameter(name: "new_framing", type: .string, description: "New framing or context for the discovery questions", required: true)
            ]
        case .replanExecution:
            return [
                ToolParameter(name: "task_id", type: .string, description: "ID of the task to replan", required: true),
                ToolParameter(name: "guidance", type: .string, description: "Additional guidance for replanning", required: false)
            ]
        case .readNote:
            return [
                ToolParameter(name: "note_path", type: .string, description: "Full path to the note file to read", required: true)
            ]
        case .createKnowledgeEntity:
            return [
                ToolParameter(name: "name", type: .string, description: "Name of the entity to create", required: true),
                ToolParameter(name: "content", type: .string, description: "Content for the entity note", required: false)
            ]
        case .linkKnowledgeEntities:
            return [
                ToolParameter(name: "source_note", type: .string, description: "The source note: use the full note_path from context, or just the entity name", required: true),
                ToolParameter(name: "target_entity", type: .string, description: "Name of the entity to link to", required: true)
            ]
        case .replaceTextWithLink:
            return [
                ToolParameter(name: "note_path", type: .string, description: "Full path to the note file to edit", required: true),
                ToolParameter(name: "text_to_find", type: .string, description: "The exact text to find and replace", required: true),
                ToolParameter(name: "target_entity", type: .string, description: "Name of the entity to link to", required: true)
            ]
        case .editNote:
            return [
                ToolParameter(name: "note_path", type: .string, description: "Full path to the note file to edit", required: true),
                ToolParameter(name: "new_body", type: .string, description: "The new body content for the note (replaces existing body)", required: true)
            ]
        case .generateKnowledgeSummary:
            return []
        case .searchNotes:
            return [
                ToolParameter(name: "query", type: .string, description: "Search query to match against note names", required: true)
            ]
        case .completeSubTask:
            return [
                ToolParameter(name: "task_id", type: .string, description: "ID of the task", required: true),
                ToolParameter(name: "subtask_id", type: .string, description: "ID of the subtask to complete", required: true)
            ]
        case .skipSubTask:
            return [
                ToolParameter(name: "task_id", type: .string, description: "ID of the task", required: true),
                ToolParameter(name: "subtask_id", type: .string, description: "ID of the subtask to skip", required: true)
            ]
        case .splitSubTask:
            return [
                ToolParameter(name: "task_id", type: .string, description: "ID of the task", required: true),
                ToolParameter(name: "subtask_id", type: .string, description: "ID of the subtask to replace", required: true),
                ToolParameter(name: "new_subtasks", type: .string, description: "JSON array of new subtasks, each with 'title' and optional 'description'. Example: [{\"title\":\"Research stores\",\"description\":\"Find nearby stores\"},{\"title\":\"Buy cable\"}]", required: true)
            ]
        case .updateSubTask:
            return [
                ToolParameter(name: "task_id", type: .string, description: "ID of the task", required: true),
                ToolParameter(name: "subtask_id", type: .string, description: "ID of the subtask to update", required: true),
                ToolParameter(name: "title", type: .string, description: "New title for the subtask", required: false),
                ToolParameter(name: "description", type: .string, description: "New description for the subtask", required: false)
            ]
        }
    }

    func toAPISchema() -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []

        for param in parameters {
            properties[param.name] = [
                "type": param.type.rawValue,
                "description": param.description
            ]
            if param.required {
                required.append(param.name)
            }
        }

        return [
            "name": rawValue,
            "description": description,
            "input_schema": [
                "type": "object",
                "properties": properties,
                "required": required
            ]
        ]
    }
}

struct ToolParameter {
    let name: String
    let type: ParameterType
    let description: String
    let required: Bool

    enum ParameterType: String {
        case string
        case number
        case boolean
    }
}

struct ToolCall: Codable, Equatable {
    let id: String
    let name: String
    let arguments: [String: String]
}
