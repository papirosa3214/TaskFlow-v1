import Foundation
import XCTest
@testable import TaskFlow

final class AppleRemindersDueDateTests: XCTestCase {
    /// Напоминание без времени на 30-е — в TaskFlow тоже 30-е, не 29-е.
    func testImportAllDayReminderKeepsDay() {
        let components = DateComponents(year: 2026, month: 9, day: 30)
        XCTAssertEqual(AppleRemindersSync.dueDateString(from: components), "2026-09-30")
    }

    /// Раннее время (до 03:00 по Москве) тоже не уводит на прошлый день.
    func testImportEarlyTimeKeepsDay() {
        let components = DateComponents(year: 2026, month: 9, day: 30, hour: 1, minute: 30)
        XCTAssertEqual(AppleRemindersSync.dueDateString(from: components), "2026-09-30")
    }

    func testImportWithoutDayIsNil() {
        XCTAssertNil(AppleRemindersSync.dueDateString(from: DateComponents(hour: 9)))
    }

    /// Срок задачи уходит в Напоминания как день без времени — без 03:00.
    func testExportDueDateIsDayWithoutTime() {
        let components = AppleRemindersSync.reminderComponents(dueDate: "2026-09-30")
        XCTAssertEqual(components?.year, 2026)
        XCTAssertEqual(components?.month, 9)
        XCTAssertEqual(components?.day, 30)
        XCTAssertNil(components?.hour)
        XCTAssertNil(components?.minute)
    }

    func testExportBadDueDateIsNil() {
        XCTAssertNil(AppleRemindersSync.reminderComponents(dueDate: "30.09.2026"))
    }
}
