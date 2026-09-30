import Foundation
import Observation

/// Кому адресуется черновик сообщения — три состояния кнопки-адресата в
/// композере (SCREENS-2 §3.1): не выбран / выбраны все / выбран конкретный
/// участник.
enum ChatAddressee: Equatable {
    case none
    case all
    case user(id: String, name: String)
}

/// Кто сейчас печатает/работает — для `TypingLine`.
struct ChatTypist: Identifiable, Equatable {
    var id: String { userId }
    let userId: String
    let name: String
}

/// Состояние экрана «Чат» — свой `APIClient` и свой `RealtimeClient`
/// (ВТОРОЕ, отдельное от приложенческого в `Sources/App/`): общий канал в
/// environment уже занят единственным слотом `onEvent` под `TaskStore`/
/// `NotificationStore` (`Sources/App/TaskFlowApp.swift`), переписать его
/// отсюда значило бы молча оборвать обновление задач для всего приложения.
/// Своя папка — свой сокет; владелец инфраструктуры может позже свести оба
/// в один мультиплексор в `Core`, это уже не моя граница.
@MainActor
@Observable
final class ChatViewModel {
    private(set) var messages: [ApiChatMessage] = []
    private(set) var participants: [ApiChatParticipant] = []
    private(set) var isLoadingHistory = false
    var historyErrorMessage: String?
    var sendErrorMessage: String?
    var uploadErrorMessage: String?
    var transcribeErrorMessage: String?

    /// Выбранный локально канал переключателя — значим, только если
    /// `bothChannelsVisible` (иначе всегда действует `agents`, см. `activeChannel`).
    var channel: ChatChannel = .owner

    var draftText: String = "" {
        didSet { onDraftChanged() }
    }
    private(set) var pendingAttachments: [ApiChatAttachment] = []
    var isUploadingAttachment = false
    var addressee: ChatAddressee = .none
    var isAddresseeMenuOpen = false

    private(set) var typists: [ChatTypist] = []

    /// Статистика (`GET /chat/stats`, spec §3.9 — «кто кого озадачивает»).
    /// Кнопка в шапке раньше была пустой заглушкой (`ChatStatsSheet — вне
    /// охвата») — эндпоинт и модель `ApiChatStats` уже были готовы (не мои),
    /// просьба владельца 03.09.2026 — подключить, раз оно реально есть.
    private(set) var stats: ApiChatStats?
    private(set) var isLoadingStats = false
    var statsErrorMessage: String?
    var isStatsSheetOpen = false

    private(set) var currentUserId: String?
    private var isOwner = false
    private var isOrchestrator = false

    private let api: APIClient
    private let realtime = RealtimeClient()
    private var typingSweepTask: Task<Void, Never>?
    private var typingDeadlines: [String: (name: String, until: Date)] = [:]
    private var lastTypingSignalSentAt: Date?
    private var historyCursor: String?

    init(api: APIClient = APIClient()) {
        self.api = api
        realtime.onEvent = { [weak self] event in self?.handle(event) }
        realtime.onReconnected = { [weak self] in
            Task { await self?.reloadAll() }
        }
    }

    /// `SessionStore.currentUser` приходит из `@Environment`, недоступного
    /// внутри `init()` вью — экран зовёт это явно в `.task` до `start()`.
    func configure(currentUser: ApiUser?) {
        currentUserId = currentUser?.id
        isOwner = currentUser?.role == .owner
        isOrchestrator = currentUser?.role == .orchestrator
    }

    // MARK: - Производные состояния (1:1 `ChatScreen.tsx`)

    var bothChannelsVisible: Bool { isOwner || isOrchestrator }
    var activeChannel: ChatChannel { bothChannelsVisible ? channel : .agents }
    var headerTitle: String { bothChannelsVisible ? "Чат" : "Чат агентов" }

