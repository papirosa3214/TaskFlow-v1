import XCTest
@testable import TaskFlow

/// Живой план (01.10.2026): новый формат плана и операции правки.
final class CollaborationPlanLiveTests: XCTestCase {
    func testDecodesLivePlanWithProposals() throws {
        let json = #"""
        {"id":"tcp_1","task_id":"t1","revision":1,"status":"approved","profile":"delivery","rationale":"",
         "version":4,
         "nodes":[
           {"slot_key":"qa","role_key":"qa","required":true,"expected_result":"Проверка"},
           {"slot_key":"designer_2","role_key":"designer","required":true,"expected_result":"UX",
            "instructions":"Экран настроек","origin":"role","added_by":"role_architect",
            "added_reason":"новый экран","iteration":0,"rework_of_key":null,"skipped_at":null,"skip_reason":null}
         ],
         "edges":[{"from_slot_key":"designer_2","to_slot_key":"qa","start_condition":"accepted","artifact_key":null}],
         "pending_proposals":[{"id":"tcpo_1","actor_id":"role_qa","actor_name":"QA","reason":"r4",
           "ops":[{"op":"add_step","role_key":"qa","expected_result":"Нагрузочный тест"}],"created_at":"2026-10-01"}]}
        """#
        let plan = try JSONDecoder().decode(ApiCollaborationPlan.self, from: Data(json.utf8))
        XCTAssertEqual(plan.version, 4)
        XCTAssertNil(plan.nodes[0].origin, "старый узел без новых полей разбирается")
        XCTAssertEqual(plan.nodes[1].origin, "role")
        XCTAssertEqual(plan.nodes[1].addedReason, "новый экран")
        XCTAssertFalse(plan.nodes[1].isSkipped)
        XCTAssertEqual(plan.pendingProposals?.first?.ops.first?.expectedResult, "Нагрузочный тест")
    }

    func testOldServerPlanStillDecodes() throws {
        let json = #"""
        {"id":"tcp_2","task_id":"t1","revision":2,"status":"draft","profile":"research","rationale":"",
         "nodes":[{"slot_key":"research","role_key":"researcher","required":true,"expected_result":"Факты"}],"edges":[]}
        """#
        let plan = try JSONDecoder().decode(ApiCollaborationPlan.self, from: Data(json.utf8))
        XCTAssertNil(plan.version)
        XCTAssertNil(plan.pendingProposals)
    }

    func testOpEncodesOnlyFilledFields() throws {
        let op = ApiPlanOp(op: "skip_step", slotKey: "design", reason: "экранов нет")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(op)) as? [String: Any]
        XCTAssertEqual(object?.keys.sorted(), ["op", "reason", "slot_key"])
    }

    func testProposalDescription() {
        let text = CollaborationPlanView.describe(
            ApiPlanOp(op: "add_step", roleKey: "designer", expectedResult: "UX экрана"),
            title: { $0 == "designer" ? "Дизайнер" : $0 }
        )
        XCTAssertEqual(text, "Новый шаг — Дизайнер: UX экрана")
    }
}
