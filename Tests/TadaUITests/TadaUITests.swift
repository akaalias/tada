import XCTest

/// End-to-end happy path: create a task → answer 1 discovery question →
/// continue past the execution plan sheet → complete 1 execution step →
/// verify the task lands in Completed AND the knowledge base has the
/// expected notes on disk.
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
        app.launchArguments = ["-UITestMode", "1"]
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

        // 2. Discovery: navigate to Information Required and answer the question.
        let infoRow = app.buttons["sidebar.Information Required"]
        XCTAssertTrue(infoRow.waitForExistence(timeout: 10))
        infoRow.click()

        submitTextResponse(in: app, answer: "next weekend", phase: "discovery")

        // 3. After the discovery answer, the execution-plan sheet appears.
        let continueExecution = app.buttons["executionPlan.continue"]
        XCTAssertTrue(continueExecution.waitForExistence(timeout: 10))
        continueExecution.click()

        // 4. Action Required loads the scripted execution step.
        XCTAssertTrue(
            app.buttons["sidebar.Action Required"].waitForExistence(timeout: 5)
        )
        submitTextResponse(in: app, answer: "booked", phase: "execution")

        // 5. Task should land in Completed.
        app.buttons["sidebar.Completed"].click()
        let completedCard = app.staticTexts["Plan a weekend trip to Paris"]
        XCTAssertTrue(completedCard.waitForExistence(timeout: 10))

        // 6. Knowledge Base: navigate through the wiki UI and verify each
        // expected note is reachable and renders.
        verifyKnowledgeBaseNotesInUI(app)
    }

    /// Ensures the task card is expanded (the Action Required view starts
    /// collapsed) then types an answer and clicks Submit.
    @MainActor
    private func submitTextResponse(in app: XCUIApplication, answer: String, phase: String) {
        let submit = app.buttons["actionUI.submit"]
        if !submit.waitForExistence(timeout: 3) {
            let chevron = app.buttons["taskCard.toggleExpand"].firstMatch
            XCTAssertTrue(chevron.waitForExistence(timeout: 5), "No expand chevron (\(phase) phase)")
            chevron.click()
            XCTAssertTrue(submit.waitForExistence(timeout: 10), "Submit not visible after expanding (\(phase) phase)")
        }

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

        // 1. Index page renders with our task linked under "In progress" or
        // "Completed". The label is the task title.
        XCTAssertTrue(
            app.staticTexts["index.md"].waitForExistence(timeout: 5),
            "Toolbar should show 'index.md' on the KB landing page"
        )
        let taskLink = app.buttons.matching(
            NSPredicate(format: "identifier ENDSWITH %@", "_overview.md")
        ).firstMatch
        XCTAssertTrue(
            taskLink.waitForExistence(timeout: 5),
            "Index page should expose a button link to the task's _overview.md"
        )
        // The visible label is the task title, not the folder slug.
        XCTAssertEqual(taskLink.label, "Plan a weekend trip to Paris")
        taskLink.click()

        // 2. Task overview renders. Toolbar shows _overview.md. Sub-task notes
        // section lists one button per note.
        XCTAssertTrue(
            app.staticTexts["_overview.md"].waitForExistence(timeout: 5),
            "Toolbar should show '_overview.md' after clicking the task link"
        )
        XCTAssertTrue(
            app.staticTexts["Sub-task notes"].waitForExistence(timeout: 3),
            "Task overview should include the 'Sub-task notes' heading"
        )

        // Expected subtask notes on disk, in the order they appear in the
        // overview's "Sub-task notes" list. For each: (filename, label shown
        // in overview list, the user's answer text that must be visible in
        // the note body — proves we're on the right sub-task's page).
        let expectedNotes: [(filename: String, listLabel: String, answer: String)] = [
            ("01-what-dates-are-you-traveling.md", "What dates are you traveling?", "next weekend"),
            ("02-book-flights.md", "Book flights", "booked")
        ]
        for note in expectedNotes {
            let button = app.buttons["kb.link.\(note.filename)"]
            XCTAssertTrue(
                button.waitForExistence(timeout: 3),
                "Overview should list a link button for note '\(note.filename)'"
            )
            XCTAssertEqual(button.label, note.listLabel)
        }

        // 3. Click each subtask note in turn and verify the page renders with
        // the expected heading, then go back to the overview.
        let backButton = app.buttons.matching(identifier: "chevron.left").firstMatch
        for note in expectedNotes {
            let button = app.buttons["kb.link.\(note.filename)"]
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            button.click()

            XCTAssertTrue(
                app.staticTexts[note.filename].waitForExistence(timeout: 5),
                "Toolbar should show '\(note.filename)' after clicking the note link"
            )
            // The note's body must include the answer the user typed during
            // the journey. This is what proves we landed on the sub-task's
            // own page rather than the parent task's repeated content.
            XCTAssertTrue(
                app.staticTexts[note.answer].waitForExistence(timeout: 3),
                "Note '\(note.filename)' should render the recorded answer '\(note.answer)'"
            )

            // Back to overview for the next iteration.
            if backButton.exists {
                backButton.click()
                XCTAssertTrue(app.staticTexts["_overview.md"].waitForExistence(timeout: 3))
            }
        }
    }
}
