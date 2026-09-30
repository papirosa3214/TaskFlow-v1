// Tests/ServiceTicketMarkdownParserTests.swift
import XCTest
@testable import TaskFlow

final class ServiceTicketMarkdownParserTests: XCTestCase {
    // Живой файл с .110, curl+ssh 27.09.2026 (урезан ради читаемости теста,
    // содержимое совпадает по структуре с настоящим).
    private let liveExample = """
    # Автономность .110 — сводка за сутки

    - когда: 2026-09-27T01:51:33
    - от кого: autonomy-110
    - уровень: error
    - тревога: да
    - приёмка: rendezvous.py v1

    ## Сводка (для отображения в приложении)

    ```
    Сводка уведомлений от 27.09.26

    **Работают в штатном режиме:**
    - сжатие памяти: 4 прогонов, свёрнуто 0 записей

    **Не отработали в штатном режиме:**
    - доставка тревог: у отправителей НЕ УШЛО 13
    По данным проблемным местам создана карточка на диагностику:
    tf://task/demo-diag-uuid-1 (27.09.2026, Codex)
    ```
    """

    func test_parsesLiveExample() throws {
        let d = try XCTUnwrap(ServiceTicketMarkdownParser.parse(liveExample))
        XCTAssertEqual(d.title, "Автономность .110 — сводка за сутки")
        XCTAssertEqual(d.when, "2026-09-27T01:51:33")
        XCTAssertEqual(d.from, "autonomy-110")
        XCTAssertEqual(d.level, "error")
        XCTAssertTrue(d.isAlarm)
        XCTAssertEqual(d.diagnosticTaskId, "demo-diag-uuid-1")
        XCTAssertTrue(d.notWorkingText?.contains("НЕ УШЛО") == true)
        XCTAssertTrue(d.resolutionItems.isEmpty) // Phase 4 блока в этом файле ещё нет
    }

    // Сконструированная фикстура Phase 4 — backend её пока не пишет, см. спеку.
    private let withPhase4Block = """
    # Тикет с итогом устранения

    - когда: 2026-09-27T02:00:00
    - от кого: demo
    - уровень: error
    - тревога: да

    ## Сводка (для отображения в приложении)
    ```
    demo
    ```

    ## Итог по устранению
    - доставка тревог — (исправлено)
    - доступ к базе — (не исправлено: нет доступов у исполнителя)
    - канал telegram — (не исправлено, нужно ваше решение по вопросу выбора канала:
      1) переключить на резервный канал
      2) увеличить таймаут отправки
      3) отключить проверку до утра
      4) свой вариант)
    """

    func test_parsesPhase4ResolutionBlock_bestEffort() throws {
        let d = try XCTUnwrap(ServiceTicketMarkdownParser.parse(withPhase4Block))
        XCTAssertEqual(d.resolutionItems.count, 3)
        XCTAssertEqual(d.resolutionItems[0].problem, "доставка тревог")
        XCTAssertEqual(d.resolutionItems[0].status, .fixed)
        XCTAssertEqual(d.resolutionItems[1].status, .unresolved(reason: "нет доступов у исполнителя"))
        guard case .needsDecision(let options) = d.resolutionItems[2].status else {
            return XCTFail("expected needsDecision")
        }
        XCTAssertEqual(options, [
            "переключить на резервный канал",
            "увеличить таймаут отправки",
            "отключить проверку до утра"
        ])
    }

    func test_returnsNil_onGarbage() {
        XCTAssertNil(ServiceTicketMarkdownParser.parse("случайный текст без нужных полей"))
    }

    // Живой файл с .110, ssh 27.09.2026 03:xx — writer rendezvous.py
    // переключился на `**жирные**` ключи метаданных ПОЗЖЕ в тот же день
    // (первая проверка утром была без жирного — см. `test_parsesLiveExample`).
    // Оба варианта должны разбираться одним и тем же парсером.
    private let liveExampleBoldMeta = """
    # Автономность .110 — сводка за сутки

    - **когда:** 2026-09-27T01:51:33
    - **от кого:** autonomy-110
    - **уровень:** error
    - **тревога:** да
    - **приёмка:** rendezvous.py v1

    ## Сводка (для отображения в приложении)

    ```
    Сводка уведомлений от 27.09.26

    **Работают в штатном режиме:**
    - сжатие памяти: 4 прогонов, свёрнуто 0 записей.

    **Не отработали в штатном режиме:**
    - доставка тревог: у отправителей НЕ УШЛО 13.

    ```

    ## Сырые строки (для парсинга)
    raw
    """

