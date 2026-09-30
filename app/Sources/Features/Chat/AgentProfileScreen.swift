import SwiftUI

/// Профиль роли (LOCK-183): сначала сотрудник, потом его конфигурация.
/// Открывается тапом по строке «Команды», а не раскрытием тяжёлой карточки.
///
/// Здесь только то, что относится к роли: чем занята, модель,
/// инструкции, инструменты, навыки, права и короткий итог работы. Pi,
/// провайдеры, OAuth и credentials не показываются.
///
/// Визуально это тот же образец, что и «Модели и голоса» — эталон владельца
/// (20.09.2026): карточки `TFCard` со строками `VoiceModelRow` (иконка,
/// заголовок, подпись, значение, точка-статус), разделители `TFDivider`,
/// раскрытие прямо в строке. Своей вёрстки строк здесь нет.
struct AgentProfileScreen: View {
    let roleID: String

    @Environment(TaskStore.self) private var taskStore
    @Environment(SessionStore.self) private var session
    @State private var viewModel = AgentsViewModel()
    @State private var sheetTaskID: String?
    /// Развёрнута ли инструкция роли (тап по строке «Инструкции»).
    @State private var isInstructionsExpanded = false
    /// Развёрнут ли список инструментов MCP (тап по строке «Инструменты»).
    @State private var isToolsExpanded = false

