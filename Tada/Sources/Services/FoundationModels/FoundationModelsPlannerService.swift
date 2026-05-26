import Foundation
import FoundationModels

/// On-device planner. Each method opens its own specialized `LanguageModelSession`
/// with a lean instruction set; output shape is guaranteed by the `@Generable`
/// return type, so the format rules that bloated the Claude prompts are gone.
struct FoundationModelsPlannerService: PlannerAIServiceProtocol {

    func generateDiscoveryQuestions(for task: String) async throws -> TaskPlan {
        let session = LanguageModelSession {
            """
            You are a task coach. The user shares a task; generate 1-7 clarifying questions \
            to understand it before planning. Each question asks exactly ONE thing — never \
            combine with "and" or "or". The plan title names the USER'S task in their own \
            terms, never a generic label like "Clarifying Questions". No emojis.
            """
        }
        let response = try await session.respond(
            to: "Task the user entered: \"\(task)\"",
            generating: GenTaskPlan.self,
            options: GenerationOptions(temperature: 0.6)
        )
        return response.content.toDomain()
    }

    func createExecutionPlan(
        originalTask: String,
        discoveryAnswers: [CompletedSubTaskInfo]
    ) async throws -> TaskPlan {
        let answers = discoveryAnswers
            .map { "Q: \($0.title)\nA: \($0.response)" }
            .joined(separator: "\n\n")
        let learnings = PlanningMemoryService.shared.getLearningsForPrompt()

        let session = LanguageModelSession {
            """
            You are a task coach. Turn what was learned into a concrete action plan of 3-7 \
            atomic steps. ONE step = ONE action; never bundle actions with "and". Use the \
            EXACT item names the user gave; never invent items. Set requiresExternalAction \
            for steps needing real-world action (calls, emails, calendar, travel, talking to \
            someone). Skip automatic things like setting reminders. No emojis.
            """
        }
        var prompt = "Original task: \"\(originalTask)\"\n\nWhat we learned from the user:\n\(answers)"
        if !learnings.isEmpty { prompt += "\n\n\(learnings)" }
        prompt += "\n\nNow create the action plan."

        let response = try await session.respond(
            to: prompt,
            generating: GenTaskPlan.self,
            options: GenerationOptions(temperature: 0.4)
        )
        return response.content.toDomain()
    }

    func revisePlan(
        originalTask: String,
        completedSubTasks: [CompletedSubTaskInfo],
        remainingSubTasks: [String]
    ) async throws -> PlanRevision {
        let done = completedSubTasks.map { "- \($0.title): \($0.response)" }.joined(separator: "\n")
        let remaining = remainingSubTasks.map { "- \($0)" }.joined(separator: "\n")

        let session = LanguageModelSession {
            """
            You evaluate whether a task plan needs revising. Revise (revised=true) when any \
            remaining step bundles multiple actions (contains "and") or is generic when the \
            user gave specific items — then return atomic, concrete replacement steps using \
            the user's exact item names. Otherwise revised=false with no steps. No emojis.
            """
        }
        let prompt = """
        Original goal: \(originalTask)

        What the user told us:
        \(done)

        Remaining steps:
        \(remaining)

        Should we continue as-is or revise?
        """
        let response = try await session.respond(
            to: prompt,
            generating: GenPlanRevision.self,
            options: GenerationOptions(temperature: 0.3)
        )
        return response.content.toDomain()
    }

    func breakDownStep(
        stepTitle: String,
        stepDescription: String,
        taskContext: String,
        discoveryContext: String,
        executionProgress: String
    ) async throws -> [SubTaskPlan] {
        let session = LanguageModelSession {
            """
            The user is overwhelmed by a step. Break it into 2-5 smaller steps, each a single \
            action. Use the EXACT item names from the user's data; never use generic categories \
            when specific names exist, and never add items the user didn't mention. Split any \
            "and" compounds. Set requiresExternalAction for real-world actions. No emojis.
            """
        }
        let prompt = """
        Overwhelming step: "\(stepTitle)"
        \(stepDescription.isEmpty ? "" : "Description: \(stepDescription)\n")
        Goal: \(taskContext)

        Discovery answers:
        \(discoveryContext)

        Execution progress:
        \(executionProgress)
        """
        let response = try await session.respond(
            to: prompt,
            generating: GenMicroSteps.self,
            options: GenerationOptions(temperature: 0.4)
        )
        return response.content.toDomain()
    }

    func generateLearning(
        badStepTitle: String,
        taskContext: String,
        discoveryContext: String,
        executionProgress: String
    ) async throws -> String {
        let session = LanguageModelSession {
            "You extract one concise, actionable lesson (max 15 words) from a planning mistake. Return only the lesson text. No emojis."
        }
        let prompt = """
        A user marked this step as "doesn't make sense": "\(badStepTitle)"

        Task: \(taskContext)
        Discovery answers: \(discoveryContext)
        Execution progress: \(executionProgress)

        Give one lesson capturing the pattern to avoid in future plans.
        """
        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(temperature: 0.3)
        )
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
