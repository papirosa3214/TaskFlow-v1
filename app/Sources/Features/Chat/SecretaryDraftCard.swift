import SwiftUI

/// Карточка постановки в ответе Секретаря — вместо невзрачной ссылки
/// (владелец 23.09.2026): «прям карточка задачи аккуратно оформленная…
/// чтобы я сразу сориентировался, канает, не канает», и «сразу крестик да
/// галочка… не проваливаться в карточку задачи».
///
/// Что видно: название и общее состояние, свои шаги родителя, дочерние с
/// исполнителем, числом шагов и состоянием каждой. Пока это черновик —
/// «Запустить» и «Удалить» прямо здесь. Флаг готовности как слово владельцу
/// не показывается: для него есть «черновик» и «запущено».
struct SecretaryDraftCard: View {
    let taskID: String
    /// Открыть саму задачу — по нажатию на название (прежнее поведение ссылки).
    let onOpen: () -> Void

    @Environment(SessionStore.self) private var session
    @State private var parent: ApiTask?
    @State private var children: [ApiTask] = []
    @State private var failed = false
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var isDeleteConfirmOpen = false
    @State private var isDeleted = false
    /// Кэш названий ролей (LOCK-205): ключ → русская подпись с сервера.
    /// `ApiTask` присылает `dispatchedRole` как сырой ключ, без перевода;
    /// прежний ручной словарь не знал новых ролей. Загружаем лениво при
    /// показе карточки — карточки нечастые, лишний `GET /api/roles?all=1`
    /// на каждое появление не критичен.
    @State private var roleTitleByKey: [String: String] = [:]
    /// Шаги/дочерние свёрнуты по умолчанию (владелец 25.09.2026): «сразу же
    /// высвечивались кто исполнитель, суть задачи» — заголовок и так их
    /// показывает, разворачивать нужно только ради списка шагов.
    @State private var isExpanded = false

    private let api = APIClient()

