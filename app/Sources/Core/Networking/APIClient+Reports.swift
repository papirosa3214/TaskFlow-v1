import Foundation

/// Отчёт по задаче — запись секции «Отчёты» в карточке. Физически отчёт лежит
/// документом в папке проекта (`noteID`), здесь — «зеркало»: название, автор,
/// время. Собрано `POST /api/tasks/:id/reports`.
struct TaskReport: Decodable, Identifiable, Hashable {
    let id: String
    let noteID: String?
    let title: String
    let authorName: String?
    let createdAt: String?

    var createdAtDate: Date? { DateFormats.sqliteUTC(createdAt) }

    enum CodingKeys: String, CodingKey {
        case id, title
        case noteID = "note_id"
        case authorName = "author_name"
        case createdAt = "created_at"
    }
}

private struct TaskReportsResponse: Decodable { let reports: [TaskReport] }

extension APIClient {
    /// Список отчётов задачи (свежие сверху).
    func taskReports(taskId: String) async throws -> [TaskReport] {
        let response: TaskReportsResponse = try await request(.get, "/tasks/\(taskId)/reports")
        return response.reports
    }
}
