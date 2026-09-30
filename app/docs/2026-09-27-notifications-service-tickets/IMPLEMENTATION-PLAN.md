# Тикеты сторонних сервисов в «Уведомлениях» — план реализации (v2)

> Исполнять по задачам: сначала красный тест, затем минимальная правка, затем проверка и отдельный коммит.

**Goal:** Расширить существующий экран «Уведомления» (`NotificationsScreen`)
подразделом «Сторонние сервисы» — карточки-тикеты из живого HTTP API на
`.110` (`http://192.168.1.110:5198`), с модалкой выбора решения по
нерешённым пунктам. Подраздел «Завершённые задачи» — Задача 7, источник
данных для него зависит от ответа владельца на открытый вопрос (см. спеку).

**Architecture:** Отдельный лёгкий HTTP-клиент `ServiceNotificationsClient`
(свой хост `.110:5198`, не тот же сервер что основной `APIClient`) отдаёт
список тикетов и сырой markdown; парсер разбирает markdown в
`ServiceTicketDetail` (метаданные + список пунктов «Итог по устранению»,
если сервер их уже дописал — на 27.09.2026 ещё не дописывает, Phase 4).
Компонент карточки и модалка решения — новые, изолированные от карточки
задачи. Существующий `NotificationsScreen` получает новую секцию поверх
текущего плоского списка, поведение старого списка не меняется.

**Tech Stack:** SwiftUI, `URLSession` (отдельный клиент), существующая
DesignSystem (`TFCard`, `TFSectionHeader`, `TFBottomSheet`/`.sheet`),
`APIClient.createComment` (`APIClient+Subtasks.swift:36`) для отправки
решения комментарием, XCTest, кадр симулятора.

**Спецификация:** [DESIGN.md](DESIGN.md) (v2 — читать целиком: там живой контракт backend и открытый вопрос).

## Global Constraints

- Backend живой, без авторизации: `http://192.168.1.110:5198` — проверено
  `curl` 27.09.2026. Не выдумывать другой адрес/порт.
- Никаких inline-кнопок — только текстовые строки-сноски (серая
  неактивная / красная активная) и один модальный диалог. Подтверждено
  дважды владельцем.
- Отправка решения — ТОЛЬКО через `APIClient.createComment(taskId:text:)`,
  никакой собственной submit-логики.
- Не трогать `ActivityScreen.swift`.
- Задача 7 (второй подраздел «Завершённые задачи») — не начинать, пока
  владелец не разрешил открытый вопрос в спеке. Задачи 1-6 от этого не
  зависят и выполняются независимо.
- Каждая задача — отдельный git-коммит.
- Задача 1 (реестр) — до первой правки Swift-файлов.

---

### Task 1: Открыть строку в реестре ограничений

**Files:** Modify: `AGENT-WORK-SCOPES.md`

- [ ] Добавить строку `IN_PROGRESS`, Lock ID `LOCK-227` (следующий свободный
  после `LOCK-226` — проверено `grep -oE "LOCK-[0-9]+" AGENT-WORK-SCOPES.md`
  27.09.2026), Scope ID `IOS-NOTIFICATIONS-SERVICE-TICKETS`, экран →
  элемент `Уведомления → подраздел «Сторонние сервисы»`, разрешённые файлы —
  список из Files всех задач 2-6 этого плана плюс сами доки. Проверка:
  `xcodebuild` BUILD SUCCEEDED + кадр симулятора экрана «Уведомления».
- [ ] `git add AGENT-WORK-SCOPES.md && git commit -m "docs: открыть LOCK-227 на тикеты сторонних сервисов"`

---

### Task 2: Модели данных тикета

**Files:**
- Create: `Sources/Core/Models/ServiceNotificationTicket.swift`
- Test: `Tests/ServiceNotificationTicketTests.swift`

