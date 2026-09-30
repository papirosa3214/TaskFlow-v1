import XCTest
@testable import VoiceMessageLab

final class VoiceComposerPresentationTests: XCTestCase {
    func test_recordingState_exposesStopAffordance() {
        XCTAssertEqual(
            VoiceComposerPresentation(state: .recording).action,
            .stop
        )
    }
}
