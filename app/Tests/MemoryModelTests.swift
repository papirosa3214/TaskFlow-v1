import XCTest
@testable import TaskFlow

/// Память ролей (02.10.2026): разбор записей сервера.
final class MemoryModelTests: XCTestCase {
    func testDecodesRoleWrittenMemory() throws {
        let json = #"""
        {"id":"m1","scope":"role","role_key":"builder","project_id":null,"kind":"lesson","title":null,
         "text":"Тесты сервера: npx vitest run","source_kind":"role","source_ref":null,"created_by":"role_builder",
         "updated_by":"role_builder","pinned":0,"attachment_id":null,"use_count":3,"last_used_at":null,
         "created_at":"2026-10-02 10:00:00","updated_at":"2026-10-02 10:00:00"}
        """#
        let memory = try JSONDecoder().decode(ApiMemory.self, from: Data(json.utf8))
        XCTAssertTrue(memory.isFromRole)
        XCTAssertFalse(memory.isPinned)
        XCTAssertFalse(memory.isFile)
        XCTAssertEqual(memory.useCount, 3)
        XCTAssertNil(memory.chunks)
    }

    func testFileMemoryWithChunks() throws {
        let json = #"""
        {"id":"m2","scope":"team","role_key":null,"project_id":null,"kind":"file","title":"релиз.md",
         "text":"…","source_kind":"owner","created_by":"u1","pinned":1,"chunks":4}
        """#
        let memory = try JSONDecoder().decode(ApiMemory.self, from: Data(json.utf8))
        XCTAssertTrue(memory.isFile)
        XCTAssertTrue(memory.isPinned)
        XCTAssertEqual(memory.chunks, 4)
        XCTAssertEqual(MemoryScreen.icon(memory.kind), "doc.text")
        XCTAssertEqual(MemoryScreen.kindTitle("preference"), "предпочтение")
    }
}
