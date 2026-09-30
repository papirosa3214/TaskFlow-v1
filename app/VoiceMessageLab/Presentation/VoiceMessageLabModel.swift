import Foundation
import Observation

@MainActor
@Observable
final class VoiceMessageLabModel {
    private let recorder: any VoiceRecording
    private let store: LocalVoiceMessageStore
    private let transcriber: any VoiceTranscribing

    private(set) var messages: [VoiceMessage]
    private(set) var draft: VoiceMessage?
    var recordingState: VoiceRecorder.State { recorder.state }
    var recorderWaveform: [Double] { (recorder as? VoiceRecorder)?.waveform ?? [] }

    init(
        recorder: any VoiceRecording,
        store: LocalVoiceMessageStore,
        transcriber: any VoiceTranscribing
    ) {
        self.recorder = recorder
        self.store = store
        self.transcriber = transcriber
        messages = (try? store.load()) ?? []
    }

    @discardableResult
    func startRecording() async -> Bool {
        do {
            try await recorder.start()
            if case .recording = recorder.state { return true }
            return false
        } catch {
            return false
        }
    }

    func cancelRecording() {
        recorder.cancel()
    }

    func stopRecording() async {
        guard let recorded = try? recorder.finish() else { return }
        let message = VoiceMessage(audioURL: recorded.url, duration: recorded.duration, waveform: recorded.waveform)
        draft = message

        Task { [weak self, transcriber] in
            let state: TranscriptState
            do {
                let text = try await transcriber.transcribe(url: recorded.url)
                state = text.isEmpty ? .failed : .ready(text)
            } catch {
                state = .failed
            }
            self?.applyTranscript(state, to: message.id)
        }
    }

    func sendDraft() {
        guard let draft else { return }
        messages.insert(draft, at: 0)
        self.draft = nil
        persist()
    }

    func discardDraft() {
        guard let draft else { return }
        try? VoiceRecorder.cancelRecordingFile(at: draft.audioURL)
        self.draft = nil
    }

    private func applyTranscript(_ state: TranscriptState, to id: UUID) {
        if draft?.id == id {
            draft?.transcript = state
        } else if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].transcript = state
            persist()
        }
    }

    private func persist() {
        try? store.save(messages)
    }
}
