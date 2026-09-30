import Foundation

/// Единая ошибка сети/API. Сервер всегда отдаёт `{ "error": "человекочитаемое
/// сообщение" }` при не-2xx статусе (spec/API.md §1) — здесь это разобрано в
/// `.server(status:message:)` и именованных вариантах для частых кодов.
public enum APIError: Error, LocalizedError, Sendable {
    case transport(Error)
    case invalidResponse
    case decoding(Error)
    /// 401 — токен истёк/невалиден. Обработчик наверху (`SessionStore`) должен
    /// на этот случай сразу разлогинить и показать экран входа (spec §2.2:
    /// LAN-релогин веба нативному клиенту не подходит).
    case unauthorized(message: String)
    case forbidden(message: String)
    /// Чужой ресурс, недоступный по видимости, отдаёт 404 — сервер не
    /// подтверждает даже факт существования чужого объекта (spec §2.3).
    case notFound(message: String)
    /// Тоже 404, но совсем про другое: такого МАРШРУТА у сервера нет, и
    /// записи тут ни при чём. Раньше эти два случая были неразличимы, и
    /// владелец 15.09.2026 справедливо не понимал, почему приложение пишет
    /// «запись удалена» про живую запись. Отдельный случай нужен не только
    /// ради текста: по `notFound` строку списка можно смело считать
    /// протухшей и убрать, а по этой ошибке — ни в коем случае.
    case routeMissing(message: String)
    case conflict(message: String)
    case server(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .transport(let error): "Сеть недоступна: \(error.localizedDescription)"
        case .invalidResponse: "Сервер вернул неожиданный ответ"
        case .decoding(let error): "Не удалось разобрать ответ сервера: \(error.localizedDescription)"
        // Сервер на этих трёх отвечает служебной англоязычной заглушкой
        // («Not found», «Forbidden»), и она долетала прямо в баннер поверх
        // карточки — владелец 11.09.2026 увидел на экране «Not found».
        // Свой текст подставляем только вместо заглушки: осмысленное
        // сообщение сервера («нужен комментарий: что сделано» и прочие)
        // куда информативнее нашего и остаётся как есть.
        case .unauthorized(let message): Self.humanized(message, fallback: "Нужно войти заново")
        case .forbidden(let message): Self.humanized(message, fallback: "Недостаточно прав для этого действия")
        case .notFound(let message): Self.humanized(message, fallback: "Не найдено или нет доступа к этой записи")
        case .routeMissing(let message): message
        case .conflict(let message): message
        case .server(_, let message): message
        }
    }

    /// Заглушки сервера — короткие английские строки без кириллицы. Всё
    /// остальное он пишет по-русски и по делу.
    private static func humanized(_ message: String, fallback: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        let hasCyrillic = trimmed.range(of: "[а-яА-ЯёЁ]", options: .regularExpression) != nil
        return hasCyrillic ? trimmed : fallback
    }
}

/// Тело ошибки сервера. Основная форма — `{ "error": "..." }`, но когда
/// запрошенного маршрута на сервере нет, Fastify отвечает иначе:
/// `{ "message": "Route GET:/api/me not found", "error": "Not Found" }` —
/// и вся суть лежит в `message`, тогда как в `error` служебная заглушка.
/// Раньше читалось только `error`, поэтому настоящая причина («такого
/// адреса нет») до экрана не доезжала вовсе и подменялась нашей фразой про
/// удалённую запись.
struct APIErrorBody: Decodable {
    let error: String?
    let message: String?

    /// Самое содержательное из того, что прислал сервер.
    var bestMessage: String? {
        let candidates = [message, error]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // Осмысленный русский текст важнее служебной англоязычной заглушки.
        if let russian = candidates.first(where: {
            $0.range(of: "[а-яА-ЯёЁ]", options: .regularExpression) != nil
        }) { return russian }
        // Дальше — тот, что говорит о маршруте: он объясняет причину.
        if let route = candidates.first(where: { $0.contains("Route") }) { return route }
        return candidates.first
    }
}

/// Ответ вида `{ "ok": true }` — DELETE и некоторые служебные эндпоинты.
public struct APIOkResponse: Decodable, Sendable {
    public let ok: Bool
}
