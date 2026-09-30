import SwiftUI
import os

// «Задачи проекта» — spec/SCREENS-2.md §8, `/projects/:id`. Сверено построчно
// с живым `src/screens/ProjectTasksScreen.tsx` 31.08.2026.
//
// ⚠️ КОНТРАКТНАЯ ДЫРА (не мой файл чинить, в отчёте оркестратору): «+» в
// шапке в вебе ведёт на `/task/new?project=id` — с предзаполненным проектом.
// `AppRoute.taskCreate` пока не несёт `projectID`, поля
// «проект» там нет — веду на пустую форму без предзаполнения, пользователь
// выберет проект вручную.
//
// Кнопка «Документация» (`ProjectNotesSection`) раньше вела на голый `.notes`
// без параметра — так же, как в вебе, но там это не мешало (веб-код умеет
// подсветить нужную папку иначе). На native это выглядело как переход в
// произвольный несвязанный корень Дневника — просьба владельца 03.09.2026
// («переносит не туда, куда надо»). Заведён `AppRoute.noteFolder(folderID:)`
// сверх контракта (`.notes` без параметра не тронут) — `NotesScreen` теперь
// умеет открыться сразу на нужной папке.
struct ProjectTasksScreen: View {
    /// `nil` — раздел «Без проекта»: все задачи без проекта, тем же списком.
    let projectID: String?

    @Environment(ProjectStore.self) private var projectStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(SessionStore.self) private var session
    @State private var relationshipTasks: [ApiTask] = []

    private let apiClient = APIClient()
    private let logger = Logger(subsystem: "com.taskflow.apiclient", category: "project-tasks")

    @State private var pendingDetail: String?

    private struct TaskRef: Identifiable {
        let id: String
    }
    @State private var showNewTask = false

    /// На проектах владелец — создатель проекта (он же владелец трекера).
    /// В этой роли доступны контекстные свайпы. Постоянное true, пока
    /// авторизация владельца не появится отдельным состоянием.
    private var isTaskOwner: Bool { true }

    private var project: ApiProject? {
        guard let projectID else { return nil }
        return projectStore.projects.first { $0.id == projectID }
    }

    /// Закреплённые — единым блоком сверху, порядок внутри каждой группы не
    /// трогаем (два `filter`, НЕ `sorted(by:)` — `Array.sort` в Swift не
    /// гарантированно стабилен, а спека и веб-код требуют стабильность).
    private var tasks: [ApiTask] {
        let source = relationshipTasks.isEmpty ? taskStore.tasks : relationshipTasks
        var openTreeIDs = Set(source.lazy.filter { task in
            task.status == .active || task.subtasks.contains { !$0.done }
        }.map(\.id))

        // Поднимаем признак открытой работы по всей цепочке родителей. В
        // проектном списке остаются только корневые задачи, а потомки живут в
        // разделе «Связанные задачи» — без дублирования на одном уровне.
        var didAddParent = true
        while didAddParent {
            didAddParent = false
            for task in source where openTreeIDs.contains(task.id) {
                if let parentID = task.parentId, openTreeIDs.insert(parentID).inserted {
                    didAddParent = true
                }
            }
        }

        let scoped = source.filter { task in
            task.projectId == projectID && task.parentId == nil && openTreeIDs.contains(task.id)
        }
        return scoped.filter { $0.pinned } + scoped.filter { !$0.pinned }
    }

