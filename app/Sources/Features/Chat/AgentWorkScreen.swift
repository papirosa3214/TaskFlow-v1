import SwiftUI

/// Какой из четырёх разделов поднять первым — веб-параметр URL `?focus=`
/// (`AgentWorkScreen.tsx`), значения дословно совпадают с ключами секций
/// там же. С 09.09.2026 маршрут `AppRoute.agentWork(focus:)` этот выбор
/// доносит: до того у него не было параметров, и все четыре плитки «Обзора»
/// открывали один и тот же полный список.
public enum AgentWorkFocus: String, Hashable {
    case inProgress = "in_progress"
    case review
    case blocked
    case stale
}

/// «Работа агента» — `/agent-work` (SCREENS-2 §5), сводка активности
/// агентов по четырём состояниям. 1:1 `src/screens/AgentWorkScreen.tsx` —
/// спека в SCREENS-2 §5 самих текстов подсказок не даёт, они сняты с
/// живого экрана (заголовок, hint под каждым разделом, тексты пустого/
/// ошибки состояний — дословно оттуда).
///
/// Источник данных — общий `TaskStore` (тот же кэш, что у «Обзора» и
/// «Сегодня»): свой запрос/поллинг экрану не нужен, `TaskFlowApp` грузит
/// список один раз при входе и держит живым реалтаймом (spec §4.2).
struct AgentWorkScreen: View {
    @Environment(TaskStore.self) private var taskStore
    private let apiClient = APIClient()

    /// Профили ролей — только чтобы подписать строку задачи «роль · модель»
    /// (LOCK-177). Не отдельный экран и не вкладка: чистая справка к строке.
    /// Загружается один раз на показ экрана; ошибка загрузки не мешает
    /// списку задач — подпись просто не появится.
    @State private var profilesByAccountID: [String: RoleProfile] = [:]

    /// `nil` — обычный порядок разделов. Задан контрактом строго без
    /// параметров (`AgentWorkScreen` в таблице INTEGRATION.md — «—»), но
    /// сам параметр инициализатора СВЕРХ контракта не ломает его: вызов
    /// `AgentWorkScreen()` без аргументов (как сейчас в фабрике маршрутов,
    /// `RouteDestinationView.swift`, чужой файл) остаётся валиден дословно.
    /// Это подготовленное место под будущую правку: у `AppRoute.agentWork`
    /// пока нет ассоциированного значения, чтобы донести фокус сюда с
    /// плиток «Обзора» — чего именно не хватает, см. отчёт по задаче.
    let focus: AgentWorkFocus?

    init(focus: AgentWorkFocus? = nil) {
        self.focus = focus
    }

    /// Задача открывается ШТОРКОЙ, как везде: с «Сегодня», из проекта и из
    /// меток она выезжает снизу, а отсюда уходила пушем вбок — владелец
    /// 09.09.2026 заметил разнобой. Своё состояние, а не общий `AppRoute`:
    /// маршрут — это про экраны в стеке, а карточка задачи теперь не экран.
    @State private var sheetTaskID: AgentWorkTaskRef?
    @State private var swipeActionError: String?

    /// `.sheet(item:)` требует `Identifiable`, голая строка им не является.
    private struct AgentWorkTaskRef: Identifiable {
        let id: String
    }

    private struct Section: Identifiable {
        let key: AgentWorkFocus
        let title: String
        let hint: String
        let tasks: [ApiTask]
        var id: AgentWorkFocus { key }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                TFErrorBanner(taskStore.errorMessage.map { _ in "Не удалось загрузить задачи" })
                    .padding(.horizontal, TFSpacing.screenHorizontal)
                    .padding(.top, TFSpacing.sm)

                // Только первый заход — `TaskStore.isLoading` включается на
                // КАЖДЫЙ `load()`, включая переподключение реалтайма; без
                // проверки на пустой кэш «Загрузка…» мигала бы поверх уже
                // показанного списка (веб-`isLoading` — только первый запрос).
                if taskStore.isLoading && taskStore.agentWorkTasks.isEmpty {
                    TFLoading(.block)
                        .frame(maxWidth: .infinity)
                        .padding(.top, TFSpacing.xl)
                }

                if isNothing {
                    Text("Агенты сейчас ничем не заняты — назначьте задачу, и она появится здесь.")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                        .padding(.top, TFSpacing.md)
                }

