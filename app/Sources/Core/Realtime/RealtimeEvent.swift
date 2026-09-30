import Foundation

/// Событие реалтайм-канала — spec/API.md §4/§4.1. Хендшейк `{"type":"connected"}`
/// подтверждён живым подключением к `ws://192.168.1.110:3001/ws` 31.08.2026
/// (Node-скрипт поверх `ws`, свой агентский токен) — сервер шлёт его сразу
/// после апгрейда, без обёртки, ровно как в документе.
///
/// Часть форм (`task:activity`, `chat:typing`, `error`) спека прямо помечает
/// как «не проверено исчерпывающе» (§10) — разбор здесь нарочно ЗАЩИТНЫЙ:
/// одно неожиданное поле не должно ронять весь WS-пайплайн, непонятное
/// событие уходит в `.unknown`, а не кидает ошибку декодера наружу.
public enum RealtimeEvent: Sendable {
    case connected
    case ping
    case pong
    case taskCreated(ApiTask)
    case taskUpdated(ApiTask)
    case taskCompleted(ApiTask)
    /// Спека не расписывает `task:deleted` отдельно от общего «сама сущность
    /// целиком» — разбираем оба варианта: полный `ApiTask` ИЛИ голый `{ id }`.
    case taskDeleted(id: String)
    case taskState(ApiTask)
    case taskActivity(taskId: String?, raw: JSONValue)
    case notificationNew(ApiNotification)
    case chatNew(ApiChatMessage)
    case chatTyping(raw: JSONValue)
    /// Новое сообщение в чате с ролями (`chat:new` с `chat_id`). Несём только
    /// id чата: экран сам перечитывает ленту и список — формат строки у
    /// новых чатов свой (`RoleChatMessage`), не `ApiChatMessage` канала.
    case roleChatMessage(chatId: String)
    /// Роль готовит ответ в чате (`chats:typing`): `active` — начала/закончила.
    /// Сигнал даёт сервер ровно на время ответа роли (22.09.2026).
    case roleChatTyping(chatId: String, userId: String, name: String, active: Bool, tool: String?)
    /// Живой ход роли в чате (`chats:live`, 27.09.2026): снимок целиком —
    /// текст по словам и шаги. `turn == nil` — ход закончился, ответ придёт
    /// обычным `chat:new`.
    case roleChatLive(chatId: String, userId: String, turn: RoleChatLiveTurn?)
    case serverError(message: String?)
    case unknown(type: String, raw: JSONValue)

    private struct Envelope: Decodable { let type: String }
    private struct BareID: Decodable { let id: String }
    private struct TaskIdField: Decodable { let task_id: String? }
    private struct ErrorPayload: Decodable { let message: String?; let error: String? }
    private struct ChatIDEnvelope: Decodable {
        struct Message: Decodable { let chat_id: String? }
        let message: Message?
    }
    private struct RoleTypingPayload: Decodable {
        let chat_id: String
        let user_id: String
        let name: String?
        let active: Bool
        let tool: String?
    }
    private struct RoleLivePayload: Decodable {
        let chat_id: String
        let user_id: String
        let turn: RoleChatLiveTurn?
    }

    public static func parse(_ data: Data) -> RealtimeEvent? {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { return nil }
        let raw = (try? decoder.decode(JSONValue.self, from: data)) ?? .null

        func decodeTask() -> ApiTask? { try? decoder.decode(ApiTask.self, from: data) }

        switch envelope.type {
        case "connected": return .connected
        case "ping": return .ping
        case "pong": return .pong
        case "task:created":
            return decodeTask().map(RealtimeEvent.taskCreated) ?? .unknown(type: envelope.type, raw: raw)
        case "task:updated":
            return decodeTask().map(RealtimeEvent.taskUpdated) ?? .unknown(type: envelope.type, raw: raw)
        case "task:completed":
            return decodeTask().map(RealtimeEvent.taskCompleted) ?? .unknown(type: envelope.type, raw: raw)
        case "task:deleted":
            if let task = decodeTask() { return .taskDeleted(id: task.id) }
            if let bare = try? decoder.decode(BareID.self, from: data) { return .taskDeleted(id: bare.id) }
            return .unknown(type: envelope.type, raw: raw)
        case "task:state":
            return decodeTask().map(RealtimeEvent.taskState) ?? .unknown(type: envelope.type, raw: raw)
        case "task:activity":
            let taskId = (try? decoder.decode(TaskIdField.self, from: data))?.task_id
            return .taskActivity(taskId: taskId, raw: raw)
        case "notification:new":
            guard let n = try? decoder.decode(ApiNotification.self, from: data) else {
                return .unknown(type: envelope.type, raw: raw)
            }
            return .notificationNew(n)
        case "chat:new":
            // Сообщение чата с ролями — отдельное событие. Раньше оно
            // разбиралось как сообщение канала (у него тоже channel = chat)
            // и могло попасть в открытую ленту канала координации.
            if let envelope = try? decoder.decode(ChatIDEnvelope.self, from: data),
               let chatId = envelope.message?.chat_id, !chatId.isEmpty {
                return .roleChatMessage(chatId: chatId)
            }
            guard let m = try? decoder.decode(ApiChatMessage.self, from: data) else {
                return .unknown(type: envelope.type, raw: raw)
            }
            return .chatNew(m)
        case "chat:typing":
            return .chatTyping(raw: raw)
        case "chats:typing":
            guard let p = try? decoder.decode(RoleTypingPayload.self, from: data) else {
                return .unknown(type: envelope.type, raw: raw)
            }
            return .roleChatTyping(chatId: p.chat_id, userId: p.user_id, name: p.name ?? "", active: p.active, tool: p.tool)
        case "chats:live":
            guard let p = try? decoder.decode(RoleLivePayload.self, from: data) else {
                return .unknown(type: envelope.type, raw: raw)
            }
            return .roleChatLive(chatId: p.chat_id, userId: p.user_id, turn: p.turn)
        case "error":
            let payload = try? decoder.decode(ErrorPayload.self, from: data)
            return .serverError(message: payload?.message ?? payload?.error)
        default:
            return .unknown(type: envelope.type, raw: raw)
        }
    }
}
