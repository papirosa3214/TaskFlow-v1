import Foundation

struct VoiceActivityGate {
    private var consecutiveVoiceSamples = 0

    mutating func filteredLevel(from candidate: Double) -> Double {
        guard candidate >= 0.18 else {
            consecutiveVoiceSamples = 0
            return 0
        }

        consecutiveVoiceSamples += 1
        return consecutiveVoiceSamples >= 2 ? candidate : 0
    }
}
