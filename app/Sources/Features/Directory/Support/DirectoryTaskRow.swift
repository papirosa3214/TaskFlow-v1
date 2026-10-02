import SwiftUI
import UIKit

// Строка задачи для ProjectTasksScreen — дубль `src/components/TaskRow.tsx`
// (общий компонент, которым пользуется чужой набор экранов), тем же приёмом
// дублирования, что `Features/Today/TodayTaskRow.swift` уже применил для
// «Сегодня» («точность спеки важнее переиспользования» — комментарий того
// файла). Не беру TodayTaskRow как есть: этому экрану нужен подавленный
// бейдж проекта (`showProjectBadge=false` — сам экран уже внутри одного
// проекта). Кнопка закрепления в строке жила здесь до 11.09.2026, когда
// владелец её убрал: закрепление переехало в меню «…» карточки задачи.
//
// ⚠️ Сверено с живым `TaskRow.tsx` 31.08.2026: `ProjectTasksScreen.tsx`
// вызывает `<TaskRow .../>` БЕЗ пропа `overdue` — он там всегда `false` по
// умолчанию, то есть просроченные задачи здесь показывают ОБЫЧНый бейдж
// срока (день+месяц, «· N дней»), а не красную пилюлю «Просрочено» — это не
// упрощение, так in the реальном коде, красная пилюля тут в принципе
// недостижима. Верхний файловый комментарий самого TaskRow.tsx про
// «точку-переключатель статуса» — устаревшая документация: в актуальном
// JSX такой кнопки уже нет (проверено построчно), дот-toggle реально
// существует только в LabelTasksScreen (см. её отдельную реализацию).
struct DirectoryTaskRow: View {
    /// Уникальный id задачи (короткий префикс UUID), чтобы владелец мог
    /// ссылаться на конкретную карточку в чате с исполнителем («посмотри
    /// #b6b57092»). Полный UUID слишком длинный, а в мобильном интерфейсе
    /// скопировать строку нельзя — префикс из 8 hex-символов достаточно
    /// уникален в пределах проекта (коллизия по первым 8 символам UUID
    /// практически невозможна при текущем количестве задач).
    let index: String?
    let task: ApiTask
    let isOwner: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void
    /// Контекстное действие на правом свайпе: поднять флаг / принять ревью.
    let swipeAction: ProjectTaskSwipeAction?
    let onSwipeAction: () -> Void

    /// Необязательная строка «роль · модель» (LOCK-177). Заполняется только
    /// на «Работе агентов»; у остальных списков остаётся пустой и ничего не
    /// меняет. `var` с дефолтом, чтобы не трогать существующие вызовы.
    var agentLine: String? = nil

    /// Своё имя в общем реестре раскрытых строк (`TFSwipeRowRegistry`).
    @State private var rowID = UUID()
    @State private var settledOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var confirmDelete = false

    private var offsetX: CGFloat { clamp(settledOffset + dragOffset) }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                swipeIconButton(icon: "trash", color: .tfSwipeDelete) {
                    close(); confirmDelete = true
                }
                .frame(width: leftRevealWidth)
                .opacity(revealOpacity(leftRevealWidth))

                Spacer(minLength: 0)

