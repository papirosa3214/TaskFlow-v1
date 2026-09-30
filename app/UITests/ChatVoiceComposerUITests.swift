import XCTest
import UIKit

/// Кадры системного аксессуара с поднятой клавиатурой в настоящем чате.
final class ChatVoiceComposerUITests: XCTestCase {
    func testKeyboardAccessoryKeepsKeyboardDuringRecording() {
        let app = XCUIApplication()
        app.launch()
        let tab = app.buttons["Чат"]
        XCTAssertTrue(tab.waitForExistence(timeout: 25))
        tab.tap()
        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        input.typeText("test")
        let sendButton = app.buttons["Отправить"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        attachKeyboardFrame(app, startingAt: sendButton.frame.minY, name: "idle-keyboard")
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        let capsule = app.images["Удерживайте для начала записи"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 15))
        let addButton = app.buttons["Добавить вложение"]
        XCTAssertTrue(addButton.exists)

        capsule.press(forDuration: 0.3)
        let stopButton = app.buttons["Остановить запись"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        attachKeyboardFrame(app, startingAt: stopButton.frame.minY, name: "recording-keyboard")
        stopButton.tap()
        let discardButton = app.buttons["Удалить запись"]
        XCTAssertTrue(discardButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Отправить голосовое сообщение"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        attachKeyboardFrame(app, startingAt: discardButton.frame.minY, name: "preview-keyboard")
        discardButton.tap()
    }

    private func attachKeyboardFrame(_ app: XCUIApplication, startingAt top: CGFloat, name: String) {
        let screenshot = app.screenshot().image
        guard let source = screenshot.cgImage else { return XCTFail("Нет кадра симулятора") }
        let scale = CGFloat(source.width) / app.frame.width
        let pixels = CGRect(x: 0, y: max(0, (top - 8) * scale),
                            width: CGFloat(source.width), height: CGFloat(source.height) - max(0, (top - 8) * scale))
        guard let crop = source.cropping(to: pixels) else { return XCTFail("Не удалось выделить клавиатуру") }
        let attachment = XCTAttachment(image: UIImage(cgImage: crop))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
