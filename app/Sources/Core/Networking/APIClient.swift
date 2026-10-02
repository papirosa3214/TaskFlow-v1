import Foundation
import os

/// HTTP-клиент TaskFlow поверх `URLSession` (async/await) — spec/API.md §1-2.
///
/// Правила контракта, зашитые здесь:
/// - Базовый адрес `http://192.168.1.110:3001`, JSON-эндпоинты — с префиксом
///   `/api`; исключение — `/ws` (реалтайм, `RealtimeClient`) и загрузка/
///   скачивание сырых байтов, у которых свой путь без общего префикса тела.
/// - Один и тот же заголовок `Authorization: Bearer <значение>` для JWT и
///   api_token — сервер сам разбирает, что прислано (§2). Токен читается из
///   `KeychainService` на каждый запрос, а не хранится в клиенте — так
///   `APIClient` не тянет за собой состояние сессии/DI-цикл с `SessionStore`.
/// - Ошибка сервера всегда `{ "error": "..." }` при не-2xx (§1) — разбирается
///   в `APIError`. На 401 клиент чистит токен и рассылает уведомление, чтобы
///   `SessionStore` мог сразу разлогинить (§2.2: LAN-релогин веба нативу не
///   подходит, только «на выход»).
public final class APIClient: Sendable {
    public static let baseURL = ProcessInfo.processInfo.environment["TASKFLOW_LINEAR_CARD_DEMO"] == "1"
        ? URL(string: "http://127.0.0.1:3307")!
        : URL(string: "http://192.168.1.110:3001")!

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Диагностический логгер — виден в Console.app при подключении iPhone
    /// к Mac (фильтр по subsystem `com.taskflow.apiclient`) и в Xcode console.
    /// Уровень намеренно `.debug`: всё сетевое взаимодействие логируется без
    /// участия прод-логов уровня `.info`/`.error`.
    private let logger = Logger(
        subsystem: "com.taskflow.apiclient",
        category: "request"
    )

    public init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - JSON-запросы

