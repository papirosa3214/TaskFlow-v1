import XCTest
@testable import TaskFlow

final class RoleChatComposerTests: XCTestCase {
    func testDeepResearchRequiresResearcherAndKeepsBackwardCompatibility() throws {
        let decoder = JSONDecoder()
        let plain = try decoder.decode(RoleChat.self, from: Data(#"{"id":"c","kind":"direct","created_by":"u","members":[{"id":"role_builder","name":"Разработчик"}]}"#.utf8))
        XCTAssertEqual(RoleChatWorkMode.available(in: plain), [.work, .plan])
        let researcher = try decoder.decode(RoleChat.self, from: Data(#"{"id":"c","kind":"direct","created_by":"u","members":[{"id":"custom","name":"Имя","role_key":"researcher"}]}"#.utf8))
        XCTAssertEqual(RoleChatWorkMode.available(in: researcher), [.work, .plan, .deepResearch])
    }

    func testFinalSnapshotDoesNotSkipUnrevealedText() {
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text("Проверяю источник и сверяю")])
        pacer.advance(elapsed: 0.2)
        let shown = pacer.visibleItems
        pacer.ingest([.text("Проверяю источник и сверяю факты. Готово.")])
        XCTAssertEqual(pacer.visibleItems, shown)
        XCTAssertTrue(pacer.hasPendingText)
        for _ in 0..<500 { pacer.advance(elapsed: 0.016) }
        XCTAssertEqual(pacer.visibleItems, [.text("Проверяю источник и сверяю факты. Готово.")])
        XCTAssertLessThanOrEqual(pacer.rate, RoleLiveTextPacer.maxRate)
    }
}
