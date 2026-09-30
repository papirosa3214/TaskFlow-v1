import XCTest

final class RoleInstructionControlUITests: XCTestCase {
    private func openContext(_ app: XCUIApplication) {
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "agents"
        app.launchEnvironment["TASKFLOW_ROLE_CONTEXT_FIXTURE"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Команда"].waitForExistence(timeout: 30))
        let role = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Разработчик'")).firstMatch
        XCTAssertTrue(role.waitForExistence(timeout: 20))
        role.tap()
        let context = app.buttons["Как запускается роль"]
        XCTAssertTrue(context.waitForExistence(timeout: 10))
        context.tap()
        XCTAssertTrue(app.staticTexts["Контекст роли"].waitForExistence(timeout: 10))
    }
    func testOwnerCanReachAndEditInstructionWithoutServerWrites() {
        let app = XCUIApplication()
        openContext(app)
        let row = app.buttons["roleContext.block.role.prompt"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let editor = app.textViews["roleContext.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(". Проверить сохранение")
        let save = app.buttons["roleContext.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue((editor.value as? String ?? "").contains("Проверить сохранение"))
        XCTAssertFalse(app.staticTexts["roleContext.error"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "role-instruction-after-save"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSharedRuleShowsTeamScope() {
        let app = XCUIApplication()
        openContext(app)
        let picker = app.buttons["roleContext.groups"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.tap()
        app.buttons["Общие"].tap()
        let row = app.buttons["roleContext.block.rules"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let scope = app.buttons["roleContext.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 10))
        scope.tap()
        app.buttons["Вся команда"].tap()
        XCTAssertTrue(app.staticTexts["Общая правка затронет роли, у которых нет личного переопределения."].waitForExistence(timeout: 5))
        let editor = app.textViews["roleContext.editor"]
        XCTAssertEqual(editor.value as? String, "Общее правило")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "role-shared-instruction"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
