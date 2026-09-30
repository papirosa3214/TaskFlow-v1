import Foundation

/// Версионируемый граф совместной работы над задачей — LOCK-246.
///
/// Источник — `server/src/routes/task-collaboration-plans.ts` (`GET
/// /api/tasks/:id/collaboration-plans`). Клиент только читает: создание и
/// утверждение плана делает оркестратор/владелец через API напрямую,
/// графового редактора на телефоне нет и не планируется (docs/
/// 2026-09-28-parent-child-execution-context, этап 10, «вне первого этапа»).
///
/// Runtime-состояние узлов (кто в работе, кто закрыт) — с 29.09.2026 НЕ
/// отдельная сущность (`task_role_slots` выведена из употребления, см.
/// docs/2026-09-29-role-slot-execution-integration/DESIGN.md), а обычные
/// `ApiSubtask` с `collaborationPlanId`/`planNodeKey` — читай их напрямую
/// вместо `ApiRoleSlot` (убран).
public struct ApiCollaborationPlanNode: Codable, Sendable, Hashable, Identifiable {
    public let slotKey: String
    public let roleKey: String
    public let required: Bool
    public let expectedResult: String

    public var id: String { slotKey }

    enum CodingKeys: String, CodingKey {
        case slotKey = "slot_key"
        case roleKey = "role_key"
        case required
        case expectedResult = "expected_result"
    }
}

public struct ApiCollaborationPlanEdge: Codable, Sendable, Hashable {
    public let fromSlotKey: String
    public let toSlotKey: String
    public let startCondition: String

    enum CodingKeys: String, CodingKey {
        case fromSlotKey = "from_slot_key"
        case toSlotKey = "to_slot_key"
        case startCondition = "start_condition"
    }
}

public struct ApiCollaborationPlan: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let taskId: String
    public let revision: Int
    public let status: String
    public let profile: String
    public let rationale: String
    public let nodes: [ApiCollaborationPlanNode]
    public let edges: [ApiCollaborationPlanEdge]

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case revision, status, profile, rationale, nodes, edges
    }
}

