// APIClient+LiveActivity.swift
// Токен островка: приложение отдаёт его серверу, сервер по нему двигает
// карточку через APNs, пока приложение свёрнуто (server/src/apns.ts).
//
// Эндпоинты на сервере были написаны ещё под Capacitor-обёртку и всё это
// время лежали без клиента — нативное приложение до 10.09.2026 островок
// вообще не поднимало.

import Foundation

public extension APIClient {
    /// Токен выдаётся системой не сразу и меняется со временем; сервер
    /// перезаписывает его по `task_id`, точка отсчёта таймера не сдвигается.
    func registerLiveActivityToken(taskId: String, token: String) async throws {
        struct Body: Encodable {
            let taskId: String
            let token: String
            enum CodingKeys: String, CodingKey {
                case taskId = "taskId"
                case token
            }
        }
        try await requestVoid(.post, "/live-activity/token", body: Body(taskId: taskId, token: token))
    }

    /// Островок погашен — снимаем токен, чтобы сервер не стучался в мёртвую
    /// активность.
    func dropLiveActivityToken(taskId: String) async throws {
        try await requestVoid(.delete, "/live-activity/token/\(taskId)")
    }
}
