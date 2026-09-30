import XCTest
@testable import TaskFlow

final class RoleRuntimeContextTests: XCTestCase {
    func testDecodesServerLayersAndKeepsUnknownLayerVisible() throws {
        let data = Data(#"""
        {
          "role": "architect",
          "layers": [
            {"id":"role","title":"Роль","scope":"Все режимы","source":"roles.prompt","editable":true,"text":"Инструкция"},
            {"id":"future","title":"Новый слой","scope":"Тест","source":"server","editable":false,"text":"Будущее правило"}
          ]
        }
        """#.utf8)

        let context = try JSONDecoder().decode(RoleRuntimeContext.self, from: data)

        XCTAssertEqual(context.role, "architect")
        XCTAssertEqual(context.layers.map(\.id), ["role", "future"])
        XCTAssertEqual(context.layers[1].title, "Новый слой")
        XCTAssertFalse(context.layers[1].editable)
    }

    func testDecodesEditableBlockAndPreservesDraftAcrossConflict() throws {
        let data = Data(#"""
        {
          "role":"builder","layers":[],"canEdit":true,
          "blocks":[{
            "id":"task.start","title":"Первый запуск","group":"Задача",
            "scope":"command_default","source":"instructionDefaults.ts",
            "editable":true,"text":"Для этой роли","teamText":"Для команды",
            "defaultText":"Исходный текст","version":2,"commandVersion":4,
            "modes":["work"],"placeholders":["taskId"],"allowsTeam":true
          }]
        }
        """#.utf8)
        let context = try JSONDecoder().decode(RoleRuntimeContext.self, from: data)
        let block = try XCTUnwrap(context.blocks?.first)
        XCTAssertEqual(block.teamText, "Для команды")
        XCTAssertEqual(block.commandVersion, 4)
        var draft = RoleInstructionDraft(text: "Моя правка", expectedVersion: block.version)
        draft.conflict()
        XCTAssertEqual(draft.text, "Моя правка")
        draft.adoptRevision(3)
        XCTAssertEqual(draft.text, "Моя правка")
        XCTAssertEqual(draft.expectedVersion, 3)
        XCTAssertFalse(draft.hasConflict)
    }
}