    private var notFound: Bool {
        projectID != nil && !projectStore.isLoading && projectStore.errorMessage == nil && project == nil
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.md) {
                TFErrorBanner(projectStore.errorMessage, variant: .inline)
                TFErrorBanner(taskStore.errorMessage, variant: .inline)

                if projectStore.isLoading || taskStore.isLoading { TFLoading(.block) }

                if notFound {
                    notFoundView
                } else if projectID == nil || project != nil {
                    if tasks.isEmpty {
                        TFEmptyState(
                            icon: "tray",
                            text: projectID == nil ? "Задач без проекта нет" : "В проекте пока нет задач"
                        )
                        .padding(.horizontal, TFSpacing.xs)
                    } else {
                        VStack(spacing: 2) {
                            ForEach(tasks.indices, id: \.self) { rowIndex in
                                rowWithIndex(rowIndex)
                            }
                        }
                    }

                    if let project {
                        ProjectNotesSection(project: project, onProjectPatched: { _ in
                            Task { await projectStore.load() }
                        })
                    }
                }
            }
            .padding(.top, TFSpacing.sm)
            .padding(.bottom, TFSpacing.xl)
        }
        .refreshable {
            await taskStore.load(silent: true)
            await refreshRelationshipTasks()
        }
        .background(Color.tfBackground)
        // Штатная шапка (просьба владельца 03.09.2026 — «нативные кнопки
        // везде одним элементом»). Была `DirectoryCompactHeader` (свой
        // ZStack) ради цветного кружка проекта перед заголовком —
        // `tfNativeHeader` такого слота не даёт (только `String`), но у
        // toolbar есть штатное место как раз под это: `.principal` меняет
        // содержимое заголовка на произвольное вью, сам разруливая место с
        // соседним «+» (тот самый наезд текста на кнопку, LOCK-060/061,
        // здесь в принципе невозможен на системном toolbar).
        .tfNativeHeader(projectID == nil ? "Без проекта" : (project?.name ?? "Проект"), displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    if let project {
                        Circle().fill(Color(hex: project.color ?? TFHexDefault.unassigned)).frame(width: 10, height: 10)
                    }
                    Text(projectID == nil ? "Без проекта" : (project?.name ?? "Проект"))
                        .tfText(.title)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(1)
                }
            }
            if project != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewTask = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Добавить")
                }
            }
        }
        .task {
            if projectStore.projects.isEmpty { await projectStore.load() }
            if taskStore.tasks.isEmpty { await taskStore.load() }
            await refreshRelationshipTasks()
        }
        .sheet(item: Binding(
            get: { pendingDetail.map(TaskRef.init) },
            set: { pendingDetail = $0?.id }
        )) { ref in
            NavigationStack { TaskFormScreen(taskID: ref.id) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.tfSheetBackground)
        }
        .onChange(of: pendingDetail) { previous, current in
            if previous != nil, current == nil {
                Task { await refreshRelationshipTasks() }
            }
        }
        .navigationDestination(isPresented: $showNewTask) { routeDestination(.taskCreate) }
    }

    private func rowWithIndex(_ rowIndex: Int) -> some View {
        if rowIndex < 0 || rowIndex >= tasks.count {
            logger.error("rowWithIndex out of bounds: index=\(rowIndex) count=\(tasks.count)")
            return AnyView(EmptyView())
        }
        let task = tasks[rowIndex]
        let shortId = String(task.id.prefix(8))
        let swipeAction = ProjectTaskSwipeAction.action(
            for: task, isOwner: isTaskOwner, currentUserID: session.currentUser?.id
        )
        return AnyView(
            DirectoryTaskRow(
                index: shortId,
                task: task,
                isOwner: isTaskOwner,
                onOpen: { pendingDetail = task.id },
                onDelete: { Task { await deleteTask(task) } },
                swipeAction: swipeAction,
                onSwipeAction: { Task { await performSwipe(task: task, action: swipeAction) } }
            )
        )
    }

    /// Удаление строки из проектного списка. `TaskStore.delete` чистит только
    /// `taskStore.tasks`, а строки этого экрана рисуются из
    /// `relationshipTasks` (`tasks(includeChildren: true)`) — из-за этого
    /// удалённая задача оставалась на месте до ручного pull-to-refresh
    /// (владелец 19.09.2026: «после действия не исчезают, сам должен
    /// обновлять»). Гасим строку в обоих источниках и подтягиваем свежий
    /// список, чтобы пересчиталось дерево.
    private func deleteTask(_ task: ApiTask) async {
        _ = await taskStore.delete(taskId: task.id)
        relationshipTasks.removeAll { $0.id == task.id }
        await refreshRelationshipTasks()
    }

    /// Свайп-действие по строке проекта. «Запустить» — сервер поднимает флаг.
    /// Принять ревью — снять блокировку и закрыть задачу (как в TaskDetailViewModel).
    private func performSwipe(task: ApiTask, action: ProjectTaskSwipeAction?) async {
        guard let action else { return }
        do {
            switch action {
            case .markReadyForPickup:
                // «Запустить» — тем же путём, что в карточке и в чате Секретаря.
                if task.parentId == nil {
                    try await apiClient.startDraft(taskID: task.id)
                } else {
                    _ = try await apiClient.patchTask(id: task.id, fields: ["ready_for_pickup": .bool(true)])
                }
            case .complete:
                // complete покрывает «принять задачу» — и ревью, и просто
                // завершить. Если был ревью — сначала снимаем блокировку.
                if task.agentState == .review {
                    try await apiClient.approveCurrentTaskVersion(taskID: task.id)
                    _ = try await apiClient.setTaskAgentState(id: task.id, state: nil, comment: nil)
                }
                _ = try await apiClient.patchTask(id: task.id, fields: ["status": .string("completed")])
            }
            await taskStore.load(silent: true)
            await refreshRelationshipTasks()
        } catch {
            // Тихая ошибка: визуально строка просто не изменится. Подробный
            // тост для свайпа не показывается — это быстрый жест, и отдельная
            // обработка ошибок выглядит лишней (как в существующих свайпах).
        }
    }

    private func refreshRelationshipTasks() async {
        relationshipTasks = (try? await apiClient.tasks(includeChildren: true)) ?? []
    }

    private var notFoundView: some View {
        VStack(spacing: TFSpacing.md) {
            Text("Проект не найден — возможно, он удалён.")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            NavigationLink(value: AppRoute.projects) {
                Text("К списку проектов")
                    .tfText(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tfText)
                    .padding(.horizontal, TFSpacing.lg)
                    .frame(height: 44)
                    .background(Color.tfCard)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
            }
            .buttonStyle(TFTapScaleStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TFSpacing.xl)
    }
}
