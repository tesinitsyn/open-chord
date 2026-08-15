import XCTest

@MainActor
final class OpenChordUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFirstLaunchShowsIntroduction() {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedWelcome", "NO"]
        app.launch()

        let continueButton = app.buttons["welcomeContinue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Skip"].exists)
    }
}
