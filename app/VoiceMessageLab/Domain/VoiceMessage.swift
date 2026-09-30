import Foundation

enum TranscriptState: Codable, Equatable {
    case pending
    case ready(String)
    case failed
}

struct VoiceMessage: Codable, Equatable, Identifiable {
    let id: UUID
    let audioURL: URL
    let duration: TimeInterval
    let waveform: [Double]
    let createdAt: Date
    var transcript: TranscriptState

    init(
        id: UUID = UUID(),
        audioURL: URL,
        duration: TimeInterval,
        waveform: [Double] = [],
        createdAt: Date = .now,
        transcript: TranscriptState = .pending
    ) {
        self.id = id
        self.audioURL = audioURL
        self.duration = duration
        self.waveform = waveform
        self.createdAt = createdAt
        self.transcript = transcript
    }
}
