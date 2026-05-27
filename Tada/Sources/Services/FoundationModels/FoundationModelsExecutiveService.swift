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

    // DIAGNOSTIC: the original (Claude-era) mapping prompt restored in full — the field-type
    // catalog, the complete MATCH THE UI TO THE TASK table, and all external-action rules —
    // to isolate whether the weak field-type choices come from prompt trimming or from the
    // on-device model's lower capability. Only the original's literal JSON output example is
    // omitted: it shows a `fields` array / `placeholder` the @Generable shape doesn't use
    // (guided generation enforces the real shape) and is irrelevant to type selection.
    private static let instructions = """
    You create ONE creative, appropriate UI for a single sub-task.

    CRITICAL: Use the EXACT sub-task title provided - do NOT invent a different title.

    CRITICAL: Generate exactly ONE field. Pick the BEST type for this specific task.

    CRITICAL: If you provide an "options" list, the field "type" MUST be a selection type - singleSelect (choose one) or multiSelect (choose several). NEVER pair options with text, textarea, number, slider, rangeSlider, date, or countSelector - those ignore options and show an empty or bare input box. Whenever you enumerate choices (even numeric ones like "1 day / 2 days / 7 days"), use singleSelect.

    Available field types:

    SELECTION (when you can enumerate the options):
    - singleSelect: Pick ONE from a list (mutually exclusive choices)
    - multiSelect: Pick MULTIPLE from a list
    - yesNo: Simple yes/no toggle or confirmation
    - orderedList: Drag-and-drop list to put items in a sequence. USE THIS FOR ANY "arrange / sort / order / prioritize / put in sequence" prompt. Provide the items to reorder via the options array (each option's label is one item). The user reorders them by dragging.
    - hierarchicalList: Drag-and-drop tree where users can also nest items as children. USE THIS FOR "organize into categories / group / outline / build a hierarchy / mind map / nested structure / parent and child" prompts. Seed it via prefillRows where each row has {"item": "Label", "depth": "0"} (0 = root, 1 = child, 2 = grandchild). If only flat items are known, use options instead and the user will nest them manually.

    INPUT (when you need specific information):
    - text: Short free-form text (names, phone numbers, brief answers)
    - textarea: Longer text (explanations, lists, availability, details)
    - number: Specific numeric value with units
    - countSelector: Small counts 1-5+ (passengers, tickets, rooms, guests) - shows clickable buttons
    - slider: Choose a single value (ratings 1-10, satisfaction scores) - NOT for budgets!
    - rangeSlider: Choose a min-max range with two handles - USE THIS FOR ALL BUDGET/PRICE QUESTIONS
    - date: A specific date
    - itemTable: Table with custom columns. MAXIMUM 3 COLUMNS.
      * ONLY for shopping lists, expense tracking, or inventories the user will actually fill out
      * Each option = one column (id, label, description for type)
      * description: "currency" for € amounts, "select:A,B,C" for dropdown, or omit for text
      * ONLY use 2-3 columns: item + one or two data columns (price, category, etc.)
      * Example: options: [{id: "item", label: "Item"}, {id: "price", label: "Price", description: "currency"}]
      * NEVER create tables with more than 3 columns - they don't fit on screen
      * NEVER use tables for research findings or analysis - that's busywork!

    VISUAL (ONLY for physical/spatial things):
    - drawing: ONLY for room layouts, floor plans, physical dimensions, diagrams
      DO NOT use for: schedules, availability, lists, preferences, or anything non-physical

    MATCH THE UI TO THE TASK:
    - "When do you need to...?" → date (this is asking for a DATE, use calendar!)
    - "When is the trip?" → date
    - "When should we schedule?" → date
    - "Which mornings are you free?" → textarea (let them type "Monday and Wednesday mornings")
    - "What's your availability?" → textarea (NOT drawing!)
    - "Preferred times?" → textarea or text
    - "What's your budget?" → rangeSlider (let user set min-max range)
    - "Budget and preferences?" → rangeSlider (focus on the budget range)
    - "What is your budget and preferred X?" → rangeSlider (the budget is the key input)
    - "Max budget for flights?" → rangeSlider
    - "How much do you want to spend?" → rangeSlider
    - "Create a shopping list" → itemTable with item + price (2 columns max)
    - "List items to buy" → itemTable with item + cost (2 columns)
    - "Budget breakdown" → itemTable with item + amount (2 columns)
    - "Track purchases" → itemTable with item + price + status (3 columns max)
    - "How many passengers?" → countSelector (small counts use buttons, not sliders!)
    - "How many tickets?" → countSelector
    - "How many rooms?" → countSelector
    - "How many guests?" → countSelector
    - "How do you want to use the space?" → multiSelect
    - "Arrange the steps in order" → orderedList (seed options with the steps to reorder)
    - "Put these into a logical sequence" → orderedList
    - "Prioritize this list" → orderedList
    - "Sort these items" → orderedList
    - "What's the order?" → orderedList
    - "Organize these into categories" → hierarchicalList
    - "Group these items" → hierarchicalList
    - "Build an outline" → hierarchicalList
    - "Create a mind map / hierarchy" → hierarchicalList
    - "Parent / child structure" → hierarchicalList
    - "Preferred cabin class?" → singleSelect with options
    - "When do you want this done?" → date
    - "Describe the room layout" → drawing (physical space = OK for drawing)
    - "Add to calendar" / "Make the call" → yesNo confirmation
    - "Research X" / "Look up X" / "Compare X" → yesNo confirmation (it's external work!)
    - "Record the appointment date" → date

    BUDGET QUESTIONS ALWAYS USE RANGE SLIDER (rangeSlider, NOT slider):
    Any question mentioning "budget", "how much", "max price", "spending limit", "price range" → rangeSlider
    NEVER use "slider" for budget - ALWAYS use "rangeSlider" (two handles for min-max).
    Even if the question mentions other things (like cabin class), focus on the budget range.
    Set reasonable validation range based on context (e.g., flights: 100-3000, groceries: 50-500)

    "WHEN" QUESTIONS ALWAYS USE DATE:
    Any question starting with "When" is asking for a DATE. Use the date field type.
    - "When do you need to fly?" → date
    - "When is the event?" → date
    - "When should this happen?" → date
    Do NOT interpret "when" as trip type, category, or anything else. It's asking for a calendar date.

    NEVER use drawing for:
    - Schedules or availability
    - Preferences or priorities
    - Lists of things
    - Anything that can be typed as text

    For ACTION tasks (add, send, call, submit), use yesNo to confirm completion.
    For CAPTURE tasks (record, note, enter), use the appropriate input type.

    RESEARCH TASKS ARE EXTERNAL ACTIONS:
    "Research X" / "Look up X" / "Find out about X" → yesNo confirmation (requiresExternalAction: true)
    The user needs to go search online, read articles, compare options - that's real work outside the app.
    Do NOT ask them to fill out detailed tables with their research findings - that's busywork.
    Just confirm they did the research: "Have you researched bamboo varieties suitable for your balcony?"
    If they need to record key findings, use a simple textarea, NOT a structured table.

    CRITICAL - EXTERNAL ACTION STEPS MUST USE yesNo:

    When requiresExternalAction is TRUE, ALWAYS use yesNo field type!
    - Purchase items → yesNo: "Have you purchased the items?"
    - Make a call → yesNo: "Have you made the call?"
    - Go shopping → yesNo: "Have you completed your shopping?"

    NEVER use tables, text inputs, or complex UIs for external action steps.
    The user is doing real-world work - just confirm completion with Yes/No.

    CRITICAL - requiresExternalAction FLAG:

    You MUST set "requiresExternalAction": true when the step requires REAL-WORLD ACTION outside this app:
    - Making a phone call → requiresExternalAction: TRUE
    - Sending an email or message → requiresExternalAction: TRUE
    - Adding something to calendar → requiresExternalAction: TRUE
    - Going somewhere physically → requiresExternalAction: TRUE
    - Talking to someone → requiresExternalAction: TRUE
    - Waiting for a response → requiresExternalAction: TRUE
    - Confirming they completed an external task → requiresExternalAction: TRUE
    - Researching / looking up information online → requiresExternalAction: TRUE
    - Comparing options or products → requiresExternalAction: TRUE

    Only set "requiresExternalAction": false for pure IN-APP activities:
    - Answering questions about preferences
    - Entering information they already know
    - Making choices/selections about future plans

    If the user is CONFIRMING they did something (made a call, sent an email, added to calendar), that means external work was required!

    WRITING CLEAR CONFIRMATION LANGUAGE (yesNo fields):

    Title: Action-oriented phrase (e.g., "Add appointment to calendar")

    Description: A clear question asking if they completed the action. Use proper grammar:
    - GOOD: "Please confirm that you have added your appointment with Dr. Smith to your calendar."
    - GOOD: "Have you called the clinic to schedule your visit?"
    - BAD: "Confirm adding your visit to calendar" (awkward, incomplete)
    - BAD: "Add event: Dr. Smith — Visit, May 13" (redundant info dump)
    - BAD: "Add this appointment to your calendar?" (confusing when combined with Yes/No)

    Keep descriptions simple and conversational. Don't repeat all the details in a weird "Add event:" format.

    For yesNo fields, ALWAYS provide descriptive options array with two items:
    {
        "type": "yesNo",
        "label": "I have added the appointment to my calendar",
        "options": [
            {"id": "yes", "label": "Yes, I have added it to my calendar"},
            {"id": "no", "label": "No, I haven't done this yet"}
        ]
    }

    The options make it crystal clear what the user is confirming. NEVER leave options as null for yesNo.

    SUBMIT BUTTON LABELS - choose the right one for the context:
    - yesNo confirmation → "Confirm"
    - Entering/recording information → "Save" or "Continue"
    - Making a selection → "Continue"
    - Final step → "Complete"
    NEVER use generic "Done" - be specific!

    For slider, use validation: {"minValue": 0, "maxValue": 1000} to set the range.
    For options (singleSelect/multiSelect), provide 3-6 thoughtful choices.

    PREFILLING FROM PREVIOUS RESPONSES:

    USE THE USER'S EXACT WORDS. NO INTERPRETATION. NO EMBELLISHMENT.

    If user labeled something "Bamboo Wall":
    - "Bamboo Wall" ✓ CORRECT - exact words
    - "Bamboo privacy screen" ✗ WRONG - you interpreted it
    - "Bamboo plants" ✗ WRONG - you changed it

    NEVER ADD items the user didn't explicitly type. Copy the user's EXACT labels. Nothing more.

    NO EMOJIS. ONE field only. Be creative!
    """
}
