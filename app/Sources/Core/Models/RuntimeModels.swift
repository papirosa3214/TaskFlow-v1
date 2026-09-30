import Foundation

// LOCK-175, этап 1 миграции iOS на серверную модель
// `AgentProfile → Pi Runtime → Model → Provider/Auth`.
//
// Это только DTO — источник истины TaskFlow Server. Контракты сверены
// 18.09.2026 с серверным фасадом (`server/src/runtime/types.ts`,
// `server/src/routes/runtime.ts`, `server/src/runtime/PiRuntimeAdapter.ts`,
// `server/src/runtime/AuthSession.ts`) и спекой
// `docs/superpowers/specs/2026-09-18-pi-runtime-facade.md`.
//
// Никакой бизнес-логики сервера здесь не дублируется: клиент показывает
// то, что отдал рантайм, и не решает сам, какая модель «правильная».
//
// В серверном JSON смешаны snake_case (`account_id`, `runtime_id`) и
// camelCase (`modelPolicy`, `contextWindow`, `authSessionId`) — ключи заданы
// явно через `CodingKeys`, полагаться на `.convertFromSnakeCase` нельзя.
//
// Незнакомые значения статусов (сервер новее клиента) не роняют
// декодирование: у перечислений есть `unknown`.

// MARK: - Runtime

/// Единственный рантайм первого этапа — Pi. `kind` оставлен строкой, чтобы
/// будущий второй рантайм не ломал старый клиент.
public enum RuntimeState: String, Codable, Sendable, Hashable {
    case ready, starting, down, unknown

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = RuntimeState(rawValue: raw) ?? .unknown
    }
}

public struct RuntimeStatus: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: String
    public let status: RuntimeState
    public let version: String
    public let endpoint: String

    public var isOnline: Bool { status == .ready }

    /// Человекочитаемая подпись для Settings → Server.
    public var statusTitle: String {
        switch status {
        case .ready: "Online"
        case .starting: "Запускается"
        case .down: "Offline"
        case .unknown: "Неизвестно"
        }
    }
}

// MARK: - AgentProfile

public enum AgentProfileStatus: String, Codable, Sendable, Hashable {
    case ready, working, blocked, unavailable, unknown

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = AgentProfileStatus(rawValue: raw) ?? .unknown
    }

    public var title: String {
        switch self {
        case .ready: "Свободен"
        case .working: "Работает"
        case .blocked: "Заблокирован"
        case .unavailable: "Недоступен"
        case .unknown: "—"
        }
    }
}

/// Размер исходника промпта на сервере — клиент его не хранит и не правит.
public struct AgentPrompt: Codable, Sendable, Hashable {
    public let source: String
    public let size: Int
}

/// Установленный агенту скилл (`GET /api/runtime/profiles`).
public struct AgentProfileSkill: Codable, Sendable, Hashable {
    public let name: String
    public let description: String?
}

/// Политика моделей роли: primary + УПОРЯДОЧЕННЫЕ fallback'и. Порядок —
/// это порядок эскалации, сортировать его на клиенте нельзя.
public struct AgentModelPolicy: Codable, Sendable, Hashable {
    public let primary: String
    public let fallbacks: [String]

    /// Полная цепочка в порядке применения: primary, затем fallback'и.
    public var orderedModels: [String] { [primary] + fallbacks }
}

/// Профиль агента. `id == role`, `account_id` — ролевая учётка в `users`.
/// Runtime всегда Pi (`runtime_id == "runtime:pi"`), в обычном UI не
/// показывается.
public struct AgentProfile: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let role: String
    public let title: String
    public let accountID: String
    public let runtimeID: String
    public let prompt: AgentPrompt
    public let skills: [AgentProfileSkill]
    public let tools: [String]
    public let permissions: String?
    public let modelPolicy: AgentModelPolicy
    public let status: AgentProfileStatus

    public static let autoAssignID = "auto"

    enum CodingKeys: String, CodingKey {
        case id, role, title, prompt, skills, tools, permissions, status
        case accountID = "account_id"
        case runtimeID = "runtime_id"
        case modelPolicy
    }
}

// MARK: - Model

/// Модель из каталога Pi. `available` — авторизован ли провайдер реально;
/// каталог и доступность приходят одним списком.
public struct RuntimeModel: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let provider: String
    public let runtimeID: String
    public let available: Bool
    public let name: String?
    public let contextWindow: Int?
    public let maxTokens: Int?
    public let thinking: Bool?
    public let images: Bool?

    /// Имя из каталога Pi, иначе id — в списках показываем это.
    public var displayName: String { name ?? id }

    /// Идентификатор строки в списке: у одного id бывают разные провайдеры.
    public var uid: String { "\(provider):\(id)" }

    enum CodingKeys: String, CodingKey {
        case id, provider, available, name, contextWindow, maxTokens, thinking, images
        case runtimeID = "runtime_id"
    }
}

// MARK: - Provider

public enum ProviderStatus: String, Codable, Sendable, Hashable {
    case connected, disconnected, expired, unknown

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = ProviderStatus(rawValue: raw) ?? .unknown
    }

    public var title: String {
        switch self {
        case .connected: "Подключён"
        case .disconnected: "Не подключён"
        case .expired: "Истёк доступ"
        case .unknown: "—"
        }
    }
}

