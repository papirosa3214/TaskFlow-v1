import SwiftUI

// «Проекты» — spec/SCREENS-2.md §7, `/projects`. Сверено построчно с живым
// `src/screens/ProjectsScreen.tsx` 31.08.2026 (ARCHITECTURE.md правило 3 —
// расходится спека с кодом, верю коду). Правка 03.09.2026 по прямой просьбе
// владельца — см. пункты 1 и 2 ниже.
//
// 1. Шапка — `.tfNativeHeader` (TFNativeHeader.swift), не самодельный
//    `.toolbarBackground(.ultraThinMaterial, ...)`. Старая ручная связка
//    конфликтовала с системным scroll edge effect (iOS 26 рисует блюр по
//    скроллу сама, без единой строчки кода — см. комментарий в
//    TFNativeHeader.swift) и давала серую плашку при прокрутке вверх.
// 2. Управление списком — нативная пара `Menu` в toolbar: фильтр и «…».
//    Создание, поиск и выбор проекта для изменения не занимают отдельные
//    кнопки и остаются доступны без скрытых жестов.
// 3. Пустое состояние — просто строка текста (не `TFEmptyState` с иконкой,
//    как у Меток) — 1:1 с кодом, текст обновлён под новую кнопку.
struct ProjectsScreen: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(TaskStore.self) private var taskStore

    @State private var editingID: String?
    @State private var showCreate = false
    @State private var deleteRequest: DirectoryConfirmRequest?
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var searchPresented = false
    @State private var filter = ProjectFilter.all
    @State private var isSelecting = false
    @State private var selectedProjectIDs: Set<String> = []
    @State private var hasOpenedCreateForm = false

    /// Сценарий центрального «+»: список остаётся контекстом формы, но сама
    /// форма открывается сразу, без промежуточного ручного тапа по «…».
    private let opensCreateForm: Bool

    private let apiClient = APIClient()

    init(opensCreateForm: Bool = false) {
        self.opensCreateForm = opensCreateForm
    }

    var body: some View {
        // Урок 2026-09-25 (чёрные треугольники в углах системной клавиатуры,
        // iOS 26): фон одним слоем на самом верху тела экрана, `ZStack` +
        // `.ignoresSafeArea()` без ограничения edges — тут в этом же списке
        // прямо на месте открывается `ProjectCreateForm`/`ProjectEditForm`
        // с текстовым полем, и до фикса под клавиатурой были те же уголки.
        ZStack {
        Color.tfBackground.ignoresSafeArea()
        ScrollView {
            // Интервал 8pt, а не 2pt: карточки (`ProjectCard`) — отдельные
            // объекты со скруглением, слипшийся ряд из них читается как
            // сломанная таблица.
            LazyVStack(spacing: TFSpacing.sm) {
                if showCreate {
                    ProjectCreateForm(onCreated: { showCreate = false }, onCancel: { showCreate = false })
                }

                if !isSelecting {
                    noProjectRow
                }

                ForEach(visibleProjects) { project in
                    if editingID == project.id {
                        ProjectEditForm(project: project, apiClient: apiClient, onSaved: {
                            editingID = nil
                            Task { await projectStore.load() }
                        }, onCancel: { editingID = nil })
                    } else if isSelecting {
                        selectionRow(project)
                    } else {
                        DirectorySwipeRow(
                            onEdit: { editingID = project.id },
                            onDelete: { requestDelete(project) },
                            cornerRadius: TFRadius.xl
                        ) {
                            projectRow(project)
                        }
                    }
                }

                if projectStore.projects.isEmpty && !projectStore.isLoading && !showCreate {
                    TFEmptyState(
                        icon: "folder",
                        text: "Проектов пока нет — создайте первый через меню «…»"
                    )
                    .padding(.horizontal, TFSpacing.xs)
                } else if visibleProjects.isEmpty && !projectStore.isLoading && !showCreate {
                    Text("Проекты не найдены")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TFSpacing.xs)
                }

                if projectStore.isLoading { TFLoading(.block) }
                TFErrorBanner(projectStore.errorMessage, variant: .inline)
                TFErrorBanner(errorMessage, variant: .block)
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.top, TFSpacing.sm)
            .padding(.bottom, TFSpacing.xl)
        }
        // Штатный pull-to-refresh (iOS 15+). Прокрути вниз и потяни — вызовет
        // projectStore.load(). Сегодня не трогаю по требованию владельца.
        .refreshable { await projectStore.load() }
        }
        // Штатная SwiftUI-шапка. Системная стрелка назад добавляется стеком
        // навигации; пару кнопок группирует сам toolbar iOS.
        .tfNativeHeader("Проекты")
        .searchable(
            text: $searchText,
            isPresented: $searchPresented,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Поиск проектов"
        )
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                projectFilterMenu
                projectActionsMenu
            }
        }
        .task {
            if opensCreateForm && !hasOpenedCreateForm {
                hasOpenedCreateForm = true
                showCreate = true
            }
            if projectStore.projects.isEmpty { await projectStore.load() }
        }
        .directoryConfirm($deleteRequest)
    }

    private var projectFilterMenu: some View {
        Menu {
            ForEach(ProjectFilter.allCases) { option in
                Button {
                    filter = option
                } label: {
                    Label(option.title, systemImage: filter == option ? "checkmark.circle.fill" : option.icon)
                }
            }
        } label: {
            TFPlannerToolbarIcon(
                systemName: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill",
                tint: filter == .all ? .tfSub : .tfRed
            )
        }
        .accessibilityLabel("Фильтр проектов")
    }

    private var projectActionsMenu: some View {
        Menu {
            if isSelecting {
                Button(role: .destructive) {
                    requestDeleteSelected()
                } label: {
                    Label("Удалить выбранные (\(selectedProjectIDs.count))", systemImage: "trash")
                }
                .disabled(selectedProjectIDs.isEmpty)

                // Владелец 27.09.2026: закреплять проекты пачкой из режима выбора.
                // Все выбранные уже закреплены — пункт открепляет.
                Button {
                    Task { await pinSelected(!allSelectedPinned) }
                } label: {
                    Label(
                        allSelectedPinned
                            ? "Открепить выбранные (\(selectedProjectIDs.count))"
                            : "Закрепить выбранные (\(selectedProjectIDs.count))",
                        systemImage: allSelectedPinned ? "pin.slash" : "pin"
                    )
                }
                .disabled(selectedProjectIDs.isEmpty)

                Button {
                    endSelection()
                } label: {
                    Label("Завершить выбор", systemImage: "checkmark")
                }
            } else {
                Button {
                    editingID = nil
                    showCreate = true
                } label: {
                    Label("Добавить проект", systemImage: "plus")
                }

                Menu {
                    if projectStore.projects.isEmpty {
                        Text("Нет проектов")
                    } else {
                        ForEach(projectStore.projects) { project in
                            Button(project.name) {
                                showCreate = false
                                editingID = project.id
                            }
                        }
                    }
                } label: {
                    Label("Изменить проект", systemImage: "pencil")
                }

                Button {
                    beginSelection()
                } label: {
                    Label("Выбрать проекты", systemImage: "checkmark.circle")
                }
            }
        } label: {
            Image(systemName: isSelecting ? "checkmark.circle.fill" : "ellipsis")
        }
        .accessibilityLabel("Действия с проектами")
    }

    private var visibleProjects: [ApiProject] {
        projectStore.projects.filter { project in
            let queryMatches = searchText.isEmpty
                || project.name.localizedCaseInsensitiveContains(searchText)
            guard queryMatches else { return false }

            let status = ProjectTaskStatusSummary(project: project, tasks: taskStore.tasks)
            switch filter {
            case .all: return true
            case .pinned: return project.pinned
            case .inWork: return status.inWork > 0
            case .review: return status.review > 0
            case .blocked: return status.blocked > 0
            case .completed: return status.total > 0 && status.completed == status.total
            }
        }
    }

    /// Строка проекта — карточка (`ProjectCard`), а не однострочный ряд:
    /// владелец 08.09.2026 попросил видеть в списке жизнь проекта, а не одно
    /// число. Сам ряд остался кнопкой в тот же маршрут и по-прежнему живёт
    /// внутри `DirectorySwipeRow` (правка/удаление свайпом).
    /// «Без проекта» — синтетический раздел рядом со списком проектов: все
    /// задачи без проекта аккумулируются в один список. Владелец 19.09.2026:
    /// неназначенные задачи терялись по спискам, хочу видеть их
    /// централизованно, как проект. Это не проектная сущность: ни свайпа,
    /// ни выбора, ни формы — только переход в список.
    private var noProjectCount: Int {
        taskStore.tasks.filter { $0.projectId == nil && $0.status == .active }.count
    }

    private var noProjectRow: some View {
        NavigationLink(value: AppRoute.noProjectTasks) {
            TFCard {
                HStack(spacing: TFSpacing.md) {
                    Image(systemName: "tray")
                        .tfText(.title)
                        .foregroundStyle(Color.tfSub)
                        .frame(width: 28, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Без проекта")
                            .tfText(.title)
                            .foregroundStyle(Color.tfText)
                        Text(
                            noProjectCount == 0
                                ? "Нет активных задач"
                                : "\(noProjectCount) \(DirectoryPluralize.taskWord(noProjectCount))"
                        )
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfDim)
                }
            }
        }
        .buttonStyle(TFTapRowStyle())
    }

    private func projectRow(_ project: ApiProject) -> some View {
        NavigationLink(value: AppRoute.projectTasks(projectID: project.id)) {
            ProjectCard(project: project, tasks: taskStore.tasks)
        }
        .buttonStyle(TFTapRowStyle())
    }

    private func selectionRow(_ project: ApiProject) -> some View {
        let selected = selectedProjectIDs.contains(project.id)
        return Button {
            if selected {
                selectedProjectIDs.remove(project.id)
            } else {
                selectedProjectIDs.insert(project.id)
            }
        } label: {
            HStack(spacing: TFSpacing.sm) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .tfText(.input)
                    .foregroundStyle(selected ? Color.tfRed : Color.tfDim)
                    .accessibilityHidden(true)
                ProjectCard(project: project, tasks: taskStore.tasks)
            }
        }
        .buttonStyle(TFTapRowStyle())
        .accessibilityLabel(selected ? "Отменить выбор проекта \(project.name)" : "Выбрать проект \(project.name)")
    }

    private func beginSelection() {
        editingID = nil
        showCreate = false
        searchPresented = false
        selectedProjectIDs.removeAll()
        isSelecting = true
    }

    private func endSelection() {
        selectedProjectIDs.removeAll()
        isSelecting = false
    }

    /// Текст confirm-а зависит от `task_count` — прямая цитата `ProjectsScreen.tsx`.
    private func requestDelete(_ project: ApiProject) {
        let count = project.taskCount ?? 0
        deleteRequest = DirectoryConfirmRequest(
            title: "Удалить проект «\(project.name)»?",
            description: count > 0
                ? "Задачи внутри (\(count) \(DirectoryPluralize.taskWord(count))) не удалятся — они останутся без проекта. Сам проект и его столбец на доске исчезнут без возможности отмены."
                : "В нём сейчас нет задач. Действие нельзя отменить.",
            onConfirm: {
                Task {
                    await projectStore.delete(projectId: project.id)
                }
            }
        )
    }

    private func requestDeleteSelected() {
        let selected = projectStore.projects.filter { selectedProjectIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        let openProjects = selected.filter { project in
            let summary = ProjectTaskStatusSummary(project: project, tasks: taskStore.tasks)
            return summary.inWork > 0 || summary.review > 0 || summary.blocked > 0
        }
        guard openProjects.isEmpty else {
            let names = openProjects.prefix(2).map(\.name).joined(separator: ", ")
            let suffix = openProjects.count > 2 ? " и ещё \(openProjects.count - 2)" : ""
            errorMessage = "Пакетное удаление доступно только для проектов без открытых задач. Сначала закройте задачи в: \(names)\(suffix)."
            return
        }
        let count = selected.count
        let tasksCount = selected.reduce(0) { partial, project in
            partial + (project.taskCount ?? 0) + (project.completedCount ?? 0)
        }
        deleteRequest = DirectoryConfirmRequest(
            title: "Удалить выбранные проекты (\(count))?",
            description: "Задачи внутри (\(tasksCount)) не удалятся — они останутся без проекта. Действие нельзя отменить.",
            confirmLabel: "Удалить \(count)",
            onConfirm: {
                Task { await deleteSelectedProjects(selected.map(\.id)) }
            }
        )
    }

    private var allSelectedPinned: Bool {
        let selected = projectStore.projects.filter { selectedProjectIDs.contains($0.id) }
        return !selected.isEmpty && selected.allSatisfy(\.pinned)
    }

    private func pinSelected(_ pinned: Bool) async {
        errorMessage = nil
        for id in selectedProjectIDs {
            do {
                _ = try await apiClient.patchProject(id: id, fields: ["pinned": .bool(pinned)])
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                break
            }
        }
        await projectStore.load()
        endSelection()
    }

    private func deleteSelectedProjects(_ ids: [String]) async {
        errorMessage = nil
        for id in ids {
            do {
                try await apiClient.deleteProject(id: id)
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                break
            }
        }
        await projectStore.load()
        let existingIDs = Set(projectStore.projects.map(\.id))
        selectedProjectIDs.formIntersection(existingIDs)
        if selectedProjectIDs.isEmpty { isSelecting = false }
    }
}

