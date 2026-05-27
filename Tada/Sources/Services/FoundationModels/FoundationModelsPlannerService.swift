import Foundation
import FoundationModels

/// On-device planner. Each method opens its own specialized `LanguageModelSession`
/// with a lean instruction set; output shape is guaranteed by the `@Generable`
/// return type, so the format rules that bloated the Claude prompts are gone.
/// Every call is recorded to `APILog` so it shows up in the Console.
struct FoundationModelsPlannerService: PlannerAIServiceProtocol {

    func generateDiscoveryQuestions(for task: String) async throws -> TaskPlan {
        let instructions = """
        You are a personal task coach. The user just shared a task they want to accomplish.

        Before making any plans, you need to UNDERSTAND what they actually mean. Generate 3-5 clarifying QUESTIONS that help you understand:
        - What specifically are they trying to accomplish?
        - What's the context? (who, what, when, where, why)
        - What constraints or preferences do they have?
        - KEY DETAILS needed for execution (names, dates, budget, locations, etc.)

        CRITICAL: These are QUESTIONS that gather information FROM the user — NOT a to-do list of steps.
        - GOOD (questions): "How many people are traveling?", "What's your budget for this trip?", "Where will you be travelling from?", "When do you need to depart?", "Do you already have accommodations booked?"
        - BAD (these are TASKS, never produce them here): "Book accommodations", "Research attractions", "Arrange transportation", "Create a budget". If tempted to write a task, rewrite it as the question that uncovers the missing info (e.g. "Book accommodations" -> "Do you already have accommodations booked?").

        TASK TITLE & DESCRIPTION (the top-level "title"/"description"):
        - "title" is the NAME OF THE USER'S TASK in their own terms (4-9 words) — NOT a label like "Clarifying Questions".
        - Example: "Untangle my German tax returns for 2020-2024" -> title: "Sort Out 2020-2024 German Tax Returns".
        - "description" summarises the task itself in one plain sentence.

        QUESTION GUIDELINES (each subTask "title" IS the question the user sees):
        - Each title is a COMPLETE question, concise and natural (around 5-10 words).
        - ONE QUESTION PER ITEM. NEVER combine with "and"/"or" — split into separate questions.
          BAD: "What are your departure city and travel dates?" -> split into two.

        Generate 1-7 focused questions based on how much context is needed. No emojis.
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
                generating: GenDiscoveryPlan.self,
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
        You are a personal task coach. Based on the user's answers to your clarifying questions, create a concrete ACTION PLAN.

        These are STEPS the user will DO — not questions. Each step is an action.

        IMPORTANT RULES:
        1. AIM FOR 3-7 STEPS. Prefer more atomic steps over fewer compound ones ("Purchase A" + "Purchase B", not "Purchase A and B").
        2. NEVER INVENT ITEMS. Only use items the user explicitly mentioned — no creative additions.
        3. USE WHAT YOU LEARNED IN DISCOVERY. If the user already told you details, USE them; don't ask them to "find" info they already gave.
        4. ONE STEP = ONE ACTION. Never bundle actions. If a step needs more than one input, SPLIT it. A title with "and" combining different activities is wrong.
        5. SEPARATE CAPTURE STEPS FOR DIFFERENT DATA. Date+time can be one step; location/address is its own step.
        6. SKIP OBVIOUS/AUTOMATIC THINGS (no "set a reminder"; no generic "gather documents" unless relevant).
        7. MARK EXTERNAL ACTIONS with requiresExternalAction=true: phone calls, emails, adding to calendar, going somewhere, talking to someone. In-app data entry (recording/noting details) is false.

        GOOD example (user already said "Dr. Smith, morning preferred"):
        - {"title": "Call Dr. Smith's office", "requiresExternalAction": true}
        - {"title": "Record appointment date and time", "requiresExternalAction": false}
        - {"title": "Record clinic address", "requiresExternalAction": false}
        - {"title": "Add to calendar", "requiresExternalAction": true}

        BAD — never do: "Assess furniture and plan layout" (split!), "Record date, time, and location" (location separate!), "Find your GP's number" (should've asked in discovery!), "Set a reminder".

        No emojis.
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
