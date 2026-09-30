import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import PhotosUI
import UIKit
import QuickLook

/// Личные и групповые чаты живут отдельно от старого окна постановки задач.
///
/// Вид списка — по образцу Microsoft Teams (владелец 21.09.2026, LOCK-195):
/// аватар слева, имя, превью последнего сообщения, справа время и бейдж
/// непрочитанных, строки во всю ширину — без карточек и шевронов. Фон и
/// шапку экрана правка НЕ трогает: владелец прямо сказал «фон не трогай».
///
/// Отдельным блоком над списком — «Секретарь»: это прежний owner-канал
/// (надиктовка → карточка), но в списке он выглядит как обычный собеседник.
/// Владелец 21.09.2026: «сделай его просто как отдельный вид участника», без
/// подписей-подсказок.
struct RoleChatsScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var chats: [RoleChat] = []
    @State private var secretary: SecretarySnapshot?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingCreate = false
    @State private var realtime = RealtimeClient()
    private let api = APIClient()

    /// Блок «Секретарь» кормится старым каналом `owner`: у новых чатов
    /// свой контракт (`GET /api/chats`), у него — `GET /chat` и `/chat/unread`.
    private struct SecretarySnapshot: Equatable {
        var preview: String
        var fromMe: Bool
        var createdAt: String?
        var unread: Int
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isLoading && chats.isEmpty && secretary == nil {
                    ProgressView("Загрузка чатов")
                        .frame(maxWidth: .infinity)
                        .padding(.top, TFSpacing.xl)
                } else {
                    secretaryBlock
                    // Граница блока: «Секретарь» стоит особняком, а не первым
                    // в общем списке (владелец 21.09.2026).
                    TFDivider()
                    if chats.isEmpty {
                        Text("Пока нет чатов. Создайте чат с одной или несколькими ролями.")
                            .tfText(.action)
                            .foregroundStyle(Color.tfDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TFSpacing.screenHorizontal)
                            .padding(.top, TFSpacing.xl)
                    } else {
                    ForEach(Array(chats.enumerated()), id: \.element.id) { index, chat in
                        NavigationLink(value: AppRoute.roleChat(id: chat.id)) {
                            chatRow(chat)
                        }
                        .buttonStyle(.plain)
                            if index < chats.count - 1 {
                                // Разделитель отбит до начала текста, а не под
                                // аватар — так строка читается как строка
                                // списка, а не как карточка.
                                TFDivider(inset: TFSpacing.screenHorizontal + TFAvatar.Size.xl.rawValue + TFSpacing.md)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, TFSpacing.xl)
        }
        .background(Color.tfBackground)
        .tfNativeHeader("Чаты")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Создать чат")
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateRoleChatScreen {
                Task { await load() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        // Живое обновление (владелец 22.09.2026: «чтобы не выходить и не
        // заходить заново»): пока список открыт, слушаем сокет и на новое
        // сообщение тихо перечитываем превью и непрочитанные.
        .task {
            realtime.onEvent = { event in
                switch event {
                case .roleChatMessage:
                    Task { await reloadSilently() }
                case .chatNew:
                    Task { await loadSecretary() }
                default:
                    break
                }
            }
            realtime.onReconnected = { Task { await reloadSilently() } }
            realtime.connect()
        }
        .onDisappear { realtime.disconnect() }
        .alert("Не удалось загрузить чаты", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Повторить") { Task { await load() } }
            Button("Закрыть", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Блок «Секретарь»

    @ViewBuilder
    private var secretaryBlock: some View {
        // Только владельцу: owner-канал — его разговор с секретарём, у
        // остальных учёток этого чата нет.
        if session.currentUser?.role == .owner {
            NavigationLink(value: AppRoute.roleChat(id: "chat-secretary")) {
                ChatListRow(
                    avatar: AnyView(TFAvatar(
                        size: .xl,
                        initials: secretaryInitials,
                        tint: Color.tfTeal,
                        userID: "u-secretary"
                    )),
                    title: "Секретарь",
                    preview: secretaryPreview,
                    time: ChatListTime.label(secretary?.createdAt),
                    unread: secretary?.unread ?? 0
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var secretaryInitials: String {
        "С"
    }

    private var secretaryPreview: String {
        guard let secretary, !secretary.preview.isEmpty else { return "" }
        return secretary.fromMe ? "Вы: \(secretary.preview)" : secretary.preview
    }

    // MARK: - Строка чата с ролями

    private func chatRow(_ chat: RoleChat) -> some View {
        ChatListRow(
            avatar: AnyView(chatAvatar(chat)),
            title: chat.displayTitle(excluding: session.currentUser?.id),
            preview: previewText(chat),
            time: ChatListTime.label(chat.lastMessage?.createdAt),
            unread: chat.unread,
            taskTitle: chat.taskTitle
        )
    }

    @ViewBuilder
    private func chatAvatar(_ chat: RoleChat) -> some View {
        let others = chat.others(excluding: session.currentUser?.id)
        if chat.kind == "group" {
            RoleGroupAvatar(members: others)
        } else if let member = others.first {
            RoleMemberAvatar(member: member)
        } else {
            TFAvatar(size: .xl, initials: "?", tint: Color(hex: TFHexDefault.unassigned))
        }
    }

    private func previewText(_ chat: RoleChat) -> String {
        guard let last = chat.lastMessage else { return "" }
        let body = last.displayText
        guard !body.isEmpty else { return "" }
        if last.fromUserID == session.currentUser?.id { return "Вы: \(body)" }
        // Имя отправителя нужно только там, где он неочевиден, — в группе.
        if chat.kind == "group", let name = last.fromUserName, !name.isEmpty {
            return "\(name): \(body)"
        }
        return body
    }

    // MARK: - Загрузка

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do { chats = try await api.roleChats().filter { $0.id != Self.secretaryChatID } }
        catch is CancellationError {
            // Потянули «обновить» ещё раз, пока прошлая загрузка не
            // закончилась — предыдущая отменяется штатно, не повод пугать.
        }
        catch { errorMessage = error.localizedDescription }
        await loadSecretary()
    }

    /// Секретарь (владелец 25.09.2026, docs/ПЛАН Супер Секретарь/) — с этого
    /// момента настоящая комната `/api/chats`, но в общем списке стоит
    /// особняком своим блоком (владелец 21.09.2026) — фильтруем, чтобы не
    /// задвоилась.
    private static let secretaryChatID = "chat-secretary"

    /// Фоновое обновление по сокету: без спиннера и без алерта — сбой
    /// здесь не повод пугать, следующее событие или «потянуть вниз» догонят.
    private func reloadSilently() async {
        if let fresh = try? await api.roleChats() { chats = fresh.filter { $0.id != Self.secretaryChatID } }
    }

    /// Отдельно от списка чатов: падение этого блока не должно показывать
    /// ошибку всего экрана — и наоборот.
    private func loadSecretary() async {
        guard session.currentUser?.role == .owner else {
            secretary = nil
            return
        }
        async let history = try? api.fetchChatHistory(channel: .owner, limit: 1)
        async let unread = try? api.chatUnread()
        let (page, counter) = await (history, unread)
        let last = page?.messages.first
        secretary = SecretarySnapshot(
            preview: last?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            fromMe: last?.fromUserId != nil && last?.fromUserId == session.currentUser?.id,
            createdAt: last?.createdAt,
            unread: counter?.count ?? 0
        )
    }
}

/// Комната чата по идентификатору — адресат маршрута `AppRoute.roleChat`.
/// Список отдаёт только id: маршрут обязан быть `Hashable` и не тащить
/// состав чата с собой.
struct RoleChatRoomLoader: View {
    let chatID: String
    @State private var chat: RoleChat?
    @State private var failed = false
    private let api = APIClient()

    var body: some View {
        Group {
            if let chat {
                RoleChatRoomScreen(chat: chat)
            } else if failed {
                ContentUnavailableView(
                    "Чат не открылся",
                    systemImage: "bubble.left",
                    description: Text("Проверьте связь и зайдите ещё раз.")
                )
            } else {
                ProgressView("Загрузка чата")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tfBackground)
        .task { await load() }
    }

    private func load() async {
        do { chat = try await api.roleChat(id: chatID) }
        catch { failed = true }
    }
}

/// Обёртка для блока «Секретарь». `ChatScreen` считает себя корневым экраном
/// вкладки «Чат»: его стрелка «назад» зовёт действие, которое кладёт
/// `RootShellView` (сброс вкладки в «Обзор»). Здесь он открыт пушем из
/// списка, поэтому свою стрелку он не рисует (`hidesOwnBackButton`), а
/// действие всё равно подменяем на закрытие пуша — на случай, если системную
/// кнопку в будущем уберут.
struct SecretaryChatScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ChatScreen(hidesOwnBackButton: true)
            .environment(\.chatBackAction, { dismiss() })
    }
}

/// Строка списка чатов — одна на все виды (роль, группа, секретарь):
/// аватар, имя, превью, время, бейдж непрочитанных. Строка во всю ширину,
/// без карточки и шеврона — вид списка, а не меню настроек.
private struct ChatListRow: View {
    let avatar: AnyView
    let title: String
    let preview: String
    let time: String?
    let unread: Int
    /// Название задачи, за которой закреплён чат (`nil` — свободный).
    var taskTitle: String?

    var body: some View {
        HStack(spacing: TFSpacing.md) {
            // Аватар — украшение: имя стоит рядом текстом, и VoiceOver не
            // должен читать «Аватар: Q» перед ним. Без этого строка
            // «Секретарь» озвучивалась дважды («Секретарь, Секретарь»).
            avatar.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .tfText(.body)
                    .fontWeight(unread > 0 ? .semibold : .regular)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                Text(preview)
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
                // Пометка «чат за задачей»: по ней видно, куда уходит
                // переписка (владелец 21.09.2026: «пометка нужна»).
                if let taskTitle, !taskTitle.isEmpty {
                    Label(taskTitle, systemImage: "checklist")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfDim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: TFSpacing.sm)
            VStack(alignment: .trailing, spacing: TFSpacing.sm) {
                if let time {
                    Text(time)
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
                }
                if unread > 0 { badge }
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.vertical, TFSpacing.md)
        .contentShape(Rectangle())
        // Строка целиком — одна единица для VoiceOver: без этого он читает
        // аватар, имя, превью и время как четыре отдельных элемента.
        .accessibilityElement(children: .combine)
    }

    private var badge: some View {
        Text(unread > 99 ? "99+" : "\(unread)")
            .tfText(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, TFSpacing.xs + 2)
            .frame(minWidth: 20, minHeight: 20)
            .background(Capsule().fill(Color.tfRedSolid))
            .accessibilityLabel("Непрочитанных: \(unread)")
    }
}

// FlowLayout переехал в Sources/DesignSystem/Components/FlowLayout.swift
// (28.09.2026) — чипам «Сведения» на карточке задачи нужна та же раскладка.

/// «Разработчик печатает…» с анимированными точками — показывается только
/// по сигналу сервера, пока роль действительно готовит ответ (22.09.2026).
private struct RoleChatTypingLine: View {
    let names: [String]

    var body: some View {
        HStack(spacing: TFSpacing.sm) {
            Text(text)
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
                .lineLimit(1)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    TypingDot(delay: Double(i) * TFAnimation.typingDotPhaseShift)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var text: String {
        if names.count == 1 { return "\(names[0]) печатает" }
        return "\(names.dropLast().joined(separator: ", ")) и \(names.last ?? "") печатают"
    }
}

/// Подпись/иконка по имени инструмента с сервера — сервер имя не
/// интерпретирует, это целиком презентационная таблица клиента.
enum RoleStepPresentation {
    static func label(forTool tool: String) -> String {
        switch tool {
        case "read": return "Читает"
        case "edit", "write": return "Правит"
        case "bash": return "Выполняет команду"
        case "grep", "glob": return "Ищет"
        default: return "Работает"
        }
    }

    static func symbol(forTool tool: String) -> String {
        switch tool {
        case "read": return "doc.text"
        case "edit", "write": return "pencil.line"
        case "bash": return "bolt"
        case "grep", "glob": return "magnifyingglass"
        default: return "gearshape"
        }
    }
}

/// Строка «роль делает шаг прямо сейчас» — замена `RoleChatTypingLine`
/// в 1:1-чате, когда для роли пришёл `tool`. По мотивам референсного
/// AgentActivityFeed (26.09.2026, брейнсторм с владельцем).
struct RoleStepLine: View {
    let name: String
    let tool: String

    var body: some View {
        HStack(spacing: TFSpacing.sm) {
            Image(systemName: RoleStepPresentation.symbol(forTool: tool))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.tfSub)
                .symbolEffect(.pulse, options: .repeating)
            Text("\(name): \(RoleStepPresentation.label(forTool: tool))")
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(RoleStepPresentation.label(forTool: tool))")
    }
}

/// Аватар участника чата — фото, если оно есть у учётки, иначе инициалы.
private struct RoleMemberAvatar: View {
    let member: RoleChatMember
    var size: TFAvatar.Size = .xl

    var body: some View {
        let initials = member.initials ?? String(member.name.prefix(1))
        let tint = Color(hex: member.avatarColor ?? TFHexDefault.unassigned)
        if let path = member.avatarURL,
           let url = URL(string: APIClient.baseURL.absoluteString + path) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    TFAvatar(size: size, image: image, initials: initials, tint: tint, userID: member.id)
                } else {
                    TFAvatar(size: size, initials: initials, tint: tint, userID: member.id)
                }
            }
        } else {
            TFAvatar(size: size, initials: initials, tint: tint, userID: member.id)
        }
    }
}

/// Составной аватар группы: двое участников внахлёст, как в Teams. Больше
/// двух не рисуем — на 44pt третий уже неразличим, а полный состав виден в
/// заголовке комнаты.
private struct RoleGroupAvatar: View {
    let members: [RoleChatMember]

    var body: some View {
        let shown = Array(members.prefix(2))
        ZStack {
            if shown.count == 1 {
                RoleMemberAvatar(member: shown[0])
            } else if shown.count >= 2 {
                RoleMemberAvatar(member: shown[0], size: .md)
                    .overlay(Circle().stroke(Color.tfBackground, lineWidth: 2))
                    .offset(x: -7)
                RoleMemberAvatar(member: shown[1], size: .md)
                    .overlay(Circle().stroke(Color.tfBackground, lineWidth: 2))
                    .offset(x: 7)
            } else {
                TFAvatar(size: .xl, initials: "?", tint: Color(hex: TFHexDefault.unassigned))
            }
        }
        .frame(width: TFAvatar.Size.xl.rawValue, height: TFAvatar.Size.xl.rawValue)
    }
}

/// Время в строке списка чатов: сегодня — часы, вчера — словом, дальше до
/// недели — день недели, ещё дальше — дата. Формат взят у Teams, потому что
/// строка списка читается «когда было последнее сообщение», а не «сколько
/// прошло» (`RelativeTime` в этой же папке отвечает на второй вопрос).
private enum ChatListTime {
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM"
        return formatter
    }()

    static func label(_ raw: String?) -> String? {
        guard let moment = DateFormats.sqliteUTC(raw) else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(moment) { return clock.string(from: moment) }
        if calendar.isDateInYesterday(moment) { return "Вчера" }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: moment),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        if days < 7 { return weekday.string(from: moment).capitalized }
        return shortDate.string(from: moment)
    }
}

private struct CreateRoleChatScreen: View {
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void
    @State private var roles: [RoleProfile] = []
    @State private var selectedIDs: Set<String> = []
    @State private var title = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let api = APIClient()

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Необязательно", text: $title)
                }
                Section {
                    if roles.isEmpty { ProgressView("Загрузка ролей") }
                    ForEach(roles) { role in
                        Button {
                            guard let id = role.accountID else { return }
                            if !selectedIDs.insert(id).inserted { selectedIDs.remove(id) }
                        } label: {
                            HStack {
                                Text(role.title)
                                    .foregroundStyle(Color.tfText)
                                Spacer()
                                if let id = role.accountID, selectedIDs.contains(id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Роли")
                } footer: {
                    Text("Одна роль — персональный чат, несколько — групповой.")
                }
            }
            .navigationTitle("Новый чат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Крестик слева — закрыть, галочка справа — подтвердить:
                // так во всём приложении (владелец 21.09.2026).
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Закрыть")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await create() } } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(selectedIDs.isEmpty || isSaving)
                    .accessibilityLabel("Создать чат")
                }
            }
            .task { await loadRoles() }
            .alert("Не удалось создать чат", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Закрыть", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func loadRoles() async {
        do {
            // Только роли с учёткой могут быть участниками серверного чата.
            roles = try await api.roles().filter { $0.accountID?.hasPrefix("role_") == true }
        } catch { errorMessage = error.localizedDescription }
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let ids = roles.compactMap(\.accountID).filter { selectedIDs.contains($0) }
            _ = try await api.createRoleChat(title: name.isEmpty ? nil : name, memberIDs: ids)
            dismiss()
            onCreated()
        } catch { errorMessage = error.localizedDescription }
    }
}

/// `.sheet(item:)` требует `Identifiable` — `String` сам по себе не годится.
private struct RoomTaskRef: Identifiable { let id: String }

private struct RoleChatRoomScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var taskStore
    @Environment(\.dismiss) private var dismiss
    @State private var chat: RoleChat
    @State private var messages: [RoleChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    /// Последнее сообщение, до которого чат уже отмечен прочитанным (LOCK-206).
    @State private var markedReadMessageID: String?
    /// Карточка задачи в сообщении (владелец 25.09.2026, этап 2 «Супер
    /// Секретаря») — открывает её шторкой, тот же приём, что у ChatBubble.
    @State private var pendingTaskID: String?
    @State private var voice = RoleChatVoiceController()
    @State private var isFileImporterPresented = false
    /// Меню «+» (владелец 26.09.2026): фото/файл/камера.
    @State private var isPhotoPickerPresented = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var pendingAttachments: [ApiChatAttachment] = []
    @State private var isUploadingAttachment = false
    @State private var openingAttachmentIDs: Set<String> = []
    @State private var previewAttachmentURL: URL?
    @State private var player = VoicePlayer()
    @State private var pendingVoices: [VoiceMessage] = []
    @State private var uploadedVoiceIDs: [UUID: String] = [:]
    @State private var sendingVoiceIDs: Set<UUID> = []
    /// Режим выбора сообщений: включается из меню «…» или долгим нажатием на
    /// сообщение. В нём панель ввода заменяется полосой выбора, а тап по
    /// сообщению отмечает его (владелец 21.09.2026: «долгое нажатие максимум
    /// активирует эту функцию выбора, чтобы я потом протыкал и удалил»).
    @State private var isSelecting = false
    @State private var selectedMessageIDs: Set<String> = []
    @State private var isDeleteSelectedConfirmOpen = false
    @State private var isClearChatConfirmOpen = false
    @State private var isDetailsPresented = false
    @State private var realtime = RealtimeClient()
    /// Кто сейчас готовит ответ: userId → имя. Наполняет только сервер
    /// (`chats:typing`) — на время, пока роль действительно отвечает.
    @State private var typists: [String: String] = [:]
    /// Текущий инструмент по тайписту (userId → имя инструмента с сервера,
    /// например "read"/"edit"/"bash") — только пока `active == true` и
    /// сервер прислал `tool`. Живёт ровно как `typists`: без истории.
    @State private var typistTools: [String: String] = [:]
    /// Идущие ходы ролей (userId → снимок): текст по словам и шаги
    /// (`chats:live`, 27.09.2026). Рисуются и в группах.
    @State private var liveTurns: [String: RoleChatLiveTurn] = [:]
    /// На переходе к сохранённому ответу оставляем живой ход на мгновение,
    /// чтобы клиент успел выпустить остаток очереди без дублирования текста.
    @State private var finishingLiveTurnMessageIDs: [String: Set<String>] = [:]
    /// Автопрокрутка работает, пока владелец читает конец ленты. Ручной
    /// скролл отключает её до возвращения к низу.
    @State private var followsChatBottom = true
    @State private var userIsScrollingChat = false
    @State private var chatIsNearBottom = true
    private let api = APIClient()

    init(chat: RoleChat) { _chat = State(initialValue: chat) }

    var body: some View {
        ZStack {
            // Владелец 25.09.2026: фон экрана ЗДЕСЬ — на самом верхнем
            // уровне, а не за панелью композера, и без ограничения edges
            // (регион .keyboard входит в .ignoresSafeArea() по умолчанию).
            // Иначе в углах системной клавиатуры (у неё скруглённые верхние
            // углы) сквозь скругление просвечивал фон корневого UIWindow
            // (чёрный) — композер стоит НАД клавиатурой, его собственный фон
            // до этого места физически не достаёт.
            Color.tfBackground.ignoresSafeArea()
            composerRoom
        }
        .quickLookPreview($previewAttachmentURL)
        .onChange(of: previewAttachmentURL) { oldURL, newURL in
            if newURL == nil, let oldURL {
                try? FileManager.default.removeItem(at: oldURL.deletingLastPathComponent())
            }
        }
    }

    private var composerRoom: some View {
        VStack(spacing: 0) {
            messageScroll
            if !mentionCandidates.isEmpty {
                mentionSuggestions
            }
            if !pendingAttachments.isEmpty {
                HStack {
                    ForEach(pendingAttachments) { attachment in
                        Label(attachment.fileName, systemImage: "paperclip")
                            .lineLimit(1)
                        Button { pendingAttachments.removeAll { $0.id == attachment.id } } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Убрать вложение")
                    }
                }
                .padding(.horizontal, TFSpacing.lg)
            }
        }
        .chatComposerBar {
            if isSelecting {
                selectionBar
            } else {
                ChatVoiceComposer(
                    text: $draft,
                    placeholder: "Сообщение",
                    canSendText: (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
                        && !isSending && !isUploadingAttachment,
                    voice: voice,
                    onAttachmentSource: { source in
                        switch source {
                        case .photo: isPhotoPickerPresented = true
                        case .file: isFileImporterPresented = true
                        case .camera: isCameraPresented = true
                        }
                    },
                    onSendText: { Task { await send() } },
                    onSendVoice: sendVoicePreview,
                    onDiscardVoice: { _ in }
                )
            }
        }
        .navigationTitle(chat.displayTitle(excluding: session.currentUser?.id))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Шапка — ещё и вход в состав: владелец 21.09.2026 — «нет
            // возможности понять, кто в этом чате присутствует». Тап открывает
            // название и участников.
            ToolbarItem(placement: .principal) {
                Button { isDetailsPresented = true } label: {
                    VStack(spacing: 1) {
                        Text(chat.displayTitle(excluding: session.currentUser?.id))
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(chat.members.count) \(participantsWord(chat.members.count))")
                            .font(.caption2)
                            .foregroundStyle(Color.tfSub)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Чат: название и участники")
            }
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button { exitSelection() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Отменить выбор")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        isDeleteSelectedConfirmOpen = true
                    } label: {
                        Text(selectedMessageIDs.isEmpty
                             ? "Удалить"
                             : "Удалить (\(selectedMessageIDs.count))")
                    }
                    .disabled(selectedMessageIDs.isEmpty)
                }
            } else {
                if chat.id == "chat-secretary" {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: AppRoute.secretaryVoiceCall) {
                            Image(systemName: "waveform")
                        }
                        .accessibilityLabel("Голосовой разговор с Секретарём")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Меню «…» построено как соседние меню приложения
                        // (`ChatScreen`, `TodayScreen`, `VoiceModelsScreen`):
                        // действия — `Label`, связанные группы — `Section`,
                        // выбор из списка — ПОДМЕНЮ `Menu`, выбранное отмечено
                        // галочкой (владелец 21.09.2026: «посмотри, как у нас
                        // троеточия и подменю, и сделай ровно так же»).
                        Section {
                            // Привязка к задаче — только создателю: сервер
                            // остальным отвечает 403.
                            if chat.createdBy == session.currentUser?.id {
                                Menu {
                                    if taskStore.tasks.isEmpty {
                                        Text("Нет задач")
                                    } else {
                                        ForEach(taskStore.tasks) { task in
                                            Button {
                                                Task { await bindTask(task.id) }
                                            } label: {
                                                if task.id == chat.taskID {
                                                    Label(task.title, systemImage: "checkmark")
                                                } else {
                                                    Text(task.title)
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Label(chat.taskID == nil ? "Привязать к задаче" : "Сменить задачу",
                                          systemImage: "checklist")
                                }
                                if chat.taskID != nil {
                                    Button { Task { await bindTask(nil) } } label: {
                                        Label("Отвязать от задачи", systemImage: "xmark.circle")
                                    }
                                }
                            }
                        }
                        Section {
                            Button { enterSelection(selecting: nil) } label: {
                                Label("Выбрать сообщения", systemImage: "checkmark.circle")
                            }
                            // Владелец 25.09.2026: «очистить чат не надо —
                            // надо по сессиям потом полистать». История не
                            // трогается, сбрасывается только память роли.
                            Button { Task { await newSession() } } label: {
                                Label("Новая сессия", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        if session.currentUser?.role == .owner {
                            Section {
                                Button(role: .destructive) {
                                    isClearChatConfirmOpen = true
                                } label: {
                                    Label("Удалить все сообщения", systemImage: "trash")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Ещё")
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if let taskID = chat.taskID {
                NavigationLink(value: AppRoute.taskDetail(taskID: taskID)) {
                    Label("Задача чата", systemImage: "checklist")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(TFSpacing.md)
                }
                .background(Color.tfCard)
            }
        }
        .task {
            // Живые события (22.09.2026): новое сообщение этого чата — сразу
            // перечитываем ленту; «печатает» — ровно по сигналу сервера.
            let chatID = chat.id
            realtime.onEvent = { event in
                switch event {
                case .roleChatMessage(let id) where id == chatID:
                    Task { await refresh() }
                case .roleChatTyping(let id, let userID, let name, let active, let tool) where id == chatID:
                    if active {
                        typists[userID] = name.isEmpty ? "Участник" : name
                        typistTools[userID] = tool
                    } else {
                        typists[userID] = nil
                        typistTools[userID] = nil
                    }
                case .roleChatLive(let id, let userID, let turn) where id == chatID:
                    if let turn {
                        finishingLiveTurnMessageIDs[userID] = nil
                        liveTurns[userID] = turn
                    } else {
                        let finishedStart = liveTurns[userID]?.startedAt
                        finishingLiveTurnMessageIDs[userID] = Set(messages.map(\.id))
                        Task {
                            await refresh()
                            // Последний пакет сервера может ещё лежать в
                            // очереди; готовый ответ покажем после её дренажа.
                            try? await Task.sleep(for: .milliseconds(700))
                            guard liveTurns[userID]?.startedAt == finishedStart else { return }
                            liveTurns[userID] = nil
                            finishingLiveTurnMessageIDs[userID] = nil
                        }
                    }
                default:
                    break
                }
            }
            realtime.onReconnected = {
                // За время разрыва сигнал «закончил» мог потеряться.
                typists = [:]
                typistTools = [:]
                Task {
                    await refresh()
                    await loadLiveTurns()
                }
            }
            realtime.connect()
            // Чат открыт посреди ответа роли — подтягиваем, что уже сделано.
            await loadLiveTurns()
        }
        .onDisappear { realtime.disconnect() }
        .task {
            // Опрос остаётся запасным путём на случай, если сокет молчит.
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { await refresh() }
            }
        }
        .alert("Ошибка чата", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Повторить") { Task { await refresh() } }
            Button("Закрыть", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .sheet(isPresented: $isDetailsPresented) {
            RoleChatDetailsSheet(chat: chat, onChanged: { updated in
                chat = updated
                Task { await refresh() }
            }, onDeleted: { dismiss() })
        }
        .confirmationDialog("Удалить выбранные сообщения?", isPresented: $isDeleteSelectedConfirmOpen,
                            titleVisibility: .visible) {
            Button("Удалить (\(selectedMessageIDs.count))", role: .destructive) {
                Task { await deleteSelected() }
            }
        }
        .confirmationDialog("Удалить все сообщения чата?", isPresented: $isClearChatConfirmOpen,
                            titleVisibility: .visible) {
            Button("Удалить все", role: .destructive) { Task { await clearChat() } }
        }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.item]) { result in
            handleFileImport(result)
        }
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoPickerItem, matching: .images)
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            photoPickerItem = nil
            Task { await uploadPickedPhoto(item) }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraCaptureView(
                onCapture: { image in
                    isCameraPresented = false
                    Task { await uploadCameraPhoto(image) }
                },
                onCancel: { isCameraPresented = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: voice.errorMessage) { _, reason in
            if let reason { errorMessage = reason }
        }
        .onDisappear { voice.cancel(); player.stop() }
        .sheet(item: Binding(
            get: { pendingTaskID.map(RoomTaskRef.init) },
            set: { pendingTaskID = $0?.id }
        )) { ref in
            NavigationStack { TaskFormScreen(taskID: ref.id) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var messageScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // История здесь пока небольшая (на сервере максимум 58
                // сообщений на 28.09). LazyVStack измерял длинные ответы
                // только при прокрутке вверх и сдвигал уже видимую ленту.
                VStack(alignment: .leading, spacing: TFSpacing.md) {
                    if messages.isEmpty {
                        ContentUnavailableView("Пока нет сообщений", systemImage: "bubble.left",
                                               description: Text("Напишите первое сообщение."))
                    }
                    ForEach(visibleMessages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                    // Владелец 26.09.2026: плашки быстрых ответов должны
                    // крепиться к сообщению роли, а не болтаться отдельным
                    // оверлеем над полем ввода — переехали в саму ленту,
                    // сразу под последним сообщением, и скроллятся вместе с
                    // перепиской.
                    if !isSelecting, let replies = lastQuickReplies {
                        quickReplyRow(replies)
                    }
                    ForEach(pendingVoices) { message in
                        VStack(alignment: .trailing, spacing: 4) {
                            // Ещё не отправленное голосовое: имя и иконка
                            // берутся из текущей сессии — сообщения с
                            // сервера для него пока нет.
                            VoiceMessageBubble(
                                message: message,
                                player: player,
                                style: RoleChatVoiceStyle.own,
                                header: AnyView(ownSenderLine)
                            )
                            if sendingVoiceIDs.contains(message.id) { ProgressView("Отправка…") }
                            else if message.transcript != .pending {
                                Button("Повторить отправку") { Task { await sendVoice(message.id) } }
                                    .font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .id(message.id)
                    }
                    ForEach(visibleLiveTurns, id: \.userID) { turn in
                        liveTurnRow(turn)
                    }
                    if !visibleTypists.isEmpty {
                        if chat.kind != "group", let onlyUserID = visibleTypists.keys.first,
                           let tool = typistTools[onlyUserID] {
                            RoleStepLine(name: visibleTypists[onlyUserID] ?? "Роль", tool: tool)
                                .id("typing-line")
                        } else {
                            RoleChatTypingLine(names: visibleTypists.values.sorted())
                                .id("typing-line")
                        }
                    }
                    // Постоянный якорь низа ленты (как в ChatScreen): строки
                    // «печатает» и живого хода появляются и исчезают, и
                    // scrollTo к только что вставленной строке ленивого стека
                    // не срабатывал — живая проверка 27.09.2026 показала, что
                    // и пузырь хода, и «печатает» оставались под полем ввода.
                    // Сам якорь занимает место: scrollTo выравнивает его
                    // нижний край, поэтому отступ СНАРУЖИ LazyVStack не
                    // создавал зазора над композером (проверено на телефоне).
                    Color.clear
                        .frame(height: TFSpacing.xl + TFSpacing.lg)
                        .id("chat-bottom")
                }
                .padding(TFSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            // Начальная позиция — конец истории. Дальше лентой управляет
            // followsChatBottom: общий defaultScrollAnchor(.bottom) ещё и
            // подстраивал её при каждом изменении высоты живого ответа.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .alignment)
            .defaultScrollAnchor(followsChatBottom ? .bottom : nil, for: .sizeChanges)
            .background(Color.tfBackground)
            .hideComposerScrollEdgeEffect()
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY <= 80
            } action: { _, nearBottom in
                chatIsNearBottom = nearBottom
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting {
                    userIsScrollingChat = true
                    followsChatBottom = false
                } else if phase == .idle && userIsScrollingChat {
                    userIsScrollingChat = false
                    followsChatBottom = chatIsNearBottom
                }
            }
            .onChange(of: messages.last?.id) { _, id in
                if id != nil && messages.last?.fromUserID == session.currentUser?.id {
                    followsChatBottom = true
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
        }
    }

    /// Живой ход виден и в группе: у каждого ответа своя подпись роли.
    private var visibleLiveTurns: [RoleChatLiveTurn] {
        return liveTurns.values
            .filter { !$0.items.isEmpty || $0.thinking != nil }
            .sorted { $0.userID < $1.userID }
    }

    private var visibleMessages: [RoleChatMessage] {
        messages.filter { message in
            guard let userID = message.fromUserID,
                  let precedingIDs = finishingLiveTurnMessageIDs[userID] else {
                return true
            }
            return precedingIDs.contains(message.id)
        }
    }

    /// «Печатает» — пока у роли нет ни текста, ни шагов; дальше вместо
    /// точек растёт её живой пузырь.
    private var visibleTypists: [String: String] {
        let live = Set(visibleLiveTurns.map(\.userID))
        return typists.filter { !live.contains($0.key) }
    }

    private func liveTurnRow(_ turn: RoleChatLiveTurn) -> some View {
        RoleLiveTurnBubble(turn: turn, showsName: chat.kind == "group")
            .id(turn.startedAt ?? turn.userID)
    }

    private func loadLiveTurns() async {
        guard let turns = try? await api.roleChatLive(id: chat.id) else { return }
        liveTurns = Dictionary(turns.map { ($0.userID, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// Полоса выбора вместо панели ввода: отметить всё или снять отметки.
    private var selectionBar: some View {
        HStack(spacing: TFSpacing.md) {
            Button(allMessagesSelected ? "Снять выбор" : "Выбрать все") {
                if allMessagesSelected {
                    selectedMessageIDs.removeAll()
                } else {
                    selectedMessageIDs = Set(messages.map(\.id))
                }
            }
            .disabled(messages.isEmpty)
            Spacer(minLength: TFSpacing.md)
            Text("Выбрано: \(selectedMessageIDs.count)")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.md)
    }

    private var allMessagesSelected: Bool {
        !messages.isEmpty && selectedMessageIDs.count == messages.count
    }

    /// «1 участник / 2 участника / 5 участников» — тот же разбор исключений
    /// 11–14, что у `DirectoryPluralize`, но для слова «участник».
    private func participantsWord(_ count: Int) -> String {
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 14 { return "участников" }
        switch count % 10 {
        case 1: return "участник"
        case 2, 3, 4: return "участника"
        default: return "участников"
        }
    }

    private func enterSelection(selecting id: String?) {
        isSelecting = true
        selectedMessageIDs = id.map { [$0] } ?? []
    }

    private func exitSelection() {
        isSelecting = false
        selectedMessageIDs.removeAll()
    }

    private func toggleSelection(_ id: String) {
        if selectedMessageIDs.contains(id) { selectedMessageIDs.remove(id) }
        else { selectedMessageIDs.insert(id) }
    }

    private func deleteSelected() async {
        let ids = selectedMessageIDs
        guard !ids.isEmpty else { return }
        do {
            try await api.deleteRoleChatMessages(chatID: chat.id, ids: Array(ids))
            messages.removeAll { ids.contains($0.id) }
            exitSelection()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Новая сессия (владелец 25.09.2026, docs/ПЛАН Супер Секретарь/):
    /// сбрасывает память роли, история остаётся — сервер сам вставляет
    /// метку-разделитель, которую здесь просто дописываем в ленту.
    private func newSession() async {
        guard let roleID = chat.others(excluding: session.currentUser?.id).first?.id else { return }
        do {
            let marker = try await api.newRoleChatSession(chatID: chat.id, roleID: roleID)
            if !messages.contains(where: { $0.id == marker.id }) { messages.append(marker) }
        } catch { errorMessage = error.localizedDescription }
    }

    private func clearChat() async {
        do {
            try await api.deleteRoleChatMessages(chatID: chat.id)
            messages = []
            exitSelection()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Привязать чат к задаче (`taskID == nil` — отвязать). Сервер отвечает
    /// обновлённым чатом, поэтому локальный состав переписки перечитывать не
    /// нужно — меняется только сама привязка.
    private func bindTask(_ taskID: String?) async {
        do {
            chat = try await api.bindRoleChatToTask(id: chat.id, taskID: taskID)
        } catch { errorMessage = error.localizedDescription }
    }

    @ViewBuilder
    private func messageRow(_ message: RoleChatMessage) -> some View {
        if message.isSessionMarker {
            sessionMarkerRow(message)
        } else if isFlatReply(message) {
            flatReplyRow(message)
        } else {
            messageBubbleRow(message)
        }
    }

    /// Ответ роли в 1:1-чате — плоским текстом по фону, как в окне Claude
    /// Code (владелец 27.09.2026, LOCK-230). Облачка остаются у сообщений
    /// владельца, у голосовых и во всех групповых чатах.
    private func isFlatReply(_ message: RoleChatMessage) -> Bool {
        guard chat.kind != "group", message.fromUserID != session.currentUser?.id else { return false }
        return !(message.attachments?.contains { $0.isVoiceRecording } ?? false)
    }

    private func flatReplyRow(_ message: RoleChatMessage) -> some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            if isSelecting {
                Image(systemName: selectedMessageIDs.contains(message.id)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selectedMessageIDs.contains(message.id)
                                     ? Color.tfRed : Color.tfDim)
            }
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                if let steps = message.steps, steps.hasDetails {
                    RoleLiveItemsList(items: steps.items)
                }
                if let taskID = message.taskID {
                    SecretaryDraftCard(taskID: taskID) { pendingTaskID = taskID }
                } else if !message.text.isEmpty {
                    RoleReplyMarkdown(text: message.text)
                }
                nonVoiceAttachments(message)
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture {
            if !isSelecting { enterSelection(selecting: message.id) }
        }
        .overlay {
            if isSelecting {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSelection(message.id) }
            }
        }
    }

    /// Разделитель «новая сессия» (владелец 25.09.2026) — не пузырь,
    /// центрированная метка, как разрыв даты в iMessage.
    private func sessionMarkerRow(_ message: RoleChatMessage) -> some View {
        HStack {
            Spacer()
            Text("Новая сессия")
                .tfText(.caption)
                .foregroundStyle(Color.tfDim)
                .padding(.horizontal, TFSpacing.md)
                .padding(.vertical, 4)
                .background(Color.tfCard)
                .clipShape(Capsule())
            Spacer()
        }
    }

    private func messageBubbleRow(_ message: RoleChatMessage) -> some View {
        let mine = message.fromUserID == session.currentUser?.id
        let hasAudio = message.attachments?.contains { $0.isVoiceRecording } ?? false
        return HStack(alignment: .top, spacing: TFSpacing.sm) {
            if isSelecting {
                // Отметка выбора слева от сообщения — как в почте и Teams.
                Image(systemName: selectedMessageIDs.contains(message.id)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selectedMessageIDs.contains(message.id)
                                     ? Color.tfRed : Color.tfDim)
                    .padding(.top, TFSpacing.md)
            }
            if mine { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                // Иконка отправителя — вплотную слева от его имени, внутри
                // сообщения сверху (владелец 21.09.2026). Раньше она стояла
                // отдельным столбцом сбоку и у своих сообщений не рисовалась
                // вовсе, хотя иконка есть у всех.
                //
                // У голосового своя подложка — пузырь, поэтому там эта строка
                // уезжает ВНУТРЬ пузыря, а не висит над ним отдельно.
                if !hasAudio {
                    senderLine(message, color: Color.tfSub)
                }
                // Ход, который привёл к ответу (27.09.2026), — как шёл вживую (01.10.2026).
                if let steps = message.steps, steps.hasDetails {
                    RoleLiveItemsList(items: steps.items)
                }
                ForEach(message.attachments?.filter { $0.isVoiceRecording } ?? []) { attachment in
                    RoleChatRemoteVoiceBubble(
                        attachment: attachment,
                        message: message,
                        player: player,
                        api: api,
                        isOwn: mine,
                        header: AnyView(senderLine(message, color: .white.opacity(0.85)))
                    )
                }
                nonVoiceAttachments(message)
                // Карточка задачи (владелец 25.09.2026, этап 2 «Супер
                // Секретаря») — раньше была только у Секретаря
                // (ChatBubble.swift, message.fromUserId == secretaryID),
                // здесь — для любой роли, отправитель не важен.
                if let taskID = message.taskID {
                    SecretaryDraftCard(taskID: taskID) { pendingTaskID = taskID }
                } else if !message.text.isEmpty && !hasAudio {
                    Text(message.text)
                        .foregroundStyle(Color.tfText)
                }
            }
            .padding(hasAudio ? 0 : TFSpacing.md)
            // Подложка одна и та же у своих и у чужих — отличает их только
            // обводка (владелец 21.09.2026: «в моих сообщениях делай такую же
            // самую подложку, как фон делаешь другим»).
            .background(hasAudio ? Color.clear : Color.tfCard)
            .overlay {
                if mine && !hasAudio {
                    RoundedRectangle(cornerRadius: TFRadius.lg)
                        .strokeBorder(Color.tfRed, lineWidth: TFBorder.width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
            if !mine { Spacer(minLength: 48) }
        }
        // Долгое нажатие только ВКЛЮЧАЕТ выбор — с этим сообщением уже
        // отмеченным; дальше отмечаешь тапами (владелец 21.09.2026). В самом
        // режиме выбора тап по сообщению отмечает его, а внутренние кнопки
        // (воспроизведение) перекрыты прозрачным слоем, чтобы не срабатывали.
        .contentShape(Rectangle())
        .onLongPressGesture {
            if !isSelecting { enterSelection(selecting: message.id) }
        }
        .overlay {
            if isSelecting {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSelection(message.id) }
            }
        }
    }

    @ViewBuilder
    private func nonVoiceAttachments(_ message: RoleChatMessage) -> some View {
        ForEach(message.attachments?.filter { !$0.isVoiceRecording } ?? []) { attachment in
            Button {
                Task { await openAttachment(attachment) }
            } label: {
                if attachment.mime?.hasPrefix("image/") == true {
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        ChatAttachmentImage(attachmentId: attachment.id, fileName: attachment.fileName)
                        Text(attachment.fileName)
                            .tfText(.caption)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(1)
                    }
                } else {
                    ChatFileChip(fileName: attachment.fileName)
                }
            }
            .buttonStyle(.plain)
            .disabled(openingAttachmentIDs.contains(attachment.id))
            .overlay {
                if openingAttachmentIDs.contains(attachment.id) { ProgressView() }
            }
            .accessibilityLabel("Открыть \(attachment.fileName)")
        }
    }

    private func openAttachment(_ attachment: ApiChatAttachment) async {
        guard openingAttachmentIDs.insert(attachment.id).inserted else { return }
        defer { openingAttachmentIDs.remove(attachment.id) }
        do {
            let data = try await api.downloadAttachment(id: attachment.id)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("taskflow-chat-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeName = URL(fileURLWithPath: attachment.fileName).lastPathComponent
            let url = directory.appendingPathComponent(safeName.isEmpty ? "attachment" : safeName)
            try data.write(to: url, options: .atomic)
            previewAttachmentURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Иконка отправителя вплотную слева от имени — одна и та же строка и в
    /// текстовом сообщении, и внутри голосового пузыря. Цвет подписи зависит
    /// от подложки: на карточке — приглушённый, на заливке пузыря — белый.
    private func senderLine(_ message: RoleChatMessage, color: Color) -> some View {
        HStack(spacing: TFSpacing.sm) {
            RoleChatAvatar(message: message, size: .sm)
            Text(message.fromUserName ?? "Участник")
                .font(.caption)
                .foregroundStyle(color)
        }
    }

    /// Строка отправителя для голосового, которое ещё не отправлено: на
    /// сервере его пока нет, поэтому имя и иконка берутся из сессии.
    private var ownSenderLine: some View {
        HStack(spacing: TFSpacing.sm) {
            RoleChatAvatar(user: session.currentUser, size: .sm)
            Text(session.currentUser?.name ?? "Вы")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func refresh() async {
        do {
            async let chatRequest = api.roleChat(id: chat.id)
            async let messagesRequest = api.roleChatMessages(id: chat.id)
            let (updatedChat, updatedMessages) = try await (chatRequest, messagesRequest)
            chat = updatedChat
            if updatedMessages.map(\.id) != messages.map(\.id) || updatedMessages.map(\.attachments) != messages.map(\.attachments) {
                messages = updatedMessages
            }
            // Комната открыта — всё в ней прочитано. Бейдж в списке сервер
            // считает от отметки прочтения, а двигает её только этот вызов
            // (LOCK-206): без него счётчик копился навсегда. Счётчика в
            // ответе на один чат нет, поэтому отмечаем при открытии и когда
            // появилось новое последнее сообщение, а не каждые 4 с опроса.
            if let lastID = updatedMessages.last?.id, lastID != markedReadMessageID {
                if (try? await api.markRoleChatRead(id: chat.id)) != nil {
                    markedReadMessageID = lastID
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Быстрые ответы (владелец 25.09.2026, docs/ПЛАН Супер Секретарь/) —
    /// только у самого последнего сообщения, и только если оно не моё:
    /// собственный ответ снимает актуальность предложенных вариантов.
    /// Владелец 26.09.2026: модель иногда даёт 4 — обрезаем до 3, четвёртый
    /// почти никогда не нужен и только загромождает ряд.
    private var lastQuickReplies: [String]? {
        guard let last = messages.last, last.fromUserID != session.currentUser?.id,
              visibleMessages.last?.id == last.id,
              let replies = last.quickReplies, !replies.isEmpty else { return nil }
        return Array(replies.prefix(3))
    }

    /// То же стекло, что у капсулы поля ввода (`voiceCapsuleSurface`) —
    /// владелец 26.09.2026: «почему у композера фон есть, а тут нет» —
    /// плоская заливка читалась плашкой, голый контур без заливки — как
    /// дыра; нужна была именно системная капсула, а не то и не другое.
    private func quickReplyPillStyle<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.body)
            .foregroundStyle(Color.tfText)
            .padding(.horizontal, TFSpacing.md)
            .padding(.vertical, TFSpacing.sm)
            .voiceCapsuleSurface()
            .overlay {
                Capsule().strokeBorder(Color.tfRed.opacity(0.3), lineWidth: TFBorder.width)
            }
    }

    /// Владелец 26.09.2026: плашки крепятся к сообщению роли, в ленте, а не
    /// в отдельном оверлее над композером. Раскладка — переносом строк
    /// (сколько влезает в строку, столько и встаёт, лишнее уходит на
    /// следующую), а не одна горизонтально скроллящаяся строка: владелец
    /// прямо попросил «так и клади, не в столбик» вместо горизонтального
    /// скролла или одного варианта на строку.
    private func quickReplyRow(_ replies: [String]) -> some View {
        FlowLayout(spacing: TFSpacing.sm) {
            ForEach(replies, id: \.self) { reply in
                Button {
                    draft = reply
                    Task { await send() }
                } label: {
                    quickReplyPillStyle { Text(reply) }
                }
                .buttonStyle(.plain)
                .disabled(isSending)
            }
        }
        .padding(.vertical, TFSpacing.xs)
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || !pendingAttachments.isEmpty), !isSending, !isUploadingAttachment else { return }
        isSending = true
        defer { isSending = false }
        do {
            let message = try await api.sendRoleChatMessage(chatID: chat.id, text: text,
                                                            attachmentIDs: pendingAttachments.map(\.id))
            draft = ""
            pendingAttachments = []
            if !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Упоминание через «@»

    /// Набираемое упоминание в конце черновика: «…@Раз» → «Раз». `nil` —
    /// упоминание сейчас не идёт. «@» засчитывается только в начале текста
    /// или после пробела — иначе сработало бы на адресе почты.
    private var mentionQuery: String? {
        guard let at = draft.lastIndex(of: "@") else { return nil }
        if at > draft.startIndex {
            let before = draft[draft.index(before: at)]
            guard before.isWhitespace else { return nil }
        }
        let query = draft[draft.index(after: at)...]
        guard !query.contains(where: { $0.isWhitespace }) else { return nil }
        return String(query)
    }

    /// Справочник для «@» — участники этого чата, кроме меня: сервер
    /// отвечает только ролями, которые есть в чате. Сначала совпадения с
    /// начала имени, потом по вхождению.
    private var mentionCandidates: [RoleChatMember] {
        guard !isSelecting, let query = mentionQuery?.lowercased() else { return [] }
        let others = chat.members.filter { $0.id != session.currentUser?.id }
        guard !query.isEmpty else { return others }
        let matching = others.filter { $0.name.lowercased().contains(query) }
        return matching.filter { $0.name.lowercased().hasPrefix(query) }
            + matching.filter { !$0.name.lowercased().hasPrefix(query) }
    }

    private var mentionSuggestions: some View {
        VStack(spacing: 0) {
            ForEach(mentionCandidates) { member in
                Button { insertMention(member) } label: {
                    HStack(spacing: TFSpacing.md) {
                        RoleMemberAvatar(member: member, size: .md)
                        Text(member.name)
                            .tfText(.body)
                            .foregroundStyle(Color.tfText)
                        Spacer()
                    }
                    .padding(.horizontal, TFSpacing.lg)
                    .padding(.vertical, TFSpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.tfCard)
    }

    /// «…@Раз» → «…@Разработчик » — пробел в конце, чтобы продолжение
    /// набора не слилось с именем и подсказка закрылась.
    private func insertMention(_ member: RoleChatMember) {
        guard let at = draft.lastIndex(of: "@") else { return }
        draft = String(draft[..<at]) + "@\(member.name) "
    }

    private func sendVoicePreview(_ message: VoiceMessage) async -> Bool {
        if !pendingVoices.contains(where: { $0.id == message.id }) { pendingVoices.append(message) }
        await sendVoice(message.id)
        // Запись передана ленте; при сетевой ошибке в ней остаётся повтор.
        return true
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            isUploadingAttachment = true
            defer { isUploadingAttachment = false }
            do {
                let data = try Data(contentsOf: url)
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                let attachment = try await api.uploadRoleChatAttachment(fileName: url.lastPathComponent,
                                                                        data: data, mime: mime)
                pendingAttachments.append(attachment)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    /// Фото из галереи (владелец 26.09.2026, пункт «Фото» в «+»). JPEG —
    /// `PhotosPickerItem` сам даёт исходные данные оригинала любого формата,
    /// но сервер/лента ожидают предсказуемый тип; пережимаем в JPEG 0.9,
    /// как это уже делает камера ниже.
    private func uploadPickedPhoto(_ item: PhotosPickerItem) async {
        isUploadingAttachment = true
        defer { isUploadingAttachment = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
            let attachment = try await api.uploadRoleChatAttachment(fileName: "photo.jpg", data: jpeg, mime: "image/jpeg")
            pendingAttachments.append(attachment)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Снимок камерой (владелец 26.09.2026, пункт «Камера» в «+»).
    private func uploadCameraPhoto(_ image: UIImage) async {
        isUploadingAttachment = true
        defer { isUploadingAttachment = false }
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
        do {
            let attachment = try await api.uploadRoleChatAttachment(fileName: "camera.jpg", data: jpeg, mime: "image/jpeg")
            pendingAttachments.append(attachment)
        } catch { errorMessage = error.localizedDescription }
    }

    private func sendVoice(_ id: UUID) async {
        guard let message = pendingVoices.first(where: { $0.id == id }),
              message.transcript != .pending,
              sendingVoiceIDs.insert(id).inserted else { return }
        defer { sendingVoiceIDs.remove(id) }
        do {
            let attachmentID: String
            if let existing = uploadedVoiceIDs[id] {
                attachmentID = existing
            } else {
                let data = try Data(contentsOf: message.audioURL)
                let attachment = try await api.uploadRoleChatAttachment(
                    fileName: message.audioURL.lastPathComponent, data: data, mime: "application/octet-stream"
                )
                attachmentID = attachment.id
                uploadedVoiceIDs[id] = attachmentID
            }
            let text: String
            if case .ready(let recognized) = message.transcript { text = recognized }
            else { text = "" }
            let sent = try await api.sendRoleChatMessage(chatID: chat.id, text: text, attachmentIDs: [attachmentID])
            if !messages.contains(where: { $0.id == sent.id }) { messages.append(sent) }
            pendingVoices.removeAll { $0.id == id }
            uploadedVoiceIDs.removeValue(forKey: id)
        } catch { errorMessage = error.localizedDescription }
    }
}

/// Выбор задачи для привязки чата (владелец 21.09.2026: «привязка конкретных
/// чатов к проекту и, соответственно, к задаче»). Список берётся из общего
/// `TaskStore` — задачи уже загружены приложением, отдельный запрос не нужен.
/// Название и состав чата: переименование, добавление и исключение участников.
/// Владелец 21.09.2026: «нет возможности вообще как-то понять, кто в этом чате
/// присутствует», «переименовывать не умею», «исключать не умею», «добавлять не
/// умею».
///
/// Построено как остальные экраны приложения: крестик слева — закрыть, «…»
/// справа — действия (добавление участника — ПОДМЕНЮ со списком ролей, как
/// выбор модели в `VoiceModelsScreen`), удаление участника — по зажатию на
/// строке, без значков в списке.
private struct RoleChatDetailsSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let onChanged: (RoleChat) -> Void
    /// Владелец 26.09.2026: «Удалить чат» переехал сюда, в «…» этой же
    /// шторки — раньше жил в общем меню комнаты чата вместе с «Название и
    /// участники», хотя открыть их можно было и тапом по имени. Строка
    /// удаления сама закрывает шторку и вызывает этот колбэк, который
    /// закрывает саму комнату чата (чата больше нет — там нечего показывать).
    let onDeleted: () -> Void
    @State private var chat: RoleChat
    @State private var title: String
    @State private var roles: [RoleProfile] = []
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var isDeleteChatConfirmOpen = false
    private let api = APIClient()

    init(chat: RoleChat, onChanged: @escaping (RoleChat) -> Void, onDeleted: @escaping () -> Void) {
        _chat = State(initialValue: chat)
        _title = State(initialValue: chat.title ?? "")
        self.onChanged = onChanged
        self.onDeleted = onDeleted
    }

    private var isCreator: Bool { chat.createdBy == session.currentUser?.id }
    private var isOwner: Bool { session.currentUser?.role == .owner }

    /// Роли, которых в чате ещё нет: участником может быть только роль с
    /// серверной учёткой — иначе отвечать в чате ей нечем.
    private var availableRoles: [RoleProfile] {
        roles.filter { profile in
            guard let account = profile.accountID, account.hasPrefix("role_") else { return false }
            return !chat.members.contains { $0.id == account }
        }
    }

    private var titleChanged: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines) != (chat.title ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    if isCreator {
                        TextField("Без названия", text: $title)
                            .onSubmit { Task { await saveTitle() } }
                    } else {
                        Text(chat.title?.isEmpty == false ? chat.title! : "Без названия")
                            .foregroundStyle(Color.tfSub)
                    }
                }
                Section("Участники") {
                    ForEach(chat.members) { member in
                        memberRow(member)
                    }
                }
            }
            .navigationTitle("Чат")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Закрыть")
                }
                if isCreator || isOwner {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if isCreator {
                                Menu {
                                    if availableRoles.isEmpty {
                                        Text("Все роли уже в чате")
                                    } else {
                                        ForEach(availableRoles) { profile in
                                            Button {
                                                guard let account = profile.accountID else { return }
                                                Task { await addMember(account) }
                                            } label: {
                                                Text(profile.title)
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Добавить участника", systemImage: "person.badge.plus")
                                }
                            }
                            if isOwner {
                                Button(role: .destructive) {
                                    isDeleteChatConfirmOpen = true
                                } label: {
                                    Label("Удалить чат", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Ещё")
                    }
                }
            }
            .alert("Не удалось изменить чат", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Закрыть", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .confirmationDialog("Удалить чат?", isPresented: $isDeleteChatConfirmOpen,
                                titleVisibility: .visible) {
                Button("Удалить чат", role: .destructive) { Task { await deleteChat() } }
            }
            // Название сохраняется само: отдельной кнопки в шапке нет — там
            // «…». Правка уходит на сервер по клавише «готово» и при закрытии
            // шторки, если текст успел измениться.
            .onDisappear {
                if titleChanged { Task { await saveTitle() } }
            }
            .task {
                roles = (try? await api.roles()) ?? []
            }
        }
    }

    private func memberRow(_ member: RoleChatMember) -> some View {
        HStack(spacing: TFSpacing.md) {
            RoleMemberAvatar(member: member, size: .lg)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).foregroundStyle(Color.tfText)
                if member.id == chat.createdBy {
                    Text("создатель чата").tfText(.meta).foregroundStyle(Color.tfDim)
                }
            }
            Spacer(minLength: TFSpacing.sm)
        }
        // Удаление — по зажатию: всплывает контекстное меню. Никаких значков в
        // строке (владелец 21.09.2026: «по зажатию, чтоб выплывало контекстное
        // окно… а не крестики, какие-то иконки рисовать»). Свайп оставлен
        // вторым, невидимым путём — он ничего не рисует.
        .contentShape(Rectangle())
        .contextMenu {
            if isCreator, member.id != session.currentUser?.id {
                Button(role: .destructive) {
                    Task { await removeMember(member) }
                } label: {
                    Label("Удалить из чата", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .trailing) {
            if isCreator, member.id != session.currentUser?.id {
                Button(role: .destructive) {
                    Task { await removeMember(member) }
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
    }

    /// Сервер отвечает обновлённым чатом — им и обновляем экран, и отдаём
    /// наверх, в комнату: переименование и состав видны сразу.
    private func apply(_ updated: RoleChat) {
        chat = updated
        title = updated.title ?? ""
        onChanged(updated)
    }

    private func saveTitle() async {
        guard titleChanged else { return }
        isBusy = true
        defer { isBusy = false }
        do { apply(try await api.renameRoleChat(id: chat.id, title: title)) }
        catch { errorMessage = error.localizedDescription }
    }

    private func deleteChat() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.deleteRoleChat(id: chat.id)
            dismiss()
            onDeleted()
        } catch { errorMessage = error.localizedDescription }
    }

    private func addMember(_ memberID: String) async {
        isBusy = true
        defer { isBusy = false }
        do { apply(try await api.addRoleChatMember(chatID: chat.id, memberID: memberID)) }
        catch { errorMessage = error.localizedDescription }
    }

    private func removeMember(_ member: RoleChatMember) async {
        isBusy = true
        defer { isBusy = false }
        do { apply(try await api.removeRoleChatMember(chatID: chat.id, memberID: member.id)) }
        catch { errorMessage = error.localizedDescription }
    }
}

/// Оформление голосового пузыря в чате. Своё сообщение — красная обводка без
/// заливки, ровно как у своего текстового: вид отправленного сообщения не
/// зависит от того, как его отправили (владелец 21.09.2026).
///
/// Цвета задаются ЗДЕСЬ, а не в `VoiceMessageBubble`: тот файл собирается
/// ещё и в отдельное приложение-прототип `VoiceMessageLab`, которому
/// дизайн-система TaskFlow недоступна.
enum RoleChatVoiceStyle {
    /// Своё голосовое — та же подложка, что у остальных, и красная обводка
    /// поверх. Отличает свои сообщения только обводка, как и у текстовых.
    /// Кнопка воспроизведения — один красный треугольник, без круга и без
    /// обводки (владелец 21.09.2026).
    ///
    /// Отступ и радиус — как у текстового сообщения в чате. С числами
    /// прототипа (14 и 22) иконка отправителя и текст расшифровки вставали
    /// на других вертикалях, чем в текстовом: владелец 21.09.2026 —
    /// «интервалы абсолютно одинаковые, симметрия».
    static let own = VoiceBubbleStyle(
        fill: Color.tfCard,
        stroke: Color.tfRed,
        playTint: Color.tfRed,
        playDisc: .none,
        padding: TFSpacing.md,
        cornerRadius: TFRadius.lg
    )

    /// Чужое голосовое: пузырь прототипа, но с теми же отступами, что у
    /// текстового сообщения — по той же причине.
    static let others = VoiceBubbleStyle(
        padding: TFSpacing.md,
        cornerRadius: TFRadius.lg
    )
}

private struct RoleChatRemoteVoiceBubble: View {
    let attachment: ApiChatAttachment
    /// Сообщение-владелец вложения: из него берётся расшифровка и строка
    /// отправителя (иконка + имя), которая у голосового стоит ВНУТРИ пузыря.
    let message: RoleChatMessage
    let player: VoicePlayer
    let api: APIClient
    /// Своё ли сообщение: голосовое приходит из истории теми же вложениями,
    /// поэтому сторону нужно передать явно — иначе своё голосовое нарисовалось
    /// бы чужой карточкой.
    let isOwn: Bool
    let header: AnyView
    @State private var localMessage: VoiceMessage?
    @State private var failed = false

    var body: some View {
        Group {
            if let localMessage {
                // Своё голосовое — та же подложка, что у остальных, плюс
                // красная обводка; чужое — прежний пузырь прототипа
                // (владелец 21.09.2026: вид не зависит от способа отправки).
                VoiceMessageBubble(
                    message: localMessage,
                    player: player,
                    style: isOwn ? RoleChatVoiceStyle.own : RoleChatVoiceStyle.others,
                    header: header
                )
            } else if failed {
                Label("Не удалось загрузить аудио", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView("Загрузка аудио…")
            }
        }
        .task(id: attachment.id) {
            do {
                let data = try await api.downloadRaw(path: "/attachments/\(attachment.id)")
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("role-chat-\(attachment.id).m4a")
                try data.write(to: url, options: .atomic)
                let duration = try AVAudioPlayer(contentsOf: url).duration
                let transcript = message.text
                localMessage = VoiceMessage(
                    audioURL: url,
                    duration: duration,
                    transcript: transcript.isEmpty ? .failed : .ready(transcript)
                )
            } catch { failed = true }
        }
    }
}

private struct RoleChatAvatar: View {
    let initials: String
    let tint: Color
    let avatarURL: String?
    let userID: String?
    /// В строке сообщения иконка стоит рядом с именем — там нужен мелкий
    /// размер (`.sm`), а не полноразмерный аватар отдельным столбцом.
    var size: TFAvatar.Size = .md

    /// Иконка автора сообщения с сервера.
    init(message: RoleChatMessage, size: TFAvatar.Size = .md) {
        self.initials = message.fromUserInitials ?? String((message.fromUserName ?? "?").prefix(1))
        self.tint = Color(hex: message.fromUserColor ?? TFHexDefault.unassigned)
        self.avatarURL = message.fromUserAvatarURL
        self.userID = message.fromUserID
        self.size = size
    }

    /// Иконка текущего пользователя — для голосового, которое ещё не ушло на
    /// сервер и потому не имеет строки сообщения.
    init(user: ApiUser?, size: TFAvatar.Size = .md) {
        let name = user?.name ?? "?"
        self.initials = user?.initials ?? String(name.prefix(1))
        self.tint = Color(hex: user?.avatarColor ?? TFHexDefault.unassigned)
        self.avatarURL = user?.avatarUrl
        self.userID = user?.id
        self.size = size
    }

    var body: some View {
        if let path = avatarURL,
           let url = URL(string: APIClient.baseURL.absoluteString + path) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    TFAvatar(size: size, image: image, initials: initials, tint: tint, userID: userID)
                } else {
                    TFAvatar(size: size, initials: initials, tint: tint, userID: userID)
                }
            }
        } else {
            TFAvatar(size: size, initials: initials, tint: tint, userID: userID)
        }
    }
}
