import Foundation

/// `ApiProject` — spec/API.md §3.2. `pinned` — SQLite 0/1 в БД, приведено к
/// Bool декодером (см. `CodableHelpers`). `taskCount` — derived, только в
/// ответе API, не хранится как поле БД.
///
/// Счётчики после `taskCount` добавлены 08.09.2026 вместе с правкой
/// `GET /api/projects` на сервере (одна группировка по задачам) — под карточку
/// проекта, которой нужен прогресс, а не одно число. Все они
/// `decodeIfPresent`: сервер может быть старее клиента, и тогда карточка
/// просто не покажет соответствующую строку.
/// Агент, занятый в проекте прямо сейчас: есть активная задача на его учётке.
/// Аренда (`agent_state`) для списка не годится — она живёт пять минут, и
/// карточка мигала бы; «когда-то делал» ничего не говорит о сегодняшнем дне.
public struct ApiProjectAgent: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    /// Сколько активных задач проекта на нём висит.
    public let tasks: Int
}

public struct ApiProject: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let color: String?
    public let ownerId: String?
    public let createdAt: String?
    public let position: Int?
    public let pinned: Bool
    public let notesFolderId: Int?
    /// Активные задачи проекта (выполненные не считаются — так же, как на
    /// экране проекта, см. комментарий в `server/src/routes/projects.ts`).
    public let taskCount: Int?
    public let completedCount: Int?
    /// Активные задачи, у которых срок уже прошёл.
    public let overdueCount: Int?
    /// Последнее движение по задачам проекта (`MAX(updated_at)`), не дата
    /// создания: карточка отвечает на вопрос «сколько висит без движения».
    public let lastActivityAt: String?
    /// Записей в папке документации проекта.
    public let docsCount: Int?
    /// Свой датасет базы знаний (RAGFlow). Пусто — общий датасет TaskFlow.
    /// Владелец 08.09.2026: специфический проект не должен подмешивать свою
    /// документацию туда, где ищут рабочее.
    public let knowledgeDatasetId: String?
    /// Кто из агентов сейчас работает в проекте.
    public let agents: [ApiProjectAgent]

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case position, pinned
        case notesFolderId = "notes_folder_id"
        case taskCount = "task_count"
        case completedCount = "completed_count"
        case overdueCount = "overdue_count"
        case lastActivityAt = "last_activity_at"
        case docsCount = "docs_count"
        case knowledgeDatasetId = "knowledge_dataset_id"
        case agents
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        ownerId = try c.decodeIfPresent(String.self, forKey: .ownerId)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        position = try c.decodeIfPresent(Int.self, forKey: .position)
        pinned = try c.decodeIntBool(forKey: .pinned)
        notesFolderId = try c.decodeIfPresent(Int.self, forKey: .notesFolderId)
        taskCount = try c.decodeIfPresent(Int.self, forKey: .taskCount)
        completedCount = try c.decodeIfPresent(Int.self, forKey: .completedCount)
        overdueCount = try c.decodeIfPresent(Int.self, forKey: .overdueCount)
        lastActivityAt = try c.decodeIfPresent(String.self, forKey: .lastActivityAt)
        docsCount = try c.decodeIfPresent(Int.self, forKey: .docsCount)
        knowledgeDatasetId = try c.decodeIfPresent(String.self, forKey: .knowledgeDatasetId)
        agents = try c.decodeIfPresent([ApiProjectAgent].self, forKey: .agents) ?? []
    }

    public init(
        id: String, name: String, color: String?, ownerId: String?, createdAt: String?,
        position: Int?, pinned: Bool, notesFolderId: Int?, taskCount: Int?,
        completedCount: Int? = nil, overdueCount: Int? = nil,
        lastActivityAt: String? = nil, docsCount: Int? = nil,
        knowledgeDatasetId: String? = nil,
        agents: [ApiProjectAgent] = []
    ) {
        self.id = id; self.name = name; self.color = color; self.ownerId = ownerId
        self.createdAt = createdAt; self.position = position; self.pinned = pinned
        self.notesFolderId = notesFolderId; self.taskCount = taskCount
        self.completedCount = completedCount; self.overdueCount = overdueCount
        self.lastActivityAt = lastActivityAt; self.docsCount = docsCount
        self.knowledgeDatasetId = knowledgeDatasetId
        self.agents = agents
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(ownerId, forKey: .ownerId)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(position, forKey: .position)
        try c.encode(pinned ? 1 : 0, forKey: .pinned)
        try c.encodeIfPresent(notesFolderId, forKey: .notesFolderId)
        try c.encodeIfPresent(taskCount, forKey: .taskCount)
        try c.encodeIfPresent(completedCount, forKey: .completedCount)
        try c.encodeIfPresent(overdueCount, forKey: .overdueCount)
        try c.encodeIfPresent(lastActivityAt, forKey: .lastActivityAt)
        try c.encodeIfPresent(docsCount, forKey: .docsCount)
        try c.encodeIfPresent(knowledgeDatasetId, forKey: .knowledgeDatasetId)
        try c.encode(agents, forKey: .agents)
    }
}
