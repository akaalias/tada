import XCTest

final class TadaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
    }

    @MainActor
    func testWindowAppears() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 5),
            "App window did not appear after launch"
        )
    }
}
