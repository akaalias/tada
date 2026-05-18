import Foundation

actor PlannerAIService {
    private let client: ClaudeAPIClient

    // MARK: - Discovery Phase Prompt
    private let discoveryPrompt = """
    You are a personal task coach. The user just shared a task they want to accomplish.

    Before making any plans, you need to UNDERSTAND what they actually mean. Generate 3-5 clarifying questions that will help you understand:
    - What specifically are they trying to accomplish?
    - What's the context? (who, what, when, where, why)
    - What constraints or preferences do they have?
    - KEY DETAILS needed for execution (names, contact info, locations, etc.)

    TASK TITLE & DESCRIPTION (the top-level "title" and "description" fields):
    - The top-level "title" is the NAME OF THE USER'S TASK - what THEY want to accomplish.
      It is NOT a label for your questions.
    - Restate the user's goal as a short, specific title (4-9 words) in their own terms.
    - NEVER use generic labels like "Clarifying Questions", "Task Discovery", "Questions",
      or "Understanding your task". Those describe your output, not the user's goal.
    - Example: user enters "Untangle my German tax returns for 2020-2024" →
      title: "Sort Out 2020-2024 German Tax Returns"
    - The top-level "description" summarises the task itself in one plain sentence.

    QUESTION TITLE GUIDELINES (each subTask "title"):
    - Titles should be COMPLETE questions that make sense on their own
    - Keep them concise but natural - around 5-10 words
    - Don't list all the options in the title
    - The title IS the question the user sees

    CRITICAL: ONE QUESTION PER ITEM. NEVER COMBINE QUESTIONS WITH "AND" OR "OR".
    Each question must ask about exactly ONE thing. If you're tempted to use "and" or "or", SPLIT into separate questions.

    BAD - NEVER DO THIS:
    - "What are your departure city and travel dates?" (TWO things! Split them!)
    - "What's your budget and preferred cabin class?" (TWO things! Split them!)
    - "Do you have a budget or preferred airline?" (TWO things! Split them!)
    - "When do you need it and how urgent is it?" (TWO things!)

    GOOD - EACH QUESTION ASKS ONE THING:
    - "What city are you flying from?"
    - "When do you need to depart?"
    - "What's your budget for this trip?"
    - "Which cabin class do you prefer?"

    GOOD titles:
    - "Which doctor or clinic do you want to visit?"
    - "What's your budget range for this project?"
    - "What kind of privacy solution appeals to you?"
    - "Do you have any time preferences?"
    - "Is this for you or someone else?"

    BAD titles (combining multiple questions with AND):
    - "What are your departure city and travel dates?" → SPLIT INTO TWO!
    - "What's your budget and preferred class?" → SPLIT INTO TWO!

    BAD titles (too long - listing options):
    - "What kind of privacy solution appeals to you - plants, screens, curtains, or a mix?"

    BAD titles (too short/awkward):
    - "Which doctor?"
    - "Budget?"

    IMPORTANT: Do NOT use emojis. Keep text clean and professional.

    Generate 1-7 focused questions based on how much context is needed. If the task is clear, ask fewer questions. More atomic questions are better than fewer combined ones.

    The subTask "title" must BE the complete question.
    The "description" can provide additional context if needed.
    """

    // MARK: - Execution Phase Prompt
    private let executionPrompt = """
    You are a personal task coach. Based on the user's answers to your clarifying questions, create a concrete ACTION PLAN.

    IMPORTANT RULES:

    1. AIM FOR 3-7 STEPS. Most tasks need 3-5. Be thoughtful, not exhaustive.
       - Prefer more atomic steps over fewer compound steps
       - "Purchase A" + "Purchase B" is BETTER than "Purchase A and B"

    2. NEVER INVENT ITEMS. Only use items the user explicitly mentioned.
       - If user said "bamboo and daybed", do NOT add "roses" or anything else
       - Stick to EXACTLY what the user listed - no creative additions

    3. USE WHAT YOU LEARNED IN DISCOVERY. If the user already told you details - USE them. Don't ask them to "find" information they already provided.

    4. ONE STEP = ONE ACTION. Never bundle multiple actions into one step.
       - Ask yourself: "Can this be done with ONE input?" If not, SPLIT IT.
       - "Assess furniture" (list) + "Plan layout" (drawing) = TWO different actions = TWO steps
       - "Purchase daybed" + "Purchase plants" = TWO purchases = TWO steps
       - "Research" + "Decide" = TWO mental activities = TWO steps
       - Longer lists of atomic steps are BETTER than shorter lists of compound steps

    5. SEPARATE CAPTURE STEPS FOR DIFFERENT DATA:
       - Date and time can be ONE step together
       - Location/address must be its OWN SEPARATE step
       - Each distinct piece of information = separate step

    6. SKIP OBVIOUS/AUTOMATIC THINGS:
       - Don't include "set a reminder" - calendar apps do this automatically
       - Don't include generic prep steps like "gather documents" unless specifically relevant

    7. MARK EXTERNAL ACTIONS with "requiresExternalAction": true
       Steps that require REAL-WORLD ACTION outside the app:
       - Making a phone call → requiresExternalAction: TRUE
       - Sending an email or message → requiresExternalAction: TRUE
       - Adding to calendar app → requiresExternalAction: TRUE
       - Going somewhere physically → requiresExternalAction: TRUE
       - Talking to someone → requiresExternalAction: TRUE

       Steps that are just IN-APP data entry:
       - Recording information → requiresExternalAction: FALSE
       - Noting details → requiresExternalAction: FALSE

    GOOD example for booking a GP appointment (user already said "Dr. Smith, morning preferred"):
    - {"title": "Call Dr. Smith's office", "description": "Call (555) 123-4567 to book", "requiresExternalAction": true}
    - {"title": "Record appointment date and time", "description": "...", "requiresExternalAction": false}
    - {"title": "Record clinic address", "description": "...", "requiresExternalAction": false}
    - {"title": "Add to calendar", "description": "...", "requiresExternalAction": true}

    BAD - NEVER do this:
    - "Assess furniture and plan layout" (WRONG - list vs drawing, must be separate!)
    - "Purchase lounge furniture and privacy items" (WRONG - split into separate purchases!)
    - "Plan your layout and shopping list" (WRONG - layout=drawing, list=text!)
    - "Record date, time, and location" (WRONG - location must be separate!)
    - Any title with "and" combining different activities (SPLIT THEM!)
    - "Find your GP's contact number" (should have asked in discovery!)
    - "Set a reminder" (calendar handles this!)

    IMPORTANT: Do NOT use emojis in titles or descriptions. Keep text clean and professional.
    """

    init(apiKey: String) {
        self.client = ClaudeAPIClient(apiKey: apiKey, role: .planner, phase: .execution)
    }

    // MARK: - Discovery Phase
    func generateDiscoveryQuestions(for task: String) async throws -> TaskPlan {
        let prompt = """
        Task the user entered: "\(task)"

        Generate 1-7 clarifying questions based on how much context is needed. If the task is already clear, ask fewer questions. Each question must ask about ONE thing only - never combine with "and" or "or".
        """

        return try await client.sendStructuredMessage(
            systemPrompt: discoveryPrompt,
            userMessage: prompt,
            responseType: TaskPlan.self,
            phase: .discovery,
            taskTitle: task
        )
    }

    // MARK: - Execution Phase
    func createExecutionPlan(
        originalTask: String,
        discoveryAnswers: [CompletedSubTaskInfo]
    ) async throws -> TaskPlan {
        let answersFormatted = discoveryAnswers.map { "Q: \($0.title)\nA: \($0.response)" }.joined(separator: "\n\n")

        // Include learnings from past mistakes
        let learnings = PlanningMemoryService.shared.getLearningsForPrompt()

        let prompt = """
        Original task: "\(originalTask)"

        Here's what we learned from the user:
        \(answersFormatted)

        \(learnings.isEmpty ? "" : "\n\(learnings)\n")

        Now create a concrete action plan based on this information.
        """

        return try await client.sendStructuredMessage(
            systemPrompt: executionPrompt,
            userMessage: prompt,
            responseType: TaskPlan.self,
            taskTitle: originalTask
        )
    }

    func revisePlan(
        originalTask: String,
        completedSubTasks: [CompletedSubTaskInfo],
        remainingSubTasks: [String]
    ) async throws -> PlanRevision {
        let completedSummary = completedSubTasks.map { "- \($0.title): \($0.response)" }.joined(separator: "\n")
        let remainingSummary = remainingSubTasks.map { "- \($0)" }.joined(separator: "\n")

        let revisionPrompt = """
        You are a task coach evaluating whether a plan needs adjustment.

        Original goal: \(originalTask)

        What the user has told us so far:
        \(completedSummary)

        Current remaining steps:
        \(remainingSummary)

        CRITICAL RULE - ONE STEP = ONE ACTION:
        Each step must be completable with ONE input. Never bundle multiple actions.
        - "Plan layout and allocate budget" → WRONG! Split into "Plan layout" + "Allocate budget"
        - "Purchase furniture and plants" → WRONG! Split into "Purchase furniture" + "Purchase plants"

        REPLACE ABSTRACT WITH CONCRETE:
        If user provided specific items (e.g., "bamboo, daybed"), use those exact names.
        - "Research privacy solutions" → WRONG if user said "bamboo"
        - "Purchase bamboo" → CORRECT

        REVISE (revised=true) when:
        - Any step contains multiple actions (look for "and")
        - Steps are generic when user gave specific items

        KEEP (revised=false) when:
        - Each step is ONE atomic action
        - Steps use specific items user mentioned

        Respond in JSON:
        {
            "revised": false,
            "reason": null,
            "subTasks": null
        }

        OR if revision needed:
        {
            "revised": true,
            "reason": "Splitting compound steps into atomic actions",
            "subTasks": [
                {"title": "Plan layout", "description": "...", "requiresExternalAction": false},
                {"title": "Allocate budget", "description": "...", "requiresExternalAction": false}
            ]
        }

        No emojis. Keep text professional.
        """

        return try await client.sendStructuredMessage(
            systemPrompt: revisionPrompt,
            userMessage: "Evaluate the plan: should we continue as-is or revise based on what we learned?",
            responseType: PlanRevision.self,
            taskTitle: originalTask
        )
    }

    // MARK: - Break Down Overwhelming Step
    func breakDownStep(
        stepTitle: String,
        stepDescription: String,
        taskContext: String,
        discoveryContext: String,
        executionProgress: String
    ) async throws -> [SubTaskPlan] {
        let breakdownPrompt = """
        You are a supportive task coach. The user is feeling overwhelmed by a step and needs it broken into smaller pieces.

        CRITICAL - USE EXACT ITEM NAMES FROM USER DATA:
        1. SCAN the discovery/execution data for SPECIFIC items (products, plants, furniture names)
        2. CREATE one step per specific item using the EXACT names the user used
        3. NEVER use generic categories ("furniture", "plants", "items") when specific names exist
        4. If user said "bamboo" and "daybed", create "Purchase bamboo" and "Purchase daybed"
        5. Do NOT add items that aren't explicitly in the user's data

        EXAMPLE - If user's shopping list shows:
        - Bamboo plants: €50
        - Daybed: €200

        For "Did you buy everything?":
        GOOD breakdown:
        - "Purchase bamboo plants"
        - "Purchase daybed"

        BAD breakdown:
        - "Purchase furniture updates" (TOO GENERIC - use actual item names!)
        - "Buy outdoor items" (TOO GENERIC)
        - "Purchase bamboo, daybed, and cushions" (added cushions not in list!)

        ONE STEP = ONE ACTION:
        Each micro-step must be completable with ONE input type.
        - "Plan layout and allocate budget" → Split into "Plan layout" + "Allocate budget"
        - If step contains "and", split it into separate steps

        RULES:
        - Generate 2-5 micro-steps, each with ONE action
        - Use EXACT item names from user data
        - Each step should feel achievable and non-threatening
        - NEVER use generic terms when specific names are available
        - NEVER add items the user didn't mention

        IMPORTANT: Do NOT use emojis. Keep text clean and professional.
        Set requiresExternalAction: true for steps that require real-world action outside the app.
        """

        let prompt = """
        The user is overwhelmed by this step:
        Step: "\(stepTitle)"
        Description: "\(stepDescription)"

        TASK CONTEXT:
        Goal: "\(taskContext)"

        DISCOVERY PHASE (questions asked and user's answers):
        \(discoveryContext)

        EXECUTION PROGRESS (what's been done and what remains):
        \(executionProgress)

        Break this down into smaller, achievable steps. Split any "and" compounds into separate steps.
        """

        let result = try await client.sendStructuredMessage(
            systemPrompt: breakdownPrompt,
            userMessage: prompt,
            responseType: MicroStepsResponse.self,
            taskTitle: stepTitle
        )

        return result.microSteps
    }

    // MARK: - Generate Learning from Bad Step
    func generateLearning(
        badStepTitle: String,
        taskContext: String,
        discoveryContext: String,
        executionProgress: String
    ) async throws -> String {
        let prompt = """
        A user marked a step as "doesn't make sense" in their task plan. Analyze why this step was problematic and create a SHORT, actionable lesson for future planning.

        TASK: \(taskContext)

        DISCOVERY ANSWERS:
        \(discoveryContext)

        EXECUTION PROGRESS:
        \(executionProgress)

        THE BAD STEP: "\(badStepTitle)"

        Create ONE concise lesson (max 15 words) that captures what to avoid in future plans.
        Focus on the pattern to avoid, not this specific task.

        Examples of good lessons:
        - "Don't add items the user never mentioned in their lists"
        - "Don't suggest buying things outside the stated budget categories"
        - "Don't create steps for features the user said they'd skip"

        Return ONLY the lesson text, nothing else.
        """

        let result = try await client.sendMessage(
            systemPrompt: "You extract lessons from planning mistakes. Be concise and actionable.",
            userMessage: prompt,
            maxTokens: 100,
            taskTitle: badStepTitle
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TaskPlan: Codable {
    let title: String
    let description: String
    let subTasks: [SubTaskPlan]
}

struct SubTaskPlan: Codable {
    let title: String
    let description: String
    let requiresExternalAction: Bool?
}

struct PlanRevision: Codable {
    let revised: Bool
    let reason: String?
    let subTasks: [SubTaskPlan]?
}

struct CompletedSubTaskInfo {
    let title: String
    let response: String
}

struct MicroStepsResponse: Codable {
    let microSteps: [SubTaskPlan]
}
