// Диагностика островка: не «почему-то не работает», а что именно вернул
// ActivityKit. Заведён 10.09.2026, когда на телефоне кнопка сказала «не
// удалось вывести», а причина в интерфейс не попадала.
import XCTest
import ActivityKit
@testable import TaskFlow

final class LiveActivityDiagTests: XCTestCase {
    func testActivityRequestReportsItsError() async throws {
        guard #available(iOS 16.2, *) else {
            throw XCTSkip("Live Activity доступны с iOS 16.2")
        }

        let info = ActivityAuthorizationInfo()
        print("[ДИАГ] activitiesEnabled = \(info.areActivitiesEnabled)")
        print("[ДИАГ] frequentPushesEnabled = \(info.frequentPushesEnabled)")

        let state = TaskActivityAttributes.ContentState(
            status: "in_progress",
            statusLabel: "В работе",
            totalSubtasks: 3,
            doneSubtasks: 1,
            progress: 0.33,
            taskTitle: "Проверка островка"
        )

        // Заход первый — как в приложении, с токеном для пушей.
        do {
            let activity = try Activity.request(
                attributes: TaskActivityAttributes(taskId: "diag-task"),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: .token
            )
            print("[ДИАГ] с токеном: ЗАПУСТИЛАСЬ, id=\(activity.id)")
            await activity.end(nil, dismissalPolicy: .immediate)
        } catch {
            print("[ДИАГ] с токеном: ОТКАЗ — \(error) | \(error.localizedDescription)")
        }

        // Заход второй — без токена: если он проходит, дело именно в пушах.
        do {
            let activity = try Activity.request(
                attributes: TaskActivityAttributes(taskId: "diag-task-2"),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            print("[ДИАГ] без токена: ЗАПУСТИЛАСЬ, id=\(activity.id)")
            await activity.end(nil, dismissalPolicy: .immediate)
        } catch {
            print("[ДИАГ] без токена: ОТКАЗ — \(error) | \(error.localizedDescription)")
        }
    }
}