**Interfaces:**
- Produces: `ServiceTicketSummary` (`Codable, Identifiable, Sendable, Hashable`;
  `id, path, title, ts, source, level, hasTriage: Bool, snippet, links: [String]`),
  `ServiceTicketInboxResponse` (`Decodable`; `date, count, items: [ServiceTicketSummary]`),
  `ServiceTicketResolutionStatus` (`enum: .fixed, .unresolved(reason: String), .needsDecision(options: [String])`),
  `ServiceTicketResolutionItem` (`Identifiable, Sendable, Hashable`; `id, problem, status, taskId: String?`),
  `ServiceTicketDetail` (`Sendable, Hashable`; `title, when, from, level, isAlarm, summaryText, notWorkingText: String?, diagnosticTaskId: String?, resolutionItems: [ServiceTicketResolutionItem]`).

- [ ] **Шаг 1: Тест на декодирование реального конверта**

```swift
// Tests/ServiceNotificationTicketTests.swift
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
```

- [ ] **Шаг 2:** `xcodebuild test -project TaskFlow.xcodeproj -scheme TaskFlow -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TaskFlowTests/ServiceNotificationTicketTests` → FAIL (типов нет).

- [ ] **Шаг 3: Реализовать модели**

```swift
// Sources/Core/Models/ServiceNotificationTicket.swift
import Foundation

/// Контракт живого API `.110` — DESIGN.md.
/// Base URL `http://192.168.1.110:5198`, без авторизации (LAN).
public struct ServiceTicketSummary: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let path: String
    public let title: String
    public let ts: String
    public let source: String
    public let level: String
    public let hasTriage: Bool
    public let snippet: String
    public let links: [String]

    enum CodingKeys: String, CodingKey {
        case id, path, title, ts, source, level
        case hasTriage = "has_triage"
        case snippet, links
    }
}

public struct ServiceTicketInboxResponse: Decodable, Sendable {
    public let date: String
    public let count: Int
    public let items: [ServiceTicketSummary]
}

/// Статус одного пункта из блока "## Итог по устранению" (Phase 4 backend —
/// на 27.09.2026 сервер этот блок ЕЩЁ НЕ дописывает; парсится по эталонному
/// шаблону `.110:~/Проекты/taskflow-уведомления/format/svodka-template.md`,
/// перепроверить на первом живом файле, когда Phase 4 будет сделана).
public enum ServiceTicketResolutionStatus: Sendable, Hashable {
    case fixed
    case unresolved(reason: String)
    /// options — 1-3 предложенных варианта из текста; "4) свой вариант" — не
    /// сюда, это всегда отдельное поле ввода в модалке (Task 6).
    case needsDecision(options: [String])
}

public struct ServiceTicketResolutionItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let problem: String
    public let status: ServiceTicketResolutionStatus
    /// Задача TaskFlow, к которой уйдёт комментарий/на которую ведёт "(исправлено)".
    /// nil, если ссылку не удалось найти рядом с пунктом — тогда UI не делает тап активным.
    public let taskId: String?

    public init(problem: String, status: ServiceTicketResolutionStatus, taskId: String?) {
        self.id = problem
        self.problem = problem
        self.status = status
        self.taskId = taskId
    }
}

public struct ServiceTicketDetail: Sendable, Hashable {
    public let title: String
    public let when: String
    public let from: String
    public let level: String
    public let isAlarm: Bool
    public let summaryText: String
    public let notWorkingText: String?
    public let diagnosticTaskId: String?
    public let resolutionItems: [ServiceTicketResolutionItem]

    public init(title: String, when: String, from: String, level: String, isAlarm: Bool,
                summaryText: String, notWorkingText: String?, diagnosticTaskId: String?,
                resolutionItems: [ServiceTicketResolutionItem]) {
        self.title = title
        self.when = when
        self.from = from
        self.level = level
        self.isAlarm = isAlarm
        self.summaryText = summaryText
        self.notWorkingText = notWorkingText
        self.diagnosticTaskId = diagnosticTaskId
        self.resolutionItems = resolutionItems
    }
}