    /// Собеседник в личном канале: у владельца — «Секретарь», у оркестратора — владелец.
    ///
    /// 10.09.2026, карточка 4396f8c9: у владельца здесь БЫЛ оркестратор, и канал
    /// читался как разговор с ним. Автономного оркестратора решением 08.09.2026
    /// нет, а канал стал ОКНОМ ПОСТАНОВКИ ЗАДАЧ: владелец наговаривает сюда
    /// работу, её разбирает локальная модель, и ответ про собранную карточку
    /// пишет «Секретарь» — учётка скрипта, не исполнитель (миграция 028).
    /// Ищем его по признакам, а не по зашитому идентификатору: единственный
    /// участник, который машина (`type == .ai`) и при этом не исполнитель
    /// (`role == .viewer`).
    var counterpart: ApiChatParticipant? {
        guard bothChannelsVisible else { return nil }
        guard isOwner else { return participants.first { $0.role == .owner } }
        return participants.first { $0.role == .viewer && $0.type == .ai }
    }

    /// Первое слово имени — «Оркестратор Claude» → «Оркестратор» (вкладка переключателя).
    /// Запасное имя разное по сторонам канала, как в `ChatScreen.tsx`: владелец
    /// разговаривает с «Секретарём», оркестратор — с «Максимом».
    var counterpartFirstName: String {
        let fallback = isOwner ? "Секретарь" : "Максим"
        return (counterpart?.name ?? fallback).split(separator: " ").first.map(String.init) ?? fallback
    }

    /// У владельца первая вкладка — окно постановки задач, и пустой экран это
    /// единственное место, где можно сказать, что оно делает: дальше он сам
    /// увидит по ответам (карточка 4396f8c9). Тексты дословно как в
    /// `ChatScreen.tsx`.
    var emptyStateText: String {
        if activeChannel == .agents && isOwner {
            return "Пока пусто — исполнители ещё не переписывались."
        }
        if activeChannel == .owner && isOwner {
            return "Пока пусто. Наговорите сюда задачу — разберу и соберу карточку-черновик, останется нажать «Запустить»."
        }
        return "Пока пусто — первое сообщение здесь твоё."
    }

    /// Себя не показываем (свою печать и так видно по клавиатуре); в
    /// личном канале — только отметку собеседника (глобальная по всему
    /// чату отметка иначе мигала бы служебными репликами в личной ленте).
    var visibleTypists: [ChatTypist] {
        typists
            .filter { $0.userId != currentUserId }
            .filter { activeChannel != .owner || $0.userId == counterpart?.id }
    }

    /// «Секретарь» (`role == .viewer`, `type == .ai`) в выбор адресата не
    /// попадает: это учётка скрипта окна постановки, а не исполнитель — писать
    /// ему адресно некому и незачем, отвечает он только на надиктовку в своём
    /// канале (миграция 028, карточка 4396f8c9). Мёртвых пунктов в списке быть
    /// не должно по той же причине, по какой в интерфейсе нет мёртвых кнопок.
    /// 1:1 с `ChatComposer.tsx`.
    var others: [ApiChatParticipant] {
        participants.filter { $0.id != currentUserId && !($0.role == .viewer && $0.type == .ai) }
    }

