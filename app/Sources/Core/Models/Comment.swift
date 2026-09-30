import Foundation

/// `ApiComment` — spec/API.md §3.6: поля `comments` + join `user_name/_color/
/// _avatar_url/_initials` + опциональные вложения.
public struct ApiComment: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let taskId: String?
    public let userId: String?
    public let text: String
    public let createdAt: String?
    public let userName: String?
    public let userColor: String?
    public let userAvatarUrl: String?
    public let userInitials: String?
    public let attachments: [ApiAttachment]?
    /// Запись пришла из чата, привязанного к задаче (`source == "chat"`) —
    /// сервер отдаёт сообщения чата в общем списке `comments`
    /// (`routes/tasks.ts`, LOCK-195). У обычного комментария поля нет.
    public let source: String?
    /// Чат, из которого пришло сообщение: по нему лента открывает переписку.
    public let chatID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case userId = "user_id"
        case text
        case createdAt = "created_at"
        case userName = "user_name"
        case userColor = "user_color"
        case userAvatarUrl = "user_avatar_url"
        case userInitials = "user_initials"
        case attachments
        case source
        case chatID = "chat_id"
    }

    public var createdAtDate: Date? { DateFormats.sqliteUTC(createdAt) }

    /// Сообщение чата, а не комментарий, написанный прямо в задаче.
    public var isFromChat: Bool { source == "chat" }
}
