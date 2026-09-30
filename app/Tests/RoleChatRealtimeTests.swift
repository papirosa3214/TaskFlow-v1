import Foundation
import XCTest
@testable import TaskFlow

/// Живые события чатов с ролями — формы как их шлёт сервер
/// (`server/src/routes/chats.ts`: `chat:new` с `chat_id`, `chats:typing`).
final class RoleChatRealtimeTests: XCTestCase {
    private func parse(_ json: String) -> RealtimeEvent? {
        RealtimeEvent.parse(Data(json.utf8))
    }

    func testRoleChatMessageCarriesChatID() {
        let event = parse(#"""
        {"type":"chat:new","message":{"id":"m1","chat_id":"chat-1","channel":"chat",
         "from_user_id":"role_builder","text":"готово","created_at":"2026-09-22 19:00:00"}}
        """#)
        guard case .roleChatMessage(let chatID, _) = event else {
            return XCTFail("ожидали roleChatMessage, пришло \(String(describing: event))")
        }
        XCTAssertEqual(chatID, "chat-1")
    }

    func testRoleChatMessageCarriesFullMessage() {
        let event = parse(#"""
        {"type":"chat:new","message":{"id":"m3","chat_id":"chat-1","channel":"chat",
         "from_user_id":"role_qa","from_user_name":"QA","text":"проверил",
         "created_at":"2026-10-01 10:00:00","attachments":[],"quick_replies":null,
         "is_session_marker":false,
         "steps":{"duration_ms":1200,"items":[{"kind":"step","id":"c1","tool":"read",
           "detail":"~/a.txt","status":"done","started_at":"2026-10-01T10:00:00.000Z"}]}}}
        """#)
        guard case .roleChatMessage(let chatID, let message?) = event else {
            return XCTFail("ожидали roleChatMessage с готовым сообщением, пришло \(String(describing: event))")
        }
        XCTAssertEqual(chatID, "chat-1")
        XCTAssertEqual(message.id, "m3")
        XCTAssertEqual(message.text, "проверил")
        XCTAssertEqual(message.steps?.stepCount, 1)
    }

    func testLiveEndCarriesReplyMessageID() {
        let event = parse(#"""
        {"type":"chats:live","chat_id":"chat-1","user_id":"role_qa","turn":null,"message_id":"m3"}
        """#)
        guard case .roleChatLive(_, _, nil, let messageID) = event else {
            return XCTFail("ожидали конец живого хода")
        }
        XCTAssertEqual(messageID, "m3")
    }

    func testChannelMessageWithoutChatIDStaysChannelMessage() {
        let event = parse(#"""
        {"type":"chat:new","message":{"id":"m2","chat_id":null,"channel":"chat",
         "from_user_id":"u1","to_user_id":"all","text":"привет","created_at":"2026-09-22 19:00:00"}}
        """#)
        if case .roleChatMessage = event {
            XCTFail("сообщение канала не должно считаться сообщением чата с ролями")
        }
    }

    func testTypingStartAndStop() {
        let start = parse(#"""
        {"type":"chats:typing","chat_id":"chat-1","user_id":"role_builder","name":"Разработчик","active":true}
        """#)
        guard case .roleChatTyping(let chatID, let userID, let name, let active, _) = start else {
            return XCTFail("ожидали roleChatTyping")
        }
        XCTAssertEqual(chatID, "chat-1")
        XCTAssertEqual(userID, "role_builder")
        XCTAssertEqual(name, "Разработчик")
        XCTAssertTrue(active)

        let stop = parse(#"""
        {"type":"chats:typing","chat_id":"chat-1","user_id":"role_builder","name":"Разработчик","active":false}
        """#)
        guard case .roleChatTyping(_, _, _, let stillActive, _) = stop else {
            return XCTFail("ожидали roleChatTyping")
        }
        XCTAssertFalse(stillActive)
    }

    func testTypingCarriesCurrentTool() {
        let withTool = parse(#"""
        {"type":"chats:typing","chat_id":"chat-1","user_id":"role_builder",
         "name":"Разработчик","active":true,"tool":"read"}
        """#)
        guard case .roleChatTyping(_, _, _, _, let tool) = withTool else {
            return XCTFail("ожидали roleChatTyping")
        }
        XCTAssertEqual(tool, "read")

        let withoutTool = parse(#"""
        {"type":"chats:typing","chat_id":"chat-1","user_id":"role_builder",
         "name":"Разработчик","active":true}
        """#)
        guard case .roleChatTyping(_, _, _, _, let noTool) = withoutTool else {
            return XCTFail("ожидали roleChatTyping")
        }
        XCTAssertNil(noTool)
    }

    func testLiveTurnCarriesThinkingPhrase() {
        let thinking = parse(#"""
        {"type":"chats:live","chat_id":"chat-qa","user_id":"role_qa",
         "turn":{"chat_id":"chat-qa","user_id":"role_qa","name":"QA",
                 "started_at":"2026-09-28T10:00:00.000Z","items":[],
                 "thinking":"Сначала посмотрю доску."}}
        """#)
        guard case .roleChatLive(let chatID, let userID, let turn?, _) = thinking else {
            return XCTFail("ожидали roleChatLive со снимком")
        }
        XCTAssertEqual(chatID, "chat-qa")
        XCTAssertEqual(userID, "role_qa")
        XCTAssertEqual(turn.thinking, "Сначала посмотрю доску.")

        // Старый сервер без поля — не думает, снимок разбирается как раньше.
        let old = parse(#"""
        {"type":"chats:live","chat_id":"c","user_id":"r",
         "turn":{"chat_id":"c","user_id":"r","name":"QA","items":[{"kind":"text","text":"Привет"}]}}
        """#)
        guard case .roleChatLive(_, _, let oldTurn?, _) = old else {
            return XCTFail("ожидали roleChatLive со снимком")
        }
        XCTAssertNil(oldTurn.thinking)
        XCTAssertEqual(oldTurn.items.count, 1)
    }
}
