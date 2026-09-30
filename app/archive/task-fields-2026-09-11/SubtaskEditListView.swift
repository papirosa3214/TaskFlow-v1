import SwiftUI

// Архивировано 2026-09-11 по DEAD-CODE-CLEANUP-REPORT.md.
// Раньше — режим edit в SubtaskFormFieldView.swift; вызывающий (TaskFormScreen)
// больше его не использует, см. LOCK-093.

/// Режим **edit** — строки с сервера, перетаскивание/переименование/удаление.
struct SubtaskEditListView: View {
    let subtasks: [ApiSubtask]
    var onReorder: ([ApiSubtask]) -> Void
    var onRename: (ApiSubtask, String) -> Void
    var onDelete: (ApiSubtask) -> Void
    var onAdd: (String) -> Void

    @State private var newTitle = ""
    @State private var renamingId: String?
    @State private var renameText = ""

    var body: some View {
        // 02.09.2026: заголовок «Подзадачи» отсюда убран — та же причина,
        // что у `SubtaskDraftListView` выше.
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            ForEach(subtasks) { subtask in
                row(subtask)
                    .draggable(subtask.id)
                    .dropDestination(for: String.self) { droppedIds, _ in
                        handleDrop(draggedId: droppedIds.first, ontoId: subtask.id)
                    }
            }
            AddSubtaskRow(text: $newTitle) {
                let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onAdd(trimmed)
                newTitle = ""
            }
        }
    }

    private func handleDrop(draggedId: String?, ontoId: String) -> Bool {
        guard let draggedId, draggedId != ontoId,
              let fromIndex = subtasks.firstIndex(where: { $0.id == draggedId }),
              let toIndexRaw = subtasks.firstIndex(where: { $0.id == ontoId }) else { return false }
        var reordered = subtasks
        let item = reordered.remove(at: fromIndex)
        let insertIndex = toIndexRaw > fromIndex ? toIndexRaw - 1 : toIndexRaw
        reordered.insert(item, at: insertIndex)
        onReorder(reordered)
        return true
    }

    private func row(_ subtask: ApiSubtask) -> some View {
        HStack(spacing: TFField.iconTextGap) {
            TFCheckbox(isChecked: subtask.done)
                .allowsHitTesting(false)

            if renamingId == subtask.id {
                TextField("", text: $renameText)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .onSubmit { commitRename(subtask) }
            } else {
                Text(subtask.title)
                    .tfText(.body)
                    .foregroundStyle(subtask.done ? Color.tfSub : Color.tfText)
                    .onTapGesture {
                        renamingId = subtask.id
                        renameText = subtask.title
                    }
            }
            Spacer()
            Button {
                onDelete(subtask)
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

    private func commitRename(_ subtask: ApiSubtask) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingId = nil
        guard !trimmed.isEmpty, trimmed != subtask.title else { return }
        onRename(subtask, trimmed)
    }
}
