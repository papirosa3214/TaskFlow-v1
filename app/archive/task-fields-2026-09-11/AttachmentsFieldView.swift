import SwiftUI

// Архивировано 2026-09-11 по DEAD-CODE-CLEANUP-REPORT.md.
// Раньше view вызывался из TaskFormScreen и TaskDetailScreen (LOCK-120
// удаляет TaskDetailScreen, TaskFormScreen переехал на нативный шторку).

struct AttachmentsFieldView: View {
    @Bindable var controller: TaskAttachmentsController
    /// 02.09.2026, владелец: в `TaskFormScreen` при правке строка «Прикрепить
    /// файл» переехала пунктом в «…» (сама же кнопка вечно занимала место,
    /// даже когда файлов нет). `QuickAddTaskView` не трогаем — там своя
    /// строка нужна как была, поэтому параметр опциональный.
    var showAddButton: Bool = true
    @State private var isPickerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Файлы").tfText(.title).foregroundStyle(Color.tfText)

            ForEach(controller.uploaded) { attachment in
                row(icon: TaskAttachmentDisplay.icon(mime: attachment.mime), name: attachment.fileName,
                    size: TaskAttachmentDisplay.sizeText(attachment.size)) {
                    Task { await controller.removeUploaded(attachment) }
                }
            }
            ForEach(controller.pending) { item in
                row(icon: TaskAttachmentDisplay.icon(mime: item.mime), name: item.fileName,
                    size: TaskAttachmentDisplay.sizeText(item.data.count)) {
                    controller.removePending(item)
                }
            }

            TFErrorBanner(controller.errorMessage, variant: .inline)

            if showAddButton {
                Button {
                    isPickerPresented = true
                } label: {
                    HStack(spacing: TFField.iconTextGap) {
                        Image(systemName: "paperclip")
                            .font(.system(size: TFIconSize.sm))
                            .foregroundStyle(Color.tfDim)
                        Text(controller.isUploading ? "Загружаю…" : "Прикрепить файл")
                            .tfText(.body)
                            .foregroundStyle(Color.tfText)
                        Spacer()
                    }
                    .padding(.horizontal, TFField.cardInsetH)
                    .frame(height: TFField.height)
                    .background(Color.tfCard)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                }
                .buttonStyle(TFTapRowStyle())
                .disabled(controller.isUploading)
            }
        }
        .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                Task { await controller.add(url: url) }
            }
        }
    }

    private func row(icon: String, name: String, size: String?, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: TFField.iconTextGap) {
            Image(systemName: icon)
                .font(.system(size: TFIconSize.sm))
                .foregroundStyle(Color.tfDim)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).tfText(.body).foregroundStyle(Color.tfText).lineLimit(1)
                if let size {
                    Text(size).tfText(.action).foregroundStyle(Color.tfSub)
                }
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .tfText(.row)
                    .foregroundStyle(Color.tfDim)
                    .frame(width: TFHitTarget.min, height: TFHitTarget.min)
            }
            .buttonStyle(TFTapScaleStyle())
        }
        .padding(.horizontal, TFField.cardInsetH)
        .frame(minHeight: TFField.height)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
    }
}
