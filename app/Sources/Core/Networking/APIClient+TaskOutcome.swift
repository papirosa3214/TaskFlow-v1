import Foundation

public extension APIClient {
    /// Итог карточки — секция «Итог» (владелец 01.10.2026).
    func taskOutcome(taskId: String) async throws -> ApiTaskOutcome {
        try await request(.get, "/tasks/\(taskId)/outcome")
    }

    /// Заметка → в базу знаний сейчас, не дожидаясь ночной выгрузки.
    func pushNoteToKnowledge(noteId: String) async throws {
        try await requestVoid(.post, "/notes/\(noteId)/knowledge")
    }
}