private enum ProjectFilter: String, CaseIterable, Identifiable {
    case all, pinned, inWork, review, blocked, completed

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "Все проекты"
        case .pinned: "Закреплённые"
        case .inWork: "В работе"
        case .review: "На ревью"
        case .blocked: "Заблокированные"
        case .completed: "Все задачи выполнены"
        }
    }

    var icon: String {
        switch self {
        case .all: "tray.full"
        case .pinned: "pin.fill"
        case .inWork: "play.circle.fill"
        case .review: "eye.fill"
        case .blocked: "exclamationmark.triangle.fill"
        case .completed: "checkmark.circle.fill"
        }
    }
}

/// Форма создания — над списком (из меню «…»), симметрично
/// `ProjectEditForm` ниже: название, системный выбор цвета и база знаний.
private struct ProjectCreateForm: View {
    @Environment(ProjectStore.self) private var projectStore
    let onCreated: () -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var color = Color.tfBlue
    @State private var isSaving = false
    /// Полка базы знаний. `nil` — общая база TaskFlow.
    @State private var datasetId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            TextField("Название проекта", text: $name)
                .tfText(.input)
                .foregroundStyle(Color.tfText)
                .padding(.horizontal, TFSpacing.sm + 4)
                .padding(.vertical, TFSpacing.sm + 2)
                .background(Color.tfCard2)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))

            ColorPicker("Цвет проекта", selection: $color, supportsOpacity: false)

            // У нового проекта документов ещё нет, переносить нечего —
            // предупреждение о переиндексации здесь не нужно.
            KnowledgeDatasetPicker(selection: $datasetId)

            TFErrorBanner(projectStore.errorMessage, variant: .block)

            HStack(spacing: TFSpacing.sm) {
                Button("Отмена", action: onCancel)
                    .buttonStyle(TFTapRowStyle())
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .tfText(.row)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tfSub)
                    .background(Color.tfCard2)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))

                Button {
                    Task { await create() }
                } label: {
                    Text(isSaving ? "Создаём…" : "Создать")
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .tfText(.row)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .background(Color.tfRedSolid)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                }
                .buttonStyle(TFTapFadeStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
        }
        .padding(TFSpacing.lg)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
    }

    private func create() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        if await projectStore.create(
            name: trimmed, color: color.toHex(), knowledgeDatasetId: datasetId
        ) != nil {
            onCreated()
        }
    }
}