                ForEach(orderedSections) { section in
                    if !section.tasks.isEmpty {
                        sectionView(section)
                    }
                }
            }
            .padding(.bottom, TFSpacing.xl)
        }
        .refreshable {
            await taskStore.load(silent: true)
        }
        .background(Color.tfBackground)
        .tfNativeHeader("Работа агентов")
        .task { await loadRoleProfiles() }
        .sheet(item: $sheetTaskID) { ref in
            NavigationStack { TaskFormScreen(taskID: ref.id) }
                // Те же детенты, что у карточки из проекта и с «Сегодня»:
                // без них шторка открывалась сразу на весь экран, и половинного
                // состояния у неё не было вовсе.
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.tfSheetBackground)
        }
    }

    private func sectionView(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(section.title) \(section.tasks.count)")
                    .tfText(.action).fontWeight(.semibold)
                    .foregroundStyle(Color.tfText)
                Text(section.hint)
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.top, TFSpacing.md)
            .padding(.bottom, TFSpacing.xs)

            ForEach(section.tasks) { task in
                DirectoryTaskRow(
                    index: nil,
                    task: task,
                    isOwner: true,
                    onOpen: { sheetTaskID = AgentWorkTaskRef(id: task.id) },
                    onDelete: { Task { await deleteTask(task) } },
                    swipeAction: ProjectTaskSwipeAction.action(for: task, isOwner: true),
                    onSwipeAction: { Task { await performSwipe(task: task) } },
                    agentLine: agentLine(for: task)
                )
            }
        }
        .padding(.bottom, TFSpacing.sm)
    }

    // MARK: - Роль и модель строки (LOCK-177)

    /// Один раз подтягиваем профили ролей и индексируем их по `account_id`:
    /// `assignee_id` задачи — это ролевая учётка, и через неё строка находит
    /// свою роль. Если исполнитель — не роль (человек), подписи не будет.
    private func loadRoleProfiles() async {
        guard profilesByAccountID.isEmpty else { return }
        guard let roles = try? await apiClient.roles() else { return }
        var index: [String: RoleProfile] = [:]
        for role in roles {
            if let accountID = role.accountID { index[accountID] = role }
        }
        profilesByAccountID = index
    }

    /// «Builder · GPT Sol» — имя роли и primary-модель. Пусто, если роль не
    /// нашлась: строка тогда выглядит как раньше, без выдуманной подписи.
    private func agentLine(for task: ApiTask) -> String? {
        guard let assigneeID = task.assigneeId,
              let role = profilesByAccountID[assigneeID] else { return nil }
        let model = role.model.flatMap { $0.isEmpty ? nil : $0 }
        return model.map { "\(role.title) · \($0)" } ?? role.title
    }

    // MARK: - Свайпы и удаление (логика 1:1 с ProjectTasksScreen.performSwipe
    // и .deleteTask — обзор показывает те же задачи, что и проекты/сегодня,
    // и те же действия должны работать).

    private func performSwipe(task: ApiTask) async {
        // Логика approve+close из ProjectTaskSwipeAction.complete: для review —
        // сначала approve, потом закрыть; для остальных состояний — просто закрыть.
        do {
            if task.agentState == .review {
                try await apiClient.approveCurrentTaskVersion(taskID: task.id)
                _ = try await apiClient.setTaskAgentState(id: task.id, state: nil, comment: nil)
            }
            _ = try await apiClient.patchTask(id: task.id, fields: ["status": .string("completed")])
            await taskStore.load(silent: true)
        } catch {
            swipeActionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Поднять флаг готовности через отдельный action — для задач в работе/пропавших,
    /// которые ещё не на ревью (ProjectTaskSwipeAction.markReadyForPickup).
    /// Не вызывается из текущей разметки (там только .complete), оставлен на
    /// будущее, когда добавим второй свайп.
    private func markReady(_ task: ApiTask) async {
        do {
            _ = try await apiClient.patchTask(id: task.id, fields: ["ready_for_pickup": .bool(true)])
            await taskStore.load(silent: true)
        } catch {
            swipeActionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func deleteTask(_ task: ApiTask) async {
        do {
            _ = try await apiClient.deleteTask(id: task.id)
            await taskStore.load(silent: true)
        } catch {
            swipeActionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Группировка (буквально `AgentWorkScreen.tsx`, useMemo groups)

    private var active: [ApiTask] {
        taskStore.agentWorkTasks.filter { $0.status == .active }
    }

    private var groupInProgress: [ApiTask] {
        active.filter { $0.agentState == .inProgress && $0.agentStale != true }
    }

    private var groupStale: [ApiTask] {
        active.filter { $0.agentState == .inProgress && $0.agentStale == true }
    }

    private var groupReview: [ApiTask] {
        active.filter { $0.agentState == .review }
    }

    private var groupBlocked: [ApiTask] {
        active.filter { $0.agentState == .blocked }
    }

    private var sections: [Section] {
        [
            Section(key: .inProgress, title: "В работе", hint: "Агент занят этими задачами прямо сейчас", tasks: groupInProgress),
            Section(key: .review, title: "На проверке", hint: "Агент закончил и сдал работу", tasks: groupReview),
            Section(key: .blocked, title: "Заблокированы", hint: "Агент не может продолжить без вас", tasks: groupBlocked),
            Section(key: .stale, title: "Пропали", hint: "Агент взялся и замолчал — задача висит без работы", tasks: groupStale),
        ]
    }

    /// `?focus=` из плитки «Обзора» или из URL: показываем ТОЛЬКО эту секцию,
    /// без остальных трёх (раньше focus двигал секцию наверх, остальные
    /// оставались — на iOS это выглядело как «нажал в работе, а внизу ещё
    /// на проверке 12», владелец 14.09.2026). Без focus — все четыре как раньше.
    private var orderedSections: [Section] {
        guard let focus else { return sections }
        return sections.filter { $0.key == focus }
    }

    private var isNothing: Bool {
        !taskStore.isLoading && taskStore.errorMessage == nil && sections.allSatisfy { $0.tasks.isEmpty }
    }
}
