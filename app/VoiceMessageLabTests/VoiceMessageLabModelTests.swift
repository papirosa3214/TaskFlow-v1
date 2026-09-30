import XCTest
@testable import VoiceMessageLab

@MainActor
final class VoiceMessageLabModelTests: XCTestCase {
    func test_startRecordingReportsFailureWhenRecorderDoesNotEnterRecordingState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioURL = directory.appendingPathComponent("voice.m4a")
        try Data().write(to: audioURL)
        let model = VoiceMessageLabModel(
            recorder: FixedRecorder(recording: RecordedVoice(url: audioURL, duration: 2, waveform: [])),
            store: LocalVoiceMessageStore(directory: directory),
            transcriber: DelayedTranscriber()
        )

        let started = await model.startRecording()
        XCTAssertFalse(started)
    }

    func test_finishRecording_addsAudioBeforeTranscriptCompletes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioURL = directory.appendingPathComponent("voice.m4a")
        try Data().write(to: audioURL)
        let transcriber = DelayedTranscriber()
        let model = VoiceMessageLabModel(
            recorder: FixedRecorder(recording: RecordedVoice(url: audioURL, duration: 2, waveform: [])),
            store: LocalVoiceMessageStore(directory: directory),
            transcriber: transcriber
        )

        await model.stopRecording()
        model.sendDraft()

        XCTAssertEqual(model.messages.first?.transcript, .pending)
    }

    func test_stopRecording_preparesDraftWithoutSendingIt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioURL = directory.appendingPathComponent("voice.m4a")
        try Data().write(to: audioURL)
        let model = VoiceMessageLabModel(
            recorder: FixedRecorder(recording: RecordedVoice(url: audioURL, duration: 9, waveform: [])),
            store: LocalVoiceMessageStore(directory: directory),
            transcriber: DelayedTranscriber()
        )

        await model.stopRecording()

        XCTAssertEqual(model.messages.count, 0)
        XCTAssertEqual(model.draft?.duration, 9)
        XCTAssertEqual(model.draft?.transcript, .pending)
    }
}

@MainActor
private final class FixedRecorder: VoiceRecording {
    let recording: RecordedVoice
    init(recording: RecordedVoice) { self.recording = recording }
    var state: VoiceRecorder.State { .idle }
    func start() async throws {}
    func finish() throws -> RecordedVoice? { recording }
    func cancel() {}
}

private struct DelayedTranscriber: VoiceTranscribing {
    func transcribe(url: URL) async throws -> String {
        try await Task.sleep(for: .seconds(10))
        return "Привет"
    }
}
