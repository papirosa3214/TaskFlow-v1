import SwiftUI

// «Задачи метки» — spec/SCREENS-2.md §10, `/labels/:id`. Сверено построчно
// с живым `src/screens/LabelTasksScreen.tsx` 31.08.2026 — этот экран НЕ
// переиспользует общий `TaskRow` (в отличие от `ProjectTasksScreen`), у него
// СВОЙ локальный ряд: без свайпа вообще, зато с настоящей точкой-переключателем
// статуса слева (spec §10 «dot-toggle» — эта деталь единственный раз реально
// существует именно тут, файловый комментарий в `TaskRow.tsx` про
// аналогичную кнопку там устарел, см. `DirectoryTaskRow.swift`).
struct LabelTasksScreen: View {
    let labelID: String

    @Environment(LabelStore.self) private var labelStore
    @Environment(TaskStore.self) private var taskStore

    @State private var pendingTaskID: String?

    private struct TaskRef: Identifiable {
        let id: String
    }

    private var label: ApiLabel? {
        labelStore.labels.first { $0.id == labelID }
    }

    private var tasks: [ApiTask] {
        taskStore.tasks.filter { $0.status == .active && $0.labels.contains { $0.id == labelID } }
    }

    private var notFound: Bool {
        !labelStore.isLoading && labelStore.errorMessage == nil && label == nil
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                TFErrorBanner(labelStore.errorMessage, variant: .inline)
                TFErrorBanner(taskStore.errorMessage, variant: .inline)
                if labelStore.isLoading || taskStore.isLoading { TFLoading(.block) }

                if notFound {
                    notFoundView
                } else if label != nil {
                    if tasks.isEmpty {
                        TFEmptyState(
                            icon: "tag",
                            text: "Этой меткой пока не помечена ни одна задача"
                        )
                        .padding(.horizontal, TFSpacing.lg)
                        .padding(.top, TFSpacing.sm)
                    } else {
                        ForEach(tasks) { task in
                            taskRow(task)
                            TFDivider(dimmed: true)
                        }
                    }
                }
            }
            .padding(.top, TFSpacing.sm)
            .padding(.bottom, TFSpacing.xl)
        }
        .refreshable {
            await taskStore.load(silent: true)
        }
        .background(Color.tfBackground)
        // Штатная шапка (просьба владельца 03.09.2026 — «нативные кнопки
        // везде одним элементом»). Была `DirectoryCompactHeader` (свой
        // ZStack) специально ради цветной иконки метки перед заголовком —
        // `tfNativeHeader` такого слота не даёт (только `String`), но у
        // toolbar есть штатное место как раз под это: `.principal` меняет
        // содержимое заголовка на произвольное вью, без ручной геометрии и
        // без риска наехать на кнопки вокруг (тот баг, что чинили в
        // DirectoryCompactHeader, тут в принципе невозможен — `.principal`
        // сам разруливает место с соседними toolbar-элементами).
        .tfNativeHeader(label?.name ?? "Метка", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    if let label {
                        Image(systemName: "tag")
                            .tfText(.row)
                            .foregroundStyle(Color(hex: label.color ?? TFHexDefault.unassigned))
                    }
                    Text(label?.name ?? "Метка")
                        .tfText(.title)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(1)
                }
            }
        }
        .task {
            if labelStore.labels.isEmpty { await labelStore.load() }
            if taskStore.tasks.isEmpty { await taskStore.load() }
        }
        .sheet(item: Binding(
            get: { pendingTaskID.map(TaskRef.init) },
            set: { pendingTaskID = $0?.id }
        )) { ref in
            NavigationStack { TaskFormScreen(taskID: ref.id) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.tfSheetBackground)
        }
    }

    // MARK: - Строка задачи: точка-переключатель + контент, БЕЗ свайпа (spec §10)

    private func taskRow(_ task: ApiTask) -> some View {
        let isDone = task.status == .completed
        let priorityColor = TaskPriority(rawValue: task.priority)?.color ?? Color(hex: "#4A9FD8")

        return HStack(alignment: .top, spacing: TFSpacing.md) {
            Button {
                Task {
                    // `apply` — пустышка, как у ВСЕХ остальных вызовов `taskStore.patch`
                    // в проекте (поля `ApiTask` — `let`, точечно не мутируются;
                    // обновление приходит из ответа сервера). Этот экран и так уже
                    // фильтрует список по `status == .active` — после патча задача
                    // просто пропадёт из `tasks` на следующей перерисовке, как и в вебе.
                    await taskStore.patch(taskId: task.id, fields: ["status": .string(isDone ? "active" : "completed")]) { _ in }
                }
            } label: {
                Circle()
                    .strokeBorder(priorityColor, lineWidth: 2)
                    .frame(width: 18, height: 18)
                    .overlay {
                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(priorityColor)
                        }
                    }
            }
            .buttonStyle(TFTapScaleStyle())
            .padding(.top, 2)

            Button { pendingTaskID = task.id } label: {
                TFTaskRowContent(title: task.title, description: task.description, isDone: isDone, horizontalPadding: 0) {
                    if let initials = task.assigneeInitials, task.assigneeId != nil {
                        TFAvatar(size: .taskList, initials: initials, tint: Color(hex: task.assigneeColor ?? TFHexDefault.unassigned), userID: task.assigneeId)
                    }
                } metadata: {
                    TFTaskStructureIndicators(priority: TaskPriority(rawValue: task.priority), subtasksDone: task.subtasks.isEmpty ? nil : task.subtasks.count { $0.done }, subtasksTotal: task.subtasks.isEmpty ? nil : task.subtasks.count, childrenCount: task.childrenCount, hasCollaborationPlan: task.hasCollaborationPlan)
                    if let due = task.dueDate {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar").font(.system(size: 10))
                            Text(DirectoryDate.dueShort(due))
                        }
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                        .padding(.horizontal, TFSpacing.sm)
                        .padding(.vertical, 2)
                        .background(Color.tfCard)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
                    }
                    ForEach(task.labels, id: \.id) { label in
                        TFLabelPill(label.name, color: Color(hex: label.color ?? TFHexDefault.unassigned)).layoutPriority(-1)
                    }
                }
            }
            .buttonStyle(TFTapRowStyle())
        }
        .padding(.horizontal, TFSpacing.lg)
    }

    private var notFoundView: some View {
        VStack(spacing: TFSpacing.md) {
            Text("Метка не найдена — возможно, она удалена.")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            NavigationLink(value: AppRoute.labels) {
                Text("К списку меток")
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
