import XCTest
@testable import VoiceMessageLab

final class LocalVoiceMessageStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func test_saveThenLoad_restoresMessageAndTranscript() throws {
        let store = LocalVoiceMessageStore(directory: temporaryDirectory)
        let message = VoiceMessage(
            audioURL: temporaryDirectory.appendingPathComponent("voice.m4a"),
            duration: 2,
            transcript: .ready("Привет")
        )

        try store.save([message])

        XCTAssertEqual(try store.load(), [message])
    }
}
