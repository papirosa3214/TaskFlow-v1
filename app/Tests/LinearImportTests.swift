import XCTest
@testable import TaskFlow

private actor FixtureLinearAPI: LinearImportServing {
    var confirmations: [String] = []
    var selections: [[String]] = []
    var failCommit = false
    let root = "00000000-0000-0000-0000-000000000001"
    let child = "00000000-0000-0000-0000-000000000002"
    func decode<T: Decodable>(_ type: T.Type, _ value: String) throws -> T { try JSONDecoder().decode(type, from: Data(value.utf8)) }
    func projects() async throws -> [ApiProject] { [] }
    func linearIssues(cursor: String?) async throws -> LinearIssuePage {
        try decode(LinearIssuePage.self, """
        {"workspace":{"id":"W","name":"Workspace"},"issues":[{"id":"\(root)","identifier":"TF-1","title":"Parent","description":null,"url":"https://linear.app/test/issue/TF-1","priority":0,"dueDate":null,"parent":null,"state":{"name":"Todo","type":"unstarted"}},{"id":"\(child)","identifier":"TF-2","title":"Child","description":"Body","url":"https://linear.app/test/issue/TF-2","priority":2,"dueDate":"2026-10-01","parent":{"id":"\(root)"},"state":{"name":"Done","type":"completed"}}],"cursor":null}
        """)
    }
    func linearPreview(issueIDs: [String], projectID: String?) async throws -> LinearImportPreview {
        selections.append(issueIDs)
        return try decode(LinearImportPreview.self, """
        {"preview_id":"preview-1","workspace":{"id":"W","name":"Workspace"},"fetched_at":"2026-10-01T00:00:00Z","expires_at":"2026-10-01T01:00:00Z","project_id":null,"create_count":2,"update_count":0,"warnings":[],"items":[{"id":"\(child)","identifier":"TF-2","title":"Child","description":"Body","url":"https://linear.app/test/issue/TF-2","parent_id":"\(root)","task_id":null,"action":"create","reason":"selected","comments":1,"history":2,"labels":0,"attachments":0,"conflicts":[],"source_state":"Done","source_assignee":null},{"id":"\(root)","identifier":"TF-1","title":"Parent","description":null,"url":"https://linear.app/test/issue/TF-1","parent_id":null,"task_id":null,"action":"create","reason":"hierarchy","comments":0,"history":0,"labels":0,"attachments":0,"conflicts":[],"source_state":"Todo","source_assignee":null}]}
        """)
    }
    func importLinear(previewID: String) async throws -> LinearImportResult {
        confirmations.append(previewID)
        if failCommit { throw URLError(.timedOut) }
        return try decode(LinearImportResult.self, #"{"created":2,"updated":0,"conflicts":[],"task_ids":[]}"#)
    }
    func failNextCommit() { failCommit = true }
    func calls() -> [String] { confirmations }
}

final class LinearImportTests: XCTestCase {
    @MainActor func testSelectionAndPreviewNeverCommit() async throws {
        let api = FixtureLinearAPI(), model = LinearImportViewModel(api: api)
        await model.load(); XCTAssertEqual(model.issues.count, 2)
        model.toggle("00000000-0000-0000-0000-000000000002")
        await model.prepare()
        let calls = await api.calls(); XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(model.preview?.rows.map(\.depth), [0, 1])
        XCTAssertEqual(model.preview?.rows.first?.item.title, "Parent")
        XCTAssertEqual(model.preview?.rows.last?.item.reason, "selected")
        XCTAssertNil(model.result)
    }
    @MainActor func testOnlyConfirmationCommitsTheReviewedSnapshot() async {
        let api = FixtureLinearAPI(), model = LinearImportViewModel(api: api)
        await model.load(); model.toggle(model.issues[0].id); await model.prepare()
        let ok = await model.commit(); XCTAssertTrue(ok)
        let calls = await api.calls(); XCTAssertEqual(calls, ["preview-1"])
        XCTAssertNil(model.preview); XCTAssertEqual(model.result?.created, 2)
    }
    @MainActor func testFailedConfirmationKeepsSamePreviewForIdempotentRetry() async {
        let api = FixtureLinearAPI(), model = LinearImportViewModel(api: api)
        await model.load(); model.toggle(model.issues[0].id); await model.prepare(); await api.failNextCommit()
        let ok = await model.commit(); XCTAssertFalse(ok)
        XCTAssertEqual(model.preview?.previewID, "preview-1"); XCTAssertNotNil(model.error)
        _ = await model.commit(); let calls = await api.calls(); XCTAssertEqual(calls, ["preview-1", "preview-1"])
    }
    @MainActor func testChangingSelectionInvalidatesPreviewAndEnforcesLimit() async {
        let api = FixtureLinearAPI(), model = LinearImportViewModel(api: api)
        await model.load(); model.toggle(model.issues[0].id); await model.prepare()
        model.toggle(model.issues[1].id); XCTAssertNil(model.preview)
        model.selected = Set((0..<50).map(String.init)); model.toggle("more")
        XCTAssertEqual(model.selected.count, 50); XCTAssertNotNil(model.error)
    }
    @MainActor func testReloadDoesNotCarrySelectionsIntoDifferentSourceSnapshot() async {
        let model = LinearImportViewModel(api: FixtureLinearAPI())
        await model.load(); model.toggle(model.issues[0].id); await model.prepare()
        await model.load(); XCTAssertTrue(model.selected.isEmpty); XCTAssertNil(model.preview)
    }
}
