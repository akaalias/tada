import Foundation
import FoundationModels

/// On-device executive. Generates ONE UI control per sub-task via guided generation.
/// The `GenActionSchema` type enforces "exactly one field" and a valid field type
/// structurally, so these instructions are kept lean: the high-value `MATCH THE UI
/// TO THE TASK` mapping plus the few population rules the type can't express.
/// `ExecutiveFieldHeuristics` is a deterministic backstop for the type mistakes the
/// on-device model still makes, so the prompt doesn't have to be exhaustive.
struct FoundationModelsExecutiveService: ExecutiveAIServiceProtocol {

    /// Cap on prior-response text injected into the prompt, to protect the
    /// 4,096-token context window (and prefill latency) on long tasks.
    private static let maxPreviousResponsesChars = 1200

    func generateActionUI(
        subTask: String,
        subTaskDescription: String,
        taskContext: String,
        previousResponses: [[String: String]],
        taskMemory: String,
        phase: TaskPhase
    ) async throws -> ActionSchema {
        var prompt = "Task: \(taskContext)\n\nSub-task to complete: \(subTask)"
        if !subTaskDescription.isEmpty { prompt += "\nDetails: \(subTaskDescription)" }
        let prev = ExecutiveAIService.formatPreviousResponses(previousResponses)
        if !prev.isEmpty { prompt += "\n\nPrevious responses in this task:\n\(prev.prefix(Self.maxPreviousResponsesChars))" }
        if !taskMemory.isEmpty { prompt += "\n\nUSER'S INSTRUCTIONS (follow strictly):\n\(taskMemory)" }
        prompt += "\n\nUse \"\(subTask)\" as the title — do not invent a different one."

        // Logged as one Console entry for the whole operation: completed with the
        // generated schema, or failed (with the fallback noted) if both attempts miss.
        let callID = await APILog.shared.begin(
            role: .executive,
            operation: "Action UI",
            instructions: Self.instructions,
            prompt: prompt,
            temperature: 0.4,
            outputType: "ActionSchema",
            phase: APIRequestPhase(phase),
            taskTitle: taskContext
        )
        let start = Date()

        // Guided generation intermittently fails to produce a decodable object on the
        // on-device model. Try twice (a fresh session each time, cooler on the retry),
        // then fall back to a deterministic schema so the user is never blocked.
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let session = LanguageModelSession { Self.instructions }
                let response = try await session.respond(
                    to: prompt,
                    generating: GenActionSchema.self,
                    options: GenerationOptions(temperature: attempt == 0 ? 0.4 : 0.2, maximumResponseTokens: 1024)
                )
                let schema = ExecutiveFieldHeuristics.corrected(response.content.toDomain())
                await APILog.shared.complete(
                    id: callID,
                    output: APILog.describe(schema),
                    durationMS: Int(Date().timeIntervalSince(start) * 1000)
                )
                return schema
            } catch {
                lastError = error
                continue
            }
        }
        await APILog.shared.fail(
            id: callID,
            error: "Guided generation failed twice; used deterministic fallback. \(lastError.map { String(describing: $0) } ?? "")",
            durationMS: Int(Date().timeIntervalSince(start) * 1000)
        )
        return Self.fallbackSchema(subTask: subTask)
    }

    /// Deterministic schema used when guided generation can't produce a valid object.
    /// Picks a sensible single field from the sub-task title so the step stays usable.
    private static func fallbackSchema(subTask: String) -> ActionSchema {
        let type = ExecutiveFieldHeuristics.fallbackType(title: subTask)
        let field = ActionField(
            id: "answer",
            type: type,
            label: subTask,
            required: true,
            validation: type == .rangeSlider ? FieldValidation(minValue: 0, maxValue: 1000) : nil
        )
        return ActionSchema(type: .form, title: subTask, fields: [field], submitLabel: "Continue")
    }

    private static let instructions = """
    You create ONE UI control for a single sub-task. Use the EXACT sub-task title given.

    MATCH THE UI TO THE TASK:
    - "When …?" / "Choose travel dates" / "Departure date" / any date or "date range" -> date \
      (a date is NEVER a slider, even when it says "range")
    - "What's your availability?" / "Preferred times?" / "Which mornings?" -> textarea
    - "What's your budget?" / "Max budget?" / "How much to spend?" -> rangeSlider
    - "Create a shopping list" / "List items to buy" / "Budget breakdown" -> itemTable (2 cols)
    - "Track purchases" -> itemTable (3 cols max)
    - "How many passengers/tickets/rooms/guests?" -> countSelector
    - "Rate / score …" (1-10, satisfaction) -> slider
    - "How do you want to use the space?" -> multiSelect
    - "Arrange / sort / prioritize / what's the order?" -> orderedList
    - "Organize into categories / group / outline / mind map" -> hierarchicalList
    - "Preferred cabin class?" and other pick-one questions -> singleSelect
    - "Describe the room layout" (physical space only) -> drawing
    - Make a call / send email / add to calendar / go somewhere / research / compare online \
      -> yesNo confirmation ("Have you …?")

    FIELD RULES:
    - yesNo: ALWAYS two options, e.g. {id:"yes", label:"Yes, I've done it"} / {id:"no", label:"No, not yet"}.
    - rangeSlider: set validation.minValue / maxValue to a sensible range (flights 100-3000, groceries 50-500).
    - slider: NEVER for budgets or dates.
    - itemTable: each option defines one column (option.description "currency" for €, "select:A,B,C" for a dropdown).
    - orderedList / hierarchicalList: provide the items to arrange via options.
    - singleSelect / multiSelect: provide 3-6 thoughtful options.

    requiresExternalAction = true for any real-world action outside the app (calls, emails, \
    calendar, travel, talking to someone, researching/comparing online); false for pure in-app entry.

    Use the user's EXACT words from previous responses — never interpret, embellish, or add items \
    they didn't mention. Submit label: yesNo -> "Confirm"; entering info -> "Save"; selection -> \
    "Continue"; final -> "Complete". No emojis. ONE field only.
    """
}