extension ServiceTicketDetail: Identifiable {
    public var id: String { title + when }
}
```

- [ ] **Шаг 4:** прогнать тест из шага 2 → PASS.
- [ ] **Шаг 5:** `git add Sources/Core/Models/ServiceNotificationTicket.swift Tests/ServiceNotificationTicketTests.swift && git commit -m "feat(notifications): модели тикетов сторонних сервисов (живой контракт .110)"`

---

### Task 3: Парсер markdown-сводки

**Files:**
- Create: `Sources/Core/Networking/ServiceTicketMarkdownParser.swift`
- Test: `Tests/ServiceTicketMarkdownParserTests.swift`

**Interfaces:**
- Consumes: типы из Task 2.
- Produces: `ServiceTicketMarkdownParser.parse(_ raw: String) -> ServiceTicketDetail?`.

- [ ] **Шаг 1: Тест на живом примере (метаданные+сводка) и на фикстуре Phase-4-блока**

```swift
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
}
```

- [ ] **Шаг 2:** прогнать → FAIL (тип не существует).

- [ ] **Шаг 3: Реализовать парсер**

```swift
// Sources/Core/Networking/ServiceTicketMarkdownParser.swift
import Foundation

/// Разбирает markdown-сводку `.110` — DESIGN.md.
/// Метаданные и блок «Сводка» — живой, проверенный формат. Блок
/// «## Итог по устранению» — Phase 4 backend, на 27.09.2026 сервер его
/// ещё не пишет; парсинг best-effort по эталонному шаблону, перепроверить
/// на первом живом файле.
public enum ServiceTicketMarkdownParser {
    public static func parse(_ raw: String) -> ServiceTicketDetail? {
        let lines = raw.components(separatedBy: .newlines)

        guard let title = lines.first(where: { $0.hasPrefix("# ") })?
            .dropFirst(2).trimmingCharacters(in: .whitespaces) else { return nil }

        func metaValue(_ key: String) -> String? {
            guard let line = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- \(key):") }) else { return nil }
            return line.split(separator: ":", maxSplits: 1).dropFirst().first
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }

        guard let when = metaValue("когда"),
              let from = metaValue("от кого"),
              let level = metaValue("уровень"),
              let alarmRaw = metaValue("тревога") else { return nil }
        let isAlarm = alarmRaw.lowercased() == "да"

        let summaryText = extractFencedBlock(lines, afterHeading: "## Сводка")
        let notWorkingText = extractNotWorkingLine(summaryText)
        let diagnosticTaskId = firstTaskLink(in: summaryText)
        let resolutionItems = extractResolutionItems(lines)

        return ServiceTicketDetail(
            title: title, when: when, from: from, level: level, isAlarm: isAlarm,
            summaryText: summaryText, notWorkingText: notWorkingText,
            diagnosticTaskId: diagnosticTaskId, resolutionItems: resolutionItems
        )
    }

