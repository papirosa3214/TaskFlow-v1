import SwiftUI
import UniformTypeIdentifiers

// `PendingAttachment` + `TaskAttachmentsController` — живые; view
// `AttachmentsFieldView` архивирован 2026-09-11 в
// archive/task-fields-2026-09-11/ по DEAD-CODE-CLEANUP-REPORT.md (LOCK-120
// убрал TaskDetailScreen, из которого он вызывался).

struct PendingAttachment: Identifiable {
    let id = UUID()
    var fileName: String
    var mime: String
    var data: Data
}

@MainActor
@Observable
final class TaskAttachmentsController {
    var uploaded: [ApiAttachment]
    var pending: [PendingAttachment] = []
    var isUploading = false
    var errorMessage: String?

    private let apiClient: APIClient
    private let taskId: String?

    init(apiClient: APIClient, taskId: String?, existing: [ApiAttachment] = []) {
        self.apiClient = apiClient
        self.taskId = taskId
        self.uploaded = existing
    }

    func add(url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            if let reason = TaskAttachmentDisplay.rejectionReason(fileName: fileName, mime: mime, size: data.count) {
                errorMessage = reason
                return
            }
            if let taskId {
                isUploading = true
                defer { isUploading = false }
                let attachment = try await apiClient.uploadTaskAttachment(
                    taskId: taskId, kind: "task", fileName: fileName, data: data, mime: mime
                )
                uploaded.append(attachment)
            } else {
                pending.append(PendingAttachment(fileName: fileName, mime: mime, data: data))
            }
        } catch {
            errorMessage = "Не удалось приложить файл"
        }
    }

    func removeUploaded(_ attachment: ApiAttachment) async {
        let snapshot = uploaded
        uploaded.removeAll { $0.id == attachment.id }
        do {
            try await apiClient.deleteAttachment(id: attachment.id)
        } catch {
            uploaded = snapshot
            errorMessage = "Не удалось приложить файл"
        }
    }

    func removePending(_ item: PendingAttachment) {
        pending.removeAll { $0.id == item.id }
    }

    /// Вызывается формой ПОСЛЕ того, как задача создана и id стал известен.
    func flushPending(taskId: String) async {
        for item in pending {
            if let attachment = try? await apiClient.uploadTaskAttachment(
                taskId: taskId, kind: "task", fileName: item.fileName, data: item.data, mime: item.mime
            ) {
                uploaded.append(attachment)
            }
        }
        pending.removeAll()
    }
}
