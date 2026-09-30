import Foundation
import XCTest
@testable import TaskFlow

/// Живой ход роли в чате (LOCK-229) — формы как их шлёт сервер
/// (`server/src/runtime/chatLiveTurn.ts`: `chats:live`, `chat_messages.steps`).
final class RoleChatLiveTurnTests: XCTestCase {
    private func parse(_ json: String) -> RealtimeEvent? {
        RealtimeEvent.parse(Data(json.utf8))
    }

    /// Прокрутить часы очереди, пока текст не выйдет весь.
    private func drain(_ pacer: inout RoleLiveTextPacer, step: TimeInterval = 0.016) {
        var guardTicks = 10_000
        while pacer.hasPendingText && guardTicks > 0 {
            pacer.advance(elapsed: step)
            guardTicks -= 1
        }
    }

    func testPacerRevealsWholeWordsAndPreservesProgressAcrossSnapshots() {
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text("Привет, как дела")])
        pacer.advance(elapsed: 0.2)
        guard case .text(let first)? = pacer.visibleItems.first else {
            return XCTFail("ожидали начало текста")
        }
        // Слово целиком, без обрывков: «Привет,» или «Привет, как».
        XCTAssertTrue(["Привет,", "Привет, как"].contains(first), "показано: \(first)")
        pacer.ingest([.text("Привет, как дела? Всё хорошо.")])
        XCTAssertEqual(pacer.visibleItems, [.text(first)])
        drain(&pacer)
        XCTAssertEqual(pacer.visibleItems, [.text("Привет, как дела? Всё хорошо.")])
    }

    func testPacerWaitsForCutWordThenShowsIt() {
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text("Смотрю доск")])
        // Первое слово успевает выйти, а хвост «доск» может дописаться — ждём.
        for _ in 0..<18 { pacer.advance(elapsed: 0.016) }
        XCTAssertEqual(pacer.visibleItems, [.text("Смотрю")])
        pacer.ingest([.text("Смотрю доску")])
        drain(&pacer)
        XCTAssertEqual(pacer.visibleItems, [.text("Смотрю доску")])
    }

    func testPacerSpeedsUpWithBacklog() {
        var slow = RoleLiveTextPacer()
        slow.ingest([.text(String(repeating: "слово ", count: 5))])
        var fast = RoleLiveTextPacer()
        fast.ingest([.text(String(repeating: "слово ", count: 300))])
        for _ in 0..<20 {
            slow.advance(elapsed: 0.016)
            fast.advance(elapsed: 0.016)
        }
        XCTAssertGreaterThan(fast.rate, slow.rate * 3)
    }

    func testPacerShowsStepsAfterPreviousTextAndResetsChangedText() {
        let step = RoleChatLiveStep(id: "s", tool: "read", detail: nil, status: .running)
        let thinking = RoleChatThinking(id: "t", text: "Думаю", isRunning: true)
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text("Проверяю файл"), .step(step), .thinking(thinking), .text("Готово")])
        pacer.advance(elapsed: 0.05)
        XCTAssertFalse(pacer.visibleItems.contains(.step(step)), "шаг не обгоняет текст перед ним")
        drain(&pacer)
        XCTAssertEqual(pacer.visibleItems, [.text("Проверяю файл"), .step(step), .thinking(thinking), .text("Готово")])
        pacer.ingest([.text("Новый ответ")])
        XCTAssertTrue(pacer.visibleItems.isEmpty)
    }

    func testRevealFadeGrowsWithDistanceAndTime() {
        let now = Date()
        let fade = RoleTextFade(rate: 100, lastRevealAt: now, isAnimating: true)
        XCTAssertEqual(fade.opacity(distance: 0, now: now), 0, accuracy: 0.001)
        XCTAssertGreaterThan(fade.opacity(distance: 20, now: now), fade.opacity(distance: 5, now: now))
        XCTAssertEqual(fade.opacity(distance: 0, now: now.addingTimeInterval(1)), 1, accuracy: 0.001)
        XCTAssertEqual(fade.shifted(by: 100).opacity(distance: 0, now: now), 1, accuracy: 0.001)
    }

    func testLiveEventCarriesThinkingItem() {
        let event = parse(#"""
        {"type":"chats:live","chat_id":"c","user_id":"r",
         "turn":{"chat_id":"c","user_id":"r","name":"QA","thinking":"Смотрю.",
                 "items":[{"kind":"thinking","id":"thinking-0","tool":"thinking",
                           "text":"Смотрю. Потом сравню","status":"running",
                           "started_at":"2026-09-30T09:00:00.000Z"}]}}
        """#)
        guard case .roleChatLive(_, _, let turn, _) = event, let turn else {
            return XCTFail("ожидали снимок")
        }
        XCTAssertEqual(turn.runningThinking?.text, "Смотрю. Потом сравню")
        XCTAssertEqual(turn.items.filter(\.isStep).count, 0)
    }

    func testSavedThinkingHasDuration() throws {
        let json = #"""
        {"duration_ms":15000,"items":[
          {"kind":"thinking","id":"thinking-0","tool":"thinking","text":"План.","status":"done",
           "started_at":"2026-09-30T09:00:00.000Z","ended_at":"2026-09-30T09:00:12.400Z"}]}
        """#
        let steps = try JSONDecoder().decode(RoleChatSteps.self, from: Data(json.utf8))
        XCTAssertTrue(steps.hasDetails)
        XCTAssertEqual(steps.stepCount, 0)
        guard case .thinking(let thinking)? = steps.items.first else { return XCTFail("ожидали размышление") }
        XCTAssertFalse(thinking.isRunning)
        XCTAssertEqual(thinking.durationSeconds, 12)
    }

    func testLiveEventCarriesTextAndSteps() {
        let event = parse(#"""
        {"type":"chats:live","chat_id":"chat-secretary","user_id":"u-secretary",
         "turn":{"chat_id":"chat-secretary","user_id":"u-secretary","name":"Секретарь",
                 "started_at":"2026-09-27T09:00:00.000Z",
                 "items":[{"kind":"text","text":"Смотрю."},
                          {"kind":"step","id":"c1","tool":"read","detail":"~/a.txt",
                           "status":"running","started_at":"2026-09-27T09:00:01.000Z"}]}}
        """#)
        guard case .roleChatLive(let chatID, let userID, let turn, _) = event, let turn else {
            return XCTFail("ожидали roleChatLive со снимком, пришло \(String(describing: event))")
        }
        XCTAssertEqual(chatID, "chat-secretary")
        XCTAssertEqual(userID, "u-secretary")
        XCTAssertEqual(turn.name, "Секретарь")
        XCTAssertNotNil(turn.startDate)
        XCTAssertEqual(turn.items, [
            .text("Смотрю."),
            .step(RoleChatLiveStep(id: "c1", tool: "read", detail: "~/a.txt", status: .running,
                                   startedAt: "2026-09-27T09:00:01.000Z")),
        ])
    }

    func testLiveEventWithNullTurnMeansFinished() {
        let event = parse(#"""
        {"type":"chats:live","chat_id":"chat-1","user_id":"role_qa","turn":null}
        """#)
        guard case .roleChatLive(_, let userID, let turn, _) = event else {
            return XCTFail("ожидали roleChatLive")
        }
        XCTAssertEqual(userID, "role_qa")
        XCTAssertNil(turn)
    }

    func testUnknownStepStatusDoesNotBreakSnapshot() {
        let event = parse(#"""
        {"type":"chats:live","chat_id":"c","user_id":"r",
         "turn":{"chat_id":"c","user_id":"r","name":"QA","items":[
           {"kind":"step","id":"s","tool":"mcp_x","status":"queued"}]}}
        """#)
        guard case .roleChatLive(_, _, let turn, _) = event, let turn else {
            return XCTFail("ожидали снимок")
        }
        XCTAssertEqual(turn.items, [.step(RoleChatLiveStep(id: "s", tool: "mcp_x", detail: nil, status: .running))])
    }

    func testMessageDecodesSavedSteps() throws {
        let json = #"""
        {"id":"m1","chat_id":"c","from_user_id":"role_qa","text":"Готово","is_session_marker":false,
         "steps":{"duration_ms":42500,"items":[
           {"kind":"text","text":"Проверяю"},
           {"kind":"step","id":"a","tool":"bash","detail":"npm test","status":"done"},
           {"kind":"step","id":"b","tool":"read","detail":null,"status":"error"}]}}
        """#
        let message = try JSONDecoder().decode(RoleChatMessage.self, from: Data(json.utf8))
        let steps = try XCTUnwrap(message.steps)
        XCTAssertEqual(steps.durationMs, 42500)
        XCTAssertEqual(steps.stepCount, 2)
        XCTAssertEqual(steps.items.first, .text("Проверяю"))
    }

    func testMessageWithoutStepsStillDecodes() throws {
        let json = #"""
        {"id":"m2","chat_id":"c","from_user_id":"u1","text":"привет","is_session_marker":false,"steps":null}
        """#
        let message = try JSONDecoder().decode(RoleChatMessage.self, from: Data(json.utf8))
        XCTAssertNil(message.steps)
    }

    func testStepsAndDurationWording() {
        XCTAssertEqual(RoleLiveFormat.steps(1), "1 шаг")
        XCTAssertEqual(RoleLiveFormat.steps(3), "3 шага")
        XCTAssertEqual(RoleLiveFormat.steps(7), "7 шагов")
        XCTAssertEqual(RoleLiveFormat.steps(12), "12 шагов")
        XCTAssertEqual(RoleLiveFormat.steps(21), "21 шаг")
        XCTAssertEqual(RoleLiveFormat.duration(seconds: 42), "42 с")
        XCTAssertEqual(RoleLiveFormat.duration(seconds: 185), "3 мин 5 с")
        XCTAssertEqual(RoleLiveFormat.duration(seconds: 720), "12 мин")
        XCTAssertEqual(RoleLiveStepKind.label(forTool: "bash"), "Команда")
        XCTAssertEqual(RoleLiveStepKind.label(forTool: "taskflow_taskflow_agents"), "Трекер")
        XCTAssertEqual(RoleLiveStepKind.label(forTool: "web_search"), "Действие")
    }
}
