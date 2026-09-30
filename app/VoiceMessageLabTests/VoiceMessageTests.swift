import XCTest
@testable import VoiceMessageLab

final class VoiceMessageTests: XCTestCase {
    func test_newVoiceMessage_startsWithPendingTranscript() {
        let message = VoiceMessage(
            audioURL: URL(fileURLWithPath: "/tmp/voice.m4a"),
            duration: 2
        )

        XCTAssertEqual(message.transcript, .pending)
    }
}
