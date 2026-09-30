import Foundation

// LOCK-208: очередь запусков ролей. Контракт — New-Todoist
// `server/src/routes/role-run-jobs.ts` и `runtime/roleRunQueue.ts`
// (миграции 059/060). Всё только для владельца: остальным сервер
// отвечает `403`.

/// Один повод запуска роли по карточке. Сервер хранит его в SQLite до
/// конца: `queued → running → succeeded`, при сбое — `retry_wait` и
/// повтор, после исчерпания попыток — `dead`.
public struct RoleRunJob: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let taskId: String
    public let reason: String
    public let status: String
    public let attempts: Int
    public let maxAttempts: Int
    public let lastError: String?
    public let createdAt: String
    public let updatedAt: String
    public let startedAt: String?
    public let finishedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, reason, status, attempts
        case taskId = "task_id"
        case maxAttempts = "max_attempts"
        case lastError = "last_error"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }

    /// Ещё не закончился: стоит в очереди, идёт или ждёт повтора.
    public var isActive: Bool { ["queued", "running", "retry_wait"].contains(status) }
    /// Сервер разрешает повтор только закончившимся неудачно.
    public var canRetry: Bool { ["dead", "cancelled", "skipped"].contains(status) }
    /// Отменить безопасно можно только то, что ещё не начало работу.
    public var canCancel: Bool { ["queued", "retry_wait"].contains(status) }
}

private struct RoleRunJobsEnvelope: Decodable { let jobs: [RoleRunJob] }
private struct RoleRunJobEnvelope: Decodable { let job: RoleRunJob }

public extension APIClient {
    /// `GET /api/role-run-jobs` — последние запуски, новые сверху.
    func roleRunJobs(limit: Int = 50) async throws -> [RoleRunJob] {
        let envelope: RoleRunJobsEnvelope = try await request(
            .get, "/role-run-jobs", query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return envelope.jobs
    }

    /// `POST /api/role-run-jobs/:id/retry` — поставить упавший запуск заново.
    @discardableResult
    func retryRoleRunJob(id: String) async throws -> RoleRunJob {
        let envelope: RoleRunJobEnvelope = try await request(.post, "/role-run-jobs/\(id)/retry")
        return envelope.job
    }

    /// `POST /api/role-run-jobs/:id/cancel` — снять ещё не начавшийся запуск.
    @discardableResult
    func cancelRoleRunJob(id: String) async throws -> RoleRunJob {
        let envelope: RoleRunJobEnvelope = try await request(.post, "/role-run-jobs/\(id)/cancel")
        return envelope.job
    }
}
