import XCTest

/// Clicking the current (actionable) sub-task in the "All Tasks" list opens a
/// focused single-task view that shows only that task's action card, with a
/// back button to return to the list.
final class FocusedTaskUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testClickingCurrentSubTaskOpensFocusedView() throws {
        let app = XCUIApplication()
        // -claude-api-key injects a dummy key so the app's "has API key" gates
        // open in a fresh environment (VM/CI) without a host-persisted key.
        app.launchArguments = ["-UITestMode", "1", "-claude-api-key", uiTestAPIKey]
        app.launch()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 5),
            "App window did not appear after launch"
        )

        // Create a task from the empty state.
        let addButton = app.buttons["allTasks.emptyState.addTask"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.click()

        let input = app.textViews["newTaskSheet.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.click()
        input.typeText("Plan a weekend trip to Paris")
        app.buttons["newTaskSheet.create"].click()

        // The All Tasks list surfaces the current discovery sub-task as a
        // clickable row.
        let currentRow = app.descendants(matching: .any)
            .matching(identifier: "subTaskRow.current").firstMatch
        XCTAssertTrue(
            currentRow.waitForExistence(timeout: 10),
            "Current sub-task row should appear in the All Tasks list"
        )
        currentRow.click()

        // The focused single-task view appears: a back button plus the task's
        // action card (its submit button).
        let back = app.buttons["focusedTask.back"]
        XCTAssertTrue(
            back.waitForExistence(timeout: 5),
            "Focused task view should show a back button"
        )
        XCTAssertTrue(
            app.buttons["actionUI.submit"].waitForExistence(timeout: 10),
            "Focused task view should render the task's action card"
        )

        // Back returns to the All Tasks list.
        back.click()
        XCTAssertTrue(
            currentRow.waitForExistence(timeout: 5),
            "Going back should return to the All Tasks list"
        )
    }
}
