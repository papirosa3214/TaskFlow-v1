import XCTest
import SnapshotTesting
import SwiftUI
@testable import TaskFlow

final class RoleStepLineSnapshotTests: XCTestCase {
    private let deviceConfig: ViewImageConfig = .iPhone13Pro
    private var record: Bool { false }

    private func snapshot(tool: String, name: String = "Разработчик") -> some View {
        RoleStepLine(name: name, tool: tool)
            .padding()
            .background(Color.tfBackground)
            .frame(width: 320)
    }

    func testReadStep() {
        assertSnapshot(of: snapshot(tool: "read"), as: .image(layout: .device(config: deviceConfig)),
                        record: record)
    }

    func testBashStep() {
        assertSnapshot(of: snapshot(tool: "bash"), as: .image(layout: .device(config: deviceConfig)),
                        record: record)
    }

    func testUnknownToolFallsBackToGenericLabel() {
        assertSnapshot(of: snapshot(tool: "some_future_tool"), as: .image(layout: .device(config: deviceConfig)),
                        record: record)
    }
}
