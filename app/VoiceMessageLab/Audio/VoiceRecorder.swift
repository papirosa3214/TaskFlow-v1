import AVFoundation
import Foundation
import Observation

struct RecordedVoice: Equatable {
    let url: URL
    let duration: TimeInterval
    let waveform: [Double]
}

@MainActor
protocol VoiceRecording: AnyObject {
    var state: VoiceRecorder.State { get }
    func start() async throws
    func finish() throws -> RecordedVoice?
    func cancel()
}

@MainActor
@Observable
final class VoiceRecorder: VoiceRecording {
    enum State: Equatable {
        case idle
        case recording(elapsed: TimeInterval, level: Double)
        case failed(String)
    }

    private(set) var state: State = .idle
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meterTask: Task<Void, Never>?
    private(set) var waveform: [Double] = []
    private var smoothedLevel = 0.0

    func start() async throws {
        guard case .idle = state else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .failed("Нет доступа к микрофону")
            return
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let directory = try Self.recordingsDirectory()
        let url = directory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let audioRecorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
        )
        audioRecorder.isMeteringEnabled = true
        guard audioRecorder.record() else {
            throw NSError(domain: "VoiceRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось начать запись"])
        }
        recorder = audioRecorder
        recordingURL = url
        waveform = []
        smoothedLevel = 0
        state = .recording(elapsed: 0, level: 0)
        startMetering()
    }

    func finish() throws -> RecordedVoice? {
        guard let recorder, let recordingURL else { return nil }
        let duration = recorder.currentTime
        stopRecorder()
        return RecordedVoice(url: recordingURL, duration: duration, waveform: waveform)
    }

    func cancel() {
        let url = recordingURL
        stopRecorder()
        if let url { try? Self.cancelRecordingFile(at: url) }
    }

    static func cancelRecordingFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func stopRecorder() {
        meterTask?.cancel()
        meterTask = nil
        recorder?.stop()
        recorder = nil
        recordingURL = nil
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { @MainActor in
            while !Task.isCancelled, let recorder {
                recorder.updateMeters()
                // Визуализация следует микрофону сразу; тишина не стирает историю.
                smoothedLevel = VoiceWaveform.recordingLevel(
                    previous: smoothedLevel,
                    averageDecibels: recorder.averagePower(forChannel: 0),
                    peakDecibels: recorder.peakPower(forChannel: 0)
                )
                waveform.append(smoothedLevel)
                if waveform.count > 120 { waveform.removeFirst(waveform.count - 120) }
                state = .recording(elapsed: recorder.currentTime, level: smoothedLevel)
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    private static func recordingsDirectory() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("VoiceMessageLab/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
