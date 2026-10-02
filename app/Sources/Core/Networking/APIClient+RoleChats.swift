import Foundation

private struct RoleChatsEnvelope: Decodable { let chats: [RoleChat] }
private struct RoleChatEnvelope: Decodable { let chat: RoleChat }
private struct RoleChatMessagesEnvelope: Decodable { let messages: [RoleChatMessage] }
private struct RoleChatMessageEnvelope: Decodable { let message: RoleChatMessage }
private struct RoleChatLiveEnvelope: Decodable { let turns: [RoleChatLiveTurn] }

private struct CreateRoleChatBody: Encodable {
    let title: String?
    let kind: String
    let member_ids: [String]
}

public extension APIClient {
    func roleChats() async throws -> [RoleChat] {
        let response: RoleChatsEnvelope = try await request(.get, "/chats")
        return response.chats
    }

    func createRoleChat(title: String?, memberIDs: [String]) async throws -> RoleChat {
        let body = CreateRoleChatBody(
            title: title,
            kind: memberIDs.count == 1 ? "direct" : "group",
            member_ids: memberIDs
        )
        let response: RoleChatEnvelope = try await request(.post, "/chats", body: body)
        return response.chat
    }

    func roleChat(id: String) async throws -> RoleChat {
        let response: RoleChatEnvelope = try await request(.get, "/chats/\(id)")
        return response.chat
    }

    func roleChatMessages(id: String) async throws -> [RoleChatMessage] {
        let response: RoleChatMessagesEnvelope = try await request(.get, "/chats/\(id)/messages")
        return response.messages
    }

    /// Идущие сейчас ходы ролей в чате — снимок для открывшего чат посреди
    /// ответа или после переподключения; дальше обновления идут `chats:live`.
    func roleChatLive(id: String) async throws -> [RoleChatLiveTurn] {
        let response: RoleChatLiveEnvelope = try await request(.get, "/chats/\(id)/live")
        return response.turns
    }

    func sendRoleChatMessage(chatID: String, text: String, attachmentIDs: [String] = [], mode: RoleChatWorkMode = .work) async throws -> RoleChatMessage {
        struct Body: Encodable { let text: String; let attachment_ids: [String]; let work_mode: RoleChatWorkMode }
        let response: RoleChatMessageEnvelope = try await request(
            .post, "/chats/\(chatID)/messages", body: Body(text: text, attachment_ids: attachmentIDs, work_mode: mode)
        )
        return response.message
    }

    /// Новая сессия без удаления истории (владелец 25.09.2026, docs/ПЛАН
    /// Супер Секретарь/): сбрасывает память роли в этом чате, история
    /// остаётся — сервер сам кладёт видимую метку-разделитель.
    func newRoleChatSession(chatID: String, roleID: String) async throws -> RoleChatMessage {
        struct Body: Encodable { let role_id: String }
        let response: RoleChatMessageEnvelope = try await request(
            .post, "/chats/\(chatID)/new-session", body: Body(role_id: roleID)
        )
        return response.message
    }

    /// Остановить идущий ход роли (или всех ролей, если `roleID == nil`).
    /// Написанное ролью до остановки сервер кладёт в чат обычным ответом.
    @discardableResult
    func stopRoleChat(chatID: String, roleID: String? = nil) async throws -> Int {
        let body: [String: JSONValue] = roleID.map { ["role_id": .string($0)] } ?? [:]
        struct Result: Decodable { let stopped: Int }
        let response: Result = try await request(.post, "/chats/\(chatID)/stop", body: body)
        return response.stopped
    }

    /// Сервер использует тот же raw-upload, что `/chat/attachments`.
    func uploadRoleChatAttachment(fileName: String, data: Data, mime: String) async throws -> ApiChatAttachment {
        struct Envelope: Decodable { let attachment: ApiChatAttachment }
        let response: Envelope = try await uploadRaw(
            path: "/chats/attachments",
            query: [URLQueryItem(name: "name", value: fileName)],
            data: data,
            mime: mime
        )
        return response.attachment
    }

    func addRoleChatMember(chatID: String, memberID: String) async throws -> RoleChat {
        let response: RoleChatEnvelope = try await request(
            .post, "/chats/\(chatID)/members", body: ["member_id": memberID]
        )
        return response.chat
    }

    func removeRoleChatMember(chatID: String, memberID: String) async throws -> RoleChat {
        let response: RoleChatEnvelope = try await request(
            .delete, "/chats/\(chatID)/members/\(memberID)"
        )
        return response.chat
    }

    /// Отметить чат прочитанным (участник). По этой отметке список чатов
    /// считает бейдж непрочитанных (миграция 055); зовётся при открытии
    /// комнаты и когда в открытом чате появилось чужое сообщение.
    func markRoleChatRead(id: String) async throws {
        try await requestVoid(.post, "/chats/\(id)/read")
    }

    /// Удалить сообщения чата. `ids` — выборка из режима выбора в комнате;
    /// пустой список означает «очистить чат целиком» и разрешён только
    /// создателю (владелец 21.09.2026: «либо удалить все, либо выбрать
    /// отдельные сообщения и потом удалить их»).
    @discardableResult
    func deleteRoleChatMessages(chatID: String, ids: [String] = []) async throws -> Int {
        var query: [URLQueryItem] = []
        if !ids.isEmpty {
            query.append(URLQueryItem(name: "ids", value: ids.joined(separator: ",")))
        }
        struct Result: Decodable { let deleted: Int }
        let response: Result = try await request(.delete, "/chats/\(chatID)/messages", query: query)
        return response.deleted
    }

    /// Удалить чат целиком (создатель). Сообщения уходят каскадом.
    func deleteRoleChat(id: String) async throws {
        try await requestVoid(.delete, "/chats/\(id)")
    }

    /// Переименовать чат (создатель). Пустая строка снимает название — тогда
    /// список и шапка показывают состав участников.
    func renameRoleChat(id: String, title: String) async throws -> RoleChat {
        let body: [String: JSONValue] = ["title": .string(title)]
        let response: RoleChatEnvelope = try await request(.patch, "/chats/\(id)", body: body)
        return response.chat
    }

    /// Привязать чат к задаче или отвязать (`nil`). Только создатель чата.
    /// Привязанный чат показывается в ленте задачи, а его сообщения начинают
    /// наследовать её — сервер переносит и уже написанные.
    ///
    /// Тело собирается вручную, а не `Encodable` с опционалом: синтезированный
    /// энкодер ПРОПУСКАЕТ `nil`, и сервер не отличил бы «отвязать» от «поле не
    /// пришло». Здесь `task_id: null` уходит явно.
    func bindRoleChatToTask(id: String, taskID: String?) async throws -> RoleChat {
        let body: [String: JSONValue] = ["task_id": taskID.map { .string($0) } ?? .null]
        let response: RoleChatEnvelope = try await request(.patch, "/chats/\(id)", body: body)
        return response.chat
    }
}
