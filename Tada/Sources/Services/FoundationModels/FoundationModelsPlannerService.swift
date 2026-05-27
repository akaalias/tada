import Foundation
import FoundationModels

/// On-device planner. Each method opens its own specialized `LanguageModelSession`
/// with a lean instruction set; output shape is guaranteed by the `@Generable`
/// return type, so the format rules that bloated the Claude prompts are gone.
/// Every call is recorded to `APILog` so it shows up in the Console.
struct FoundationModelsPlannerService: PlannerAIServiceProtocol {

    func generateDiscoveryQuestions(for task: String) async throws -> TaskPlan {
        let instructions = """
            You are a task coach. The user shares a task; generate 1-7 clarifying questions \
            to understand it before planning. Each question asks exactly ONE thing — never \
            combine with "and" or "or". The plan title names the USER'S task in their own \
            terms, never a generic label like "Clarifying Questions". No emojis.
            """
        let session = LanguageModelSession { instructions }
        let prompt = "Task the user entered: \"\(task)\""
        let temperature = 0.6

        return try await APILog.shared.record(
            role: .planner,
            operation: "Discovery questions",
            instructions: instructions,
            prompt: prompt,
            temperature: temperature,
            outputType: "TaskPlan",
            phase: .discovery,
            taskTitle: task
        ) {
            let plan = try await session.respond(
                to: prompt,
                generating: GenTaskPlan.self,
                options: GenerationOptions(temperature: temperature)
            ).content.toDomain()
            return (plan, APILog.describe(plan))
        }
    }

    func createExecutionPlan(
        originalTask: String,
        discoveryAnswers: [CompletedSubTaskInfo]
    ) async throws -> TaskPlan {
        let answers = discoveryAnswers
            .map { "Q: \($0.title)\nA: \($0.response)" }
            .joined(separator: "\n\n")
        let learnings = PlanningMemoryService.shared.getLearningsForPrompt()

        let instructions = """
            You are a task coach. Turn what was learned into a concrete action plan of 3-7 \
            atomic steps. ONE step = ONE action; never bundle actions with "and". Use the \
            EXACT item names the user gave; never invent items. Set requiresExternalAction \
            for steps needing real-world action (calls, emails, calendar, travel, talking to \
            someone). Skip automatic things like setting reminders. No emojis.
            """
        let session = LanguageModelSession { instructions }
        var prompt = "Original task: \"\(originalTask)\"\n\nWhat we learned from the user:\n\(answers)"
        if !learnings.isEmpty { prompt += "\n\n\(learnings)" }
        prompt += "\n\nNow create the action plan."
        let temperature = 0.4

        return try await APILog.shared.record(
            role: .planner,
            operation: "Execution plan",
            instructions: instructions,
            prompt: prompt,
            temperature: temperature,
            outputType: "TaskPlan",
            phase: .execution,
            taskTitle: originalTask
        ) {
            let plan = try await session.respond(
                to: prompt,
                generating: GenTaskPlan.self,
                options: GenerationOptions(temperature: temperature)
            ).content.toDomain()
            return (plan, APILog.describe(plan))
        }
    }

    func revisePlan(
        originalTask: String,
        completedSubTasks: [CompletedSubTaskInfo],
        remainingSubTasks: [String]
    ) async throws -> PlanRevision {
        let done = completedSubTasks.map { "- \($0.title): \($0.response)" }.joined(separator: "\n")
        let remaining = remainingSubTasks.map { "- \($0)" }.joined(separator: "\n")

        let instructions = """
            You evaluate whether a task plan needs revising. Revise (revised=true) when any \
            remaining step bundles multiple actions (contains "and") or is generic when the \
            user gave specific items — then return atomic, concrete replacement steps using \
            the user's exact item names. Otherwise revised=false with no steps. No emojis.
            """
        let session = LanguageModelSession { instructions }
        let prompt = """
        Original goal: \(originalTask)

        What the user told us:
        \(done)

        Remaining steps:
        \(remaining)

        Should we continue as-is or revise?
        """
        let temperature = 0.3

        return try await APILog.shared.record(
            role: .planner,
            operation: "Revise plan",
            instructions: instructions,
            prompt: prompt,
            temperature: temperature,
            outputType: "PlanRevision",
            phase: .execution,
            taskTitle: originalTask
        ) {
            let revision = try await session.respond(
                to: prompt,
                generating: GenPlanRevision.self,
                options: GenerationOptions(temperature: temperature)
            ).content.toDomain()
            return (revision, APILog.describe(revision))
        }
    }

    func breakDownStep(
        stepTitle: String,
        stepDescription: String,
        taskContext: String,
        discoveryContext: String,
        executionProgress: String
    ) async throws -> [SubTaskPlan] {
        let instructions = """
            The user is overwhelmed by a step. Break it into 2-5 smaller steps, each a single \
            action. Use the EXACT item names from the user's data; never use generic categories \
            when specific names exist, and never add items the user didn't mention. Split any \
            "and" compounds. Set requiresExternalAction for real-world actions. No emojis.
            """
        let session = LanguageModelSession { instructions }
        let prompt = """
        Overwhelming step: "\(stepTitle)"
        \(stepDescription.isEmpty ? "" : "Description: \(stepDescription)\n")
        Goal: \(taskContext)

        Discovery answers:
        \(discoveryContext)

        Execution progress:
        \(executionProgress)
        """
        let temperature = 0.4

        return try await APILog.shared.record(
            role: .planner,
            operation: "Break down step",
            instructions: instructions,
            prompt: prompt,
            temperature: temperature,
            outputType: "SubTaskPlan",
            phase: .execution,
            taskTitle: taskContext
        ) {
            let steps = try await session.respond(
                to: prompt,
                generating: GenMicroSteps.self,
                options: GenerationOptions(temperature: temperature)
            ).content.toDomain()
            return (steps, APILog.describe(steps))
        }
    }

    func generateLearning(
        badStepTitle: String,
        taskContext: String,
        discoveryContext: String,
        executionProgress: String
    ) async throws -> String {
        let instructions = "You extract one concise, actionable lesson (max 15 words) from a planning mistake. Return only the lesson text. No emojis."
        let session = LanguageModelSession { instructions }
        let prompt = """
        A user marked this step as "doesn't make sense": "\(badStepTitle)"

        Task: \(taskContext)
        Discovery answers: \(discoveryContext)
        Execution progress: \(executionProgress)

        Give one lesson capturing the pattern to avoid in future plans.
        """
        let temperature = 0.3

        return try await APILog.shared.record(
            role: .planner,
            operation: "Planning learning",
            instructions: instructions,
            prompt: prompt,
            temperature: temperature,
            phase: .execution,
            taskTitle: taskContext
        ) {
            let lesson = try await session.respond(
                to: prompt,
                options: GenerationOptions(temperature: temperature)
            ).content.trimmingCharacters(in: .whitespacesAndNewlines)
            return (lesson, lesson)
        }
    }
}
