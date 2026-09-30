import SwiftUI

// Подзадачи формы — spec/SCREENS-1.md §3.7/§5.5.
//
// Два режима были реализованы отдельными view (`SubtaskDraftListView` — create,
// `SubtaskEditListView` — edit). Оба архивированы 2026-09-11 в
// archive/task-fields-2026-09-11/ по DEAD-CODE-CLEANUP-REPORT.md; текущая форма
// работает только с моделью `SubtaskDraft` и полем ввода `AddSubtaskRow`.

struct SubtaskDraft: Identifiable, Equatable {
    let id = UUID()
    var title: String
}

/// `AddSubtaskRow` — spec §3.7: плейсхолдер «Добавить подзадачу...», галочка
/// справа появляется только когда в поле есть текст, Enter добавляет и чистит поле.
///
/// Была в карточке (`Color.tfCard` + скруглённый фон) — просьба владельца
/// 03.09.2026: «название задачи без оболочки, описание без оболочки —
/// подзадача тоже должна быть без оболочки, это всё текстовые вещи,
/// должно быть однородно». Фон убран — тот же голый текстовый ввод, что у
/// названия/описания задачи.
struct AddSubtaskRow: View {
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: TFField.iconTextGap) {
            TextField("", text: $text, prompt: Text("Добавить подзадачу...").foregroundStyle(Color.tfDim))
                .tfText(.input)
                .foregroundStyle(Color.tfText)
                .onSubmit(onSubmit)
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: onSubmit) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.tfRed)
                        .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                }
                .buttonStyle(TFTapScaleStyle())
            }
        }
        .frame(minHeight: TFField.height)
    }
}
