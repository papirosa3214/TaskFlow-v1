import Foundation

/// Per-user системные промпты для серверной модели — обвязка
/// `GET /api/ai/prompts` и `PUT /api/ai/prompts/:scope`.
///
/// Серверный контракт (см. server-задачу `dcd03225`):
///   GET  /api/ai/prompts                  → { prompts: [{scope, prompt, updated_at}] }
///   PUT  /api/ai/prompts/:scope           → { prompt: string } → { ok, scope, prompt, updated_at }
///
/// На 13.09.2026 серверная часть ещё не залита — iOS-клиент работает в режиме
/// «локальный кеш + попытка синхронизации, при отказе остаёмся на кеше»
/// (см. `AIPromptsStore`). Когда серверная карточка `dcd03225` уйдёт в
/// REVIEW, вызовы начнут возвращать реальные данные.

struct AIUserPrompt: Codable, Hashable, Sendable {
    let scope: String
    let prompt: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case scope, prompt
        case updatedAt = "updated_at"
    }
}

private struct AIUserPromptsResponse: Decodable {
    let prompts: [AIUserPrompt]
    /// Штатные серверные промпты по скоупам — показываем их placeholder'ом.
    let defaults: [String: String]?
}
private struct AIUserPromptUpsertRequest: Encodable { let prompt: String }

/// Разобранный ответ `GET /api/ai/prompts`.
struct AIUserPromptsPayload: Sendable {
    let prompts: [AIUserPrompt]
    let defaults: [String: String]
}

extension APIClient {
    /// `GET /api/ai/prompts` — все сохранённые промпты текущего пользователя
    /// плюс штатные серверные (для показа placeholder'ом).
    func aiUserPrompts() async throws -> AIUserPromptsPayload {
        let response: AIUserPromptsResponse = try await request(.get, "/ai/prompts")
        return AIUserPromptsPayload(prompts: response.prompts, defaults: response.defaults ?? [:])
    }

    /// `PUT /api/ai/prompts/:scope` — сохранить/перезаписать промпт.
    /// Пустая строка трактуется сервером как «сброс на дефолт».
    func setAIUserPrompt(scope: String, prompt: String) async throws -> AIUserPrompt {
        try await request(
            .put, "/ai/prompts/\(scope)",
            body: AIUserPromptUpsertRequest(prompt: prompt)
        )
    }
}
