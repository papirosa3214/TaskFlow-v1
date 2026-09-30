import Foundation

/// `ApiTaskEvent` — журнал задачи (`task_events`), spec/API.md §3.8. Только
/// INSERT/SELECT сервером. `kind` — открытый список строк (`"claimed" |
/// "state_changed" | ...`), разбирается как `String`, не `enum`.
public struct ApiTaskEvent: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let taskId: String?
    /// `nil` = системная запись, не действие конкретного пользователя.
    public let actorId: String?
    /// Имя автора — сервер присылает его JOIN'ом по `users`. `nil` у
    /// системной записи: тогда в ленте пишется «Система».
    public let actorName: String?
    public let kind: String
    public let field: String?
    public let fromValue: String?
    public let toValue: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case actorId = "actor_id"
        case actorName = "actor_name"
        case kind, field
        case fromValue = "from_value"
        case toValue = "to_value"
        case createdAt = "created_at"
    }

    public var createdAtDate: Date? { DateFormats.sqliteUTC(createdAt) }
}
