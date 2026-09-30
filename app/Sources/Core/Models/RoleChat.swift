import Foundation

extension ApiChatAttachment {
    /// Пока серверный валидатор не принимает audio/mp4, .m4a приходит как octet-stream.
    var isVoiceRecording: Bool {
        mime?.hasPrefix("audio/") == true || fileName.lowercased().hasSuffix(".m4a")
    }
}

/// Отдельный чат с ролями; старые каналы owner/agents имеют другой контракт.
public struct RoleChat: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: String?
    public let kind: String
    public let createdBy: String
    public let taskID: String?
    public let members: [RoleChatMember]
    public let lastMessage: RoleChatPreview?
    /// Непрочитанных у ТЕКУЩЕГО пользователя (миграция 055, отметка на
    /// участнике чата). Опционально: сервер до этой правки поля не слал, и
    /// старый ответ не должен ронять декодирование.
    public let unreadCount: Int?
    /// Название задачи, к которой привязан чат (`nil` — свободный). Нужно
    /// пометкой в строке списка: по ней видно, какой чат за какой задачей.
    public let taskTitle: String?

    enum CodingKeys: String, CodingKey {
        case id, title, kind, members
        case createdBy = "created_by"
        case taskID = "task_id"
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
        case taskTitle = "task_title"
    }

    public var unread: Int { unreadCount ?? 0 }

    /// Собеседники — участники без текущего пользователя. В личке это ровно
    /// один человек/роль, в группе — весь состав (он же идёт в заголовок).
    public func others(excluding userID: String?) -> [RoleChatMember] {
        members.filter { $0.id != userID }
    }

    public func displayTitle(excluding userID: String?) -> String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        // Сервер может вернуть пустое название группы: перечисляем роли без владельца.
        let names = others(excluding: userID)
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return names.isEmpty ? (kind == "group" ? "Групповой чат" : "Чат") : names.joined(separator: ", ")
    }
}

public struct RoleChatMember: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let avatarColor: String?
    public let avatarURL: String?
    public let initials: String?

    enum CodingKeys: String, CodingKey {
        case id, name, initials
        case avatarColor = "avatar_color"
        case avatarURL = "avatar_url"
    }
}

public struct RoleChatPreview: Decodable, Sendable {
    public let text: String
    public let fromUserID: String?
    /// Имя отправителя — превью строки списка идёт с ним («QA: проверка
    /// прошла»); у личных чатов подпись не нужна.
    public let fromUserName: String?
    public let createdAt: String?
    /// Сколько вложений в последнем сообщении. Голосовое и файл текстом не
    /// читаются (у голосового текста может не быть вовсе), поэтому строка
    /// списка показывает «Голосовое»/«Файл» вместо пустоты.
    public let attachmentCount: Int?
    public let audioCount: Int?

    enum CodingKeys: String, CodingKey {
        case text
        case fromUserID = "from_user_id"
        case fromUserName = "from_user_name"
        case createdAt = "created_at"
        case attachmentCount = "attachment_count"
        case audioCount = "audio_count"
    }

    /// Что показывать в строке списка: текст, иначе — иконка вложения.
    public var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if (audioCount ?? 0) > 0 { return "Голосовое сообщение" }
        if (attachmentCount ?? 0) > 0 { return "Файл" }
        return ""
    }
}

/// Чат, привязанный к задаче — карточка отдаёт их списком, чтобы дать переход
/// в переписку. Сам чат в карточке не рисуется: для него есть свой экран
/// (владелец 21.09.2026, LOCK-195).
public struct ApiTaskChat: Decodable, Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String?
    public let kind: String?
    public let membersCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, kind
        case membersCount = "members_count"
    }

    /// Что показать в строке карточки: название чата, иначе — по составу.
    public var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return kind == "group" ? "Групповой чат" : "Чат"
    }
}

