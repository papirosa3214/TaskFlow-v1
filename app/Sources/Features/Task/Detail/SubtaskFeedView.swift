import SwiftUI

// `SubtaskFeed` — spec/SCREENS-2.md §19.1 (компонент карточки задачи,
// описан в чужой половине спеки, но физически смонтирован здесь — раздел
// прямо адресован «параллельному агенту», то есть этому экрану).
struct SubtaskFeedView: View {
    let subtasks: [ApiSubtask]
    let isOwner: Bool
    var onToggleDone: (ApiSubtask) -> Void
    var onSubmitReply: (ApiSubtask, String) -> Void
    var onAccept: (ApiSubtask) -> Void

    @State private var expandedId: String?
    @State private var replyingId: String?
    @State private var replyText = ""

    /// Публично — TaskFormScreen 02.09.2026 сам показывает «N из M» в
    /// заголовке своей сворачиваемой секции (заголовок «Подзадачи» отсюда
    /// убран, дублировал бы её же).
    var doneCount: Int { subtasks.count { $0.done } }

    // Была обёрнута в `TFFieldGroup` (карточка-фон, тот же приём, что у
    // группы «Срок/Проект/Приоритет/Метки») — просьба владельца 03.09.2026:
    // «заметка не в фоне, название не в фоне — а подзадача почему в фоне?»
    // `TFFieldGroup` не трогаю (общий компонент, та группа полей — другое,
    // её не касалось), здесь просто больше не оборачиваю в неё.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, subtask in
                row(subtask)
                if index != subtasks.count - 1 { TFFieldDivider() }
            }
        }
    }

    private func ringState(_ subtask: ApiSubtask) -> TFSubtaskState {
        switch subtask.state {
        case .done: .done
        case .running: .running
        case .blocked: .blocked
        case .review: .review
        case .pending, .none: .pending
        }
    }

    /// Есть что показывать при раскрытии — текст результата или блокировка.
    private func hasDetails(_ subtask: ApiSubtask) -> Bool {
        (subtask.result?.isEmpty == false) || subtask.agentState == .blocked
    }

    private func row(_ subtask: ApiSubtask) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: TFField.iconTextGap) {
                Button {
                    guard subtask.agentState != .review else { return } // review не реагирует на тап
                    onToggleDone(subtask)
                } label: {
                    TFSubtaskStatusRing(ringState(subtask))
                }
                .buttonStyle(TFTapScaleStyle())
                // Подпись («Готово»/«Выполняется»/…) приходит от самого кольца,
                // здесь — только описание ДЕЙСТВИЯ, иначе VoiceOver читает
                // «Готово, кнопка» без понимания, что произойдёт по тапу.
                .accessibilityHint(subtask.agentState == .review ? "" : "Отмечает шаг выполненным")

                // Было `.strikethrough(subtask.done)` — просьба владельца
                // 03.09.2026: «не надо зачёркивать, я не вижу, как называется
                // подзадача». Приглушённый цвет (`tfSub`) один и так
                // достаточно сигналит «готово», не мешая читать текст.
                //
                // Выравнивание по ширине пробовали и отменили — владелец
                // 03.09.2026: «нет инструмента, хрен с ним как есть» (justify
                // на технических «словах без пробелов» вроде имён файлов
                // растягивал буквы внутри слова). Обычный `Text`.
                Text(subtask.title)
                    .tfText(.body)
                    .foregroundStyle(subtask.done ? Color.tfSub : Color.tfText)
                Spacer()
                if hasDetails(subtask) {
                    Image(systemName: expandedId == subtask.id ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.tfDim)
                }
            }
            .padding(.horizontal, TFField.cardInsetH)
            .frame(minHeight: TFField.height)
            .contentShape(Rectangle())
            .onTapGesture {
                guard hasDetails(subtask) else { return }
                withAnimation(.easeInOut(duration: TFDuration.fast)) {
                    expandedId = expandedId == subtask.id ? nil : subtask.id
                }
            }

            if expandedId == subtask.id {
                expandedContent(subtask)
                    .padding(.horizontal, TFField.cardInsetH)
                    .padding(.bottom, TFSpacing.md)
            }
        }
    }

    @ViewBuilder
    private func expandedContent(_ subtask: ApiSubtask) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            if let result = subtask.result, !result.isEmpty {
                Text(result).tfText(.action).foregroundStyle(Color.tfSub)
            }
            if replyingId == subtask.id {
                replyForm(subtask)
            } else if isOwner {
                ownerActions(subtask)
            }
        }
    }

    @ViewBuilder
    private func ownerActions(_ subtask: ApiSubtask) -> some View {
        HStack(spacing: TFSpacing.sm) {
            if subtask.agentState == .review {
                TFButton("Принять", icon: "checkmark", variant: .primary) { onAccept(subtask) }
                TFButton("Вернуть", variant: .secondary) { startReply(subtask) }
            } else if subtask.agentState == .blocked {
                TFButton("Ответить", variant: .secondary) { startReply(subtask) }
            }
        }
    }

    private func replyForm(_ subtask: ApiSubtask) -> some View {
        // Упрощённая ReplyForm — только текст, без микрофона/файла (спека
        // §19.1 их тоже предполагает, но диктовки в этой волне нет нигде —
        // см. отчёт `NATIVE-PARTS.md`).
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFTextField("Ответ…", text: $replyText)
            HStack(spacing: TFSpacing.sm) {
                TFButton("Отправить", variant: .primary, isEnabled: !replyText.trimmingCharacters(in: .whitespaces).isEmpty) {
                    onSubmitReply(subtask, replyText)
                    replyText = ""
                    replyingId = nil
                }
                TFButton("Отмена", variant: .outline) {
                    replyText = ""
                    replyingId = nil
                }
            }
        }
    }

    private func startReply(_ subtask: ApiSubtask) {
        replyText = ""
        replyingId = subtask.id
    }
}
