import XCTest
@testable import TaskFlow

/// Состав и порядок секций списка «Сегодня». Прежний `TodaySectionInfo` —
/// удалённый источник истины ручной липкой шапки; сейчас состав решает
/// `TodayListSection.sections(tab:waiting:overdue:today:upcoming:pool:todayDate:)`,
/// и именно его проверяем. Файл оставлен с историческим именем, чтобы не
/// плодить дубли.
final class TodayListSectionTests: XCTestCase {
    private let date = "2026-09-01"

    func testEmptyTasksProduceNoSections() {
        for tab in TodayListTab.allCases {
            XCTAssertTrue(sections(tab: tab).isEmpty, "вкладка \(tab.rawValue) не должна заводить пустые секции")
        }
    }

    /// Вкладка «Сегодня»: секция дня + «Предстоящие». Пустой «Предстоящие» не
    /// показывается — остаётся только день с его подписью-датой.
    func testTodayTabKeepsOnlyDaySectionWhenUpcomingEmpty() {
        let result = sections(tab: .today, today: [task("today")])

        XCTAssertEqual(result.map(\.id), ["today"])
        XCTAssertEqual(result.first?.title, TodayDate.formatDueLabel(date))
        XCTAssertNil(result.first?.icon)
        XCTAssertEqual(result.first?.marksOverdue, false)
    }

    func testTodayTabShowsUpcomingAfterDay() {
        let result = sections(tab: .today, today: [task("today")], upcoming: [task("soon")])

        XCTAssertEqual(result.map(\.id), ["today", "upcoming"])
        XCTAssertEqual(result.map { $0.tasks.map(\.id) }, [["today"], ["soon"]])
    }

    /// «Ждут вас»: сначала «Ждут вас», затем «Просрочено» с пометкой просрочки.
    func testAttentionTabOrderAndOverdueMark() {
        let result = sections(tab: .attention, waiting: [task("w")], overdue: [task("o")])

        XCTAssertEqual(result.map(\.id), ["waiting", "overdue"])
        XCTAssertEqual(result.first?.title, "Ждут вас")
        XCTAssertEqual(result.last?.title, "Просрочено")
        XCTAssertEqual(result.last?.marksOverdue, true)
    }

    /// «Входящие» — нераспределённые задачи (пул), одна секция.
    func testInboxTabUsesPool() {
        let result = sections(tab: .inbox, pool: [task("p1"), task("p2")])

        XCTAssertEqual(result.map(\.id), ["pool"])
        XCTAssertEqual(result.first?.title, "Входящие")
        XCTAssertEqual(result.first?.tasks.count, 2)
    }

    /// «Ждут вас» вычитаны из остальных наборов на уровне `TodayComputation`,
    /// поэтому здесь секции не пересекаются: каждая рисует свой набор как есть.
    func testAttentionTabDropsEmptySections() {
        let result = sections(tab: .attention, overdue: [task("o")])

        XCTAssertEqual(result.map(\.id), ["overdue"])
    }

    private func sections(
        tab: TodayListTab,
        waiting: [ApiTask] = [],
        overdue: [ApiTask] = [],
        today: [ApiTask] = [],
        upcoming: [ApiTask] = [],
        pool: [ApiTask] = []
    ) -> [TodayListSection] {
        TodayListSection.sections(
            tab: tab,
            waiting: waiting,
            overdue: overdue,
            today: today,
            upcoming: upcoming,
            pool: pool,
            todayDate: date
        )
    }

    private func task(_ id: String) -> ApiTask {
        TestTaskFactory.makeTask(id: id)
    }
}