/// `/chats/:id/messages` возвращает те же поля, что общий чат, но channel=chat.
public struct RoleChatMessage: Decodable, Identifiable, Sendable {
    public let id: String
    public let chatID: String?
    public let fromUserID: String?
    public let fromUserName: String?
    public let fromUserColor: String?
    public let fromUserAvatarURL: String?
    public let fromUserInitials: String?
    public let text: String
    public let createdAt: String?
    public let attachments: [ApiChatAttachment]?
    /// Задача, которую роль создала этим ходом (владелец 25.09.2026,
    /// docs/ПЛАН Супер Секретарь/, этап 2) — есть значение → вместо текста
    /// рисуется карточка (см. RoleChatsScreen).
    public let taskID: String?
    public let taskTitle: String?
    /// Быстрые ответы (владелец 25.09.2026, docs/ПЛАН Супер Секретарь/) —
    /// 2-4 коротких варианта, которые предложила роль вместо того, чтобы
    /// печатать руками. Только у последнего сообщения роли есть смысл.
    public let quickReplies: [String]?
    /// Разделитель «новая сессия» (владелец 25.09.2026) — рисуется не
    /// пузырём, а меткой посередине; сама история при сбросе сессии не
    /// удаляется, разделитель просто показывает границу.
    public let isSessionMarker: Bool
    /// Шаги хода роли, которые привели к этому ответу (владелец 27.09.2026,
    /// живой ход как в Claude Code) — рисуются свёрнутой строкой «N шагов ·
    /// M с» над текстом. `nil` — ход без шагов или сообщение не от роли.
    public let steps: RoleChatSteps?

    enum CodingKeys: String, CodingKey {
        case id, text, attachments, steps
        case chatID = "chat_id"
        case fromUserID = "from_user_id"
        case fromUserName = "from_user_name"
        case fromUserColor = "from_user_color"
        case fromUserAvatarURL = "from_user_avatar_url"
        case fromUserInitials = "from_user_initials"
        case createdAt = "created_at"
        case taskID = "task_id"
        case taskTitle = "task_title"
        case quickReplies = "quick_replies"
        case isSessionMarker = "is_session_marker"
    }
}

/// Шаги хода роли, сохранённые вместе с ответом (`chat_messages.steps`).
public struct RoleChatSteps: Decodable, Sendable, Equatable {
    public let durationMs: Int
    public let items: [RoleChatLiveItem]

    enum CodingKeys: String, CodingKey {
        case items
        case durationMs = "duration_ms"
    }

    public var stepCount: Int { items.filter(\.isStep).count }
    /// Есть что показать свёрнутой строкой: шаги или размышления.
    public var hasDetails: Bool { items.contains { !$0.isText } }
}

/// Элемент хода роли — кусок текста, шаг (вызов инструмента) или
/// размышление. Сервер отдаёт голое имя инструмента и короткую подпись из
/// аргументов (путь, команда); действие по-русски выбирает клиент
/// (`RoleLiveStepKind`).
public enum RoleChatLiveItem: Decodable, Sendable, Equatable, Identifiable {
    case text(String)
    case step(RoleChatLiveStep)
    case thinking(RoleChatThinking)

    public var id: String {
        switch self {
        case .text(let text): return "text-\(text.hashValue)"
        case .step(let step): return step.id
        case .thinking(let thinking): return thinking.id
        }
    }

    public var isStep: Bool {
        if case .step = self { return true }
        return false
    }

    public var isText: Bool {
        if case .text = self { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey { case kind, text }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "thinking":
            self = .thinking(try RoleChatThinking(from: decoder))
        default:
            self = .step(try RoleChatLiveStep(from: decoder))
        }
    }
}

/// Размышление роли (владелец 30.09.2026): полный текст, пока идёт — растёт.
/// В чате свёрнуто в строку «Думает…»/«Размышления · 12 с»; текст виден в
/// раскрытом окошке или в шторке по тапу.
public struct RoleChatThinking: Decodable, Sendable, Equatable {
    public let id: String
    public let text: String
    public let isRunning: Bool
    public let startedAt: String?
    public let endedAt: String?

