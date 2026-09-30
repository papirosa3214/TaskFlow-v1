import Foundation

/// `ApiAttemptLadder` — спек 1.2, раздел 3.4 / R9. Серверная «лесенка модели»:
/// какая сейчас ступень попытки, сколько всего ступеней у `reason_code=
/// insufficient_capability`, и история прошлых попыток с моделью, исходом
/// и причиной закрытия.
///
/// Источник правды — `attempt_policies` в БД, читается через
/// `server/src/lib/attemptLadder.ts` на сервере (коммит `taskflow-server`
/// 1.2.8). Клиент только рисует; никаких запросов списка ступеней с iPhone
/// не делается — приходят только `current_step` / `total_steps` /
/// `current_model`.
///
/// Поле опционально в `ApiTask`: на старых задачах (созданы до спек 1.2)
/// сервер поля не отдаёт. В UI такие задачи лесенки не показывают.
public struct ApiAttemptLadder: Codable, Sendable, Hashable {
    /// 1-based номер текущей ступени. 0 — серверу не удалось вычислить
    /// (например, модель не входит в лесенку). >0 — попытка жива на этой
    /// ступени или только что закрылась с инскалацией.
    public let currentStep: Int
    /// Полное число ступеней в лесенке (сейчас 3: Haiku → Sonnet → Opus).
    public let totalSteps: Int
    /// Имя модели текущей попытки (`haiku` / `sonnet` / `opus`) — короткие
    /// алиасы из `attempt_policies.from_model`. nil если ступень не нашли.
    public let currentModel: String?
    /// История попыток в хронологическом порядке (started_at ASC).
    /// Попытки подзадач (`subtask_id IS NOT NULL`) в историю не идут.
    public let history: [ApiAttemptLadderHistoryItem]

    enum CodingKeys: String, CodingKey {
        case currentStep = "current_step"
        case totalSteps = "total_steps"
        case currentModel = "current_model"
        case history
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentStep = try c.decode(Int.self, forKey: .currentStep)
        totalSteps = try c.decode(Int.self, forKey: .totalSteps)
        currentModel = try c.decodeIfPresent(String.self, forKey: .currentModel)
        history = try c.decodeIfPresent([ApiAttemptLadderHistoryItem].self, forKey: .history) ?? []
    }

    public init(
        currentStep: Int,
        totalSteps: Int,
        currentModel: String?,
        history: [ApiAttemptLadderHistoryItem]
    ) {
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.currentModel = currentModel
        self.history = history
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(currentStep, forKey: .currentStep)
        try c.encode(totalSteps, forKey: .totalSteps)
        try c.encodeIfPresent(currentModel, forKey: .currentModel)
        try c.encode(history, forKey: .history)
    }
}

/// Запись истории попыток в лесенке. На сервере живёт в `attempts` (см.
/// спек 1.2 §4.1, расширение `attempts.consultation_count`) — клиенту
/// нужны только дампы на момент построения лесенки, никаких действий.
public struct ApiAttemptLadderHistoryItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let model: String?
    public let outcome: String?
    public let reasonCode: String?
    /// `SQLite UTC` (`'YYYY-MM-DD HH:MM:SS'`), парсится через `DateFormats.sqliteUTC`.
    public let startedAt: String
    public let endedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, model, outcome
        case reasonCode = "reason_code"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome)
        reasonCode = try c.decodeIfPresent(String.self, forKey: .reasonCode)
        startedAt = try c.decode(String.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(String.self, forKey: .endedAt)
    }

    public init(
        id: String,
        model: String?,
        outcome: String?,
        reasonCode: String?,
        startedAt: String,
        endedAt: String?
    ) {
        self.id = id
        self.model = model
        self.outcome = outcome
        self.reasonCode = reasonCode
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(outcome, forKey: .outcome)
        try c.encodeIfPresent(reasonCode, forKey: .reasonCode)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(endedAt, forKey: .endedAt)
    }
}