    func test_parsesLiveExample_withBoldMetaKeys() throws {
        let d = try XCTUnwrap(ServiceTicketMarkdownParser.parse(liveExampleBoldMeta))
        XCTAssertEqual(d.when, "2026-09-27T01:51:33")
        XCTAssertEqual(d.from, "autonomy-110")
        XCTAssertEqual(d.level, "error")
        XCTAssertTrue(d.isAlarm)
        XCTAssertTrue(d.notWorkingText?.contains("НЕ УШЛО") == true)
    }

    // file-format.md (документация NAS 00-taskflow/notifications-backend/,
    // получена 27.09.2026): ссылка на карточку диагностики живёт в СВОЕЙ
    // секции "## Карточка диагностики", не внутри блока "## Сводка".
    private let liveExampleWithDiagnosticSection = """
    # Тикет с диагностикой

    - **когда:** 2026-09-27T02:00:00
    - **от кого:** demo
    - **уровень:** error
    - **тревога:** да

    ## Сводка (для отображения в приложении)
    ```
    demo, без ссылки внутри
    ```

    ## Карточка диагностики

    Создана задача на диагностику: [карточка #88a18485](tf://task/88a18485-120a-4e97-ab20-e45a48d5fe58)
    """

    func test_diagnosticTaskId_foundOutsideSummaryBlock() throws {
        let d = try XCTUnwrap(ServiceTicketMarkdownParser.parse(liveExampleWithDiagnosticSection))
        XCTAssertEqual(d.diagnosticTaskId, "88a18485-120a-4e97-ab20-e45a48d5fe58")
    }

    // Important #4 финального ревью LOCK-227: старый символьный класс
    // `[^0-9)]+?` в захватывающей группе исключал ВСЕ цифры, поэтому вариант
    // с числом внутри текста (таймауты, секунды, порты — обычный контент для
    // этого домена) терялся целиком. Фикс — `.+?` + lookahead "пробел(ы) +
    // цифры + `)`" — должен и захватить цифру внутри текста, и не сломать
    // границу с соседним вариантом.
    private let withDigitInsideOption = """
    # Тикет с цифрой внутри варианта

    - когда: 2026-09-27T02:00:00
    - от кого: demo
    - уровень: error
    - тревога: да

    ## Сводка (для отображения в приложении)
    ```
    demo
    ```

    ## Итог по устранению
    - канал telegram — (не исправлено, нужно ваше решение по вопросу выбора канала:
      1) переключить на резервный канал
      2) увеличить таймаут отправки до 30 секунд
      3) отключить проверку на 6 часов
      4) свой вариант)
    """

    func test_extractNumberedOptions_keepsOptionWithDigitInside() throws {
        let d = try XCTUnwrap(ServiceTicketMarkdownParser.parse(withDigitInsideOption))
        XCTAssertEqual(d.resolutionItems.count, 1)
        guard case .needsDecision(let options) = d.resolutionItems[0].status else {
            return XCTFail("expected needsDecision")
        }
        XCTAssertEqual(options, [
            "переключить на резервный канал",
            "увеличить таймаут отправки до 30 секунд",
            "отключить проверку на 6 часов"
        ])
    }

    // Critical #1 финального ревью LOCK-227: "сегодня" для запроса
    // `fetchInbox(date:)` должно быть локальным календарным днём устройства,
    // НЕ UTC. `ISO8601DateFormatter` по умолчанию отдаёт GMT — ровно в
    // 01:00 по Москве (UTC+3) это ещё 22:00 предыдущего дня по UTC, и наивный
    // расчёт запросил бы вчерашнюю дату, пропустив только что созданный тикет.
    func test_localDayString_usesLocalCalendarDayNotUTC() throws {
        var moscow = Calendar(identifier: .gregorian)
        moscow.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        // 2026-09-27T01:00:00 по Москве == 2026-09-26T22:00:00 UTC.
        let instant = try XCTUnwrap(utc.date(from: DateComponents(
            year: 2026, month: 9, day: 26, hour: 22, minute: 0, second: 0
        )))

        XCTAssertEqual(ServiceTicketDate.localDayString(for: instant, calendar: moscow), "2026-09-27")
        // Санитарная проверка: наивный UTC-расчёт для этого же момента
        // ошибочно отдал бы "26", а не "27" — именно этот класс багов и
        // исправляет `localDayString`.
        XCTAssertEqual(ServiceTicketDate.localDayString(for: instant, calendar: utc), "2026-09-26")
    }
}
