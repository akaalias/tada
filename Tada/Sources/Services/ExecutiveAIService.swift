import Foundation

actor ExecutiveAIService {
    private let client: ClaudeAPIClient

    private let systemPrompt = """
    You create ONE creative, appropriate UI for a single sub-task.

    CRITICAL: Use the EXACT sub-task title provided - do NOT invent a different title.

    CRITICAL: Generate exactly ONE field. Pick the BEST type for this specific task.

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

    JSON format (example for a confirmation that requires external action):
    {
        "type": "form",
        "title": "Call Dr. Smith's Office",
        "description": "Please call to schedule your appointment",
        "submitLabel": "Confirm",
        "requiresExternalAction": true,
        "fields": [
            {
                "id": "answer",
                "type": "yesNo",
                "label": "I have called the office and scheduled my appointment",
                "placeholder": null,
                "required": true,
                "options": [
                    {"id": "yes", "label": "Yes, I have made the call"},
                    {"id": "no", "label": "No, I haven't called yet"}
                ],
                "validation": null
            }
        ]
    }

    For slider, use validation: {"minValue": 0, "maxValue": 1000} to set the range.
    For options (singleSelect/multiSelect), provide 3-6 thoughtful choices.

    PREFILLING FROM PREVIOUS RESPONSES:

    USE THE USER'S EXACT WORDS. NO INTERPRETATION. NO EMBELLISHMENT.

    If user labeled something "Bamboo Wall":
    - "Bamboo Wall" ✓ CORRECT - exact words
    - "Bamboo privacy screen" ✗ WRONG - you interpreted it
    - "Bamboo plants" ✗ WRONG - you changed it

    If user said "Daybed":
    - "Daybed" ✓ CORRECT
    - "Daybed / Lounge Area furniture" ✗ WRONG - you added words

    If user said "Roses":
    - "Roses" ✓ CORRECT
    - "Roses wall planters" ✗ WRONG - you added words

    NEVER ADD:
    - "Additional plant pots" - user didn't say this
    - "Accessories" - user didn't say this
    - Any item the user didn't explicitly type

    Copy the user's EXACT labels. Nothing more.

    NO EMOJIS. ONE field only. Be creative!
    """

    init(apiKey: String) {
        self.client = ClaudeAPIClient(apiKey: apiKey, role: .executive, phase: .execution)
    }

    func generateActionUI(
        subTask: String,
        subTaskDescription: String,
        taskContext: String,
        previousResponses: [[String: String]],
        taskMemory: String = "",
        phase: TaskPhase
    ) async throws -> ActionSchema {
        let memorySection = taskMemory.isEmpty ? "" : """

        USER'S INSTRUCTIONS (follow these strictly):
        \(taskMemory)
        """

        let contextMessage = """
        Task: \(taskContext)

        Current sub-task to complete: \(subTask)
        \(subTaskDescription.isEmpty ? "" : "Details: \(subTaskDescription)")

        \(previousResponses.isEmpty ? "" : "Previous responses in this task:\n\(Self.formatPreviousResponses(previousResponses))")
        \(memorySection)

        Design a simple UI for the user to complete this sub-task.

        IMPORTANT: Use "\(subTask)" as the title - do NOT invent a different title.
        """

        return try await client.sendStructuredMessage(
            systemPrompt: systemPrompt,
            userMessage: contextMessage,
            responseType: ActionSchema.self,
            phase: APIRequestPhase(phase),
            taskTitle: subTask
        )
    }

    /// Renders prior sub-task answers as prompt text. Drawing fields store their
    /// image as a `data:image/png;base64,…` URL — that blob is useless as text
    /// and costs thousands of tokens, so it is dropped here. The companion
    /// `field_drawing` text description is kept, so the model still has context.
    nonisolated static func formatPreviousResponses(_ responses: [[String: String]]) -> String {
        responses.map { dict in
            dict
                .filter { !$0.value.hasPrefix("data:image") }
                .map { "- \($0.key): \($0.value)" }
                .joined(separator: "\n")
        }.joined(separator: "\n")
    }
}