    var body: some View {
        Group {
            if isDeleted {
                Text("Постановка удалена")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                    .padding(.horizontal, 4)
            } else if let parent {
                card(parent)
            } else if failed {
                Button(action: onOpen) {
                    Text("Открыть задачу").tfText(.meta).foregroundStyle(Color.tfSub).underline()
                }
                .buttonStyle(.plain)
            } else {
                ProgressView().padding(TFSpacing.md)
            }
        }
        .task(id: taskID) {
            async let titles: Void = loadRoleTitles()
            await load()
            await titles
        }
        .confirmationDialog("Удалить постановку целиком?", isPresented: $isDeleteConfirmOpen,
                            titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await deleteTree() } }
        } message: {
            Text("Задача и все её дочерние удалятся без возможности вернуть.")
        }
    }

    // MARK: - Вид

    private func card(_ parent: ApiTask) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                Button(action: onOpen) {
                    Text(parent.title)
                        .tfText(.row)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tfText)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                Spacer(minLength: TFSpacing.sm)
                let overall = overallState
                TFPill(overall.text, color: overall.color)
            }

            // Суть в одной строке, видна и свёрнутой: исполнитель + счёт
            // шагов/подзадач (владелец 25.09.2026).
            Text(summaryLine(parent))
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)

            let hasDetails = !parent.subtasks.isEmpty || !children.isEmpty
            if hasDetails {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Свернуть шаги" : "Показать шаги")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                if !parent.subtasks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(parent.subtasks) { step in
                            stepRow(step)
                        }
                    }
                }

                if !children.isEmpty {
                    VStack(alignment: .leading, spacing: TFSpacing.sm) {
                        ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                            childRow(child, number: index + 1)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            if let errorText {
                Text(errorText).tfText(.meta).foregroundStyle(Color.tfRed)
            }

            if canDecide {
                HStack(spacing: TFSpacing.sm) {
                    TFButton("Запустить", icon: "checkmark", variant: .primary, isEnabled: !isBusy) {
                        Task { await start() }
                    }
                    TFButton("Удалить", icon: "xmark", variant: .outline, isEnabled: !isBusy) {
                        isDeleteConfirmOpen = true
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(TFSpacing.md)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
    }

    private func stepRow(_ step: ApiSubtask) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(step.done ? Color.tfGreen : Color.tfDim)
            Text(step.title)
                .tfText(.meta)
                .foregroundStyle(step.done ? Color.tfSub : Color.tfText)
        }
    }

    private func childRow(_ child: ApiTask, number: Int) -> some View {
        let state = childState(child)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                Text("\(number). \(child.title)")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfText)
                Spacer(minLength: TFSpacing.sm)
                Text(state.text)
                    .tfText(.caption)
                    .foregroundStyle(state.color)
            }
            Text(childSubtitle(child))
                .tfText(.caption)
                .foregroundStyle(Color.tfSub)
        }
    }

    // MARK: - Состояния

    private var ownerID: String? { session.currentUser?.id }
    private var isOwner: Bool { session.currentUser?.role == .owner }

    /// Карточки, которые исполняют агенты: дочерние, а без них — сама задача.
    /// Личные (исполнитель — владелец) сюда не входят.
    private var executable: [ApiTask] {
        let cards = children.isEmpty ? (parent.map { [$0] } ?? []) : children
        return cards.filter { $0.status == .active && $0.assigneeId != ownerID }
    }

    /// Решать есть что, пока хоть одна исполняемая карточка ещё не запущена.
    private var canDecide: Bool {
        isOwner && executable.contains { !$0.readyForPickup }
    }

    private var overallState: (text: String, color: Color) {
        let all = children.isEmpty ? (parent.map { [$0] } ?? []) : children
        if !all.isEmpty && all.allSatisfy({ $0.status == .completed }) { return ("Готово", .tfGreen) }
        if executable.contains(where: { !$0.readyForPickup }) { return ("Черновик", .tfSub) }
        if executable.isEmpty { return ("Ваше дело", .tfSub) }
        return ("Запущено", .tfBlue)
    }

    private func childState(_ child: ApiTask) -> (text: String, color: Color) {
        if child.status == .completed { return ("готово", .tfGreen) }
        switch child.agentState {
        case .inProgress: return ("в работе", .tfBlue)
        case .review: return ("на проверке", .tfBlue)
        case .blocked: return ("заблокирована", .orange)
        case .todo: return ("в очереди", .tfSub)
        case nil: break
        }
        if child.assigneeId == ownerID { return ("делаете вы", .tfSub) }
        if !child.readyForPickup { return ("черновик", .tfSub) }
        if child.description?.contains("⛓ ОЧЕРЕДЬ:") == true && child.dispatchedRole == nil {
            return ("ждёт очереди", .tfSub)
        }
        return ("запущена", .tfSub)
    }

    private func childSubtitle(_ child: ApiTask) -> String {
        var parts: [String] = []
        if child.assigneeId == ownerID {
            parts.append("Вы")
        } else if let role = child.dispatchedRole ?? child.ownerSelectedRole ?? child.machineSelectedRole {
            // Серверный кэш. Если роль не пришла (новая, или сеть легла) —
            // показываем ключ как есть: пользователь увидит «role_builder»
            // вместо «Разработчик», но не провал.
            parts.append(roleTitleByKey[role] ?? role)
        } else {
            parts.append("исполнитель подберётся")
        }
        let steps = child.subtasks.count
        if steps > 0 {
            let done = child.subtasks.filter(\.done).count
            parts.append(done > 0 ? "шаги \(done) из \(steps)" : "\(steps) \(Self.stepsWord(steps))")
        }
        return parts.joined(separator: " · ")
    }

    /// Строка «сути» под заголовком — исполнитель + счёт, одна строка,
    /// видна и в свёрнутом виде.
    private func summaryLine(_ parent: ApiTask) -> String {
        if !children.isEmpty {
            let done = children.filter { $0.status == .completed }.count
            var text = "\(children.count) \(Self.tasksWord(children.count))"
            if done > 0 { text += " · готово \(done) из \(children.count)" }
            return text
        }
        var parts: [String] = []
        if parent.assigneeId == ownerID {
            parts.append("Вы")
        } else if let role = parent.dispatchedRole ?? parent.ownerSelectedRole ?? parent.machineSelectedRole {
            parts.append(roleTitleByKey[role] ?? role)
        } else {
            parts.append("исполнитель подберётся")
        }
        let steps = parent.subtasks.count
        if steps > 0 {
            let done = parent.subtasks.filter(\.done).count
            parts.append(done > 0 ? "шаги \(done) из \(steps)" : "\(steps) \(Self.stepsWord(steps))")
        }
        return parts.joined(separator: " · ")
    }

    private static func tasksWord(_ n: Int) -> String {
        let mod100 = n % 100, mod10 = n % 10
        if (11...14).contains(mod100) { return "задач" }
        if mod10 == 1 { return "задача" }
        if (2...4).contains(mod10) { return "задачи" }
        return "задач"
    }

    private static func stepsWord(_ n: Int) -> String {
        let mod100 = n % 100, mod10 = n % 10
        if (11...14).contains(mod100) { return "шагов" }
        if mod10 == 1 { return "шаг" }
        if (2...4).contains(mod10) { return "шага" }
        return "шагов"
    }

    // MARK: - Данные и действия

    private func load() async {
        do {
            let loaded = try await api.task(id: taskID)
            // В ответе задачи дочерние приходят без своих шагов — дочитываем
            // каждую, их немного (Секретарь режет до десяти).
            let ids = (loaded.children ?? []).map(\.id)
            var detailed: [String: ApiTask] = [:]
            await withTaskGroup(of: (String, ApiTask?).self) { group in
                for id in ids {
                    group.addTask { (id, try? await APIClient().task(id: id)) }
                }
                for await (id, task) in group { detailed[id] = task }
            }
            parent = loaded
            children = ids.compactMap { id in detailed[id] ?? loaded.children?.first { $0.id == id } }
            failed = false
        } catch {
            failed = parent == nil
        }
    }

    /// Подписи ролей с сервера (`GET /api/roles?all=1`). Падаем молча: без
    /// кэша карточка покажет ключи ролей как есть, и это лучше, чем баннер
    /// ошибки поверх ответа Секретаря.
    private func loadRoleTitles() async {
        do {
            let all = try await api.roles(all: true)
            roleTitleByKey = Dictionary(uniqueKeysWithValues: all.map { ($0.role, $0.title) })
        } catch {
            roleTitleByKey = [:]
        }
    }

    private func start() async {
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            try await api.startDraft(taskID: taskID)
            await load()
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Не удалось запустить"
        }
    }

    /// Сначала дочерние, потом родитель: сервер удаляет карточку поодиночке,
    /// и так не остаются дочерние без родителя, если что-то сорвётся посреди.
    private func deleteTree() async {
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            for child in children { try await api.deleteTask(id: child.id) }
            try await api.deleteTask(id: taskID)
            isDeleted = true
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Не удалось удалить"
            await load()
        }
    }
}