/// Инлайн-форма правки — разворачивается на месте строки: название,
/// системный `ColorPicker`, закрепление, база знаний и сохранение. Своим `APIClient()`
/// зовёт `patchProject` — `ProjectStore` метода `update` не даёт (Core чужой),
/// после успеха родитель перезагружает стор, чтобы кэш не разъехался с сервером.
private struct ProjectEditForm: View {
    let project: ApiProject
    let apiClient: APIClient
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var color: Color
    @State private var pinned: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Полка базы знаний. `nil` — общая база TaskFlow.
    @State private var datasetId: String?
    /// Текст предупреждения от сервера (409): сколько документов переедет и
    /// сколько примерно займёт переиндексация. Пока он не пуст — показан
    /// диалог, и до ответа владельца ничего не сохраняется.
    @State private var reindexPrompt: String?

    init(project: ApiProject, apiClient: APIClient, onSaved: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.project = project
        self.apiClient = apiClient
        self.onSaved = onSaved
        self.onCancel = onCancel
        _name = State(initialValue: project.name)
        _color = State(initialValue: Color(hex: project.color ?? TFHexDefault.unassigned))
        _pinned = State(initialValue: project.pinned)
        _datasetId = State(initialValue: project.knowledgeDatasetId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            TextField("Название проекта", text: $name)
                .tfText(.input)
                .foregroundStyle(Color.tfText)
                .padding(.horizontal, TFSpacing.sm + 4)
                .padding(.vertical, TFSpacing.sm + 2)
                .background(Color.tfCard2)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))