    /// `tf://task/<id>` встречается как обычный текст внутри markdown — не
    /// системная URL-схема, приложение сам разбирает и открывает через
    /// внутреннюю навигацию (`route = .taskDetail(taskID:)`), регистрировать
    /// `tf://` в Info.plist не нужно.
    static func firstTaskLink(in text: String) -> String? {
        guard let range = text.range(of: #"tf://task/([\w-]+)"#, options: .regularExpression) else { return nil }
        return String(text[range]).replacingOccurrences(of: "tf://task/", with: "")
    }

    private static func extractFencedBlock(_ lines: [String], afterHeading: String) -> String {
        guard let headingIdx = lines.firstIndex(where: { $0.hasPrefix(afterHeading) }) else { return "" }
        let rest = lines[(headingIdx + 1)...]
        guard let fenceStart = rest.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }) else { return "" }
        let afterFence = lines[(fenceStart + 1)...]
        guard let fenceEnd = afterFence.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }) else { return "" }
        return lines[(fenceStart + 1)..<fenceEnd].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractNotWorkingLine(_ summary: String) -> String? {
        let lines = summary.components(separatedBy: .newlines)
        guard let idx = lines.firstIndex(where: { $0.contains("Не отработали в штатном режиме") }) else { return nil }
        return lines[(idx + 1)...].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Собирает пункты "## Итог по устранению" — каждый пункт начинается с
    /// "- " и может продолжаться на нескольких отступленных строках (см.
    /// вариант "нужно ваше решение..." в шаблоне), пока не встретится
    /// следующий "- " или конец блока.
    private static func extractResolutionItems(_ lines: [String]) -> [ServiceTicketResolutionItem] {
        guard let headingIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("## Итог по устранению") }) else {
            return []
        }
        var blocks: [String] = []
        var current: String?
        for line in lines[(headingIdx + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("##") { break }
            if trimmed.hasPrefix("- ") {
                if let c = current { blocks.append(c) }
                current = String(trimmed.dropFirst(2))
            } else if !trimmed.isEmpty, current != nil {
                current! += " " + trimmed
            } else if trimmed.isEmpty, current != nil, !blocks.contains(current!) {
                // Пустая строка внутри многострочного пункта — ещё не конец,
                // граница — следующий "- " или "##"; продолжаем накопление.
                continue
            }
        }
        if let c = current { blocks.append(c) }

        return blocks.compactMap { block -> ServiceTicketResolutionItem? in
            guard let dashRange = block.range(of: " — (") else { return nil }
            let problem = String(block[block.startIndex..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            var statusText = String(block[dashRange.upperBound...])
            if statusText.hasSuffix(")") { statusText.removeLast() }
            let taskId = firstTaskLink(in: block)

            if statusText == "исправлено" {
                return ServiceTicketResolutionItem(problem: problem, status: .fixed, taskId: taskId)
            }
            if statusText.contains("нужно ваше решение") {
                let options = extractNumberedOptions(statusText)
                return ServiceTicketResolutionItem(problem: problem, status: .needsDecision(options: options), taskId: taskId)
            }
            if statusText.hasPrefix("не исправлено:") {
                let reason = statusText.replacingOccurrences(of: "не исправлено:", with: "").trimmingCharacters(in: .whitespaces)
                return ServiceTicketResolutionItem(problem: problem, status: .unresolved(reason: reason), taskId: taskId)
            }
            return nil
        }
    }

    /// "1) ... 2) ... 3) ... 4) свой вариант" → ["...", "...", "..."] (без пункта 4 — он всегда отдельное поле ввода в модалке).
    private static func extractNumberedOptions(_ text: String) -> [String] {
        let pattern = #"(\d+)\)\s*([^0-9)]+?)(?=\s*\d+\)|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var options: [String] = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let numberRange = Range(match.range(at: 1), in: text),
                  let textRange = Range(match.range(at: 2), in: text) else { return }
            let number = Int(text[numberRange]) ?? 0
            guard number <= 3 else { return } // "4) свой вариант" — не предложенный вариант
            let value = text[textRange].trimmingCharacters(in: CharacterSet(charactersIn: " ,)"))
            if !value.isEmpty { options.append(value) }
        }
        return options
    }
}
```

- [ ] **Шаг 4:** прогнать тест из шага 2 → PASS (все случаи).
- [ ] **Шаг 5:** `git add Sources/Core/Networking/ServiceTicketMarkdownParser.swift Tests/ServiceTicketMarkdownParserTests.swift && git commit -m "feat(notifications): парсер markdown-сводок, включая Phase-4 блок устранения"`

---

### Task 4: HTTP-клиент живого API `.110`

**Files:**
- Create: `Sources/Features/Directory/Support/ServiceNotificationsClient.swift`

**Interfaces:**
- Consumes: `ServiceTicketInboxResponse`, `ServiceTicketSummary` (Task 2).
- Produces: `ServiceNotificationsClient.fetchInbox(date: String) async throws -> [ServiceTicketSummary]`,
  `ServiceNotificationsClient.fetchRaw(path: String) async throws -> String` (используются в Task 7).

- [ ] **Шаг 1: Реализовать клиент**

Отдельный клиент, не расширение `APIClient` — другой хост
(`192.168.1.110:5198`, без `/api`-префикса, без токена), см. Global
Constraints. `APIClient.baseURL` (порт 3001, с авторизацией) сюда не
подходит.

```swift
// Sources/Features/Directory/Support/ServiceNotificationsClient.swift
import Foundation

