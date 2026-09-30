import Foundation

/// `status` — spec/API.md §3.4, CHECK-constraint в БД, закрытый список.
public enum TaskStatus: String, Codable, Sendable, Hashable {
    case active, completed
}

/// `agent_state` — НЕЗАВИСИМОЕ от `status` поле (spec §7): пока агент работает
/// над задачей, `status` весь срок остаётся `active`. Матрица допустимых
/// переходов — на сервере (`canTransition()`), клиент её не дублирует.
public enum AgentState: String, Codable, Sendable, Hashable {
    case inProgress = "in_progress"
    case blocked
    case review
    /// Ставит только `scheduler.py` (.110, systemd-таймер) — напрямую в БД,
    /// в обход `POST /api/tasks/:id/state`: `blocked`→`todo` после истечения
    /// ретрай-задержки или успешного переподбора роли. Значит «в очереди,
    /// дальше подхватит диспетчер сам». Клиент это значение никогда не
    /// выставляет — только показывает (27.09.2026, декодинг без него валил
    /// весь `/api/tasks` разом).
    case todo
}

/// `ApiTask` — spec/API.md §3.4. Приоритет — обычный `Int` 1...4 (сервер не
/// именует уровни текстом, меньше = важнее); сопоставление в цвет/подпись —
/// дело UI-слоя (`TaskPriority` в `DesignSystem`), Core от него не зависит.
public struct ApiTask: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let description: String?
    /// `'YYYY-MM-DD' | nil` — календарная дата, см. `DateFormats.calendarDate`.
    public let dueDate: String?
    public let projectId: String?
    public let priority: Int
    public let assigneeId: String?
    public let creatorId: String?
    public let status: TaskStatus
    public let createdAt: String?
    public let updatedAt: String?
    public let completedAt: String?
    public let agentState: AgentState?
    public let agentHeartbeatAt: String?
    public let position: Int?
    public let agentSessionId: String?
    /// `'HH:MM'` локальное, nil = задача без времени в календаре.
    public let startTime: String?
    public let durationMin: Int?
    public let pinned: Bool
    /// Есть только в живой БД, НЕ создаётся системой миграций (spec §12 п.6) —
    /// на свежесозданной с нуля базе может отсутствовать вовсе.
    public let parentId: String?
    /// Готовность к самозахвату (миграция 026, карточки d598de9f/dc669154/04426aeb).
    /// Поднимает только владелец трекера; пока false — claim отклоняется.
    public let readyForPickup: Bool
    /// Когда подняли (`SQLite UTC`).
    public let readySetAt: String?
    /// id учётки, кто поднял.
    public let readySetBy: String?
    /// Новая карточка по умолчанию проходит Reviewer; старые — direct owner-flow.
    public let requiresReviewerReview: Bool
    /// «Нужно глубокое исследование» (миграция 052, сервер New-Todoist) —
    /// галочка владельца, по ней запускается серверный конвейер исследования.
    /// Старые ответы поля не содержат — `decodeIntBool` даёт false.
    public let needsResearch: Bool
    /// Повтор карточки: none|daily|weekdays|weekly|monthly.
    public let runRepeat: String?
    /// До какой даты повторять (ISO-дата); nil — постоянно.
    public let repeatUntil: String?
    /// Сколько дочерних задач у этой (`parent_id = t.id`), независимо от их
    /// статуса — для ярлыка «есть дочерние» в строке списка (владелец
    /// 28.09.2026). Дешёвый коррелированный подзапрос на сервере
    /// (TASK_COLUMNS), не отдельный вызов.
    public let childrenCount: Int
    /// Есть ли у задачи УТВЕРЖДЁННЫЙ collaboration plan (LOCK-246/247) —
    /// для ярлыка «есть план» в строке списка. Тот же приём, что и
    /// childrenCount.
    public let hasCollaborationPlan: Bool
    /// 1 — серия повтора уже завершена (следующее вхождение не создавать),
    /// 0 — ещё идёт. Признак воркера, владельцу виден для «Продлить на год».
    public let recurrenceSpawned: Int?

    // MARK: Derived (hydrateTask()/withAgentStale())

    /// `agent_heartbeat_at` старше 15 минут при непустом `agent_state`
    /// («агент пропал») — ОТДЕЛЬНОЕ число от аренды `LEASE_MINUTES=5`, не путать.
    public let agentStale: Bool?
    public let agentStartedAt: String?
    /// ТОЛЬКО в `GET /api/tasks` (список), завязано на текущую сессию.
    public let mine: Bool?
    public let assigneeName: String?
    public let assigneeColor: String?
    public let assigneeAvatarUrl: String?
    public let assigneeInitials: String?
    /// Кто завёл карточку. Владелец 14.09.2026: «почему я не вижу в
    /// карточке, кто создаёт карточки». Раньше приходил только
    /// `creator_id`, по которому на экране ничего не покажешь. Нужно это с
    /// тех пор, как карточки заводит не только владелец: их создают роли и
    /// разбор надиктовки.
    public let creatorName: String?
    public let creatorColor: String?
    public let creatorAvatarUrl: String?
    public let creatorInitials: String?
    public let projectName: String?
    public let projectColor: String?
    public let labels: [ApiLabel]
    public let subtasks: [ApiSubtask]
    /// Только `GET /api/tasks/:id` — дочерние задачи (`parent_id` = этот id).
    public let children: [ApiTask]?
    /// Только `GET /api/tasks/:id`.
    public let comments: [ApiComment]?
    /// Только `GET /api/tasks/:id`.
    public let events: [ApiTaskEvent]?
    /// Только `GET /api/tasks/:id` — чаты, привязанные к этой задаче. Нужны
    /// карточке для перехода «Чат по задаче»; сам чат в карточке не рисуется
    /// (владелец 21.09.2026, LOCK-195).
    public let chats: [ApiTaskChat]?
    /// Только `GET /api/tasks/:id` — файлы самой задачи (`kind='task'`).
    public let attachments: [ApiAttachment]?
    /// Спек 1.2, 1.2.10 — лесенка модели. Только `GET /api/tasks/:id`. На
    /// старых задачах (созданных до спек 1.2) поле отсутствует в ответе —
    /// UI просто не рисует индикатор. Тип и история в `AttemptLadder.swift`.
    public let attemptLadder: ApiAttemptLadder?
    /// Логическая роль задачи: `dispatched_role`, иначе `owner_selected_role`,
    /// иначе пусто (LOCK-178). Сервер отдаёт её строкой в `GET /api/tasks/:id`,
    /// чтобы клиент не гадал по двум колонкам. Пусто — роль ещё не выбрана.
    public let role: String?
    /// Выбор владельца (кто из ролей должен исполнять) и зафиксированная
    /// диспетчером роль — сырыми колонками. Читаем их отдельно: на живом
    /// сервере вычисленное `role` может оказаться пустым, хотя
    /// `owner_selected_role` записан, и тогда пикер исполнителя показывал бы
    /// «Автоматически» вместо выбранной роли.
    public let ownerSelectedRole: String?
    public let dispatchedRole: String?
    /// Роль, подобранная при постановке (Секретарём) или диспетчером, до
    /// раздачи. Отдельно от `effectiveRole`: её показывает только карточка
    /// черновика в чате — там исполнитель виден ещё до запуска.
    public let machineSelectedRole: String?

    /// Роль для показа/выбора: зафиксированная диспетчером важнее выбора
    /// владельца, но если обе пусты — `nil`. Падать на вычисленное `role` не
    /// полагаемся.
    public var effectiveRole: String? {
        for candidate in [dispatchedRole, ownerSelectedRole, role] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case dueDate = "due_date"
        case projectId = "project_id"
        case priority
        case assigneeId = "assignee_id"
        case creatorId = "creator_id"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case agentState = "agent_state"
        case agentHeartbeatAt = "agent_heartbeat_at"
        case position
        case agentSessionId = "agent_session_id"
        case startTime = "start_time"
        case durationMin = "duration_min"
        case pinned
        case parentId = "parent_id"
        case readyForPickup = "ready_for_pickup"
        case readySetAt = "ready_set_at"
        case readySetBy = "ready_set_by"
        case requiresReviewerReview = "requires_reviewer_review"
        case needsResearch = "needs_research"
        case runRepeat = "run_repeat"
        case repeatUntil = "repeat_until"
        case recurrenceSpawned = "recurrence_spawned"
        case childrenCount = "children_count"
        case hasCollaborationPlan = "has_collaboration_plan"
        case agentStale = "agent_stale"
        case agentStartedAt = "agent_started_at"
        case mine
        case assigneeName = "assignee_name"
        case assigneeColor = "assignee_color"
        case assigneeAvatarUrl = "assignee_avatar_url"
        case assigneeInitials = "assignee_initials"
        case creatorName = "creator_name"
        case creatorColor = "creator_color"
        case creatorAvatarUrl = "creator_avatar_url"
        case creatorInitials = "creator_initials"
        case projectName = "project_name"
        case projectColor = "project_color"
        case labels, subtasks, children, comments, events, chats, attachments
        case attemptLadder = "attempt_ladder"
        case role
        case ownerSelectedRole = "owner_selected_role"
        case dispatchedRole = "dispatched_role"
        case machineSelectedRole = "machine_selected_role"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
        projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 1
        assigneeId = try c.decodeIfPresent(String.self, forKey: .assigneeId)
        creatorId = try c.decodeIfPresent(String.self, forKey: .creatorId)
        status = try c.decode(TaskStatus.self, forKey: .status)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        completedAt = try c.decodeIfPresent(String.self, forKey: .completedAt)
        agentState = try c.decodeIfPresent(AgentState.self, forKey: .agentState)
        agentHeartbeatAt = try c.decodeIfPresent(String.self, forKey: .agentHeartbeatAt)
        position = try c.decodeIfPresent(Int.self, forKey: .position)
        agentSessionId = try c.decodeIfPresent(String.self, forKey: .agentSessionId)
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
        durationMin = try c.decodeIfPresent(Int.self, forKey: .durationMin)
        pinned = try c.decodeIntBool(forKey: .pinned)
        parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
        // Сервер отдаёт `ready_for_pickup` как INTEGER (0/1) — не Boolean,
        // чтобы поле дефолтом было 0 в существующих строках после миграции.
        // Используем тот же приём `decodeIntBool`, что и `pinned` выше.
        readyForPickup = try c.decodeIntBool(forKey: .readyForPickup)
        readySetAt = try c.decodeIfPresent(String.self, forKey: .readySetAt)
        readySetBy = try c.decodeIfPresent(String.self, forKey: .readySetBy)
        requiresReviewerReview = try c.decodeIntBool(forKey: .requiresReviewerReview)
        needsResearch = try c.decodeIntBool(forKey: .needsResearch)
        runRepeat = try c.decodeIfPresent(String.self, forKey: .runRepeat)
        repeatUntil = try c.decodeIfPresent(String.self, forKey: .repeatUntil)
        recurrenceSpawned = try c.decodeIfPresent(Int.self, forKey: .recurrenceSpawned)
        childrenCount = try c.decodeIfPresent(Int.self, forKey: .childrenCount) ?? 0
        hasCollaborationPlan = try c.decodeIntBool(forKey: .hasCollaborationPlan)
        agentStale = try c.decodeIfPresent(Bool.self, forKey: .agentStale)
        agentStartedAt = try c.decodeIfPresent(String.self, forKey: .agentStartedAt)
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine)
        assigneeName = try c.decodeIfPresent(String.self, forKey: .assigneeName)
        assigneeColor = try c.decodeIfPresent(String.self, forKey: .assigneeColor)
        assigneeAvatarUrl = try c.decodeIfPresent(String.self, forKey: .assigneeAvatarUrl)
        assigneeInitials = try c.decodeIfPresent(String.self, forKey: .assigneeInitials)
        creatorName = try c.decodeIfPresent(String.self, forKey: .creatorName)
        creatorColor = try c.decodeIfPresent(String.self, forKey: .creatorColor)
        creatorAvatarUrl = try c.decodeIfPresent(String.self, forKey: .creatorAvatarUrl)
        creatorInitials = try c.decodeIfPresent(String.self, forKey: .creatorInitials)
        projectName = try c.decodeIfPresent(String.self, forKey: .projectName)
        projectColor = try c.decodeIfPresent(String.self, forKey: .projectColor)
        labels = try c.decodeIfPresent([ApiLabel].self, forKey: .labels) ?? []
        subtasks = try c.decodeIfPresent([ApiSubtask].self, forKey: .subtasks) ?? []
        children = try c.decodeIfPresent([ApiTask].self, forKey: .children)
        comments = try c.decodeIfPresent([ApiComment].self, forKey: .comments)
        events = try c.decodeIfPresent([ApiTaskEvent].self, forKey: .events)
        chats = try c.decodeIfPresent([ApiTaskChat].self, forKey: .chats)
        attachments = try c.decodeIfPresent([ApiAttachment].self, forKey: .attachments)
        attemptLadder = try c.decodeIfPresent(ApiAttemptLadder.self, forKey: .attemptLadder)
        let roleValue = try c.decodeIfPresent(String.self, forKey: .role)
        role = (roleValue?.isEmpty == false) ? roleValue : nil
        let ownerRole = try c.decodeIfPresent(String.self, forKey: .ownerSelectedRole)
        ownerSelectedRole = (ownerRole?.isEmpty == false) ? ownerRole : nil
        let dispatched = try c.decodeIfPresent(String.self, forKey: .dispatchedRole)
        dispatchedRole = (dispatched?.isEmpty == false) ? dispatched : nil
        let machine = try c.decodeIfPresent(String.self, forKey: .machineSelectedRole)
        machineSelectedRole = (machine?.isEmpty == false) ? machine : nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(dueDate, forKey: .dueDate)
        try c.encodeIfPresent(projectId, forKey: .projectId)
        try c.encode(priority, forKey: .priority)
        try c.encodeIfPresent(assigneeId, forKey: .assigneeId)
        try c.encodeIfPresent(creatorId, forKey: .creatorId)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encodeIfPresent(agentState, forKey: .agentState)
        try c.encodeIfPresent(agentHeartbeatAt, forKey: .agentHeartbeatAt)
        try c.encodeIfPresent(position, forKey: .position)
        try c.encodeIfPresent(agentSessionId, forKey: .agentSessionId)
        try c.encodeIfPresent(startTime, forKey: .startTime)
        try c.encodeIfPresent(durationMin, forKey: .durationMin)
        try c.encode(pinned ? 1 : 0, forKey: .pinned)
        try c.encodeIfPresent(parentId, forKey: .parentId)
        try c.encode(readyForPickup ? 1 : 0, forKey: .readyForPickup)
        try c.encodeIfPresent(readySetAt, forKey: .readySetAt)
        try c.encodeIfPresent(readySetBy, forKey: .readySetBy)
        try c.encode(requiresReviewerReview ? 1 : 0, forKey: .requiresReviewerReview)
        try c.encode(needsResearch ? 1 : 0, forKey: .needsResearch)
        try c.encodeIfPresent(runRepeat, forKey: .runRepeat)
        try c.encodeIfPresent(repeatUntil, forKey: .repeatUntil)
        try c.encodeIfPresent(recurrenceSpawned, forKey: .recurrenceSpawned)
        try c.encode(childrenCount, forKey: .childrenCount)
        try c.encode(hasCollaborationPlan ? 1 : 0, forKey: .hasCollaborationPlan)
        try c.encodeIfPresent(agentStale, forKey: .agentStale)
        try c.encodeIfPresent(agentStartedAt, forKey: .agentStartedAt)
        try c.encodeIfPresent(mine, forKey: .mine)
        try c.encodeIfPresent(assigneeName, forKey: .assigneeName)
        try c.encodeIfPresent(assigneeColor, forKey: .assigneeColor)
        try c.encodeIfPresent(assigneeAvatarUrl, forKey: .assigneeAvatarUrl)
        try c.encodeIfPresent(assigneeInitials, forKey: .assigneeInitials)
        try c.encodeIfPresent(creatorName, forKey: .creatorName)
        try c.encodeIfPresent(creatorColor, forKey: .creatorColor)
        try c.encodeIfPresent(creatorAvatarUrl, forKey: .creatorAvatarUrl)
        try c.encodeIfPresent(creatorInitials, forKey: .creatorInitials)
        try c.encodeIfPresent(projectName, forKey: .projectName)
        try c.encodeIfPresent(projectColor, forKey: .projectColor)
        try c.encode(labels, forKey: .labels)
        try c.encode(subtasks, forKey: .subtasks)
        try c.encodeIfPresent(children, forKey: .children)
        try c.encodeIfPresent(comments, forKey: .comments)
        try c.encodeIfPresent(events, forKey: .events)
        try c.encodeIfPresent(attachments, forKey: .attachments)
        try c.encodeIfPresent(attemptLadder, forKey: .attemptLadder)
        try c.encodeIfPresent(role, forKey: .role)
        try c.encodeIfPresent(ownerSelectedRole, forKey: .ownerSelectedRole)
        try c.encodeIfPresent(dispatchedRole, forKey: .dispatchedRole)
        try c.encodeIfPresent(machineSelectedRole, forKey: .machineSelectedRole)
    }

    // MARK: Удобные вычисляемые даты (raw-строки остаются полями — см. DateFormats)

    public var createdAtDate: Date? { DateFormats.sqliteUTC(createdAt) }
    public var updatedAtDate: Date? { DateFormats.sqliteUTC(updatedAt) }
    public var completedAtDate: Date? { DateFormats.sqliteUTC(completedAt) }
    public var dueDateAsDate: Date? { DateFormats.calendarDate(dueDate) }
    public var isDueToday: Bool { dueDate == DateFormats.todayString() }
}
