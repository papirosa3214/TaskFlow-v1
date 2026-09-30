import XCTest
@testable import VoiceMessageLab

final class VoiceActivityGateTests: XCTestCase {
    func test_singleLoudTransientDoesNotOpenGate() {
        var gate = VoiceActivityGate()

        XCTAssertEqual(gate.filteredLevel(from: 0.9), 0)
        XCTAssertEqual(gate.filteredLevel(from: 0), 0)
    }

    func test_twoConsecutiveVoiceSamplesOpenGate() {
        var gate = VoiceActivityGate()

        _ = gate.filteredLevel(from: 0.5)
        XCTAssertEqual(gate.filteredLevel(from: 0.5), 0.5)
    }
}