/// HTTP-клиент отдельного сервиса `notifications-api.service` на `.110`
/// (`http://192.168.1.110:5198`) — НЕ тот же сервер, что основной
/// `APIClient` (порт 3001, с Bearer-токеном). Без авторизации, LAN.
/// DESIGN.md.
public struct ServiceNotificationsClient: Sendable {
    public static let baseURL = URL(string: "http://192.168.1.110:5198")!

    private let session: URLSession

    public init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
    }

    public enum ClientError: Error {
        case badStatus(Int)
        case decoding(Error)
    }

    public func fetchInbox(date: String) async throws -> [ServiceTicketSummary] {
        var url = Self.baseURL.appendingPathComponent("notifications/inbox")
        url.append(queryItems: [URLQueryItem(name: "date", value: date)])
        let (data, response) = try await session.data(from: url)
        try Self.checkStatus(response)
        do {
            return try JSONDecoder().decode(ServiceTicketInboxResponse.self, from: data).items
        } catch {
            throw ClientError.decoding(error)
        }
    }

    public func fetchRaw(path: String) async throws -> String {
        var url = Self.baseURL.appendingPathComponent("notifications/raw")
        url.append(queryItems: [URLQueryItem(name: "path", value: path)])
        let (data, response) = try await session.data(from: url)
        try Self.checkStatus(response)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ClientError.badStatus(code)
        }
    }
}

private extension URL {
    mutating func append(queryItems: [URLQueryItem]) {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return }
        components.queryItems = queryItems
        if let url = components.url { self = url }
    }
}
```

Примечание для исполнителя: перед сборкой свериться, что
`session.data(from:)` (async API `URLSession`, iOS 15+) доступен на
deployment target проекта (`grep -n "IPHONEOS_DEPLOYMENT_TARGET" project.yml`)
— в этом кодбейсе он уже используется где-то (проверить
`grep -rn "session.data(from:" Sources`), если нет — заменить на
`session.data(for: URLRequest(url: url))`, семантика та же.

- [ ] **Шаг 2: Собрать проект**

```bash
cd "$HOME/Проекты/TaskFlowNativeBuild" && xcodegen generate && xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build_sim build
```
Expected: BUILD SUCCEEDED.

- [ ] **Шаг 3: Живая ручная проверка (не автотест — сетевой вызов на реальный `.110`)**

Добавить временный `print`/breakpoint или отдельный debug-скрипт не нужно —
достаточно, что `curl` уже подтвердил контракт (Task 2 тест целиком на
живом примере). В Task 7 будет живая проверка через сам экран.

- [ ] **Шаг 4:** `git add Sources/Features/Directory/Support/ServiceNotificationsClient.swift && git commit -m "feat(notifications): HTTP-клиент живого API .110:5198"`

---

### Task 5: Компонент карточки-тикета

**Files:**
- Create: `Sources/Features/Directory/Support/NotificationTicketCard.swift`

**Interfaces:**
- Consumes: `ServiceTicketSummary`, `ServiceTicketDetail`, `ServiceTicketResolutionItem`, `ServiceTicketResolutionStatus` (Task 2).
- Produces: `NotificationTicketCard` (`View`; `init(summary:, detail:, onOpenTask: (String) -> Void, onTapResolutionItem: (ServiceTicketResolutionItem) -> Void)`).

- [ ] **Шаг 1: Реализовать карточку**

```swift
// Sources/Features/Directory/Support/NotificationTicketCard.swift
import SwiftUI

/// Карточка-тикет сводки стороннего сервиса — визуально ОТДЕЛЬНАЯ от
/// карточки-задачи. Строки "Итог по устранению" — текстовые сноски
/// (серая неактивная / красная активная), НЕ inline-кнопки.
struct NotificationTicketCard: View {
    let summary: ServiceTicketSummary
    let detail: ServiceTicketDetail?
    let onOpenTask: (String) -> Void
    let onTapResolutionItem: (ServiceTicketResolutionItem) -> Void