    public init(id: String, text: String, isRunning: Bool, startedAt: String? = nil, endedAt: String? = nil) {
        self.id = id
        self.text = text
        self.isRunning = isRunning
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, status
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        isRunning = (try container.decodeIfPresent(String.self, forKey: .status) ?? "running") == "running"
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(String.self, forKey: .endedAt)
    }

    /// Сколько роль думала — для «Размышления · 12 с»; идёт — nil.
    public var durationSeconds: Int? {
        RoleChatTime.seconds(from: startedAt, to: endedAt)
    }
}

enum RoleChatTime {
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func seconds(from start: String?, to end: String?) -> Int? {
        guard let start = date(start), let end = date(end) else { return nil }
        return max(0, Int(end.timeIntervalSince(start).rounded()))
    }
}

/// Локальная очередь показа ответа. Сервер присылает накопленные снимки
/// раз в 150 мс, а экран выпускает текст с ровной скоростью по словам:
/// скорость плавно подстраивается под очередь, поэтому поток не идёт
/// рывками «пачка — пауза — пачка» (владелец 30.09.2026). Шаги и
/// размышления видны сразу, как только до них дошёл текст.
struct RoleLiveTextPacer {
    private(set) var target: [RoleChatLiveItem] = []
    private(set) var visibleCharacters: [Int] = []
    /// Текущая скорость, символов в секунду — ей же рендер проявляет хвост.
    private(set) var rate: Double = Self.minRate
    /// Когда видимый текст последний раз вырос.
    private(set) var lastRevealAt: Date = .distantPast
    private var texts: [[Character]] = []
    private var budget: Double = 0
    /// Сколько очередь стоит без новых слов — недописанное сервером слово
    /// показываем, только если продолжения долго нет.
    private var stall: TimeInterval = 0

    static let minRate: Double = 40
    static let maxRate: Double = 900
    /// На сколько секунд экран в среднем отстаёт от сервера.
    static let targetLag: TimeInterval = 0.4
    /// Сколько ждать продолжения оборванного слова в конце снимка.
    static let tailWait: TimeInterval = 0.35

    mutating func ingest(_ items: [RoleChatLiveItem]) {
        var next = Array(repeating: 0, count: items.count)
        var nextTexts: [[Character]] = Array(repeating: [], count: items.count)
        for index in items.indices {
            guard case .text(let new) = items[index] else { continue }
            let chars = Array(new)
            nextTexts[index] = chars
            guard index < target.count, case .text = target[index] else { continue }
            let old = texts[index]
            let shown = visibleCharacters[index]
            if chars.count >= shown, old.count >= shown, chars[0..<shown] == old[0..<shown] {
                next[index] = shown
            }
        }
        target = items
        texts = nextTexts
        visibleCharacters = next
    }

    var pendingCharacters: Int {
        texts.indices.reduce(0) { $0 + max(0, texts[$1].count - visibleCharacters[$1]) }
    }

    var hasPendingText: Bool { pendingCharacters > 0 }