            HStack {
                ColorPicker("Цвет проекта", selection: $color, supportsOpacity: false)
                Button {
                    pinned.toggle()
                } label: {
                    Label(
                        pinned ? "Открепить проект" : "Закрепить проект",
                        systemImage: pinned ? "pin.slash" : "pin"
                    )
                    .labelStyle(.iconOnly)
                }
                .accessibilityLabel(pinned ? "Открепить проект" : "Закрепить проект")
            }

            KnowledgeDatasetPicker(
                selection: $datasetId,
                reindexWarning: datasetChanged && documentCount > 0
                    ? "Смена базы знаний = переиндексация: \(documentCount) док. уедут "
                      + "в другую базу и будут посчитаны заново. Это займёт время, и "
                      + "пока идёт индексация, эти документы в поиске не находятся."
                    : nil
            )

            TFErrorBanner(errorMessage, variant: .block)

            HStack(spacing: TFSpacing.sm) {
                Button("Отмена", action: onCancel)
                    .buttonStyle(TFTapRowStyle())
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .tfText(.row)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tfSub)
                    .background(Color.tfCard2)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))

                Button {
                    Task { await save() }
                } label: {
                    Text(isSaving ? "Сохраняем…" : "Сохранить")
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .tfText(.row)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .background(Color.tfRedSolid)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                }
                .buttonStyle(TFTapFadeStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
        }
        .padding(TFSpacing.lg)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
        // Текст диалога — тот, что прислал сервер: там точное число
        // документов и оценка минут, а не догадка клиента.
        .confirmationDialog(
            "Переиндексация",
            isPresented: Binding(
                get: { reindexPrompt != nil },
                set: { if !$0 { reindexPrompt = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Перенести и переиндексировать", role: .destructive) {
                Task { await save(confirmReindex: true) }
            }
            Button("Отмена", role: .cancel) { reindexPrompt = nil }
        } message: {
            Text(reindexPrompt ?? "")
        }
    }

    /// Документов у проекта — из карточки (`docs_count`). Нужно, чтобы не
    /// пугать предупреждением там, где переносить нечего.
    private var documentCount: Int { project.docsCount ?? 0 }

    private var datasetChanged: Bool { datasetId != project.knowledgeDatasetId }

    private func save(confirmReindex: Bool = false) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        var fields: [String: JSONValue] = [
            "name": .string(trimmed),
            "color": .string(color.toHex()),
            "pinned": .bool(pinned),
        ]
        // Датасет шлём только когда он реально поменялся: лишнее поле в теле
        // заставило бы сервер считать это сменой и требовать подтверждения.
        if datasetChanged {
            fields["knowledge_dataset_id"] = datasetId.map { JSONValue.string($0) } ?? .null
            if confirmReindex { fields["confirm_reindex"] = .bool(true) }
        }

        do {
            _ = try await apiClient.patchProject(id: project.id, fields: fields)
            reindexPrompt = nil
            onSaved()
        } catch APIError.conflict(let message) {
            // 409 — сервер ничего не записал и просит подтверждения; в
            // сообщении уже есть число документов и оценка времени.
            reindexPrompt = message
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось переименовать проект"
        }
    }
}