                if let swipeAction {
                    swipeIconButton(
                        icon: swipeAction.icon,
                        color: .tfGreen
                    ) { close(); onSwipeAction() }
                    .frame(width: rightRevealWidth)
                    .opacity(revealOpacity(rightRevealWidth))
                }
            }

            row
                .background(Color.tfBackground)
                .offset(x: offsetX)
                // UIKit-pan не забирает вертикальный жест у ScrollView.
                // Обычный DragGesture здесь делал начало прокрутки вязким:
                // список ждал, решит ли строка трактовать касание как свайп.
                .gesture(
                    HorizontalPan(
                        onBegin: { UIImpactFeedbackGenerator(style: .soft).impactOccurred() },
                        onChange: { dx in dragOffset = dx },
                        onEnd: { dx, velocity in settle(dx: dx, velocity: velocity) }
                    )
                )
        }
        .clipped()
        // Раскрыта всегда одна строка: как только реестр называет другую
        // (или прокрутка гасит всё), эта закрывается сама.
        .onChange(of: TFSwipeRowRegistry.shared.openRowID) { _, openID in
            if openID != rowID, settledOffset != 0 { close() }
        }
        // Ближайший native-эквивалент своего нижнего экшн-листа из TaskRow.tsx
        // (красная «Удалить» текстом + отдельная карточка «Отмена») — тот же
        // приём, что уже выбрал TodayTaskRow.swift для идентичного узла.
        .confirmationDialog("Удалить задачу?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive, action: onDelete)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("«\(task.title)» будет удалена безвозвратно")
        }
    }

    private var leftRevealWidth: CGFloat { max(offsetX, 0) }
    private var rightRevealWidth: CGFloat { max(-offsetX, 0) }

    private func revealOpacity(_ width: CGFloat) -> Double {
        min(1, Double(width / TFRowActionWidth) * 1.3)
    }

    /// Кнопка свайпа — только иконка, без надписи (владелец 11.09.2026).
    private func swipeIconButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: TFIconSize.md))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(color)
        }
        .buttonStyle(.plain)
        .clipped()
        .allowsHitTesting(abs(offsetX) >= TFRowActionWidth * 0.7)
        .accessibilityHidden(abs(offsetX) < TFRowActionWidth * 0.7)
    }

    private var row: some View {
        Button {
            if settledOffset != 0 { close() } else { onOpen() }
        } label: {
            TFTaskRowContent(title: task.title, description: task.description, isDone: task.status == .completed) {
                if let initials = task.assigneeInitials, task.assigneeId != nil {
                    TFAvatar(size: .taskList, initials: initials, tint: Color(hex: task.assigneeColor ?? TFHexDefault.unassigned), userID: task.assigneeId)
                }
            } metadata: {
                TFTaskStructureIndicators(priority: TaskPriority(rawValue: task.priority), subtasksDone: task.subtasks.isEmpty ? nil : task.subtasks.count { $0.done }, subtasksTotal: task.subtasks.isEmpty ? nil : task.subtasks.count, childrenCount: task.childrenCount, hasCollaborationPlan: task.hasCollaborationPlan)
                if let due = task.dueDate {
                    HStack(spacing: 3) {
                        Text(DirectoryDate.formatDuePlain(due))
                        Text("· \(DirectoryDate.formatDaysLeft(due))")
                        .foregroundStyle(DirectoryDate.daysUntil(due) <= 3 ? Color.tfOrange : Color.tfDim)
                    }
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
                    .padding(.horizontal, TFSpacing.sm)
                    .padding(.vertical, 2)
                    .background(Color.tfCard)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
                }
                if task.needsResearch {
                    TFPill("Исследование", color: .tfSub, solidBackground: .tfCard)
                }
                if let status = DirectoryAgentStateTag.text(task) {
                    Text(status).foregroundStyle(DirectoryAgentStateTag.color(task)).layoutPriority(-1)
                }
                if let index {
                    Text("#" + index).font(.system(.caption, design: .monospaced))
                }
                if let agentLine, !agentLine.isEmpty {
                    Label(agentLine, systemImage: "cpu")
                }
                ForEach(task.labels, id: \.id) { label in
                    TFLabelPill(label.name, color: Color(hex: label.color ?? TFHexDefault.unassigned)).layoutPriority(-1)
                }
            }
        }
        .buttonStyle(TFTapRowStyle())
    }


    private func close() {
        withAnimation(TFRowSwipe.settleAnimation(velocity: 0)) {
            settledOffset = 0
            dragOffset = 0
        }
        TFSwipeRowRegistry.shared.didClose(rowID)
    }

    // Пороги 1:1 с `TaskRow.tsx`: открытие >36px/280px·с⁻¹, закрытие
    // обратным сдвигом >25px/250px·с⁻¹ — асимметрично, легче закрыть, чем открыть.
    private func settle(dx: CGFloat, velocity: CGFloat) {
        let finalOffset = clamp(settledOffset + dx)
        withAnimation(TFRowSwipe.settleAnimation(velocity: velocity)) {
            if settledOffset == 0 {
                if swipeAction != nil, (finalOffset < -TFRowSwipe.openThreshold || velocity < -TFRowSwipe.openVelocity) {
                    settledOffset = -TFRowActionWidth
                } else if finalOffset > TFRowSwipe.openThreshold || velocity > TFRowSwipe.openVelocity {
                    // Открыть «Удалить» слева — те же пороги, что и для
                    // действия справа. confirmDelete срабатывает по тапу.
                    settledOffset = TFRowActionWidth
                } else {
                    settledOffset = 0
                }
            } else if settledOffset < 0 {
                settledOffset = (dx > TFRowSwipe.closeThreshold || velocity > TFRowSwipe.closeVelocity) ? 0 : -2 * TFRowActionWidth
            } else {
                settledOffset = (dx < -TFRowSwipe.closeThreshold || velocity < -TFRowSwipe.closeVelocity) ? 0 : TFRowActionWidth
            }
            dragOffset = 0
        }
        if settledOffset == 0 {
            TFSwipeRowRegistry.shared.didClose(rowID)
        } else {
            TFSwipeRowRegistry.shared.didOpen(rowID)
        }
    }

    /// «Резина» за пределом раскрытия — веб: `W + over × 30 / (30 + over)`.
    /// По одной кнопке с каждой стороны.
    private func clamp(_ raw: CGFloat) -> CGFloat {
        if raw < 0, swipeAction == nil { return 0 }
        let limit = TFRowActionWidth
        if raw > limit {
            let over = raw - limit
            return limit + (over * 30) / (30 + over)
        } else if raw < -limit {
            let over = -raw - limit
            return -limit - (over * 30) / (30 + over)
        }
        return raw
    }
}