    /// Шаг часов на `elapsed` секунд. Возвращает true, пока в очереди
    /// остаются символы.
    @discardableResult
    mutating func advance(elapsed: TimeInterval, now: Date = .now) -> Bool {
        let pending = pendingCharacters
        guard pending > 0 else {
            budget = 0
            stall = 0
            return false
        }
        // Скорость тянется к «очередь уйдёт за targetLag», но плавно — без
        // скачков, из-за которых поток то бежит, то встаёт.
        let desired = min(Self.maxRate, max(Self.minRate, Double(pending) / Self.targetLag))
        let blend = min(1, elapsed / 0.3)
        rate += (desired - rate) * blend
        budget += rate * elapsed
        stall += elapsed

        guard let index = texts.indices.first(where: { visibleCharacters[$0] < texts[$0].count }) else {
            return false
        }
        let chars = texts[index]
        // Текст, за которым уже идёт шаг, дописан; у последнего куска
        // хвостовое слово может быть оборвано снимком посередине.
        let mayGrow = index == texts.count - 1
        var shown = visibleCharacters[index]
        let before = shown
        while shown < chars.count {
            // Конец следующего слова: пробелы перед ним и само слово.
            var stop = shown
            while stop < chars.count, chars[stop].isWhitespace { stop += 1 }
            while stop < chars.count, !chars[stop].isWhitespace { stop += 1 }
            let cost = Double(stop - shown)
            if mayGrow && stop == chars.count {
                // Продолжение слова ещё может прийти. Ждём его, не копя
                // бюджет впрок (иначе после ожидания вышел бы рывок); долго
                // не приходит — показываем как есть.
                if stall < Self.tailWait {
                    budget = min(budget, cost)
                    break
                }
                budget = 0
                shown = stop
                break
            }
            if cost > budget { break }
            budget -= cost
            shown = stop
        }
        if shown > before {
            visibleCharacters[index] = shown
            lastRevealAt = now
            stall = 0
        }
        return hasPendingText
    }

    /// Выпустить всё сразу (тесты и конец хода).
    mutating func flush(now: Date = .now) {
        for index in texts.indices { visibleCharacters[index] = texts[index].count }
        lastRevealAt = now
        budget = 0
    }

    var visibleItems: [RoleChatLiveItem] {
        var result: [RoleChatLiveItem] = []
        for index in target.indices {
            switch target[index] {
            case .text:
                let count = visibleCharacters[index]
                let chars = texts[index]
                if count > 0 { result.append(.text(String(chars[0..<count]))) }
                if count < chars.count { return result }
            case .step, .thinking:
                result.append(target[index])
            }
        }
        return result
    }
}

public struct RoleChatLiveStep: Decodable, Sendable, Equatable {
    public enum Status: String, Decodable, Sendable {
        case running, done, error
    }

    public let id: String
    public let tool: String
    public let detail: String?
    public let status: Status
    public let startedAt: String?
    public let endedAt: String?

    public init(id: String, tool: String, detail: String?, status: Status,
                startedAt: String? = nil, endedAt: String? = nil) {
        self.id = id
        self.tool = tool
        self.detail = detail
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, tool, detail, status
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }

    /// Сколько шёл шаг — для шторки с подробностями; идёт — nil.
    public var durationSeconds: Int? {
        RoleChatTime.seconds(from: startedAt, to: endedAt)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        tool = try container.decode(String.self, forKey: .tool)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        // Незнакомый статус (сервер новее клиента) — считаем шаг идущим,
        // а не роняем весь снимок хода.
        let raw = try container.decodeIfPresent(String.self, forKey: .status) ?? "running"
        status = Status(rawValue: raw) ?? .running
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(String.self, forKey: .endedAt)
    }
}

/// Идущий сейчас ход роли в чате (`chats:live`, `GET /chats/:id/live`):
/// текст ответа растёт по словам, между кусками текста — шаги.
public struct RoleChatLiveTurn: Decodable, Sendable, Equatable {
    public let chatID: String
    public let userID: String
    public let name: String
    public let startedAt: String?
    public let items: [RoleChatLiveItem]
    /// Роль сейчас думает (28.09.2026): последняя законченная фраза её
    /// размышлений; "" — думает, фразы ещё нет; nil — не думает.
    public let thinking: String?

    enum CodingKeys: String, CodingKey {
        case name, items, thinking
        case chatID = "chat_id"
        case userID = "user_id"
        case startedAt = "started_at"
    }

    /// Когда ход начался — для счётчика «идёт 42 с».
    public var startDate: Date? { RoleChatTime.date(startedAt) }

    /// Идущее размышление из элементов хода; у сервера до 30.09.2026 его
    /// нет — тогда «думает» видно только по полю `thinking`.
    public var runningThinking: RoleChatThinking? {
        for item in items.reversed() {
            if case .thinking(let thinking) = item, thinking.isRunning { return thinking }
        }
        return nil
    }
}
