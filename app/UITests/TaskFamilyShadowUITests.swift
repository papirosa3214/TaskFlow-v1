import XCTest

final class TaskFamilyShadowUITests: XCTestCase {
    func testIntermediateFamilyPull() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"] = "1"
        app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = try XCTUnwrap(
            ProcessInfo.processInfo.environment["TEST_RUNNER_TF_CARD_DEMO_TOKEN"]
        )
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "tasksheet:11e72477-6241-4506-84be-fac3a5a2750d"
        app.launch()

        let grabber = app.buttons["Sheet Grabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 25))
        grabber.swipeUp()

        let description = app.buttons["Описание"]
        XCTAssertTrue(description.waitForExistence(timeout: 15))
        description.tap()

        let tab = app.buttons["task.family.6ca26c5f-a1b8-4607-89e1-2d97a15ad7ac"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        let start = tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = app.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.52))
        start.press(forDuration: 0.6, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 2.0)
    }
}