    var body: some View {
        TFCard(padding: TFSpacing.md) {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                Text(detail?.title ?? summary.title).tfText(.action).fontWeight(.semibold)
                metaRow

                if let summaryText = detail?.summaryText, !summaryText.isEmpty {
                    Text(summaryText).tfText(.meta).foregroundStyle(Color.tfSub)
                } else {
                    Text(summary.snippet).tfText(.meta).foregroundStyle(Color.tfSub)
                }

                if let notWorking = detail?.notWorkingText {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Не отработали в штатном режиме").tfText(.meta).foregroundStyle(Color.tfRed)
                        Text(notWorking).tfText(.meta).foregroundStyle(Color.tfSub)
                    }
                }

                if let taskId = detail?.diagnosticTaskId {
                    Button { onOpenTask(taskId) } label: {
                        Text("Карточка диагностики →").tfText(.meta).foregroundStyle(Color.tfSub)
                    }
                    .buttonStyle(TFTapScaleStyle())
                }

                if let items = detail?.resolutionItems, !items.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Итог по устранению").tfText(.meta).foregroundStyle(Color.tfDim)
                        ForEach(items) { item in
                            resolutionRow(item)
                        }
                    }
                }
            }
        }
        .overlay {
            if detail?.isAlarm == true || summary.level == "error" {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.tfRed, lineWidth: 1.5)
            }
        }
    }

    @ViewBuilder
    private func resolutionRow(_ item: ServiceTicketResolutionItem) -> some View {
        switch item.status {
        case .fixed:
            Button {
                if let taskId = item.taskId { onOpenTask(taskId) }
            } label: {
                Text("\(item.problem) — (исправлено)").tfText(.meta).foregroundStyle(Color.tfDim)
            }
            .buttonStyle(TFTapScaleStyle())
            .disabled(item.taskId == nil)
        case .unresolved, .needsDecision:
            Button {
                onTapResolutionItem(item)
            } label: {
                Text(resolutionRowText(item)).tfText(.meta).foregroundStyle(Color.tfRed).underline()
            }
            .buttonStyle(TFTapScaleStyle())
        }
    }

    private func resolutionRowText(_ item: ServiceTicketResolutionItem) -> String {
        switch item.status {
        case .fixed: return "\(item.problem) — (исправлено)"
        case .unresolved(let reason): return "\(item.problem) — (не исправлено: \(reason))"
        case .needsDecision: return "\(item.problem) — (не исправлено, нужно ваше решение)"
        }
    }

    private var metaRow: some View {
        let d = detail
        return VStack(alignment: .leading, spacing: 2) {
            metaLine("когда", d?.when ?? summary.ts)
            metaLine("от кого", d?.from ?? summary.source)
            metaLine("уровень", d?.level ?? summary.level)
            metaLine("тревога", (d?.isAlarm ?? summary.hasTriage) ? "да" : "нет")
        }
    }

    private func metaLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(label):").tfText(.meta).foregroundStyle(Color.tfDim)
            Text(value).tfText(.meta).foregroundStyle(Color.tfSub)
        }
    }
}
```

- [ ] **Шаг 2:** собрать (`xcodebuild build` из Task 4 Шаг 2) → BUILD SUCCEEDED.
- [ ] **Шаг 3:** `git add Sources/Features/Directory/Support/NotificationTicketCard.swift && git commit -m "feat(notifications): карточка-тикет с текстовыми сносками устранения"`

---

### Task 6: Модалка «Что делаем дальше?»

**Files:**
- Create: `Sources/Features/Directory/Support/ServiceTicketResolutionSheet.swift`

**Interfaces:**
- Consumes: `ServiceTicketResolutionItem`, `ServiceTicketResolutionStatus` (Task 2),
  `APIClient.createComment(taskId:text:attachmentIds:) async throws -> ApiComment` (существует).
- Produces: `ServiceTicketResolutionSheet` (`View`; `init(item: ServiceTicketResolutionItem, taskId: String, onSubmitted: () -> Void)`).

- [ ] **Шаг 1: Реализовать шторку**

```swift
// Sources/Features/Directory/Support/ServiceTicketResolutionSheet.swift
import SwiftUI

/// Модалка по тапу на строку-сноску "(не исправлено...)" — НЕ inline-кнопка.
/// Единственное действие — комментарий к задаче через `createComment`.
struct ServiceTicketResolutionSheet: View {
    let item: ServiceTicketResolutionItem
    let taskId: String
    let onSubmitted: () -> Void

