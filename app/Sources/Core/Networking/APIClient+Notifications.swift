import Foundation

/// Уведомления — spec/API.md §5.7.
public extension APIClient {
    func notifications() async throws -> [ApiNotification] {
        try await request(.get, "/notifications")
    }

    /// Сервер принимает только `PATCH /notifications/:id/read` без тела и
    /// отвечает подтверждением операции. Снимок уведомлений надо брать
    /// отдельным GET, а не декодировать этот ответ как `ApiNotification`.
    func markNotificationRead(id: String) async throws {
        let _: APIOkResponse = try await request(.patch, "/notifications/\(id)/read")
    }

    func deleteNotification(id: String) async throws {
        let _: APIOkResponse = try await request(.delete, "/notifications/\(id)")
    }
}
