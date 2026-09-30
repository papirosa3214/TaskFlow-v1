import Foundation

/// Серверный LOCK-146: детальная карточка агента — модель, права,
/// подключённые MCP-серверы (Composio), установленные скиллы. Раньше
/// сервер не возвращал ничего из этого (только role/type/name + online/
/// activity/last_action), и iOS-карточка показывала «не настроено».
/// Поле `agent` приходит целиком из `users` (как в `ApiUser`, плюс новые
/// `model`/`permissions`/`apiTokenSetAt`).
public struct AgentDetails: Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let role: UserRole
    public let type: UserType
    public let model: String?
    public let prompt: String?
    public let executionMode: AgentExecutionMode?
    public let modelProvider: String?
    public let modelBaseURL: String?
    public let modelCredentialRef: String?
    public let permissions: AgentPermissions
    public let avatarColor: String?
    public let avatarUrl: String?
    public let avatarUrlWorking: String?
    public let avatarUrlBlocked: String?
    public let initials: String?
    public let status: UserPresenceStatus?
    public let lastSeenAt: String?
    public let createdAt: String?
    public let isSystemBot: Int?
    public let createdBy: String?
    public let apiTokenSetAt: String?
    public let mcpServers: [AgentMcpServer]
    public let skills: [AgentSkill]

    enum CodingKeys: String, CodingKey {
        case id, name, role, type, model, prompt, permissions
        case executionMode = "execution_mode"
        case modelProvider = "model_provider"
        case modelBaseURL = "model_base_url"
        case modelCredentialRef = "model_credential_ref"
        case avatarColor = "avatar_color"
        case avatarUrl = "avatar_url"
        case avatarUrlWorking = "avatar_url_working"
        case avatarUrlBlocked = "avatar_url_blocked"
        case initials, status
        case lastSeenAt = "last_seen_at"
        case createdAt = "created_at"
        case isSystemBot = "is_system_bot"
        case createdBy = "created_by"
        case apiTokenSetAt = "api_token_set_at"
        case mcpServers, skills
    }

    /// Удобные derived-поля, чтобы не таскать форматирование по UI.
    public var lastSeenDate: Date? { DateFormats.iso8601(lastSeenAt) }
    public var createdAtDate: Date? { DateFormats.sqliteUTC(createdAt) }
    public var apiTokenSetAtDate: Date? { DateFormats.sqliteUTC(apiTokenSetAt) }
}

/// Как агент получает модель: работает через уже зарегистрированный внешний
/// runtime или сервер вызывает LLM-провайдера напрямую.
public enum AgentExecutionMode: String, Codable, Sendable, Hashable, CaseIterable {
    case agentRuntime = "agent_runtime"
    case directAPI = "direct_api"

    public var title: String {
        switch self {
        case .agentRuntime: "Текущий агент"
        case .directAPI: "Напрямую по API"
        }
    }
}

/// Per-action bool. Сервер может прислать пустой объект — тогда UI
/// показывает «нет настроек», а действия под тумблерами отключены.
public struct AgentPermissions: Codable, Sendable, Hashable {
    public var canCreateTasks: Bool
    public var canDeleteTasks: Bool
    public var canManageProjects: Bool
    public var canInviteAgents: Bool
    public var canChangeSettings: Bool

    public init(
        canCreateTasks: Bool = false,
        canDeleteTasks: Bool = false,
        canManageProjects: Bool = false,
        canInviteAgents: Bool = false,
        canChangeSettings: Bool = false
    ) {
        self.canCreateTasks = canCreateTasks
        self.canDeleteTasks = canDeleteTasks
        self.canManageProjects = canManageProjects
        self.canInviteAgents = canInviteAgents
        self.canChangeSettings = canChangeSettings
    }

    enum CodingKeys: String, CodingKey {
        case canCreateTasks = "can_create_tasks"
        case canDeleteTasks = "can_delete_tasks"
        case canManageProjects = "can_manage_projects"
        case canInviteAgents = "can_invite_agents"
        case canChangeSettings = "can_change_settings"
    }

    /// Лист для отправки на сервер — сервер хранит только bool-значения.
    public func toServerMap() -> [String: Bool] {
        [
            "can_create_tasks": canCreateTasks,
            "can_delete_tasks": canDeleteTasks,
            "can_manage_projects": canManageProjects,
            "can_invite_agents": canInviteAgents,
            "can_change_settings": canChangeSettings,
        ]
    }

    /// Текст для UI — перечисление человеческим языком, чтобы карточка
    /// не выглядела как «JSON наружу». Пусто, если ничего нельзя.
    public var summary: String {
        var parts: [String] = []
        if canCreateTasks { parts.append("создавать задачи") }
        if canDeleteTasks { parts.append("удалять задачи") }
        if canManageProjects { parts.append("управлять проектами") }
        if canInviteAgents { parts.append("приглашать агентов") }
        if canChangeSettings { parts.append("менять настройки") }
        return parts.isEmpty ? "нет разрешений" : parts.joined(separator: ", ")
    }
}

/// Подключённый к агенту MCP-сервер (Composio/Smithery).
public struct AgentMcpServer: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let provider: String
    public let description: String?
    public let url: String?
    public let enabled: Bool
    public let config: AgentMcpConfig?
    public let defaultConfig: AgentMcpConfig?
    public let addedAt: String?
}

/// Скилл, установленный агенту.
public struct AgentSkill: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    public let installUrl: String?
    public let config: AgentMcpConfig?
    public let defaultConfig: AgentMcpConfig?
    public let addedAt: String?
}

/// Конфиг MCP/скилла — свободная JSON-структура (scopes, токены, опции).
/// Используем общий `JSONValue`: он уже умеет произвольное Codable-дерево,
/// действительно `Sendable` и не тащит небезопасный `Any` в модель.
public typealias AgentMcpConfig = JSONValue
