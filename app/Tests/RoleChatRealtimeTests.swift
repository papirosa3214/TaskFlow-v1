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
        guard case .roleChatMessage(let chatID) = event else {
            return XCTFail("ожидали roleChatMessage, пришло \(String(describing: event))")
        }
        XCTAssertEqual(chatID, "chat-1")
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
        guard case .roleChatLive(let chatID, let userID, let turn?) = thinking else {
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
        guard case .roleChatLive(_, _, let oldTurn?) = old else {
            return XCTFail("ожидали roleChatLive со снимком")
        }
        XCTAssertNil(oldTurn.thinking)
        XCTAssertEqual(oldTurn.items.count, 1)
    }
}
