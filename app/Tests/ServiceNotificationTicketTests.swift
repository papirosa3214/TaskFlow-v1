import XCTest
@testable import TaskFlow

final class ServiceNotificationTicketTests: XCTestCase {
    // Живой пример с .110, curl 27.09.2026 — не выдумка.
    func test_decodesInboxResponse() throws {
        let json = """
        {"date":"2026-09-27","count":1,"items":[{"id":"inbox/2026-09-27/015133-autonomy-110","path":"/home/maksim/Проекты/taskflow-уведомления/inbox/2026-09-27/015133-autonomy-110.md","title":"Автономность .110 — сводка за сутки","ts":"2026-09-27T01:51:33","source":"autonomy-110","level":"error","has_triage":true,"snippet":"## Сводка...","links":[]}]}
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(ServiceTicketInboxResponse.self, from: json)
        XCTAssertEqual(resp.count, 1)
        XCTAssertEqual(resp.items[0].id, "inbox/2026-09-27/015133-autonomy-110")
        XCTAssertEqual(resp.items[0].path, "/home/maksim/Проекты/taskflow-уведомления/inbox/2026-09-27/015133-autonomy-110.md")
        XCTAssertTrue(resp.items[0].hasTriage)
    }

    func test_resolutionStatus_equality() {
        XCTAssertEqual(ServiceTicketResolutionStatus.fixed, ServiceTicketResolutionStatus.fixed)
        XCTAssertEqual(
            ServiceTicketResolutionStatus.unresolved(reason: "нет доступов"),
            ServiceTicketResolutionStatus.unresolved(reason: "нет доступов")
        )
    }
}
