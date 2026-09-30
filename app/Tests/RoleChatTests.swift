import Foundation
import XCTest
@testable import TaskFlow

/// Формы JSON соответствуют ответам `/api/chats` и `/api/chats/:id/messages`.
final class RoleChatTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testGroupChatDecodesServerFieldsAndMembers() throws {
        let chat = try decode(RoleChat.self, #"""
        {
          "id": "chat-1", "title": null, "kind": "group", "created_by": "owner-1",
          "task_id": null, "created_at": "2026-09-21T10:00:00.000Z",
          "members": [
            { "id": "owner-1", "name": "Максим", "role": "owner", "type": "human",
              "avatar_color": null, "avatar_url": null, "initials": "М" },
            { "id": "role_architect", "name": "Архитектор", "role": "architect",
              "type": "agent", "avatar_color": "#345678", "avatar_url": "/avatar/a.png",
              "initials": "А" },
            { "id": "role_reviewer", "name": "Ревьюер", "role": "reviewer",
              "type": "agent", "avatar_color": null, "avatar_url": null,
              "initials": "Р" }
          ],
          "last_message": {
            "text": "Проверил задачу", "created_at": "2026-09-21T10:01:00.000Z",
            "from_user_id": "role_reviewer"
          }
        }
        """#)

        XCTAssertEqual(chat.id, "chat-1")
        XCTAssertNil(chat.title)
        XCTAssertEqual(chat.kind, "group")
        XCTAssertEqual(chat.createdBy, "owner-1")
        XCTAssertEqual(chat.members.map(\.id), ["owner-1", "role_architect", "role_reviewer"])
        XCTAssertEqual(chat.members[1].avatarColor, "#345678")
        XCTAssertEqual(chat.members[1].avatarURL, "/avatar/a.png")
        XCTAssertEqual(chat.members[1].initials, "А")
        XCTAssertEqual(chat.lastMessage?.text, "Проверил задачу")
        XCTAssertEqual(chat.lastMessage?.fromUserID, "role_reviewer")
        XCTAssertEqual(chat.displayTitle(excluding: "owner-1"), "Архитектор, Ревьюер")
    }

    func testTitleAndParticipantFallbacks() throws {
        let named = try decode(RoleChat.self, #"""
        {"id":"chat-2","title":"План релиза","kind":"group","created_by":"owner-1",
         "members":[{"id":"owner-1","name":"Максим"},
                    {"id":"role_architect","name":"Архитектор"}],"last_message":null}
        """#)
        XCTAssertEqual(named.displayTitle(excluding: "owner-1"), "План релиза")
        XCTAssertNil(named.lastMessage)
        XCTAssertNil(named.members[1].avatarURL)

        let untitled = try decode(RoleChat.self, #"""
        {"id":"chat-3","title":"  \n ","kind":"group","created_by":"owner-1",
         "members":[{"id":"owner-1","name":"Максим"},
                    {"id":"role_architect","name":" Архитектор "},
                    {"id":"role_reviewer","name":"Ревьюер"}]}
        """#)
        XCTAssertEqual(untitled.displayTitle(excluding: "owner-1"), "Архитектор, Ревьюер")
        XCTAssertNil(untitled.lastMessage)

        let emptyGroup = try decode(RoleChat.self, #"""
        {"id":"chat-4","title":null,"kind":"group","created_by":"owner-1",
         "members":[{"id":"owner-1","name":"Максим"}]}
        """#)
        XCTAssertEqual(emptyGroup.displayTitle(excluding: "owner-1"), "Групповой чат")
    }

    func testDirectChatUsesOtherMemberName() throws {
        let chat = try decode(RoleChat.self, #"""
        {"id":"chat-5","title":null,"kind":"direct","created_by":"owner-1",
         "members":[{"id":"owner-1","name":"Максим"},
                    {"id":"role_secretary","name":"Секретарь"}]}
        """#)
        XCTAssertEqual(chat.displayTitle(excluding: "owner-1"), "Секретарь")
    }

    func testMessageDecodesServerAuthorFields() throws {
        let message = try decode(RoleChatMessage.self, #"""
        {
          "id": "msg-1", "chat_id": "chat-1", "from_user_id": "role_reviewer",
          "from_user_name": "Ревьюер", "from_user_color": "#123456",
          "from_user_avatar_url": "/avatar/reviewer.png", "from_user_initials": "Р",
          "text": "Проверил задачу", "created_at": "2026-09-21T10:01:00.000Z",
          "attachments": [], "is_session_marker": false
        }
        """#)

        XCTAssertEqual(message.id, "msg-1")
        XCTAssertEqual(message.chatID, "chat-1")
        XCTAssertEqual(message.fromUserID, "role_reviewer")
        XCTAssertEqual(message.fromUserName, "Ревьюер")
        XCTAssertEqual(message.fromUserColor, "#123456")
        XCTAssertEqual(message.fromUserAvatarURL, "/avatar/reviewer.png")
        XCTAssertEqual(message.fromUserInitials, "Р")
        XCTAssertEqual(message.text, "Проверил задачу")
        XCTAssertEqual(message.createdAt, "2026-09-21T10:01:00.000Z")
    }

    func testMessageAcceptsNullableAuthor() throws {
        let message = try decode(RoleChatMessage.self, #"""
        {"id":"msg-2","chat_id":"chat-1","from_user_id":null,
         "from_user_name":null,"from_user_color":null,"from_user_avatar_url":null,
         "from_user_initials":null,"text":"Системное сообщение","created_at":null,
         "is_session_marker":false}
        """#)
        XCTAssertNil(message.fromUserID)
        XCTAssertNil(message.fromUserName)
        XCTAssertNil(message.fromUserAvatarURL)
        XCTAssertNil(message.createdAt)
    }
}
