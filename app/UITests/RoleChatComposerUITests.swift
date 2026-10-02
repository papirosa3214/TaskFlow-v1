import XCTest

final class RoleChatComposerUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_COMPOSER_PREVIEW"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["chat.mode"].waitForExistence(timeout: 20))
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testStopInLeftCircleAndModeBesideVoicePreserveDraft() {
        let app = launch()
        let stop = app.buttons["chat.stop"]
        XCTAssertTrue(stop.exists)
        let field = app.descendants(matching: .any).matching(identifier: "chat.message").firstMatch
        let mode = app.buttons["chat.mode"]
        let voice = app.images["chat.voice"]
        XCTAssertTrue(voice.exists)
        XCTAssertLessThan(stop.frame.maxX, field.frame.minX)
        XCTAssertEqual(mode.frame.midY, voice.frame.midY, accuracy: 2)
        XCTAssertEqual(voice.frame.minX - mode.frame.maxX, 8, accuracy: 2)
        XCTAssertLessThanOrEqual(mode.frame.width, 40)
        XCTAssertFalse(app.staticTexts["Работа"].exists)
        capture(app, "composer-one-row-left-stop-mode-and-voice")
        app.buttons["chat.mode"].tap()
        app.buttons["Глубокое исследование"].tap()
        XCTAssertTrue(app.buttons["chat.mode"].label.contains("Глубокое исследование"))
        field.tap(); field.typeText("Сравни варианты")
        XCTAssertTrue(stop.exists)
        capture(app, "composer-deep-research-stop-and-draft")
        stop.tap()
        XCTAssertTrue(app.buttons["chat.attachment"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chat.stop"].exists)
        XCTAssertTrue(app.buttons["chat.send"].exists)
        XCTAssertEqual(field.value as? String, "Сравни варианты")
        XCTAssertTrue(app.buttons["chat.mode"].label.contains("Глубокое исследование"))
        capture(app, "composer-draft-after-stop")
    }
    func testPlanningAndStreamingCompletion() {
        let app = launch()
        app.buttons["chat.mode"].tap()
        app.buttons["Планирование"].tap()
        XCTAssertTrue(app.buttons["chat.mode"].label.contains("Планирование"))
        XCTAssertTrue(app.staticTexts["chat.preview.complete"].waitForExistence(timeout: 20))
        capture(app, "composer-planning-completed-stream")
    }
}
