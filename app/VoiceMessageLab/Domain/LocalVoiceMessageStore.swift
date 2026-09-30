import Foundation

struct LocalVoiceMessageStore {
    private let indexURL: URL

    init(directory: URL) {
        indexURL = directory.appendingPathComponent("voice-messages.json")
    }

    func load() throws -> [VoiceMessage] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        return try JSONDecoder().decode([VoiceMessage].self, from: Data(contentsOf: indexURL))
    }

    func save(_ messages: [VoiceMessage]) throws {
        let data = try JSONEncoder().encode(messages)
        try data.write(to: indexURL, options: .atomic)
    }
}
