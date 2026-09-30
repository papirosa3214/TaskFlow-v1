import Foundation

/// Контракт версий результата и ревью карточки задачи.
///
/// Версия нужна клиенту не для отдельного экрана, а чтобы существующее
/// действие владельца «Принять» могло явно одобрить именно тот результат,
/// который сервер считает текущим.
public extension APIClient {
    struct TaskResultVersion: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let taskId: String
        public let versionNo: Int
        public let taskRevision: Int
        public let result: String
        public let evidenceJSON: String
        public let artifactHash: String
        public let createdBy: String?
        public let createdAt: String
        public let isCurrent: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case taskId = "task_id"
            case versionNo = "version_no"
            case taskRevision = "task_revision"
            case result
            case evidenceJSON = "evidence_json"
            case artifactHash = "artifact_hash"
            case createdBy = "created_by"
            case createdAt = "created_at"
            case isCurrent = "is_current"
        }
    }

    struct TaskVersionsResponse: Decodable, Sendable, Equatable {
        public let currentVersionId: String?
        public let versions: [TaskResultVersion]

        enum CodingKeys: String, CodingKey {
            case currentVersionId = "current_version_id"
            case versions
        }
    }

    enum TaskReviewVerdict: String, Codable, Sendable {
        case approved
        case changesRequested = "changes_requested"
        case blocked
    }

    struct TaskReview: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let taskId: String
        public let versionId: String
        public let taskRevision: Int
        public let reviewerId: String
        public let artifactHash: String
        public let criteriaVersion: String
        public let verdict: TaskReviewVerdict
        public let findings: String?
        public let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case reviewId = "review_id"
            case taskId = "task_id"
            case versionId = "version_id"
            case taskRevision = "task_revision"
            case reviewerId = "reviewer_id"
            case artifactHash = "artifact_hash"
            case criteriaVersion = "criteria_version"
            case verdict
            case findings
            case createdAt = "created_at"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id)
                ?? c.decode(String.self, forKey: .reviewId)
            taskId = try c.decode(String.self, forKey: .taskId)
            versionId = try c.decode(String.self, forKey: .versionId)
            taskRevision = try c.decode(Int.self, forKey: .taskRevision)
            reviewerId = try c.decode(String.self, forKey: .reviewerId)
            artifactHash = try c.decode(String.self, forKey: .artifactHash)
            criteriaVersion = try c.decode(String.self, forKey: .criteriaVersion)
            verdict = try c.decode(TaskReviewVerdict.self, forKey: .verdict)
            findings = try c.decodeIfPresent(String.self, forKey: .findings)
            createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        }
    }

    private struct ReviewRequest: Encodable {
        let taskId: String
        let versionId: String
        let artifactHash: String
        let criteriaVersion: String
        let taskRevision: Int
        let verdict: TaskReviewVerdict
        let findings: String?

        enum CodingKeys: String, CodingKey {
            case taskId = "task_id"
            case versionId = "version_id"
            case artifactHash = "artifact_hash"
            case criteriaVersion = "criteria_version"
            case taskRevision = "task_revision"
            case verdict
            case findings
        }
    }

    /// Текущая версия уже вычислена сервером с учётом `task_revision`.
    func taskResultVersions(taskID: String) async throws -> TaskVersionsResponse {
        try await request(.get, "/tasks/\(taskID)/versions")
    }

    func recordTaskReview(
        taskID: String,
        version: TaskResultVersion,
        verdict: TaskReviewVerdict,
        findings: String? = nil,
        criteriaVersion: String = "taskflow-native-v1"
    ) async throws -> TaskReview {
        let payload = ReviewRequest(
            taskId: taskID,
            versionId: version.id,
            artifactHash: version.artifactHash,
            criteriaVersion: criteriaVersion,
            taskRevision: version.taskRevision,
            verdict: verdict,
            findings: findings
        )
        return try await request(.post, "/reviews", body: payload)
    }

    /// Одобряет актуальную версию перед существующим owner-flow закрытия.
    /// Если карточка уже изменилась, сервер вернёт конфликт по revision/hash,
    /// и клиент не попытается закрыть задачу поверх устаревшего результата.
    func approveCurrentTaskVersion(taskID: String, findings: String? = nil) async throws {
        let response = try await taskResultVersions(taskID: taskID)
        let current = response.versions.first { $0.id == response.currentVersionId }
            ?? response.versions.first(where: \.isCurrent)
        guard let current else {
            throw APIError.server(status: 422, message: "У задачи нет актуальной версии результата")
        }
        _ = try await recordTaskReview(
            taskID: taskID,
            version: current,
            verdict: .approved,
            findings: findings
        )
    }
}
