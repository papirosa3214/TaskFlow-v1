import XCTest
@testable import TaskFlow

final class AttemptLadderModelTests: XCTestCase {
    func testTaskDecodesAttemptLadderFromDetailResponse() throws {
        let data = Data(#"""
        {
          "id":"task-1","title":"Task","priority":1,"status":"active",
          "pinned":0,"creator_id":"owner","agent_state":"in_progress",
          "attempt_ladder":{
            "current_step":2,"total_steps":3,"current_model":"sonnet",
            "history":[{"id":"a1","model":"haiku","outcome":"needs_escalation","reason_code":"insufficient_capability","started_at":"2026-09-13 10:00:00","ended_at":"2026-09-13 10:01:00"}]
          }
        }
        """#.utf8)

        let task = try JSONDecoder().decode(ApiTask.self, from: data)

        XCTAssertEqual(task.attemptLadder?.currentStep, 2)
        XCTAssertEqual(task.attemptLadder?.totalSteps, 3)
        XCTAssertEqual(task.attemptLadder?.currentModel, "sonnet")
        XCTAssertEqual(task.attemptLadder?.history.first?.reasonCode, "insufficient_capability")
    }
}