    /// Тело — любой `Encodable` (обычно `[String: JSONValue]` для PATCH,
    /// строго типизированная структура для POST, см. `Encodable`-обёртки в
    /// доменных `APIClient+*.swift`).
    @discardableResult
    public func request<Response: Decodable>(
        _ method: HTTPMethodKind,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> Response {
        let request = try buildRequest(method: method, path: path, query: query, body: body, timeout: timeout)
        let (data, http) = try await send(request)
        try Self.throwIfError(status: http.statusCode, data: data, request: request)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Вариант без ожидаемого тела ответа (сервер отвечает пустым телом) —
    /// на практике в этом API не встречен (везде минимум `{ok:true}`), но
    /// оставлен для полноты интерфейса.
    public func requestVoid(
        _ method: HTTPMethodKind,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil
    ) async throws {
        let request = try buildRequest(method: method, path: path, query: query, body: body)
        let (data, http) = try await send(request)
        try Self.throwIfError(status: http.statusCode, data: data, request: request)
    }

    private func buildRequest(
        method: HTTPMethodKind,
        path: String,
        query: [URLQueryItem],
        body: (any Encodable)?,
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("/api" + path),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidResponse }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        // Долгие AI-операции (постановка большого текста локальной моделью)
        // идут десятки секунд — дефолтных 60с не хватает, и запрос обрывается
        // с «не удалось», хотя сервер доводит работу до конца. Явный таймаут
        // для таких маршрутов.
        if let timeout { request.timeoutInterval = timeout }
        Self.applyIdentity(to: &request)
        // Выбор серверной модели приложения — необязательная подсказка серверу;
        // читается только там, где модель реально уместна (см. AIServerModelSetting).
        if let model = AIServerModelSetting.selected {
            request.setValue(model, forHTTPHeaderField: "X-Ollama-Model")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        // Диагностика: логируем method/URL/заголовки (Authorization
        // маскируется как `Bearer ***`, чтобы токен не утекал в логи).
        logger.debug("→ \(method.rawValue, privacy: .public) \(url.absoluteString, privacy: .public) headers=\(Self.sanitizedHeaders(from: request), privacy: .public)")
        return request
    }

    // MARK: - Сырые байты (вложения/аватарки/аудио — spec §1, §5.10, §5.12)

    /// Загрузка файла сырыми байтами, БЕЗ multipart: тело = сам файл,
    /// `Content-Type` = реальный MIME, имя — в query `?name=`.
    @discardableResult
    public func uploadRaw<Response: Decodable>(
        path: String,
        query: [URLQueryItem],
        data: Data,
        mime: String
    ) async throws -> Response {
        guard var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("/api" + path),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidResponse }
        components.queryItems = query
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethodKind.post.rawValue
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        Self.applyIdentity(to: &request)
        request.httpBody = data

        let (responseData, http) = try await send(request)
        try Self.throwIfError(status: http.statusCode, data: responseData, request: request)
        do {
            return try decoder.decode(Response.self, from: responseData)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Скачивание файла — сырые байты. `GET /attachments/:id` требует
    /// `Authorization`, поэтому НЕ годится напрямую в `AsyncImage(url:)`
    /// (тот не умеет слать заголовки) — вызывающая сторона сама решает, что
    /// делать с байтами (превью, сохранение, показ через `UIImage(data:)`).
    /// `path` — полный путь ОТ `/api` (например `/attachments/\(id)`).
    public func downloadRaw(path: String) async throws -> Data {
        guard let url = URL(string: Self.baseURL.absoluteString + "/api" + path) else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        Self.applyIdentity(to: &request)
        let (data, http) = try await send(request)
        try Self.throwIfError(status: http.statusCode, data: data, request: request)
        return data
    }

    /// `GET /avatars/:name` — единственный ПУБЛИЧНЫЙ файловый эндпоинт (без
    /// авторизации, spec §5.10), поэтому обычному `AsyncImage(url:)` он
    /// годится напрямую — возвращаем готовый `URL`, без обёртки в запрос.
    public static func publicAvatarURL(name: String) -> URL {
        baseURL.appendingPathComponent("/api/avatars/\(name)")
    }

    // MARK: - Транспорт

    /// Кто спрашивает: признак приложения и ключ. Общий для ВСЕХ запросов —
    /// раньше признак ставил только `buildRequest`, и сырые запросы
    /// (голосовые, вложения) при входе без пароля получали 401, а 401 стирал
    /// сессию (LOCK-209).
    ///
    /// Признак «это приложение, а не скрипт»: по нему сервер пускает вход
    /// без пароля из домашней сети (`looksLikeBrowser` в server/src/auth.ts).
    /// Браузер там опознаётся по своим заголовкам, у нативного клиента их нет.
    private static func applyIdentity(to request: inout URLRequest) {
        request.setValue("ios-native", forHTTPHeaderField: "X-TaskFlow-Client")
        if let token = KeychainService.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let started = Date()
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            // Диагностика: статус, X-Request-ID (если сервер его выставил —
            // по нему лог с iPhone сопоставляется с серверным), длительность.
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            let reqId = http.value(forHTTPHeaderField: "X-Request-ID") ?? "-"
            logger.debug("← \(http.statusCode) \(request.httpMethod ?? "?") \(request.url?.path ?? "", privacy: .public) reqId=\(reqId, privacy: .public) \(elapsedMs)ms")
            return (data, http)
        } catch let error as APIError {
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            logger.error("⌀ transport error \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "", privacy: .public) после \(elapsedMs)ms: \(String(describing: error), privacy: .public)")
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            // SwiftUI пересоздаёт `.task`/`.refreshable` чаще, чем ждёт их
            // завершения — предыдущий запрос отменяется штатно, это не сбой
            // сети. Раньше это заворачивалось в `APIError.transport` и
            // владелец видел баннер «Сеть недоступна: cancelled» на ровном
            // месте (тот же класс бага уже чинили точечно в
            // TaskFormScreen.swift). Отдаём настоящую `CancellationError`,
            // чтобы вызывающий код мог её молча проигнорировать.
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            logger.error("⌀ transport cancelled \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "", privacy: .public) после \(elapsedMs)ms")
            throw CancellationError()
        } catch {
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            logger.error("⌀ transport throw \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "", privacy: .public) после \(elapsedMs)ms: \(error.localizedDescription, privacy: .public)")
            throw APIError.transport(error)
        }
    }

    private static func throwIfError(status: Int, data: Data, request: URLRequest? = nil) throws {
        guard !(200...299).contains(status) else { return }
        // Диагностика: все не-2xx логируются с телом первого килобайта —
        // этого хватает, чтобы увидеть JSON `{...}` или HTML-страницу сервера.
        let preview = Self.bodyPreview(data, limit: 1024)
        let what = describe(request)
        Logger(
            subsystem: "com.taskflow.apiclient",
            category: "request"
        ).error("✗ \(status) \(what.isEmpty ? "<n/a>" : what, privacy: .public) body=\(preview, privacy: .public)")
        let body = try? JSONDecoder().decode(APIErrorBody.self, from: data)
        let raw = body?.bestMessage ?? "Сервер ответил кодом \(status)"
        switch status {
        case 401:
            KeychainService.shared.token = nil
            NotificationCenter.default.post(name: .taskFlowUnauthorized, object: nil)
            throw APIError.unauthorized(message: raw)
        case 403:
            throw APIError.forbidden(message: raw)
        case 404:
            // Fastify так отвечает, когда маршрута у него просто нет: с
            // записями это не связано вообще, чинить надо сервер или клиент.
            if raw.contains("Route"), raw.localizedCaseInsensitiveContains("not found") {
                let what = Self.describe(request)
                throw APIError.routeMissing(message: what.isEmpty
                    ? "Сервер не знает такого запроса — похоже, приложение новее сервера"
                    : "Сервер не знает такого запроса: \(what). Похоже, приложение новее сервера")
            }
            throw APIError.notFound(message: Self.notFoundMessage(raw: raw, request: request))
        case 409:
            throw APIError.conflict(message: raw)
        default:
            throw APIError.server(status: status, message: raw)
        }
    }

    /// 404 у сервера означает три разные вещи, и раньше все три показывались
    /// одинаково — «Не найдено или нет доступа к этой записи». Владелец
    /// 15.09.2026 на это и указал: «пишет, что она удалена, но она не
    /// удалена». Теперь причина называется своим именем, а к ней добавляется
    /// упавший запрос — иначе непонятно, что именно чинить.
    private static func notFoundMessage(raw: String, request: URLRequest?) -> String {
        let what = describe(request)
        // Осмысленный ответ сервера всегда информативнее нашего текста.
        if raw.range(of: "[а-яА-ЯёЁ]", options: .regularExpression) != nil { return raw }
        return what.isEmpty
            ? "Запись не найдена или недоступна"
            : "Запись не найдена или недоступна (\(what))"
    }

    /// «PATCH /api/tasks/1234» — чтобы по баннеру было видно, что упало.
    private static func describe(_ request: URLRequest?) -> String {
        guard let request, let path = request.url?.path else { return "" }
        let method = request.httpMethod ?? "GET"
        return "\(method) \(path)"
    }

    // MARK: - Диагностика

    /// Возвращает заголовки запроса в формате `[K=V, K=V]`,
    /// c маскированием `Authorization`/`Cookie` и пр. секретных заголовков —
    /// чтобы случайный общий лог не утащил токен в системный журнал iPhone.
    private static func sanitizedHeaders(from request: URLRequest) -> String {
        guard let headers = request.allHTTPHeaderFields, !headers.isEmpty else { return "[]" }
        let redacted: Set<String> = ["authorization", "cookie", "x-api-key", "x-auth-token"]
        let pairs = headers
            .map { key, value -> String in
                if redacted.contains(key.lowercased()) { return "\(key)=Bearer ***" }
                return "\(key)=\(value)"
            }
            .sorted()
            .joined(separator: ", ")
        return "[\(pairs)]"
    }

    /// Возвращает первый `limit` байт тела ответа как UTF-8 строку
    /// (с заменой нечитаемых символов), либо плейсхолдер для пустого тела.
    /// Нужно для логов — большие ответы не помещаются в строку и нам тут не нужны.
    private static func bodyPreview(_ data: Data, limit: Int) -> String {
        guard !data.isEmpty else { return "<empty>" }
        let slice = data.prefix(limit)
        let preview = String(data: slice, encoding: .utf8)
            ?? String(data: slice, encoding: .isoLatin1)
            ?? "<\(data.count) bytes, не текст>"
        return preview.replacingOccurrences(of: "\n", with: " ")
    }
}

public enum HTTPMethodKind: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}

/// Стирает конкретный тип `Encodable`-тела до однородного значения, которое
/// можно передать в `JSONEncoder.encode` без дженерика на уровне вызова
/// (нужно, потому что `body: (any Encodable)?` — экзистенциал, а
/// `JSONEncoder.encode` дженерик по конкретному типу).
private struct AnyEncodable: Encodable {
    private let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

public extension Notification.Name {
    /// Шлётся `APIClient` на любой 401 — `SessionStore` подписан и сразу
    /// разлогинивает (spec §2.2).
    static let taskFlowUnauthorized = Notification.Name("TaskFlowUnauthorized")
}
