import SwiftUI

// Архивировано 2026-09-11 по DEAD-CODE-CLEANUP-REPORT.md.
// Раньше — режим create в SubtaskFormFieldView.swift; вызывающий (TaskFormScreen)
// теперь работает только с живым SubtaskDraft + AddSubtaskRow, без view-обёртки.

/// Режим **create** — локальный массив, без сети.
struct SubtaskDraftListView: View {
    @Binding var drafts: [SubtaskDraft]
    @State private var newTitle = ""

    var body: some View {
        // 02.09.2026: заголовок «Подзадачи» отсюда убран — секцию теперь
        // подписывает и сворачивает `TFCollapsibleSection` в TaskFormScreen
        // (единственный вызывающий), дублировать не нужно.
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            ForEach(drafts) { draft in
                draftRow(draft)
            }
            addRow
        }
    }

    private func draftRow(_ draft: SubtaskDraft) -> some View {
        HStack(spacing: TFField.iconTextGap) {
            Text(draft.title).tfText(.body).foregroundStyle(Color.tfText)
            Spacer()
            Button {
                drafts.removeAll { $0.id == draft.id }
            } label: {
                Image(systemName: "xmark").font(.system(size: TFIconSize.xs)).foregroundStyle(Color.tfDim)
                    .frame(width: TFHitTarget.min, height: TFHitTarget.min)
            }
            .buttonStyle(TFTapScaleStyle())
        }
        .padding(.horizontal, TFField.cardInsetH)
        .frame(minHeight: TFField.height)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
    }

    private var addRow: some View {
        AddSubtaskRow(text: $newTitle) {
            let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            drafts.append(SubtaskDraft(title: trimmed))
            newTitle = ""
        }
    }
}
