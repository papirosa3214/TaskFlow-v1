import Foundation

/// Внутренний чат координации агентов — spec/API.md §5.8. Минимальный набор
/// методов для экрана «Чат» (Волна 2). Удалены 2026-09-11 по DEAD-CODE-CLEANUP-REPORT.md:
/// chatMessages, sendChatMessage, sendChatTyping, markChatRead — старые контракты,
/// заменены `ChatAPI.swift` в `Sources/Features/Chat/`.
public extension APIClient {

    func chatParticipants(channel: ChatChannel? = nil) async throws -> [ApiChatParticipant] {
        var query: [URLQueryItem] = []
        if let channel { query.append(URLQueryItem(name: "channel", value: channel.rawValue)) }
        return try await request(.get, "/chat/participants", query: query)
    }

    func chatStats() async throws -> ApiChatStats {
        try await request(.get, "/chat/stats")
    }

    /// Сколько сообщений пропущено с последнего прочтения — `GET /chat/unread`.
    /// Это старый канал координации (owner/agents) с единственной отметкой
    /// прочтения на пользователя; у новых чатов счётчик свой, на участнике
    /// чата (миграция 055, `unread_count` в `GET /api/chats`). Ключ ответа
    /// сервер отдаёт по-русски — как и остальные поля этого эндпоинта.
    ///
    /// Нужен списку чатов: блок «Секретарь» — это как раз канал `owner`,
    /// и его бейдж считается здесь.
    struct ChatUnread: Decodable, Sendable {
        public let count: Int
        enum CodingKeys: String, CodingKey { case count = "непрочитано" }
    }

    func chatUnread() async throws -> ChatUnread {
        try await request(.get, "/chat/unread")
    }
}
