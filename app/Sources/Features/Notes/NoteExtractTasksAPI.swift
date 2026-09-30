import Foundation

// «Собрать задачи из текста» (spec/SCREENS-2.md §2 «Меню AI») — отдельный
// AI-эндпоинт, сосед завёл в `NotesAPI.swift` только `journalAssist` для
// трёх других пунктов меню; этот довожу здесь же, чужой файл не трогаю.
// Маршрут подтверждён чтением `server/src/routes/ai.ts` (`POST
// /api/ai/extract-tasks`, тело `{ text }`, ответ `{ tasks: [...] }`).
struct ExtractedNoteTask: Decodable {
    let title: String
    let description: String?
    let priority: Int
    let dueDate: String?

    enum CodingKeys: String, CodingKey {
        case title, description, priority
        case dueDate = "due_date"
    }
}

private struct ExtractTasksResponse: Decodable { let tasks: [ExtractedNoteTask] }

extension APIClient {
    /// Извлечь задачи из текста заметки. `systemPrompt` обычно НЕ передаётся
    /// извне — функция сама подтягивает per-user промпт из
    /// `AIPromptsStore.shared`. Это костыль на время LOCK-142 (markdown
    /// editor), когда `NoteEditorViewModel` заморожен и явная инъекция
    /// стора через DI невозможна; когда LOCK-142 снимут, auto-pull уйдёт
    /// и заменится на обязательный параметр.
    func extractTasksFromNote(text: String, systemPrompt: String? = nil) async throws -> [ExtractedNoteTask] {
        let prompt: String = {
            if let explicit = systemPrompt { return explicit }
            // `AIPromptsStore.shared` — `@MainActor`, читаем со стора.
            // UserDefaults под капотом thread-safe, вызов с любого контекста
            // безопасен; на main переключаться не требуется.
            return MainActor.assumeIsolated { AIPromptsStore.shared.extractTasksPrompt }
        }()
        var body: [String: JSONValue] = ["text": .string(text)]
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            body["system_prompt"] = .string(trimmed)
        }
        let response: ExtractTasksResponse = try await request(.post, "/ai/extract-tasks", body: body)
        return response.tasks
    }
}

/// Ответ сервера на сбор постановки: id родительской карточки, сколько
/// дочерних и как она названа.
struct StructureDraftResult: Decodable {
    let taskID: String
    let children: Int
    let title: String

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case children, title
    }
}

extension APIClient {
    /// Собрать ПОСТАНОВКУ из большого текста (заметка): сервер отдаёт текст
    /// локальной модели ТЕМ ЖЕ контуром, что и надиктовку из чата, и заводит
    /// черновик — родитель + шаги + дочерние карточки со связью `parent_id`.
    /// Запуска не происходит: карточка лежит без флага, владелец поднимает сам.
    func structureDraft(text: String) async throws -> StructureDraftResult {
        let body: [String: JSONValue] = ["text": .string(text)]
        // Локальная модель на большом тексте думает десятки секунд — даём
        // запас, иначе запрос обрывается раньше, чем сервер доведёт работу.
        return try await request(.post, "/ai/structure-draft", body: body, timeout: 300)
    }
}