    var canSend: Bool {
        (!draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
            && !isUploadingAttachment
    }

    // MARK: - Жизненный цикл

    func start() async {
        realtime.connect()
        startTypingSweep()
        await reloadAll()
    }

    func stop() {
        realtime.disconnect()
        typingSweepTask?.cancel()
        typingSweepTask = nil
    }

    func switchChannel(to newChannel: ChatChannel) {
        guard bothChannelsVisible, newChannel != channel else { return }
        channel = newChannel
        Task { await loadHistory() }
    }

    func openStats() {
        isStatsSheetOpen = true
        guard stats == nil, !isLoadingStats else { return }
        Task { await loadStats() }
    }

    func loadStats() async {
        isLoadingStats = true
        statsErrorMessage = nil
        defer { isLoadingStats = false }
        do {
            stats = try await api.chatStats()
        } catch {
            statsErrorMessage = "Не удалось загрузить статистику"
        }
    }

    private func reloadAll() async {
        async let p: () = loadParticipants()
        async let h: () = loadHistory()
        async let t: () = loadTypingSnapshot()
        _ = await (p, h, t)
        try? await api.markChatReadNow()
    }

    func loadParticipants() async {
        participants = (try? await api.chatParticipants()) ?? participants
    }

    func loadHistory() async {
        isLoadingHistory = messages.isEmpty
        defer { isLoadingHistory = false }
        do {
            // Первая загрузка — только последние сообщения, чтобы экран открылся быстро.
            // Остальное подгружается при прокрутке вверх (loadMoreHistory).
            let limit: Int = messages.isEmpty ? 50 : 50
            let page = try await api.fetchChatHistory(
                channel: activeChannel,
                before: historyCursor,
                limit: limit
            )
            if messages.isEmpty {
                messages = page.messages
            } else {
                messages.append(contentsOf: page.messages)
            }
            historyCursor = page.hasMore ? page.messages.first?.id : nil
            historyErrorMessage = nil
        } catch {
            historyErrorMessage = Self.message(for: error)
        }
    }

    /// После отправки нужна свежая страница без `before`: `loadHistory()`
    /// намеренно использует курсор старой истории. Курсор здесь не меняем,
    /// чтобы последующая пагинация продолжилась с прежнего места.
    private func refreshLatestMessages() async {
        do {
            let page = try await api.fetchChatHistory(
                channel: activeChannel,
                before: nil,
                limit: 50
            )
            var knownIDs = Set(messages.map(\.id))
            messages.append(contentsOf: page.messages.filter { knownIDs.insert($0.id).inserted })
            historyErrorMessage = nil
        } catch {
            historyErrorMessage = Self.message(for: error)
        }
    }

    // MARK: - Отправка

    func send() async {
        guard canSend else { return }
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)

        let toUserId: String
        if activeChannel == .owner {
            guard let counterpart else { return }
            toUserId = counterpart.id
        } else {
            switch addressee {
            case .none:
                // Как в вебе: не отказ, а раскрытие списка — кнопка,
                // которая просто не срабатывает, ничего не объясняет.
                isAddresseeMenuOpen = true
                return
            case .all:
                toUserId = "all"
            case .user(let id, _):
                toUserId = id
            }
        }

        do {
            sendErrorMessage = nil
            let attachmentIds = pendingAttachments.map(\.id)
            _ = try await api.postChatMessage(
                text: text, toUserId: toUserId, channel: activeChannel, attachmentIds: attachmentIds
            )
            draftText = ""
            pendingAttachments = []
            await signalTyping(typing: false)
            await refreshLatestMessages() // сразу видим своё сообщение, не дожидаясь WS
        } catch {
            sendErrorMessage = Self.message(for: error)
        }
    }

    // MARK: - Вложения

    /// Очистить ленту текущего канала (владелец). Владелец 21.09.2026:
    /// «должна быть возможность очищать этот чат».
    func clearChat() async {
        do {
            try await api.clearChatMessages(channel: activeChannel)
            messages = []
        } catch {
            sendErrorMessage = Self.message(for: error)
        }
    }

    func attach(fileName: String, data: Data, mime: String) async {
        isUploadingAttachment = true
        uploadErrorMessage = nil
        defer { isUploadingAttachment = false }
        do {
            let response = try await api.uploadChatAttachment(fileName: fileName, data: data, mime: mime)
            pendingAttachments.append(response.attachment)
        } catch {
            uploadErrorMessage = Self.message(for: error)
        }
    }

    func removePendingAttachment(_ id: String) async {
        pendingAttachments.removeAll { $0.id == id }
        try? await api.deleteAttachment(id: id)
    }

    // MARK: - «Печатает» (сигнал своей стороны)

    private func onDraftChanged() {
        let typing = !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        Task { await signalTyping(typing: typing) }
    }

    func onComposerBlur() {
        Task { await signalTyping(typing: false) }
    }

