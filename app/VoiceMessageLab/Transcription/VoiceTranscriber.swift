import AVFoundation
import FluidAudio
import Foundation

protocol VoiceTranscribing: Sendable {
    func transcribe(url: URL) async throws -> String
}

actor ParakeetVoiceTranscriber: VoiceTranscribing {
    private var manager: AsrManager?
    private var decoderState: TdtDecoderState?

    func transcribe(url: URL) async throws -> String {
        try await loadIfNeeded()
        guard let manager, var decoderState else {
            throw CocoaError(.fileReadUnknown)
        }
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer)
        let result = try await manager.transcribe(buffer, decoderState: &decoderState, language: .russian)
        self.decoderState = decoderState
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadIfNeeded() async throws {
        guard manager == nil else { return }
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
        decoderState = try TdtDecoderState()
    }
}
