import XCTest

final class RoleComposioUITests: XCTestCase {
    func testComposioEntryRemovedFromRole() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "agents"
        app.launchEnvironment["TASKFLOW_ROLE_CONTEXT_FIXTURE"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Команда"].waitForExistence(timeout: 30))
        let role = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Разработчик'")).firstMatch
        XCTAssertTrue(role.waitForExistence(timeout: 20))
        role.tap()
        XCTAssertTrue(app.staticTexts["Настройки агента"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["role.composio"].exists)
    }


}
