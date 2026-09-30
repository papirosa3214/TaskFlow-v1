import XCTest
@testable import TaskFlow

final class ThingsSyncTests: XCTestCase {
    func testMarkerParsesTaskFlowIDFromNotes() {
        XCTAssertEqual(
            ThingsSyncMerge.taskFlowID(from: "Описание\n\nTaskFlow ID: task-123"),
            "task-123"
        )
    }

    func testMarkerMissingWhenNotesHaveNoTaskFlowID() {
        XCTAssertNil(ThingsSyncMerge.taskFlowID(from: "Обычная заметка"))
    }

    func testDecisionCreatesNewTaskWhenThingHasNoMarker() {
        let decision = ThingsSyncMerge.decision(
            thingID: "thing-1",
            title: "Позвонить",
            notes: "",
            isCompleted: false,
            dueDate: "2026-09-20",
            existingTask: nil
        )
        XCTAssertEqual(decision, .createTask)
    }

    func testDecisionUpdatesExistingTaskWhenThingIsCompleted() {
        let task = ThingsSyncTaskSnapshot(
            id: "task-1", title: "Позвонить", notes: "", isCompleted: false, dueDate: nil
        )
        let decision = ThingsSyncMerge.decision(
            thingID: "thing-1",
            title: "Позвонить",
            notes: "TaskFlow ID: task-1",
            isCompleted: true,
            dueDate: nil,
            existingTask: task
        )
        XCTAssertEqual(decision, .updateTask)
    }
}
