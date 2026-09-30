import Foundation

/// Ответ `POST /api/secretary/voice-token` (Задача 1 плана Супер Секретарь) —
/// параметры комнаты LiveKit для голосового разговора с Секретарём.
public struct SecretaryVoiceToken: Decodable, Sendable {
    public let url: String
    public let token: String
    public let room: String
}

/// Голоса Gemini Live для Секретаря. Список закрытый и совпадает с серверным
/// (`secretary-voice.ts`) и воркером: незнакомое имя Gemini молча подменяет
/// голосом по умолчанию.
public enum SecretaryVoice: String, CaseIterable, Identifiable, Sendable {
    case puck = "Puck", charon = "Charon", fenrir = "Fenrir", orus = "Orus"
    case kore = "Kore", aoede = "Aoede", leda = "Leda", zephyr = "Zephyr"

    public static let storageKey = "secretary.voice"
    public static let `default` = SecretaryVoice.puck

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .puck, .charon, .fenrir, .orus: "\(rawValue) · мужской"
        case .kore, .aoede, .leda, .zephyr: "\(rawValue) · женский"
        }
    }

    /// Образец «Привет! Я твой Секретарь. Чем помочь?» этим голосом — записан
    /// один раз через Gemini Live, лежит в бандле (`Resources/SecretaryVoices`).
    public var sampleURL: URL? {
        Bundle.main.url(forResource: "secretary-voice-\(rawValue.lowercased())", withExtension: "m4a")
    }

    public static var current: SecretaryVoice {
        UserDefaults.standard.string(forKey: storageKey).flatMap(SecretaryVoice.init(rawValue:)) ?? .default
    }
}

public extension APIClient {
    /// Голос уходит в атрибуты участника внутри подписанного токена — воркер
    /// читает его при входе владельца в комнату.
    func secretaryVoiceToken(voice: SecretaryVoice) async throws -> SecretaryVoiceToken {
        try await request(.post, "/secretary/voice-token", body: ["voice": voice.rawValue])
    }
}