    @State private var selectedOption: Int?
    @State private var customText: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    private let apiClient = APIClient()

    private var options: [String] {
        if case .needsDecision(let opts) = item.status { return opts }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            Text("Что делаем дальше?").tfText(.action).fontWeight(.semibold)
            Text(item.problem).tfText(.body).foregroundStyle(Color.tfSub)

            ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                Button {
                    selectedOption = idx
                    customText = option
                } label: {
                    HStack {
                        Image(systemName: selectedOption == idx ? "largecircle.fill.circle" : "circle")
                        Text(option).tfText(.body)
                    }
                }
                .buttonStyle(TFTapRowStyle())
            }

            Text("Свой вариант:").tfText(.meta).foregroundStyle(Color.tfDim)
            TextField("Что делать?", text: $customText, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            TFErrorBanner(errorMessage, variant: .inline)

            Button {
                Task { await submit() }
            } label: {
                if isSubmitting { ProgressView() } else { Text("Отправить") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
        }
        .padding(TFSpacing.lg)
        .task {
            if customText.isEmpty {
                customText = options.first ?? {
                    if case .unresolved(let reason) = item.status { return reason }
                    return ""
                }()
            }
        }
    }

    private func submit() async {
        let text = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            _ = try await apiClient.createComment(taskId: taskId, text: text)
            onSubmitted()
        } catch {
            errorMessage = "Не удалось отправить комментарий"
        }
    }
}
```

Примечание: используется системный `Button(.borderedProminent)`/`TextField`
вместо `TFButton`/`TFTextField`, потому что их точные сигнатуры не
подтверждены чтением файла в рамках этого плана — если в проекте есть
`TFButton`/`TFTextField` с подходящей сигнатурой, исполнитель может
заменить (свериться `grep -n "public init" Sources/DesignSystem/Components/TFButton.swift Sources/DesignSystem/Components/TFTextField.swift` перед заменой), но это не обязательно для правильной работы.

- [ ] **Шаг 2:** собрать → BUILD SUCCEEDED.
- [ ] **Шаг 3:** `git add Sources/Features/Directory/Support/ServiceTicketResolutionSheet.swift && git commit -m "feat(notifications): модалка выбора решения по нерешённому пункту"`

---

### Task 7: Встраивание в NotificationsScreen

**Files:** Modify: `Sources/Features/Directory/NotificationsScreen.swift`

**Решено 27.09.2026 (владелец, вариант А):** «Завершённые задачи» — простая
ссылка (навигационная строка) на уже существующий `ActivityScreen`
(`route = .activity`, `AppRoute.swift:46`, `RouteDestinationView.swift:83`).
Никакой новой выборки данных, никакой агрегации — не редактируем
`ActivityScreen.swift`, только открываем его.

**Interfaces:** Consumes: `NotificationTicketCard`, `ServiceTicketResolutionSheet` (Task 5/6),
`ServiceNotificationsClient` (Task 4), `ServiceTicketMarkdownParser` (Task 3).

- [ ] **Шаг 1: Состояние**

```swift
    @State private var serviceTickets: [ServiceTicketSummary] = []
    @State private var serviceTicketDetails: [String: ServiceTicketDetail] = [:]
    @State private var serviceTicketsError: String?
    @State private var resolutionSheetItem: ServiceTicketResolutionItem?
    @State private var resolutionSheetTaskId: String?
    private let serviceClient = ServiceNotificationsClient()
