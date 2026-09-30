import Foundation

// LOCK-176, этапы 2–3: серверный каталог ролей — источник экрана «Команда».
// Контракт — `server/src/routes/roles.ts` (`GET /api/roles`).

private struct RolesEnvelope: Decodable { let roles: [RoleProfile] }

public extension APIClient {

    /// `GET /api/roles` — только включённые роли.
    func roles() async throws -> [RoleProfile] {
        try await roles(all: false)
    }

    /// `GET /api/roles?all=1` — вместе с отключёнными: экрану «Команда» их
    /// надо показать, чтобы было что включить обратно. Без `all=1` — только
    /// рабочие роли (LOCK-205, ссылка на `server/src/routes/roles.ts:278-285`).
    func roles(all: Bool) async throws -> [RoleProfile] {
        let query = all ? [URLQueryItem(name: "all", value: "1")] : []
        let envelope: RolesEnvelope = try await request(.get, "/roles", query: query)
        return envelope.roles
    }

    /// `GET /api/roles/:role` — одна роль (не используется списком, оставлено
    /// для точечного обновления после смены модели).
    func role(id: String) async throws -> RoleProfile {
        try await request(.get, "/roles/\(id)")
    }

    /// `GET /api/roles/:role/runtime-context` — постоянные правила запуска
    /// роли с серверным происхождением каждого слоя. Карточки, история чатов,
    /// сессии и секреты этим маршрутом намеренно не выдаются.
    func roleRuntimeContext(role: String) async throws -> RoleRuntimeContext {
        try await request(.get, "/roles/\(role)/runtime-context")
    }

    func roleInstructionHistory(role: String, block: String, team: Bool) async throws -> [RoleInstructionHistory] {
        let result: RoleInstructionHistoryEnvelope = try await request(.get, "/runtime/context/\(role)/\(block)", query: [URLQueryItem(name: "scope", value: team ? "command" : "role")])
        return result.history
    }

    func mutateRoleInstruction(role: String, block: String, team: Bool, version: Int, text: String, action: String = "set", historyVersion: Int? = nil) async throws {
        var body: [String: JSONValue] = ["scope": .string(team ? "command" : "role"), "if_match": .number(Double(version)), "text": .string(text)]
        if let historyVersion { body["version"] = .number(Double(historyVersion)) }
        let suffix = action == "set" ? "" : "/\(action)"
        try await requestVoid(action == "set" ? .patch : .post, "/runtime/context/\(role)/\(block)\(suffix)", body: body)
    }

    // MARK: - LOCK-205: создание и правка роли из экрана «Команда»

    /// `POST /api/roles` — только владелец. Сервер сам заводит учётку
    /// `role_<ключ>` (тип `ai`, без пароля и ключа) и обновляет кэш ролей.
    /// Ответ — `RoleProfile` созданной роли (см. `rolesManage.test.ts`:
    /// - `201`, поля `role`/`title`/`summary`/`enabled` присутствуют).
    ///
    /// Поля `summary` и `prompt` опциональны: пустая строка означает «не
    /// задано», и для `prompt` сервер тогда читает прежний файл
    /// `scripts/role-prompts/<роль>.md`.
    func createRole(key: String, title: String, summary: String?, prompt: String?) async throws -> RoleProfile {
        var body: [String: JSONValue] = [
            "key": .string(key),
            "title": .string(title)
        ]
        if let summary, !summary.isEmpty { body["summary"] = .string(summary) }
        if let prompt, !prompt.isEmpty { body["prompt"] = .string(prompt) }
        return try await request(.post, "/roles", body: body)
    }

    /// Что сделать с инструкцией роли в `PATCH /api/roles/:key`. На сервере
    /// пустая строка и `null` эквивалентны: оба сбрасывают на файл
    /// `scripts/role-prompts/<роль>.md`. `keep` — поле в PATCH не
    /// отправляется, и сервер его не трогает (LOCK-205).
    enum PromptChange {
        /// Поле в PATCH не отправляется (сервер оставляет прежнее значение).
        case keep
        /// Заменить инструкцию на новый текст. Пустая строка тоже
        /// считается заменой — клиент валидирует это ДО отправки.
        case set(String)
        /// Сбросить инструкцию на файл (на сервере это `prompt: ""` или `null`).
        case reset
    }

    /// `PATCH /api/roles/:key` — только владелец. Все поля опциональны,
    /// сервер требует, чтобы хотя бы одно было передано (иначе `422`).
    /// `enabled: false` отключает роль — она пропадает из работы и из
    /// списка без `?all=1`.
    func patchRole(
        role: String,
        title: String? = nil,
        summary: String? = nil,
        prompt: PromptChange = .keep,
        enabled: Bool? = nil
    ) async throws -> RoleProfile {
        var body: [String: JSONValue] = [:]
        if let title { body["title"] = .string(title) }
        if let summary { body["summary"] = .string(summary) }
        switch prompt {
        case .keep:
            break
        case .set(let text):
            body["prompt"] = .string(text)
        case .reset:
            // Сервер принимает `""` или `null` как «сбросить на файл».
            body["prompt"] = .null
        }
        if let enabled { body["enabled"] = .bool(enabled) }
        return try await request(.patch, "/roles/\(role)", body: body)
    }
}