/// Статус агента плоским текстом — дубль `TodayAgentStateTag` (`Features/Today/TodayFilters.swift`,
/// чужой файл), те же тексты/цвета AGENT-PROTOCOL.md.
enum DirectoryAgentStateTag {
    static func text(_ task: ApiTask) -> String? {
        guard let state = task.agentState else { return nil }
        if state == .inProgress, task.agentStale == true { return "Агент пропал" }
        switch state {
        case .inProgress: return "в работе"
        case .blocked: return "заблокировано"
        case .review: return "на проверке"
        case .todo: return "в очереди"
        }
    }

    static func color(_ task: ApiTask) -> Color {
        guard let state = task.agentState else { return .tfTeal }
        if state == .inProgress, task.agentStale == true { return .tfCoral }
        switch state {
        case .inProgress: return .tfTeal
        case .blocked: return .tfOrange
        case .review: return .tfBlue
        case .todo: return .tfSub
        }
    }
}


/// Контекстное действие на свайпе влево (открывается кнопка справа).
/// Решение: владелец видит разное действие в зависимости от того, готов
/// ли он отдать задачу (флаг) или уже отдал (тогда можно сразу принять).
enum ProjectTaskSwipeAction: Equatable {
    /// Поднять флаг готовности (`ready_for_pickup=1`), чтобы агент мог взять.
    case markReadyForPickup
    /// Завершить задачу (зелёная галочка). Показывается для ВСЕХ
    /// не-завершённых задач с поднятым флагом готовности — владелец 11.09.2026
    /// попросил «если флаг поднят и задача не выполнена, всё равно чтобы
    /// галочка была зелёная принять». Покрывает и ревью (снимает блокировку),
    /// и просто активную задачу в пуле.
    case complete

    /// `currentUserID` — у личного дела (исполнитель — сам владелец) сразу
    /// «Принять», а не «Запустить»: запускать там некого (23.09.2026).
    static func action(for task: ApiTask, isOwner: Bool, currentUserID: String? = nil) -> Self? {
        guard isOwner else { return nil }
        guard task.status == .active else { return nil }
        if let me = currentUserID, task.assigneeId == me { return .complete }
        if !task.readyForPickup { return .markReadyForPickup }
        return .complete
    }

    var icon: String {
        switch self {
        case .complete: "checkmark"
        case .markReadyForPickup: "play.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .complete: "Принять"
        case .markReadyForPickup: "Запустить"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .complete: "project.row.swipe.complete"
        case .markReadyForPickup: "project.row.swipe.ready"
        }
    }
}