    private var profile: RoleProfile? { viewModel.profile(for: roleID) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.lg) {
                TFErrorBanner(viewModel.listErrorMessage.map { _ in "Не удалось загрузить профиль роли" })

                if let profile {
                    header(profile)
                    sections(profile)
                } else if viewModel.isLoading {
                    TFLoading(.block)
                }
            }
            .padding(.vertical, TFSpacing.lg)
        }
        .background(Color.tfBackground)
        .tfNativeHeader(profile?.title ?? "Профиль")
        .task {
            viewModel.configure(currentUser: session.currentUser)
            await viewModel.load()
            await viewModel.loadModelsIfNeeded()
        }
        .sheet(item: Binding(
            get: { sheetTaskID.map(TaskRef.init) },
            set: { sheetTaskID = $0?.id }
        )) { ref in
            NavigationStack { TaskFormScreen(taskID: ref.id) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private struct TaskRef: Identifiable { let id: String }

    // MARK: - Шапка профиля

    /// Кто это: аватар, имя роли, её назначение. Шапка — не часть
    /// эталонных строк «Моделей и голосов», а идентичность сотрудника; владелец
    /// 20.09.2026 прямо просил её вернуть. Статус тут не дублируем — он в
    /// строке «Сейчас».
    private func header(_ profile: RoleProfile) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            HStack(spacing: TFSpacing.md) {
                RoleAvatarView(initials: initials(profile.title), tint: roleAccentColor(profile.role), size: 48, role: profile.role)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.title)
                        .tfText(.title)
                        .foregroundStyle(Color.tfText)
                    Text(roleSubtitle(profile.role))
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private func initials(_ title: String) -> String {
        let parts = title.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    // MARK: - Секции

    @ViewBuilder
    private func sections(_ profile: RoleProfile) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.lg) {
            section(title: "Роль") {
                currentRow(profile)
                rowDivider
                modelRow(profile)
                rowDivider
                instructionsRow(profile)
                if isInstructionsExpanded && !profile.prompt.isEmpty {
                    instructionsBlock(profile.prompt)
                }
            }

            section(title: "Возможности") {
                toolsRow(profile)
                if isToolsExpanded && !profile.tools.isEmpty {
                    toolsBlock(profile.tools)
                }
                rowDivider
                infoRow(
                    icon: "graduationcap",
                    title: "Навыки",
                    subtitle: joined(profile.skills.map(\.name), empty: "не установлены")
                )
                if let permissions = profile.permissions, !permissions.isEmpty {
                    rowDivider
                    infoRow(icon: "lock.shield", title: "Права", subtitle: permissions)
                }
                rowDivider
                infoRow(
                    icon: "clock.arrow.circlepath",
                    title: "Последняя работа",
                    subtitle: lastWorkText(profile)
                )
                if profile.hasProblems {
                    rowDivider
                    infoRow(
                        icon: "exclamationmark.triangle",
                        title: "Проблемы",
                        subtitle: profile.problems.joined(separator: " · ")
                    )
                }
            }
        }
    }

    /// Карточка раздела ровно как в «Моделях и голосах»: caps-заголовок,
    /// `TFCard(padding: 0)` и строки с разделителями.
    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            SettingsCapsLabel(title)
            TFCard(padding: 0) {
                VStack(spacing: 0) { content() }
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private var rowDivider: some View {
        TFDivider(inset: rowDividerInset).padding(.trailing, rowDividerInset)
    }

    private var rowDividerInset: CGFloat { TFSpacing.lg + 32 + TFSpacing.md }

    // MARK: - Строки

    /// «Сейчас» — статус роли СЛОВОМ. Владелец 20.09.2026: одна роль может
    /// вести несколько задач параллельно (технического ограничения нет),
    /// поэтому «Роль свободна» неверно; показываем статус. Идущая задача, если
    /// сервер её отдал, остаётся доступной тапом.
    @ViewBuilder
    private func currentRow(_ profile: RoleProfile) -> some View {
        let status = roleStatusLabel(profile.status)
        if let task = profile.currentTask {
            infoRow(
                icon: "bolt",
                title: "Сейчас",
                subtitle: status,
                value: task.title,
                action: { sheetTaskID = task.id }
            )
        } else {
            infoRow(icon: "bolt", title: "Сейчас", subtitle: status)
        }
    }

    /// Строка «Модель». Меняет только владелец (сервер всё равно вернёт 403).
    /// Меню — только ДОСТУПНЫЕ модели, по провайдеру; выбор применяется сразу.
    ///
    /// РЕЗЕРВНЫЕ МОДЕЛИ УДАЛЕНЫ (20.09.2026) — не по прихоти, а потому что они
    /// НИГДЕ не использовались и ни на что не влияли: эскалацию при сбое делает
    /// глобальная лесенка (`model_ladder` / `nextModelForFailure` в
    /// `agent-state.ts`), а роль-специфичную цепочку primary+fallbacks читала
    /// единственная функция `nextModelForProfile` в `roleRouting.ts`, и она не
    /// вызывается нигде. В запуск Pi уходит только основная модель
    /// (`PiRuntimeAdapter`: `routing.models[role]`). Возвращать — только вместе
    /// с подключением резервных к реальной эскалации (серверная работа).
    @ViewBuilder
    private func modelRow(_ profile: RoleProfile) -> some View {
        let subtitle = "Основная модель роли"
        let value = profile.model ?? "не задана"
        if canEdit {
            Menu {
                ForEach(modelProviderGroups) { group in
                    Section(modelProviderTitle(group.provider)) {
                        ForEach(group.models) { model in
                            Button {
                                setModel(model.id, role: profile.role)
                            } label: {
                                if model.id == profile.model {
                                    Label(model.displayName, systemImage: "checkmark")
                                } else {
                                    Text(model.displayName)
                                }
                            }
                        }
                    }
                }
            } label: {
                VoiceModelRow(icon: "cpu", title: "Модель", subtitle: subtitle, value: value)
            }
            .buttonStyle(.plain)
            .tint(Color.tfSub)
        } else {
            infoRow(icon: "cpu", title: "Модель", subtitle: subtitle, value: value)
        }
    }

    /// Строка «Инструкции». Тап раскрывает ПОЛНЫЙ текст промпта роли — владелец
    /// 20.09.2026: «у агента просто символы и всё, а что там за символы —
    /// непонятно». Счётчик символов не показываем: в эталоне его нет, там сам
    /// текст. Текст read-only: источник правды — файл на сервере.
    @ViewBuilder
    private func instructionsRow(_ profile: RoleProfile) -> some View {
        infoRow(
            icon: "text.alignleft",
            title: "Инструкции",
            subtitle: profile.prompt.isEmpty ? "не заданы" : "Системный промпт роли",
            action: profile.prompt.isEmpty ? nil : {
                withAnimation(.easeInOut(duration: TFDuration.fast)) {
                    isInstructionsExpanded.toggle()
                }
            }
        )
    }

    @ViewBuilder
    private func infoRow(
        icon: String,
        title: String,
        subtitle: String,
        value: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        let row = VoiceModelRow(icon: icon, title: title, subtitle: subtitle, value: value)
        if let action {
            Button(action: action) { row }.buttonStyle(TFTapRowStyle())
        } else {
            row
        }
    }

    /// Полный текст инструкции роли — читаемый блок под раскрытой строкой.
    @ViewBuilder
    private func instructionsBlock(_ prompt: String) -> some View {
        Text(prompt)
            .tfText(.action)
            .foregroundStyle(Color.tfSub)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TFSpacing.lg)
            .padding(.bottom, TFSpacing.md)
    }

    /// Строка «Инструменты» — как раздел MCP: имя сервера, статус-точка,
    /// тап раскрывает русский список. Владелец 20.09.2026: сырые английские
    /// имена (`taskflow_create_task`) на экране не нужны.
    @ViewBuilder
    private func toolsRow(_ profile: RoleProfile) -> some View {
        let connected = !profile.tools.isEmpty
        infoRow(
            icon: "puzzlepiece.extension",
            title: "Инструменты",
            subtitle: "TaskFlow MCP",
            value: connected ? "подключён" : "не подключён",
            action: connected ? {
                withAnimation(.easeInOut(duration: TFDuration.fast)) {
                    isToolsExpanded.toggle()
                }
            } : nil
        )
    }

    /// Список инструментов MCP по-русски: «Создать задачу — …».
    @ViewBuilder
    private func toolsBlock(_ tools: [String]) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            ForEach(tools, id: \.self) { tool in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.toolPresentation[tool]?.name ?? Self.humanizedTool(tool))
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                    if let text = Self.toolPresentation[tool]?.description {
                        Text(text)
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.bottom, TFSpacing.md)
    }

    private static func humanizedTool(_ tool: String) -> String {
        tool.replacingOccurrences(of: "taskflow_", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }

    /// Русские подписи инструментов MCP. Источник смысла — `mcp_server.py`
    /// (`TOOLS[...].description`); здесь — короткая презентационная карта для
    /// экрана (как `roleSubtitle` для ролей). Добавили инструмент на сервере —
    /// допиши строку и сюда.
    private static let toolPresentation: [String: (name: String, description: String)] = [
        "taskflow_my_tasks": ("Мои задачи", "Задачи, назначенные на роль: свободные, в работе, на проверке, заблокированные."),
        "taskflow_task": ("Карточка задачи", "Задача целиком: описание, шаги, лента комментариев и событий."),
        "taskflow_claim": ("Взять в работу", "Забрать задачу себе. Дальше аренду нужно продлевать."),
        "taskflow_heartbeat": ("Продлить аренду", "Сигнал, что работа идёт: без него задача считается брошенной."),
        "taskflow_state": ("Сменить состояние", "Сдать на проверку, заблокировать или вернуться в работу. Нужен комментарий."),
        "taskflow_review": ("Вердикт проверки", "Одобрить результат или вернуть задачу в работу."),
        "taskflow_comment": ("Комментарий", "Написать в ленту задачи; можно приложить файлы — владелец увидит их в карточке."),
        "taskflow_subtask_done": ("Закрыть шаг", "Отметить шаг сделанным с коротким итогом."),
        "taskflow_subtask_add": ("Добавить шаг", "Вставить шаг в задачу — в конец или сразу за указанным."),
        "taskflow_rules": ("Правила учёта", "Правила ведения задач, как их требует сервер."),
        "taskflow_runtime": ("Рантайм", "Какие провайдеры и модели реально доступны сейчас."),
        "taskflow_status": ("Состояние системы", "Что происходит: служба, кто что делает, что брошено, что ждёт проверки."),
        "taskflow_agents": ("Команда", "Кто есть в команде и кто на связи."),
        "taskflow_chat_send": ("Сообщение в чат", "Написать в канал координации с указанием адресата."),
        "taskflow_chat_typing": ("«Печатает…»", "Показать, что ответ готовится, а не тишина."),
        "taskflow_chat_read": ("История чата", "Свежие сообщения канала координации."),
        "taskflow_subtask_work": ("Работа над шагом", "Отметить, что взялся за шаг, упёрся или закончил."),
        "taskflow_projects": ("Проекты", "Список проектов и их идентификаторов."),
        "taskflow_project_tasks": ("Задачи проекта", "Все задачи проекта, отсортированные по сроку."),
        "taskflow_create_project": ("Создать проект", "Завести проект под задачу вместе с папкой документации."),
        "taskflow_create_task": ("Создать задачу", "Завести задачу, при желании со списком шагов."),
        "taskflow_suggest_subtasks": ("Разбить на шаги", "Умная разбивка задачи на шаги той же AI-моделью, что у владельца."),
        "taskflow_structure_dictation": ("Причесать текст", "Из сырого или надиктованного текста собрать чистую задачу: заголовок, описание, шаги, срок."),
        "taskflow_docs": ("Документация", "Папка документации проекта и всё, что в ней лежит."),
        "taskflow_doc_read": ("Прочитать заметку", "Прочитать документ проекта целиком."),
        "taskflow_doc_write": ("Записать в документацию", "Создать или дополнить документ проекта."),
        "taskflow_kb_search": ("Поиск по документации", "Найти по смыслу в документации всех проектов."),
    ]

    // MARK: - Данные строк

    private var canEdit: Bool { viewModel.isOwner }

    private func joined(_ items: [String], empty: String) -> String {
        items.isEmpty ? empty : items.joined(separator: " · ")
    }

    /// «12 задач · 10 завершено» — по задачам, где исполнитель = учётка роли.
    /// Считаем на клиенте из общего стора (отдельного поля сервер не отдаёт).
    private func lastWorkText(_ profile: RoleProfile) -> String {
        guard let accountID = profile.accountID else { return "нет данных" }
        let tasks = taskStore.tasks.filter { $0.assigneeId == accountID }
        guard !tasks.isEmpty else { return "пока ничего" }
        let completed = tasks.count { $0.status == .completed }
        return "\(tasks.count) \(Self.plural(tasks.count, "задача", "задачи", "задач")) · \(completed) завершено"
    }

    private static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod100 = n % 100
        if mod100 >= 11 && mod100 <= 14 { return many }
        switch n % 10 {
        case 1: return one
        case 2, 3, 4: return few
        default: return many
        }
    }

    private func setModel(_ id: String, role: String) {
        Task {
            _ = await viewModel.updateModelPolicy(role: role, primary: id)
        }
    }

    /// Доступные модели, сгруппированные по провайдеру (порядок — как в каталоге).
    private var modelProviderGroups: [ModelGroup] {
        var order: [String] = []
        var byProvider: [String: [RuntimeModel]] = [:]
        for model in viewModel.models where model.available {
            if byProvider[model.provider] == nil { order.append(model.provider) }
            if byProvider[model.provider, default: []].contains(where: { $0.id == model.id }) {
                continue
            }
            byProvider[model.provider, default: []].append(model)
        }
        return order.map { ModelGroup(provider: $0, models: byProvider[$0] ?? []) }
    }

    /// Человеческие подписи провайдеров; неизвестный — как есть.
    private func modelProviderTitle(_ provider: String) -> String {
        switch provider {
        case "anthropic": return "Anthropic"
        case "openai", "openai-codex": return "OpenAI"
        case "minimax", "minimax-cn": return "MiniMax"
        case "opencode": return "OpenCode"
        case "opencode-go": return "OpenCode Go"
        case "google", "google-vertex": return "Google"
        case "ollama": return "Ollama (на сервере)"
        default: return provider
        }
    }
}

/// Группа доступных моделей одного провайдера для меню выбора «Модель».
private struct ModelGroup: Identifiable {
    let provider: String
    let models: [RuntimeModel]
    var id: String { provider }
}
