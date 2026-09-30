import SwiftUI
import UIKit

// Строка задачи со свайпом — spec/SCREENS-1.md §3.3 + живой `TaskRow.tsx`.
//
// НЕ переиспользует `TFTaskRow` из DesignSystem целиком: тот не умеет
// свайп (влево — «Изменить», вправо — «Удалить») и рисует «Просрочено» БЕЗ
// даты, а живой веб-код (TaskRow.tsx, строка ~549) печатает «Просрочено,
// {formatDueLabel}» — точность спеки важнее переиспользования здесь.
// Мелкие бейджи-примитивы (TFPill/TFPriorityFlag/TFAvatar/цвета) взяты из
// DesignSystem как есть. В отчёте — оркестратору свести оба варианта.
struct TodayTaskRow: View {
    let task: ApiTask
    /// TodayScreen передаёт true для просроченных задач — красная пилюля с датой
    /// вместо обычного бейджа срока (spec: `overdue` проп TaskRow.tsx).
    let overdue: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void
    let swipeAction: TodayTaskSwipeAction?
    let onSwipeAction: () -> Void

    private let actionWidth: CGFloat = TFRowActionWidth
    /// Пороги открытия/закрытия — общие для всех списков, см. `TFRowSwipe`.
    private let openThreshold = TFRowSwipe.openThreshold
    private let openVelocity = TFRowSwipe.openVelocity
    private let closeThreshold = TFRowSwipe.closeThreshold
    private let closeVelocity = TFRowSwipe.closeVelocity
    /// Своё имя в общем реестре раскрытых строк (`TFSwipeRowRegistry`).
    @State private var rowID = UUID()
    /// Точка покоя строки: 0 (закрыта), −actionWidth («Завершить»),
    /// +actionWidth («Удалить»). Двух правых кнопок больше нет — «Перенести»
    /// убрана 09.09.2026.
    @State private var settledOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var confirmDelete = false

    private var offsetX: CGFloat { clamp(settledOffset + dragOffset) }

