import Foundation

// Задачи из вложения — серверный маршрут `POST /api/attachments/:id/tasks`.
// Сервер вытаскивает из файла ТЕКСТ (txt/md — как есть, pdf — pdftotext,
// doc/docx/odt — libreoffice) и отдаёт его ЛОКАЛЬНОЙ модели, которая
// предлагает список задач (просьба владельца 20.09.2026). Ничего не создаёт:
// подтверждение и создание — в общей шторке `NoteExtractedTasksSheetContent`.
private struct AttachmentTasksResponse: Decodable { let tasks: [ExtractedNoteTask] }

extension APIClient {
    /// Предложить задачи из вложения. Типы, которые сервер умеет читать:
    /// `text/*`, `application/pdf`, Word (`msword`/`openxmlformats`),
    /// OpenDocument. Картинки не поддержаны (OCR — на телефоне).
    func extractTasksFromAttachment(id: String) async throws -> [ExtractedNoteTask] {
        let response: AttachmentTasksResponse = try await request(
            .post, "/attachments/\(id)/tasks"
        )
        return response.tasks
    }
}

/// Умеет ли сервер вытащить текст из этого типа вложения. По этому признаку
/// показываем пункт «Создать задачи»: мёртвых ручек не заводим.
func attachmentSupportsTaskExtraction(mime: String?) -> Bool {
    guard let mime = mime?.lowercased() else { return false }
    if mime.hasPrefix("text/") { return true }
    if mime == "application/pdf" { return true }
    if mime == "application/msword" { return true }
    if mime.hasPrefix("application/vnd.openxmlformats-officedocument") { return true }
    if mime.hasPrefix("application/vnd.oasis.opendocument") { return true }
    return false
}
