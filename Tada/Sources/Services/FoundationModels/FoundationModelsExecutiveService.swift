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
                // The model's field type is authoritative: it reasons about the control
                // first (typeReasoning), then commits to a GenField case whose payload is
                // structurally consistent. No heuristic coercion — the chosen type is used.
                let content = response.content
                let schema = content.toDomain()
                await APILog.shared.complete(
                    id: callID,
                    output: "Type reasoning: \(content.typeReasoning)\n\n\(APILog.describe(schema))",
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

    // Lean instructions: the per-type selection guidance now lives on the schema's
    // `typeReasoning` guide (decoded before the field), so this only sets the framing.
    private static let instructions = """
    You design ONE input control for a single sub-task.

    Focus ONLY on the current sub-task. Previous responses are background — use them to
    pre-fill the user's own exact words where relevant, but NEVER let an earlier question's
    topic (like travel dates) become this field's label or type. The label must describe
    THIS sub-task.

    Reason about the best control first, then produce it (see the field guidance). Then fill
    its data:
    - text / textarea / number: add a short placeholder showing an example answer. For text
      and textarea, set defaultValue to the user's own exact prior words when one applies
      (prefill); otherwise leave it empty.
    - yesNo: provide two options — "Yes, I've done it" and "No, not yet".
    - singleSelect / multiSelect / orderedList: provide 3-6 thoughtful options.
    - itemTable: define 2-3 columns via options; a column's description is "currency" for
      money, "select:A,B,C" for a dropdown, or empty for text.
    - hierarchicalList: seed items with their nesting depth (0 top-level, 1 child).
    - slider / rangeSlider: set a sensible min and max.

    No emojis. Never invent items the user didn't mention.
    """
}