    var body: some View {
        ZStack {
            // ═══ Действия под строкой ═══
            //
            // Веб (`TaskRow.tsx`, `setRowPosition`) делает три вещи, которых
            // здесь не было, и владелец назвал все три (01.09.2026):
            //
            // 1. Кнопка РАСТЁТ вместе с пальцем: `btnW = max(absX, ACTION_W)`.
            //    Было — фиксированные 84pt, и кнопка выглядела «гораздо меньше
            //    самой карточки».
            // 2. Кнопка ПРОЯВЛЯЕТСЯ по ходу жеста: `opacity = min(1, progress×1.3)`.
            //    Было — `opacity(offsetX > 0 ? 1 : 0)`, то есть «появляется
            //    сразу, а не плавно вылазит».
            // 3. Кнопка занимает ВСЮ высоту строки (`top: 0; bottom: 0`).
            //    Было — фиксированные 70pt независимо от содержимого строки.
            HStack(spacing: 0) {
                actionButton(
                    icon: "trash", label: "Удалить",
                    identifier: "row.swipe.delete", color: .tfSwipeDelete
                ) { close(); confirmDelete = true }
                .frame(width: leftRevealWidth)
                .opacity(revealOpacity(leftRevealWidth))

                Spacer(minLength: 0)

                // «Перенести» из свайпа убрана 09.09.2026: срок ставится в
                // карточке, и отдельная шторка ради того же самого была
                // лишним шагом («это глупости какие-то, оно мне не надо»).
                // Массовый перенос просроченных остался — он в шапке колонки
                // «Просрочено» на доске и карточкой не заменяется.
                if let swipeAction {
                    actionButton(
                        icon: swipeAction.icon,
                        label: swipeAction.accessibilityLabel,
                        identifier: swipeAction.accessibilityIdentifier,
                        color: .tfGreen
                    ) { close(); onSwipeAction() }
                    .frame(width: rightRevealWidth)
                    .opacity(revealOpacity(rightRevealWidth))
                }
            }
            .frame(maxHeight: .infinity)

            row
                // Непрозрачный фон — веб `className="bg-bg"` на строке. Без
                // него текст задачи читался ПОВЕРХ цветной кнопки, когда
                // строка над ней проезжала (владелец: «текст накладывается
                // на цветную кнопку»).
                .background(Color.tfBackground)
                .offset(x: offsetX)
                // Свайп ловит UIKit-распознаватель, а не DragGesture: любой
                // собственный SwiftUI-жест внутри ScrollView забирает касание
                // себе, и список перестаёт листаться пальцем по задаче
                // (владелец, 01.09.2026, третий заход: «скролла нет»).
                // Подробности и числа — HorizontalPan.swift.
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
        // Разделитель под строкой — веб `border-b border-stroke/50`.
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.tfStroke.opacity(0.5))
                .frame(height: TFBorder.width)
        }
        .confirmationDialog("Удалить задачу?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive, action: onDelete)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("«\(task.title)» будет удалена безвозвратно")
        }
    }

    /// Насколько раскрыт левый край (кнопка «Удалить») — прямо за пальцем.
    private var leftRevealWidth: CGFloat { max(offsetX, 0) }
    /// То же для правого края: там одно контекстное действие.
    private var rightRevealWidth: CGFloat { max(-offsetX, 0) }

    /// Проявление кнопки по ходу жеста. Веб: `min(1, (absX / ACTION_W) × 1.3)`
    /// — к трети ширины кнопка уже читается, дальше просто растёт.
    private func revealOpacity(_ width: CGFloat) -> Double {
        min(1, Double(width / actionWidth) * 1.3)
    }

    private func actionButton(
        icon: String, label: String, identifier: String, color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: TFIconSize.md))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(color)
        }
        .buttonStyle(.plain)
        // Иконка не должна вылезать за узкую кнопку в начале жеста.
        .clipped()
        // Кнопка доступна для нажатия, только когда раскрыта заметно —
        // веб: `pointerEvents = absX >= ACTION_W * 0.7 ? "auto" : "none"`.
        .allowsHitTesting(abs(offsetX) >= actionWidth * 0.7)
        .accessibilityHidden(abs(offsetX) < actionWidth * 0.7)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var row: some View {
        Button {
            if settledOffset != 0 {
                close()
            } else {
                onOpen()
            }
        } label: {
            HStack(alignment: .top, spacing: TFSpacing.md) {
            if let initials = task.assigneeInitials, task.assigneeId != nil {
                TFAvatar(size: .taskList, initials: initials, tint: Color(hex: task.assigneeColor ?? TFHexDefault.unassigned), userID: task.assigneeId)
                    .padding(.top, task.projectName == nil ? 0 : 16)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let projectName = task.projectName {
                    HStack(spacing: 3) {
                        Image(systemName: "number")
                            .font(.system(size: 10))
                        Text(projectName)
                    }
                    .tfText(.caption)
                    .foregroundStyle(Color(hex: task.projectColor ?? TFHexDefault.unassigned))
                    .lineLimit(1)
                }

                HStack(spacing: TFSpacing.sm) {
                    Text(task.title)
                        .tfText(.body)
                        .foregroundStyle(task.status == .completed ? Color.tfSub : Color.tfText)
                        .strikethrough(task.status == .completed)
                        .lineLimit(1)
                }

                if let description = task.description, !description.isEmpty {
                    Text(description)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(2)
                }

                if let agentText = TodayAgentStateTag.text(task) {
                    Text(agentText)
                        .tfText(.meta)
                        .foregroundStyle(TodayAgentStateTag.color(task))
                }

                if hasBadges {
                    HStack(spacing: TFSpacing.xs) {
                        if !task.subtasks.isEmpty {
                            let done = task.subtasks.count { $0.done }
                            TFPill("\(done)/\(task.subtasks.count)", color: .tfSub, solidBackground: .tfCard)
                        }
                        if task.childrenCount > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "person.2")
                                Text("\(task.childrenCount)")
                            }
                            .tfText(.caption)
                            .foregroundStyle(Color.tfSub)
                            .padding(.horizontal, TFSpacing.sm)
                            .padding(.vertical, 2)
                            .background(Color.tfCard)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
                        }
                        if task.hasCollaborationPlan {
                            TFAccentTag("ПЛАН", color: .tfPurple)
                        }
                        if overdue, let due = task.dueDate {
                            TFPill("Просрочено, \(TodayDate.formatDueLabel(due))", color: .tfRed, backgroundOpacity: 0.15)
                        } else if let due = task.dueDate {
                            HStack(spacing: 3) {
                                Text(TodayDate.formatDuePlain(due))
                                Text("· \(TodayDate.formatDaysLeft(due))")
                                    .foregroundStyle(TodayDate.daysUntil(due) <= 3 ? Color.tfOrange : Color.tfDim)
                            }
                            .tfText(.caption)
                            .foregroundStyle(Color.tfSub)
                            .padding(.horizontal, TFSpacing.sm)
                            .padding(.vertical, 2)
                            .background(Color.tfCard)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
                        }
                        ForEach(task.labels, id: \.id) { label in
                            TFLabelPill(label.name, color: Color(hex: label.color ?? TFHexDefault.unassigned))
                        }
                    }
                }
            }
                Spacer(minLength: 0)
                // Приоритет — стопкой шевронов у правого края: сбоку он не
                // толкает бейджи и целиком помещается по высоте строки.
                if let priority = TaskPriority(rawValue: task.priority) {
                    TFPriorityArrows(priority)
                }
            }
            .padding(.top, 9)
            .padding(.bottom, 12)
            .padding(.horizontal, TFSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TFTapRowStyle())
        // ⚠️ Порядок важен: `accessibilityElement(children:)` создаёт НОВЫЙ
        // элемент и отбрасывает всё, что задано до него, — идентификатор,
        // поставленный выше, молча пропадал, и тесты не находили строку.
        // Сначала собираем элемент, потом даём ему имя и идентификатор.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityIdentifier("today.task-row")
        // Строка ЯВЛЯЕТСЯ кнопкой, но `children: .ignore` собирает новый
        // элемент и трейт кнопки при этом теряется: в дереве строка
        // становится «Other», VoiceOver не говорит «кнопка», а тесты её не
        // находят среди `app.buttons`. Трейт возвращаем руками.
        .accessibilityAddTraits(.isButton)
    }

    private var hasBadges: Bool {
        !task.subtasks.isEmpty || TaskPriority(rawValue: task.priority) != nil
            || overdue || task.dueDate != nil || !task.labels.isEmpty
            || task.childrenCount > 0 || task.hasCollaborationPlan
    }

    /// Короткое имя для VoiceOver: название задачи, опционально проект.
    /// Без проекта и бейджей — одна строка; с проектом — «Проект, Задача».
    private var rowAccessibilityLabel: String {
        if let projectName = task.projectName, !projectName.isEmpty {
            return "\(projectName), \(task.title)"
        }
        return task.title
    }

    private func close() {
        withAnimation(TFRowSwipe.settleAnimation(velocity: 0)) {
            settledOffset = 0
            dragOffset = 0
        }
        TFSwipeRowRegistry.shared.didClose(rowID)
    }

    /// Куда строка встаёт после жеста. Числа — из веба (`useRowSwipe.ts`):
    /// открытие при сдвиге >36px ИЛИ броске >280px/с, закрытие встречным
    /// движением >25px или >250px/с, «резина» за пределом — в `clamp`.
    ///
    /// Скорость здесь настоящая, от UIKit (px/с). Раньше она бралась как
    /// `predictedEndTranslation − translation` у SwiftUI-жеста — это НЕ px/с,
    /// а прогноз доката в пикселях, и сравнение с веб-порогом 280 срабатывало
    /// невпопад: бросок открывал строку через раз.
    private func settle(dx: CGFloat, velocity: CGFloat) {
        let finalOffset = clamp(settledOffset + dx)
        withAnimation(TFRowSwipe.settleAnimation(velocity: velocity)) {
            if settledOffset == 0 {
                // Влево — одно действие, зависящее от состояния задачи.
                if swipeAction != nil && (finalOffset < -openThreshold || velocity < -openVelocity) {
                    settledOffset = -actionWidth
                } else if finalOffset > openThreshold || velocity > openVelocity {
                    settledOffset = actionWidth
                } else {
                    settledOffset = 0
                }
            } else if settledOffset < 0 {
                // Открыто — закрываем встречным движением.
                settledOffset = (dx > closeThreshold || velocity > closeVelocity) ? 0 : -2 * actionWidth
            } else {
                settledOffset = (dx < -closeThreshold || velocity < -closeVelocity) ? 0 : actionWidth
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
        let limit = actionWidth
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

/// Смысл левого свайпа в общем списке задач. В подложке только иконка;
/// полное имя остаётся VoiceOver через `accessibilityLabel`.
enum TodayTaskSwipeAction: Equatable {
    case complete
    case acceptReview
    case markReadyForPickup

    /// `currentUserID` — чтобы у личного дела (исполнитель — сам владелец)
    /// был «Завершить», а не «Запустить»: запускать там некого (23.09.2026).
    static func action(for task: ApiTask, isOwner: Bool, currentUserID: String? = nil) -> Self? {
        guard task.status == .active else { return nil }
        if isOwner, task.agentState == .review { return .acceptReview }
        if let me = currentUserID, task.assigneeId == me { return .complete }
        if isOwner, task.agentState == nil, !task.readyForPickup { return .markReadyForPickup }
        return .complete
    }

    var icon: String {
        switch self {
        case .complete, .acceptReview: "checkmark"
        case .markReadyForPickup: "play.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .complete: "Завершить"
        case .acceptReview: "Принять"
        case .markReadyForPickup: "Запустить"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .complete: "row.swipe.complete"
        case .acceptReview: "row.swipe.accept"
        case .markReadyForPickup: "row.swipe.ready"
        }
    }
}

// RowHeightKey был удалён вместе с GeometryReader — измерение высоты через
// PreferenceKey вызывало двойной рендер (открытие «Сегодня» 2.44с вместо <2с).
// Высота кнопок свайпа больше не измеряется вовсе: они растягиваются на
// высоту ZStack (`frame(maxHeight: .infinity)`), которую задаёт сама строка,
// — как в вебе, где кнопка прибита `top: 0; bottom: 0`.
