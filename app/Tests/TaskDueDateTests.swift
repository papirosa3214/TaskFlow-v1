import Foundation
import XCTest
@testable import TaskFlow

final class TaskDueDateTests: XCTestCase {
    /// Пикер и «Сегодня/Завтра» дают московскую полночь — это 21:00 UTC
    /// предыдущих суток. На сервер должен уйти выбранный день, а не прошлый.
    func testMoscowMidnightKeepsChosenDay() {
        let chosen = ISO8601DateFormatter().date(from: "2026-09-29T21:00:00Z")!
        XCTAssertEqual(TaskFormViewModel.dueDateString(chosen), "2026-09-30")
    }

    /// Срок, прочитанный с сервера, разбирается в UTC-полночь — при
    /// сохранении без изменений он не должен сдвинуться.
    func testLoadedUTCMidnightKeepsSameDay() {
        let loaded = DateFormats.calendarDate("2026-09-30")!
        XCTAssertEqual(TaskFormViewModel.dueDateString(loaded), "2026-09-30")
    }
}
