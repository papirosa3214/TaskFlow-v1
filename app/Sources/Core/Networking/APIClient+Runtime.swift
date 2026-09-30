import Foundation

// LOCK-175, этап 1: клиент серверного рантайма (Pi-фасад).
//
// Контракты — `server/src/routes/runtime.ts`. Все пути живут под `/api`,
// общий префикс добавляет `APIClient`.
//
// Экраны сюда пока не ходят — это задел под этапы 2–8. Здесь только
// транспорт и разбор ответов; никаких решений «какая модель лучше» клиент
// не принимает.
//
// Provider credentials TaskFlow iOS НЕ хранит и не видит: POST auth лишь
// инициирует flow, дальше статус читается с сервера.

/// Ответ `PUT /api/runtime/routing/:role`.
public struct RuntimeRoutingUpdate: Codable, Sendable, Hashable {
    public let role: String
    public let primary: String
    public let fallbacks: [String]
}

private struct RuntimeStatusEnvelope: Decodable { let runtime: RuntimeStatus }
private struct RuntimeProfilesEnvelope: Decodable { let profiles: [AgentProfile] }
private struct RuntimeModelsEnvelope: Decodable { let models: [RuntimeModel] }
private struct RuntimeProvidersEnvelope: Decodable { let providers: [RuntimeProvider] }

public extension APIClient {

    // MARK: - Runtime status

    /// `GET /api/runtime/status` — online/offline, версия, endpoint.
    func runtimeStatus() async throws -> RuntimeStatus {
        let envelope: RuntimeStatusEnvelope = try await request(.get, "/runtime/status")
        return envelope.runtime
    }

    // MARK: - AgentProfile

    /// `GET /api/runtime/profiles` — все профили агентов (роли).
    func runtimeProfiles() async throws -> [AgentProfile] {
        let envelope: RuntimeProfilesEnvelope = try await request(.get, "/runtime/profiles")
        return envelope.profiles
    }

    /// `GET /api/runtime/profiles/:id` — один профиль. `id` — роль.
    func runtimeProfile(id: String) async throws -> AgentProfile {
        try await request(.get, "/runtime/profiles/\(id)")
    }

    // MARK: - Models

    /// `GET /api/runtime/models` — каталог моделей Pi с признаком
    /// `available`. Pi недоступен → сервер отвечает 503.
    func runtimeModels() async throws -> [RuntimeModel] {
        let envelope: RuntimeModelsEnvelope = try await request(.get, "/runtime/models")
        return envelope.models
    }

    // MARK: - Providers

    /// `GET /api/runtime/providers` — провайдеры со статусом подключения.
    func runtimeProviders() async throws -> [RuntimeProvider] {
        let envelope: RuntimeProvidersEnvelope = try await request(.get, "/runtime/providers")
        return envelope.providers
    }

    /// `POST /api/runtime/providers/:provider/auth`.
    ///
    /// Без `apiKey` — старт OAuth: сервер отвечает 202 и `authSessionId`,
    /// дальше события читаются отдельно. С `apiKey` — ключ пишется сразу,
    /// ответ содержит `status`/`authType`. Обе формы разбирает
    /// `ProviderAuthStart`, у которого все поля опциональны.
    func startProviderAuth(
        provider: String,
        apiKey: String? = nil
    ) async throws -> ProviderAuthStart {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: [String: String]? = (trimmed?.isEmpty == false) ? ["apiKey": trimmed!] : nil
        return try await request(
            .post, "/runtime/providers/\(provider)/auth", body: body
        )
    }

    /// `GET /api/runtime/auth/:id` — polling-снимок сессии (фолбэк без SSE).
    func runtimeAuthSession(id: String) async throws -> AuthSession {
        try await request(.get, "/runtime/auth/\(id)")
    }

    /// `POST /api/runtime/auth/:id/input` — ответ на запрос Pi
    /// (`manual_code`/`text`/`secret`/`select`). Сервер отвечает 202.
    func submitProviderAuthInput(sessionID: String, value: String) async throws {
        let _: APIOkResponse = try await request(
            .post, "/runtime/auth/\(sessionID)/input", body: ["value": value] as [String: String]
        )
    }

    /// `DELETE /api/runtime/auth/:id` — отмена сессии, ответ 204 без тела.
    func cancelProviderAuth(sessionID: String) async throws {
        try await requestVoid(.delete, "/runtime/auth/\(sessionID)")
    }

    // MARK: - Routing (owner)

    /// `PUT /api/runtime/routing/:role` — primary + упорядоченные fallback'и.
    /// Порядок сохраняется как прислан, сервер его не сортирует.
    @discardableResult
    func updateRuntimeRouting(
        role: String,
        primary: String,
        fallbacks: [String]
    ) async throws -> RuntimeRoutingUpdate {
        try await request(
            .put,
            "/runtime/routing/\(role)",
            body: [
                "primary": .string(primary),
                "fallbacks": .array(fallbacks.map { .string($0) }),
            ] as [String: JSONValue]
        )
    }
}