    /// Throttle 3с на старте печати (веб: `TYPING_SIGNAL_THROTTLE_MS`) —
    /// «перестал» шлётся немедленно, но только если до этого реально
    /// зажигали отметку (пустое поле не должно слать лишний stop).
    private func signalTyping(typing: Bool) async {
        if !typing {
            guard lastTypingSignalSentAt != nil else { return }
            lastTypingSignalSentAt = nil
            try? await api.signalChatTyping(stop: true)
            return
        }
        let now = Date()
        if let last = lastTypingSignalSentAt, now.timeIntervalSince(last) < 3.0 { return }
        lastTypingSignalSentAt = now
        try? await api.signalChatTyping(stop: false)
    }

    // MARK: - «Печатает» (чужая сторона)

    private func loadTypingSnapshot() async {
        guard let snapshot = try? await api.fetchChatTypingSnapshot() else { return }
        let now = Date()
        for entry in snapshot.typing {
            typingDeadlines[entry.userId] = (entry.name, now.addingTimeInterval(Double(entry.ttlMs) / 1000))
        }
        recomputeTypists()
    }

    private func startTypingSweep() {
        typingSweepTask?.cancel()
        typingSweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.pruneExpiredTypists()
            }
        }
    }

    private func pruneExpiredTypists() {
        let now = Date()
        typingDeadlines = typingDeadlines.filter { $0.value.until > now }
        recomputeTypists()
    }

    private func recomputeTypists() {
        // СТАБИЛЬНЫЙ порядок: словарь в Swift перебирается недетерминированно,
        // поэтому без сортировки массив каждый секундный sweep выглядел новым,
        // `onChange(of: visibleTypists)` срабатывал постоянно и лента сообщений
        // прыгала вверх-вниз (владелец 21.09.2026). Сортируем по id — тогда
        // значение меняется только при реальном изменении состава.
        typists = typingDeadlines
            .map { ChatTypist(userId: $0.key, name: $0.value.name) }
            .sorted { $0.userId < $1.userId }
    }

    // MARK: - Реалтайм

    /// Положить пришедшее по сокету сообщение в ленту, если оно из открытого
    /// канала. Идемпотентно: то же сообщение не задваивается (своё уже могло
    /// прийти ответом `POST /chat`).
    ///
    /// Событие `chat:new` несёт сообщение целиком — сервер рассылает строку
    /// `chat_messages` с joins, включая `task_title` (см. `ownerDraft.ts`,
    /// ответ Секретаря), поэтому дозагружать его отдельным запросом не нужно.
    func receiveRealtimeMessage(_ message: ApiChatMessage) {
        guard message.channel == activeChannel else { return }
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
    }

    func handle(_ event: RealtimeEvent) {
        switch event {
        case .chatNew(let message):
            // Пришло само сообщение — автор больше не «печатает» (то же,
            // что делает сервер на своей стороне, гасим и у себя, не ждём
            // отдельного chat:typing stop).
            if let from = message.fromUserId { typingDeadlines.removeValue(forKey: from) }
            recomputeTypists()
            // Раньше здесь звался `loadHistory()` — но это ПАГИНАЦИЯ: она
            // тянет сообщения СТАРШЕ курсора, и новое в ленту не попадало.
            // Ответ Секретаря с карточкой был виден только после повторного
            // входа на экран (владелец 19.09.2026).
            receiveRealtimeMessage(message)
        case .chatTyping(let raw):
            applyTypingEvent(raw)
        default:
            break
        }
    }

    private func applyTypingEvent(_ raw: JSONValue) {
        guard case .object(let dict) = raw,
              case .string(let userId)? = dict["user_id"],
              case .string(let name)? = dict["name"],
              case .string(let state)? = dict["state"]
        else { return }
        if state == "stop" {
            typingDeadlines.removeValue(forKey: userId)
        } else {
            var ttlMs: Double = 0
            if case .number(let n)? = dict["ttl_ms"] { ttlMs = n }
            typingDeadlines[userId] = (name, Date().addingTimeInterval(ttlMs / 1000))
        }
        recomputeTypists()
    }

    private static func message(for error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
