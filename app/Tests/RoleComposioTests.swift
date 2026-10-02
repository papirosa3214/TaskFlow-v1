import XCTest
@testable import TaskFlow

final class RoleComposioTests: XCTestCase {
    func testWholeCatalogAndEmptySelectionRemainDifferent() throws {
        let decoder = JSONDecoder()
        let all = try decoder.decode(RoleComposio.self, from: Data(#"{"enabled":true,"toolkits":null,"configured":true,"available":true,"catalog":[],"error":null}"#.utf8))
        let none = try decoder.decode(RoleComposio.self, from: Data(#"{"enabled":true,"toolkits":[],"configured":true,"available":true,"catalog":[],"error":null}"#.utf8))
        XCTAssertNil(all.toolkits)
        XCTAssertEqual(none.toolkits, [])
    }

    func testConnectionStatusAndFailureDecode() throws {
        let settings = try JSONDecoder().decode(RoleComposio.self, from: Data(#"{"enabled":false,"toolkits":["github"],"configured":true,"available":false,"catalog":[{"slug":"github","name":"GitHub","connected":false,"noAuth":false}],"error":"Unavailable"}"#.utf8))
        XCTAssertFalse(settings.available)
        XCTAssertFalse(settings.catalog[0].connected)
        XCTAssertEqual(settings.error, "Unavailable")
    }

    func testSelectingOneServiceDoesNotGrantWholeCatalog() throws {
        let old = ComposioAccessPolicy(enabled: false, toolkits: nil)
        let next = try old.changing("linear", allowed: true)
        XCTAssertEqual(next, ComposioAccessPolicy(enabled: true, toolkits: ["linear"]))
        XCTAssertFalse(next.allows("github"))
    }

    func testServiceChangesPreserveOtherPermissions() throws {
        let old = ComposioAccessPolicy(enabled: true, toolkits: ["github", "notion"])
        let added = try old.changing("linear", allowed: true)
        XCTAssertEqual(added.toolkits, ["github", "linear", "notion"])
        let removed = try added.changing("linear", allowed: false)
        XCTAssertEqual(removed, old)
        let empty = try ComposioAccessPolicy(enabled: true, toolkits: ["linear"]).changing("linear", allowed: false)
        XCTAssertEqual(empty, ComposioAccessPolicy(enabled: false, toolkits: []))
    }

    func testWholeCatalogCannotBeSilentlyReplacedByPartialCatalog() throws {
        let old = ComposioAccessPolicy(enabled: true, toolkits: nil)
        XCTAssertThrowsError(try old.changing("linear", allowed: false))
        XCTAssertEqual(try old.changing("linear", allowed: true), old)
        XCTAssertFalse(try old.changing(nil, allowed: false).enabled)
    }

    @MainActor func testWorkspaceSelectionOnlyChangesChosenServiceAndRoles() async {
        let model = ComposioIntegrationsViewModel(testFixture: true)
        await model.load()
        model.policies["reviewer"] = ComposioAccessPolicy(enabled: true, toolkits: ["github"])
        let success = await model.save(toolkit: "linear", selected: ["secretary", "developer"])
        XCTAssertTrue(success)
        XCTAssertEqual(model.selectedRoles(for: "linear"), ["secretary", "developer"])
        XCTAssertEqual(model.policies["reviewer"], ComposioAccessPolicy(enabled: true, toolkits: ["github"]))
        XCTAssertTrue(model.selectedRoles(for: nil).isEmpty)
    }

    func testDisabledRoleDoesNotReactivateUnselectedServices() throws {
        let disabled = ComposioAccessPolicy(enabled: false, toolkits: ["github"])
        let selected = try disabled.changing("linear", allowed: true)
        XCTAssertEqual(selected, ComposioAccessPolicy(enabled: true, toolkits: ["linear"]))
    }
}
