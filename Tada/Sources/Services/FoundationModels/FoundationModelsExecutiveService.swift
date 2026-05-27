import Foundation
import FoundationModels

/// On-device executive. Generates ONE UI control per sub-task via guided generation.
/// `GenField` is a `@Generable` enum whose options only exist on selection cases, so
/// the model's chosen type is always consistent with its payload and is used verbatim
/// (no heuristic coercion). These instructions stay lean — concise per-type selection
/// guidance — because the enum already enforces structure and the full catalog would
/// blow the 4,096-token context window. `ExecutiveFieldHeuristics` is used only for the
/// deterministic fallback when generation fails entirely.
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
                // The model's field type is authoritative: GenField is an enum with
                // associated values, so options only exist on selection cases. No
                // heuristic coercion — the type the model chose is the type used.
                let schema = response.content.toDomain()
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

    // Lean selection guidance. The GenField enum already enforces valid structure (and
    // makes options-on-text impossible), so this only needs to help the model choose the
    // right case — not enumerate field shapes. Kept small to stay well under 4,096 tokens.
    private static let instructions = """
    You design ONE input control for a single sub-task. Use the EXACT sub-task title given.

    Choose the single best control:
    - date — any date / "when" / travel dates / departure / deadline (a date is NEVER a slider).
    - rangeSlider — ALL budget / price / "how much" questions. Set a sensible min-max (flights 100-3000, groceries 50-500).
    - slider — a rating or score on a scale (NOT budgets).
    - countSelector — a small whole-number count (passengers, tickets, rooms, guests).
    - singleSelect — pick ONE from choices you can enumerate. multiSelect — pick several.
      Whenever you can list options (even numeric, like "1 day / 2 days / 7 days"), use one of these.
    - orderedList — arrange / sort / prioritize a set of items.
    - hierarchicalList — group / nest / outline / mind-map a set of items.
    - itemTable — a shopping or expense list (each option defines one column; max 3 columns).
    - textarea — open-ended longer text (availability, preferences, notes). text — short answers (names, numbers).
    - drawing — a physical room layout only.
    - yesNo — confirm an EXTERNAL action (make a call, send an email, add to calendar, go somewhere,
      research or compare options online). Provide two options: "Yes, I've done it" and "No, not yet".

    requiresExternalAction = true for real-world actions outside the app (calls, emails, calendar,
    travel, talking to someone, researching/comparing online); false for in-app data entry.

    Submit label: yesNo -> "Confirm"; entering info -> "Save"; selection -> "Continue"; final -> "Complete".
    Use the user's EXACT words from previous responses; never invent items they didn't mention. No emojis.
    """
}
