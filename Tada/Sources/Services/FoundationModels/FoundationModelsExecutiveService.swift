import Foundation
import FoundationModels

/// On-device executive. Generates ONE UI control per sub-task via guided generation.
/// The `GenActionSchema` type enforces "exactly one field" and a valid field type
/// structurally; these instructions carry the task->UI mapping and field-population
/// rules (restored from the original prompt, minus the literal JSON example which the
/// `@Generable` shape now guarantees). `ExecutiveFieldHeuristics` is a deterministic
/// backstop for the type mistakes the on-device model still makes.
struct FoundationModelsExecutiveService: ExecutiveAIServiceProtocol {

    /// Cap on prior-response text injected into the prompt, to protect the
    /// 4,096-token context window on long tasks.
    private static let maxPreviousResponsesChars = 1200

    func generateActionUI(
        subTask: String,
        subTaskDescription: String,
        taskContext: String,
        previousResponses: [[String: String]],
        taskMemory: String,
        phase: TaskPhase
    ) async throws -> ActionSchema {
        let session = LanguageModelSession { Self.instructions }

        var prompt = "Task: \(taskContext)\n\nSub-task to complete: \(subTask)"
        if !subTaskDescription.isEmpty { prompt += "\nDetails: \(subTaskDescription)" }
        let prev = ExecutiveAIService.formatPreviousResponses(previousResponses)
        if !prev.isEmpty { prompt += "\n\nPrevious responses in this task:\n\(prev.prefix(Self.maxPreviousResponsesChars))" }
        if !taskMemory.isEmpty { prompt += "\n\nUSER'S INSTRUCTIONS (follow strictly):\n\(taskMemory)" }
        prompt += "\n\nUse \"\(subTask)\" as the title — do not invent a different one."

        let response = try await session.respond(
            to: prompt,
            generating: GenActionSchema.self,
            options: GenerationOptions(temperature: 0.4)
        )
        return ExecutiveFieldHeuristics.corrected(response.content.toDomain())
    }

    private static let instructions = """
    You create ONE appropriate UI control for a single sub-task. Use the EXACT sub-task \
    title provided. Generate exactly ONE field — pick the BEST type for this task.

    FIELD TYPES:
    Selection (when you can enumerate options):
    - singleSelect: pick ONE from a list. Provide 3-6 thoughtful options.
    - multiSelect: pick MULTIPLE from a list.
    - yesNo: a yes/no confirmation. ALWAYS provide two descriptive options, e.g. \
      {id:"yes", label:"Yes, I have made the call"} / {id:"no", label:"No, not yet"}.
    - orderedList: drag-and-drop to put items in sequence. Use for arrange / sort / order / \
      prioritize / put in sequence. Provide the items via options (each option's label is one row).
    - hierarchicalList: drag-and-drop tree the user can nest. Use for organize into categories / \
      group / outline / hierarchy / mind map / parent-child. Provide the items via options.

    Input (when you need specific information):
    - text: short free-form text (names, phone numbers, brief answers).
    - textarea: longer text (explanations, lists, availability, details).
    - number: a specific numeric value with units.
    - countSelector: small whole-number counts 1-5+ (passengers, tickets, rooms, guests).
    - slider: a single value on a scale (ratings 1-10, satisfaction). NEVER for budgets or dates.
    - rangeSlider: a min-max range with two handles. Use for ALL budget/price questions. Set \
      validation.minValue / maxValue to a sensible range (flights 100-3000, groceries 50-500).
    - date: a single calendar date.
    - itemTable: a table with custom columns (MAX 3). Only for shopping lists, expense tracking, \
      or inventories. Each option defines one column (option.description: "currency" for € amounts, \
      "select:A,B,C" for a dropdown, omit for text). Never for research findings.

    Visual (ONLY physical/spatial things):
    - drawing: ONLY room layouts, floor plans, physical dimensions, diagrams. NEVER for schedules, \
      availability, lists, preferences, or anything non-physical.

    MATCH THE UI TO THE TASK:
    - "When do you need to…?" / "When is the trip?" / "When should we schedule?" -> date
    - "Choose travel dates" / "Departure date" / "Return date" / "date range" / any DATE question -> date
      (a date is NEVER a slider or rangeSlider, even when it says "range")
    - "Which mornings are you free?" / "What's your availability?" / "Preferred times?" -> textarea
    - "What's your budget?" / "Max budget?" / "How much do you want to spend?" -> rangeSlider
    - "Create a shopping list" / "List items to buy" / "Budget breakdown" -> itemTable (item + amount, 2 cols)
    - "Track purchases" -> itemTable (item + price + status, 3 cols max)
    - "How many passengers/tickets/rooms/guests?" -> countSelector
    - "How do you want to use the space?" -> multiSelect
    - "Arrange / sort / prioritize these" / "What's the order?" -> orderedList
    - "Organize into categories" / "Group these" / "Build an outline" / "mind map" -> hierarchicalList
    - "Preferred cabin class?" -> singleSelect with options
    - "Describe the room layout" -> drawing (physical space only)

    EXTERNAL ACTIONS use yesNo (and requiresExternalAction = true):
    Making a call, sending an email, adding to calendar, going somewhere, talking to someone, \
    waiting for a response, researching / looking up / comparing options online -> yesNo \
    confirmation ("Have you …?"). Do NOT ask the user to fill out tables for research findings.

    requiresExternalAction = true whenever the step needs real-world action outside the app; \
    false for pure in-app data entry (answering preferences, entering info they already know).

    SUBMIT LABEL: yesNo -> "Confirm"; entering info -> "Save"; selection -> "Continue"; final -> \
    "Complete". Never generic "Done".

    PREFILLING: use the user's EXACT words from previous responses. Never interpret, embellish, or \
    add items the user did not mention.

    No emojis. ONE field only.
    """
}
