import Foundation
import FoundationModels

/// On-device executive. Generates ONE UI control per sub-task via guided generation.
/// The `GenActionSchema` type enforces "exactly one field" and a valid field type
/// structurally, so the instruction set only needs the matching heuristics.
struct FoundationModelsExecutiveService: ExecutiveAIServiceProtocol {

    func generateActionUI(
        subTask: String,
        subTaskDescription: String,
        taskContext: String,
        previousResponses: [[String: String]],
        taskMemory: String,
        phase: TaskPhase
    ) async throws -> ActionSchema {
        let session = LanguageModelSession {
            """
            You design ONE UI control for a single sub-task. Pick the single best field type:
            - budget/price/"how much" -> rangeSlider
            - a question starting with "When" -> date
            - small counts (passengers, tickets, rooms, guests) -> countSelector
            - pick one option -> singleSelect; pick several -> multiSelect
            - rating/score -> slider
            - arrange/sort/prioritize -> orderedList; group/nest/outline -> hierarchicalList
            - shopping/expense list -> itemTable (2-3 columns)
            - physical room/layout -> drawing
            - external action (call, email, buy, add to calendar, research, compare) -> yesNo \
              confirmation with two options ("Yes, I…" / "No, not yet"), and requiresExternalAction = true
            Use the EXACT sub-task title as the title. Copy the user's exact words; never invent \
            items. No emojis.
            """
        }

        var prompt = "Task: \(taskContext)\n\nSub-task to complete: \(subTask)"
        if !subTaskDescription.isEmpty { prompt += "\nDetails: \(subTaskDescription)" }
        let prev = ExecutiveAIService.formatPreviousResponses(previousResponses)
        if !prev.isEmpty { prompt += "\n\nPrevious responses in this task:\n\(prev)" }
        if !taskMemory.isEmpty { prompt += "\n\nUSER'S INSTRUCTIONS (follow strictly):\n\(taskMemory)" }
        prompt += "\n\nUse \"\(subTask)\" as the title — do not invent a different one."

        let response = try await session.respond(
            to: prompt,
            generating: GenActionSchema.self,
            options: GenerationOptions(temperature: 0.5)
        )
        return response.content.toDomain()
    }
}
