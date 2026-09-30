import XCTest
@testable import VoiceMessageLab

@MainActor
final class VoiceRecorderStateTests: XCTestCase {
    func test_cancelRemovesPendingAudioFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioURL = directory.appendingPathComponent("pending.m4a")
        try Data("audio".utf8).write(to: audioURL)

        try VoiceRecorder.cancelRecordingFile(at: audioURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }
}
