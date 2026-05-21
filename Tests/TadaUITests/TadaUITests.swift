import XCTest

/// End-to-end happy path: create a task → open it from the "Action Items"
/// view via its "Take Action" button → answer 1 discovery question in the
/// focused single-task view → watch the task transition to "Planning
/// Execution" → complete the first execution step → return to the list →
/// verify the task lands in Completed AND the knowledge base has the
/// expected notes on disk.
///
/// Reflects the current UI: Action Items cards are not expanded in place;
/// each card has a "Take Action" button that opens the focused task view
/// where the action card is rendered.
///
/// Backed by deterministic mocks wired in under `-UITestMode 1`. The mocks
/// write structural KB notes to a stable temp directory so this test process
/// can assert them after the journey.
final class TadaUITests: XCTestCase {

    private let kbRoot: URL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("TadaUITestKnowledgeBase", isDirectory: true)

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.removeItem(at: kbRoot)
    }

    @MainActor
    func testFullTaskJourney() throws {
        let app = XCUIApplication()
        // -UITestMode routes services to deterministic mocks. -claude-api-key
        // injects a dummy key (via the UserDefaults argument domain) so the
        // app's "has API key" gates open without depending on a key persisted
        // on the host machine — makes the test hermetic (host, VM, or CI).
        app.launchArguments = ["-UITestMode", "1", "-claude-api-key", uiTestAPIKey]
        // The test process (sandboxed) and the launched app (not sandboxed) see
        // different NSTemporaryDirectory paths, so we hand the app the test's
        // tmp dir explicitly. The app's mock KB writes there; the test reads
        // from the same place.
        app.launchEnvironment = ["TADA_UI_TEST_KB_PATH": kbRoot.path]
        app.launch()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 5),
            "App window did not appear after launch"
        )

        // 1. Create a task from the empty state.
        let addButton = app.buttons["allTasks.emptyState.addTask"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.click()

        let input = app.textViews["newTaskSheet.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.click()
        input.typeText("Plan a weekend trip to Paris")

        let create = app.buttons["newTaskSheet.create"]
        XCTAssertTrue(create.isEnabled)
        create.click()

        // 2. Navigate to the "Action Items" view. Each actionable task is shown
        //    as a collapsed card with a "Take Action" button (no inline expand).
        let actionItemsRow = app.buttons["sidebar.Action Items"]
        XCTAssertTrue(actionItemsRow.waitForExistence(timeout: 10))
        actionItemsRow.click()

        let takeAction = app.buttons["taskCard.takeAction"].firstMatch
        XCTAssertTrue(
            takeAction.waitForExistence(timeout: 10),
            "Action Items should show a 'Take Action' button for the task"
        )
        takeAction.click()

        // 3. The focused single-task view opens with the action card expanded.
        XCTAssertTrue(
            app.buttons["focusedTask.back"].waitForExistence(timeout: 5),
            "Take Action should open the focused task view"
        )

        // 4. Answer the discovery question in the focused view.
        submitTextResponse(in: app, answer: "next weekend", phase: "discovery")

        // 5. After the last discovery answer the task transitions to execution;
        //    the focused card surfaces a "Planning Execution:" indicator while
        //    the mock plans (a brief window).
        XCTAssertTrue(
            app.staticTexts["Planning Execution:"].waitForExistence(timeout: 8),
            "Focused card should show 'Planning Execution:' after the last discovery answer"
        )

        // 6. The first execution step appears in the same focused view.
        submitTextResponse(in: app, answer: "booked", phase: "execution")

        // 7. Once the task completes, return to the list and confirm it landed
        //    in Completed.
        let back = app.buttons["focusedTask.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.click()

        app.buttons["sidebar.Completed"].click()
        let completedCard = app.staticTexts["Plan a weekend trip to Paris"]
        XCTAssertTrue(completedCard.waitForExistence(timeout: 10))

        // 8. Knowledge Base: navigate through the wiki UI and verify each
        // expected note is reachable and renders.
        verifyKnowledgeBaseNotesInUI(app)
    }

    /// Types an answer into the focused task's action card and clicks Submit.
    /// The focused view renders the card expanded, so the submit button and
    /// text field are present without any expand step.
    @MainActor
    private func submitTextResponse(in app: XCUIApplication, answer: String, phase: String) {
        let submit = app.buttons["actionUI.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), "Submit not visible (\(phase) phase)")

        let field = app.textFields["actionUI.field.field_text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Missing text field (\(phase) phase)")
        field.click()
        field.typeText(answer)

        let enabledPredicate = NSPredicate(format: "exists == true AND isEnabled == true")
        let enabledExp = expectation(for: enabledPredicate, evaluatedWith: submit)
        if XCTWaiter().wait(for: [enabledExp], timeout: 10) != .completed {
            XCTFail("Submit never enabled after typing (\(phase) phase)")
            return
        }
        submit.click()
    }

    /// Navigates to the Knowledge Base view, then walks the wiki by clicking
    /// real link buttons: index → task overview → each subtask note. Asserts
    /// the expected page renders at each step.
    @MainActor
    private func verifyKnowledgeBaseNotesInUI(_ app: XCUIApplication) {
        let kbRow = app.buttons["sidebar.Knowledge Base"]
        XCTAssertTrue(kbRow.waitForExistence(timeout: 5))
        kbRow.click()

        // Assert on rendered content (link buttons + note body), not toolbar
        // chrome: the toolbar path text is styled/truncated and not reliably
        // readable by XCUITest.

        // 1. Index renders with our task's overview link (label = task title).
        let taskLink = app.buttons.matching(
            NSPredicate(format: "identifier ENDSWITH %@", "_overview.md")
        ).firstMatch
        XCTAssertTrue(
            taskLink.waitForExistence(timeout: 5),
            "Index page should expose a link button to the task's _overview.md"
        )
        XCTAssertEqual(taskLink.label, "Plan a weekend trip to Paris")
        taskLink.click()

        // 2. Task overview lists one link button per sub-task note. Their
        //    presence (with the right labels) proves the index rendered, the
        //    task overview rendered, and the sub-task notes were generated.
        let expectedNotes: [(filename: String, listLabel: String, answer: String)] = [
            ("01-what-dates-are-you-traveling.md", "What dates are you traveling?", "next weekend"),
            ("02-book-flights.md", "Book flights", "booked")
        ]
        for note in expectedNotes {
            let button = app.buttons["kb.link.\(note.filename)"]
            XCTAssertTrue(
                button.waitForExistence(timeout: 5),
                "Overview should list a link button for note '\(note.filename)'"
            )
            XCTAssertEqual(button.label, note.listLabel)
        }

        // 3. Open each note and verify its body shows the recorded answer —
        //    proof we landed on that sub-task's own page — then go back.
        let backButton = app.buttons["kb.back"]
        for note in expectedNotes {
            let button = app.buttons["kb.link.\(note.filename)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.click()

            XCTAssertTrue(
                app.staticTexts[note.answer].waitForExistence(timeout: 5),
                "Note '\(note.filename)' should render the recorded answer '\(note.answer)'"
            )

            // Back to the overview: the note link buttons reappear.
            XCTAssertTrue(backButton.waitForExistence(timeout: 3), "KB back button should exist")
            backButton.click()
            XCTAssertTrue(
                app.buttons["kb.link.\(note.filename)"].waitForExistence(timeout: 5),
                "Back should return to the task overview"
            )
        }
    }
}