public enum ProviderAuthMethod: String, Codable, Sendable, Hashable {
    case apiKey = "api_key"
    case oauth
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = ProviderAuthMethod(rawValue: raw) ?? .unknown
    }
}

/// Провайдер рантайма. TaskFlow iOS НЕ хранит credentials — только статус
/// и способы авторизации, которые объявил Pi.
public struct RuntimeProvider: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let status: ProviderStatus
    /// Тип ТЕКУЩИХ credentials: `null` — их нет.
    public let authType: ProviderAuthMethod?
    /// Способы авторизации, которые провайдер поддерживает вообще.
    public let authMethods: [ProviderAuthMethod]

    public var supportsOAuth: Bool { authMethods.contains(.oauth) }
    public var supportsAPIKey: Bool { authMethods.contains(.apiKey) }

    enum CodingKeys: String, CodingKey {
        case id = "provider"
        case name, status, authType, authMethods
    }
}

/// Ответ `POST /api/runtime/providers/:provider/auth`. Сервер отвечает
/// двумя формами: записью api_key сразу (`status`, `authType`) либо 202 с
/// `authSessionId` для OAuth. Поэтому все поля опциональны.
public struct ProviderAuthStart: Codable, Sendable, Hashable {
    public let provider: String?
    public let status: ProviderStatus?
    public let authType: ProviderAuthMethod?
    public let authSessionID: String?

    enum CodingKeys: String, CodingKey {
        case provider, status, authType
        case authSessionID = "authSessionId"
    }
}

// MARK: - AgentRun

public enum AgentAttemptStatus: String, Codable, Sendable, Hashable {
    case running, completed, failed, cancelled, unknown

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = AgentAttemptStatus(rawValue: raw) ?? .unknown
    }
}

/// Одна попытка внутри запуска. История неизменна: при fallback сервер
/// создаёт НОВУЮ попытку, у старой навсегда остаётся её модель.
public struct AgentRunAttempt: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let model: String?
    public let provider: String?
    public let status: AgentAttemptStatus
    public let outcome: String?
    public let startedAt: String
    public let finishedAt: String?
    public let reason: String?

    enum CodingKeys: String, CodingKey {
        case id, model, provider, status, outcome, reason
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }
}

public enum AgentRunStatus: String, Codable, Sendable, Hashable {
    case queued, running, completed, failed, cancelled, unknown

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = AgentRunStatus(rawValue: raw) ?? .unknown
    }
}

/// Краткая сводка запуска агента. Пока нигде в UI не разворачивается в
/// отдельный экран — используется карточкой задачи и «Работой агентов».
public struct AgentRunSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let taskID: String
    public let agentID: String
    public let runtimeID: String
    public let provider: String?
    public let model: String?
    public let sessionID: String?
    public let status: AgentRunStatus
    public let startedAt: String
    public let finishedAt: String?
    public let stopReason: String?
    public let attempts: [AgentRunAttempt]?

    enum CodingKeys: String, CodingKey {
        case id, provider, model, status, attempts
        case taskID = "task_id"
        case agentID = "agent_id"
        case runtimeID = "runtime_id"
        case sessionID = "session_id"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case stopReason = "stop_reason"
    }
}

// MARK: - AuthSession

public enum AuthSessionStatus: String, Codable, Sendable, Hashable {
    case starting
    case waitingUser = "waiting_user"
    case processing
    case connected
    case failed
    case cancelled
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = AuthSessionStatus(rawValue: raw) ?? .unknown
    }

    public var isFinished: Bool {
        switch self {
        case .connected, .failed, .cancelled: true
        default: false
        }
    }

    /// Подпись для UI авторизации провайдера.
    public var title: String {
        switch self {
        case .starting: "Запускаю…"
        case .waitingUser: "Ждём ваш шаг в браузере"
        case .processing: "Проверяю…"
        case .connected: "Подключено"
        case .failed: "Не удалось"
        case .cancelled: "Отменено"
        case .unknown: "—"
        }
    }
}

public enum AuthPromptType: String, Codable, Sendable, Hashable {
    case text, secret, select
    case manualCode = "manual_code"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = AuthPromptType(rawValue: raw) ?? .unknown
    }
}

public struct AuthPromptOption: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let description: String?
}

/// Запрос ввода, который Pi ждёт от пользователя. Ответ уходит через
/// `POST /api/runtime/auth/:id/input`.
public struct AuthPrompt: Codable, Sendable, Hashable {
    public let type: AuthPromptType
    public let message: String
    public let placeholder: String?
    public let options: [AuthPromptOption]?
}

/// Событие auth-сессии (SSE или polling-снимок). `data` — свободная
/// структура: у `auth_url` это `{url, instructions}`, у `device_code` —
/// `{userCode, verificationUri, …}` и т. д.
public struct AuthSessionEvent: Codable, Sendable, Hashable {
    public let seq: Int
    public let at: String
    public let type: String
    public let data: [String: JSONValue]
}

/// Короткоживущая OAuth-сессия (10 минут). Клиент только инициирует flow,
/// credentials остаются в Pi/vault.
public struct AuthSession: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let provider: String
    public let status: AuthSessionStatus
    public let createdAt: String
    public let expiresAt: String
    public let currentPrompt: AuthPrompt?
    public let error: String?
    public let events: [AuthSessionEvent]

    enum CodingKeys: String, CodingKey {
        case id, provider, status, createdAt, expiresAt, currentPrompt, error, events
    }
}
