import Foundation

// LOCK-246: только чтение графа совместной работы для карточки задачи.
// Контракт — `server/src/routes/task-collaboration-plans.ts`. Runtime-
// состояние узлов (LOCK-246 читал его из `task-role-slots.ts`) с
// 29.09.2026 — обычные подзадачи, см. `subtasks(taskId:)` в
// `APIClient+Subtasks.swift` и `CollaborationPlan.swift`.

private struct CollaborationPlansEnvelope: Decodable { let plans: [ApiCollaborationPlan] }
private struct CollaborationPlanEnvelope: Decodable { let plan: ApiCollaborationPlan }
private struct ProposeCollaborationPlanBody: Encodable { let profile: String }

/// `POST .../collaboration-plans/suggest-from-subtasks` — два разных тела
/// по одному и тому же `suggested`: `{suggested:false, reason}`, когда
/// параллелить нечего (меньше двух открытых подзадач или все совпали с
/// текущим исполнителем), либо `{plan:{...}, suggested:true}`. Одна
/// структура с обоими полями опциональными проще, чем городить свой
/// декодер под два разных JSON-тела.
private struct FanoutSuggestionEnvelope: Decodable {
    let suggested: Bool
    let reason: String?
    let plan: ApiCollaborationPlan?
}

public enum CollaborationPlanFanoutResult: Sendable {
    case suggested(ApiCollaborationPlan)
    case notSuggested(reason: String)
}

public extension APIClient {

    /// `GET /api/tasks/:id/collaboration-plans` — все revisions, новые
    /// первыми. Карточке нужна только approved (см. `CollaborationPlanView`).
    func collaborationPlans(taskId: String) async throws -> [ApiCollaborationPlan] {
        let envelope: CollaborationPlansEnvelope = try await request(.get, "/tasks/\(taskId)/collaboration-plans")
        return envelope.plans
    }

    /// `POST /api/tasks/:id/collaboration-plans/:planId/approve` — LOCK-249.
    /// Сервер сам проверяет владельца (403 иначе); клиент только показывает
    /// кнопку владельцу. Утверждение сразу материализует узлы плана как
    /// подзадачи и стартует корневые узлы графа.
    @discardableResult
    func approveCollaborationPlan(taskId: String, planId: String) async throws -> ApiCollaborationPlan {
        let envelope: CollaborationPlanEnvelope = try await request(.post, "/tasks/\(taskId)/collaboration-plans/\(planId)/approve")
        return envelope.plan
    }

    /// `POST /api/tasks/:id/collaboration-plans/propose` — LOCK-252: явный
    /// выбор шаблона владельцем, вместо того чтобы полагаться на серверный
    /// автоподбор по ключевым словам карточки (`autoProposeCollaborationPlanIfNeeded`
    /// при создании задачи) — тот угадывает профиль не всегда надёжно.
    /// `profile` — один из шаблонов сервера: "single_executor" | "research" |
    /// "delivery" | "full_cycle" (см. PROFILES в task-collaboration-plans.ts;
    /// "product_feature" сюда не включён — ему нужны отдельные булевы флаги
    /// include_architecture/include_design/include_qa, это вне LOCK-252).
    /// Как и /suggest-from-subtasks — создаёт черновик, ничего не запускает;
    /// дальше тот же граф в карточке и та же кнопка «Утвердить».
    @discardableResult
    func proposeCollaborationPlan(taskId: String, profile: String) async throws -> ApiCollaborationPlan {
        let envelope: CollaborationPlanEnvelope = try await request(
            .post,
            "/tasks/\(taskId)/collaboration-plans/propose",
            body: ProposeCollaborationPlanBody(profile: profile)
        )
        return envelope.plan
    }

    /// `POST .../collaboration-plans/suggest-from-subtasks` — умная
    /// параллелизация (30.09.2026): подобрать план ИЗ уже написанных
    /// открытых подзадач карточки локальным классификатором, а не из
    /// шаблона по ключевым словам самой карточки. Draft, как и `/propose` —
    /// ничего не запускает, дальше тот же граф и та же кнопка «Утвердить».
    func suggestCollaborationPlanFromSubtasks(taskId: String) async throws -> CollaborationPlanFanoutResult {
        let envelope: FanoutSuggestionEnvelope = try await request(.post, "/tasks/\(taskId)/collaboration-plans/suggest-from-subtasks")
        if let plan = envelope.plan { return .suggested(plan) }
        return .notSuggested(reason: envelope.reason ?? "Параллелить нечего.")
    }

    /// Правка живого плана (01.10.2026) — черновика или уже запущенного.
    /// `baseVersion` — версия, которую видел владелец: не совпала — сервер
    /// отвечает 409, и экран перечитывает план, не теряя введённого.
    @discardableResult
    func applyCollaborationPlanOps(taskId: String, planId: String, baseVersion: Int?, ops: [ApiPlanOp],
                                   reason: String? = nil) async throws -> ApiCollaborationPlan {
        struct Body: Encodable { let base_version: Int?; let ops: [ApiPlanOp]; let reason: String? }
        let envelope: CollaborationPlanEnvelope = try await request(
            .post,
            "/tasks/\(taskId)/collaboration-plans/\(planId)/ops",
            body: Body(base_version: baseVersion, ops: ops, reason: reason)
        )
        return envelope.plan
    }

    /// Решение владельца по предложению роли сверх лимита.
    @discardableResult
    func decideCollaborationPlanProposal(taskId: String, planId: String, proposalId: String,
                                         approve: Bool) async throws -> ApiCollaborationPlan {
        let envelope: CollaborationPlanEnvelope = try await request(
            .post,
            "/tasks/\(taskId)/collaboration-plans/\(planId)/proposals/\(proposalId)/\(approve ? "approve" : "reject")"
        )
        return envelope.plan
    }
}
