import Foundation
import Observation

/// Общий мост от кнопки чата к записи и Parakeet из VoiceMessageLab.
@MainActor
@Observable
final class RoleChatVoiceController {
    enum Phase: Equatable { case idle, recording, transcribing, uploading }

    private let recorder = VoiceRecorder()
    private let transcriber = ParakeetVoiceTranscriber()
    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    var recordingState: VoiceRecorder.State { recorder.state }
    var recorderWaveform: [Double] { recorder.waveform }

    func start() async {
        guard phase == .idle else { return }
        errorMessage = nil
        do {
            try await recorder.start()
            if case .recording = recorder.state {
                phase = .recording
            } else if case .failed(let reason) = recorder.state {
                errorMessage = reason
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func finish() -> VoiceMessage? {
        guard phase == .recording else { return nil }
        do {
            guard let recorded = try recorder.finish() else { return nil }
            phase = .transcribing
            // Волна — огибающая из самого файла (реальная), а не живые уровни:
            // иначе при короткой записи она выглядит пунктиром.
            let envelope = VoiceWaveform.envelope(fromAudioFile: recorded.url)
            let waveform = envelope.isEmpty ? recorded.waveform : envelope
            return VoiceMessage(audioURL: recorded.url, duration: recorded.duration, waveform: waveform)
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
            return nil
        }
    }

    func transcribe(_ message: VoiceMessage) async -> TranscriptState {
        do {
            let text = try await transcriber.transcribe(url: message.audioURL)
            return text.isEmpty ? .failed : .ready(text)
        } catch { return .failed }
    }

    func uploading() { phase = .uploading }
    func complete() { phase = .idle }
    func fail(_ message: String) {
        errorMessage = message
        phase = .idle
    }

    func cancel() {
        recorder.cancel()
        phase = .idle
    }
}