```

- [ ] **Шаг 2:** `.task`/`.refreshable` вызывают `await loadServiceTickets()` вдобавок к `notificationStore.load()` (как в v1 плана — без изменений в этой части).

- [ ] **Шаг 3:** секция «Сторонние сервисы» в теле `ScrollView` — как в v1
  плана, `NotificationTicketCard(summary:, detail:, onOpenTask: { route = .taskDetail(taskID: $0) }, onTapResolutionItem: { item in resolutionSheetItem = item; resolutionSheetTaskId = item.taskId ?? detail-level fallback })`.

- [ ] **Шаг 4:**

```swift
    private func loadServiceTickets() async {
        serviceTicketsError = nil
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        do {
            let list = try await serviceClient.fetchInbox(date: String(today))
            serviceTickets = list
            for summary in list where serviceTicketDetails[summary.id] == nil {
                let raw = try await serviceClient.fetchRaw(path: summary.path)
                if let detail = ServiceTicketMarkdownParser.parse(raw) {
                    serviceTicketDetails[summary.id] = detail
                }
            }
        } catch {
            serviceTicketsError = "Не удалось загрузить сводки сторонних сервисов"
        }
    }
```

- [ ] **Шаг 5:** `.sheet(item: $resolutionSheetItem)` презентует `ServiceTicketResolutionSheet`, аналогично v1.

- [ ] **Шаг 6:** секция «Завершённые задачи» — одна навигационная строка,
  визуально в стиле существующих строк экрана (например, переиспользовать
  подход `notificationRow`/`TFListRow`), текст «Завершённые задачи», тап →
  `route = .activity`. Никакой фильтрации/данных не подгружается для этой
  строки — это чистая ссылка.

```swift
    Button {
        route = .activity
    } label: {
        HStack {
            Text("Завершённые задачи").tfText(.row).foregroundStyle(Color.tfText)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: TFIconSize.sm)).foregroundStyle(Color.tfDim)
        }
        .padding(.horizontal, TFSpacing.md)
        .padding(.vertical, TFSpacing.sm + 2)
        .contentShape(Rectangle())
    }
    .buttonStyle(TFTapRowStyle())
```

Разместить эту строку как отдельную секцию (свой `TFSectionHeader("Завершённые задачи")`
не нужен — заголовок уже в самой строке; обернуть в `TFCard(padding: 0) { ... }`
для визуального единства с другими списками экрана) между секцией «Сторонние
сервисы» и остальными уведомлениями.

- [ ] **Шаг 7:** собрать + кадр симулятора экрана «Уведомления» с секцией
  «Сторонние сервисы», реальными живыми тикетами с `.110` (сегодняшняя дата,
  минимум 3 штуки по состоянию на 27.09.2026).

- [ ] **Шаг 8:** `git add Sources/Features/Directory/NotificationsScreen.swift && git commit -m "feat(notifications): секция «Сторонние сервисы» на живом API .110"`

---

### Task 8: Завершение — реестр в REVIEW

- [ ] Перевести `LOCK-227` в `REVIEW`, дописать факты проверки (BUILD SUCCEEDED
  + путь к кадру симулятора), отдельно указать: секция «Завершённые задачи»
  реализована по варианту, решённому владельцем в Task 7; парсер блока
  «Итог по устранению» не проверен на живых данных backend (Phase 4 не
  реализована на 27.09.2026).
- [ ] `git add AGENT-WORK-SCOPES.md && git commit -m "docs: LOCK-227 → REVIEW"`

---

## Self-Review

**Покрытие:** «Сторонние сервисы» (живой API, парсер, карточка, модалка) —
Задачи 2-6, полностью проверяемо уже сейчас (backend живой). «Завершённые
задачи» — Задача 7, явно заблокирована открытым вопросом, не угадывается.
Никаких inline-кнопок ни в одном компоненте — проверено в Task 5/6.

**Согласованность типов:** `ServiceTicketResolutionItem`/`ServiceTicketResolutionStatus`
объявлены в Task 2, используются идентично в Task 3 (парсер), Task 5
(карточка), Task 6 (модалка) — имена полей (`problem`, `status`, `taskId`)
не меняются между задачами.

**Заглушки:** единственная сознательная неопределённость — блок «Итог по
устранению» не существует на живом backend (Phase 4) — помечена везде, где
встречается, тестируется на сконструированной фикстуре с явным
комментарием, не заявляется как проверенная на живых данных.

---

Plan complete. Два варианта выполнения (без изменений от v1):
1. **Subagent-Driven (рекомендую)** — свежий субагент на каждую задачу.
2. **Inline Execution** — пачками в этой сессии.
