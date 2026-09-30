import XCTest
@testable import TaskFlow

/// Сводки сервера для карточек «Уведомлений»: понятное название и счётчики
/// «штатно / ошибок / предупреждений» без имён скриптов.
final class ServiceTicketPresentationTests: XCTestCase {
    // Живой ответ GET /notifications/digest с .110 (27.09.2026), списки урезаны.
    private let digestJSON = """
    {"date":"2026-09-27","count":2,"items":[{"id":"digest/2026-09-27","path":"digest:2026-09-27","title":"Сводка работы сервера","ts":"2026-09-27T09:00:06","source":"server-digest","level":"error","has_triage":true,"snippet":"2 ошибок · 2 предупреждений","links":["tf://task/bfb195ab-4653-4c6c-9d22-e8d1e8357ffd"],"revision":"f8ef841de6683c2cba3af387","checks":[{"name":"Обработка памяти помощников","area":"Сервер","status":"ok","message":"4 прогонов","source":"autonomy-110","ts":"2026-09-27T09:00:06","diagnostic_task_ids":["bfb195ab-4653-4c6c-9d22-e8d1e8357ffd"]}],"ok_count":12,"error_count":2,"warning_count":2},{"id":"critical/2026-09-27/bcdb01db0a63","path":"critical:2026-09-27:bcdb01db0a63","title":"Доставка уведомлений — требуется внимание","ts":"2026-09-27T09:00:06","source":"server-digest","level":"error","has_triage":true,"snippet":"1 ошибок","links":[],"revision":"a3cc5be5a3d98555bc2d2ef0","checks":[{"name":"Доставка уведомлений","area":"Доставка уведомлений","status":"error","message":"у отправителей НЕ УШЛО 17","source":"autonomy-110","ts":"2026-09-27T09:00:06","diagnostic_task_ids":[]}],"ok_count":0,"error_count":1,"warning_count":0}]}
    """

    func test_decodesDigestWithCountsAndChecks() throws {
        let resp = try JSONDecoder().decode(ServiceTicketInboxResponse.self, from: Data(digestJSON.utf8))
        XCTAssertEqual(resp.items.count, 2)
        let digest = resp.items[0]
        XCTAssertEqual(digest.path, "digest:2026-09-27")
        XCTAssertEqual(digest.revision, "f8ef841de6683c2cba3af387")
        XCTAssertEqual(digest.okCount, 12)
        XCTAssertEqual(digest.errorCount, 2)
        XCTAssertEqual(digest.warningCount, 2)
        XCTAssertEqual(digest.checks?.first?.name, "Обработка памяти помощников")
    }

    func test_serverCountsWinOverTruncatedChecks() throws {
        let resp = try JSONDecoder().decode(ServiceTicketInboxResponse.self, from: Data(digestJSON.utf8))
        let p = ServiceTicketPresentation(summary: resp.items[0])
        XCTAssertEqual(p.title, "Сводка работы сервера")
        XCTAssertEqual(p.okCount, 12)
        XCTAssertEqual(p.errorCount, 2)
        XCTAssertEqual(p.warningCount, 2)
    }

    func test_criticalPreviewNamesTheProblem() throws {
        let resp = try JSONDecoder().decode(ServiceTicketInboxResponse.self, from: Data(digestJSON.utf8))
        let p = ServiceTicketPresentation(summary: resp.items[1])
        XCTAssertEqual(p.errorCount, 1)
        XCTAssertEqual(p.preview, "Доставка уведомлений")
    }

    /// Старый формат inbox без счётчиков: считаем по уровню, название — человеческое.
    func test_legacyInboxItemWithoutCounts() throws {
        let json = """
        {"id":"inbox/2026-09-27/015133-autonomy-110","path":"/x.md","title":"Автономность .110 — сводка за сутки","ts":"2026-09-27T01:51:33","source":"autonomy-110","level":"error","has_triage":true,"snippet":"","links":[]}
        """
        let summary = try JSONDecoder().decode(ServiceTicketSummary.self, from: Data(json.utf8))
        let p = ServiceTicketPresentation(summary: summary)
        XCTAssertEqual(p.title, "Работа серверных механизмов")
        XCTAssertEqual(p.okCount, 0)
        XCTAssertEqual(p.errorCount, 1)
        XCTAssertEqual(p.warningCount, 0)
        XCTAssertEqual(p.preview, "Состояние сервиса и результаты проверки")
    }

    func test_previewListsTwoProblemsAndTheRest() {
        let checks = ["А", "Б", "В", "Г"].map {
            ServiceTicketCheck(name: $0, area: "Сервер", status: "error", message: "")
        }
        var summary = ServiceTicketSummary(
            id: "d", path: "digest:d", title: "Сводка", ts: "2026-09-27T09:00:06",
            source: "server-digest", level: "error", hasTriage: false, snippet: "", links: []
        )
        summary.checks = checks + [ServiceTicketCheck(name: "Д", area: "Сервер", status: "ok", message: "")]
        let p = ServiceTicketPresentation(summary: summary)
        XCTAssertEqual(p.preview, "А · Б · ещё 2")
        XCTAssertEqual(p.okCount, 1)
        XCTAssertEqual(p.errorCount, 4)
    }
}
