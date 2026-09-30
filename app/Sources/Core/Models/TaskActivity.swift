import Foundation

/// Живая строка «чем агент занят прямо сейчас» — `GET /api/tasks/:id/activity`.
///
/// Сервер собирает её тремя слоями (`server/src/routes/activity.ts`): название
/// текущего шага, типизация действия по инструменту и пути, и поверх —
/// пересказ локальной моделью. Клиент печатает `text` как есть и ничего не
/// доформулировывает: сырые пути и команды владелец видеть не хочет,
/// готовую формулировку по каждому действию сервер уже кладёт в `text`.
///
/// Буфер живёт, только пока агент реально держит задачу: отдал или просрочил
/// аренду — сервер отвечает `text: null` и пустым списком, строка гаснет сама.
public struct ApiTaskActivity: Codable, Sendable, Hashable {
    /// Одна фраза о происходящем. `nil` — агент задачу не держит.
    public let text: String?
    public let actions: [ApiTaskActivityAction]

    public static let idle = ApiTaskActivity(text: nil, actions: [])

    public var isActive: Bool { text?.isEmpty == false }
}

public struct ApiTaskActivityAction: Codable, Sendable, Hashable, Identifiable {
    public let kind: String
    public let target: String
    public let detail: String?
    public let actor: String
    /// Unix-миллисекунды от сервера.
    public let at: Double
    /// Готовая формулировка от сервера — печатать как есть.
    public let text: String?

    public var id: String { "\(actor)-\(at)-\(target)" }

    public var date: Date { Date(timeIntervalSince1970: at / 1000) }
}
