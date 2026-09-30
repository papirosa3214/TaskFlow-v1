import Foundation
import Observation

/// Локальный кеш и серверная синхронизация per-user системных промптов для
/// серверной модели.
///
/// UI (например, `VoiceModelsScreen`) читает/правит `extractTasksPrompt` и
/// `journalAssistPrompt` через `@Bindable`-обёртку над стором. На изменение
/// срабатывает debounce-сохранение: сначала в UserDefaults (чтобы перезапуск
/// приложения не терял черновик), потом — `PUT /api/ai/prompts/:scope`.
///
/// `NoteExtractTasksAPI.extractTasksFromNote(text:)` сам подтягивает
/// `extractTasksPrompt` из стора, чтобы не пришлось править чужой файл
/// `NoteEditorViewModel` (LOCK-142, владелец ещё не закрыл). Когда LOCK-142
/// снимут, этот auto-pull уберётся и заменится на явный DI.
///
/// Серверная часть (`dcd03225`, ещё не реализована) при успехе перезапишет
/// локальный кеш — на случай рассинхрона после ручной правки через веб.
@MainActor
@Observable
final class AIPromptsStore {
    static let shared = AIPromptsStore()

    /// Общепринятые scope'ы — расширяемый список. Клиент знает только те, что
    /// ему нужны; сервер может принимать любые строки в `scope`.
    static let scopeExtractTasks = "extract_tasks"
    static let scopeJournalAssist = "journal_assist"
    /// Промпт расшифровки действий агента — читает серверный observer
    /// (`activity.ts`), подмешивая его вместо штатного, когда он задан.
    static let scopeActivity = "activity"
    /// Слой владельца «как собирать постановку» — стиль названия, глубина
    /// разбиения, когда одна карточка, а когда дерево. Читает серверный
    /// `structureDictationToCards` (`scope task_intake`); формат ответа
    /// пользователь всё равно переопределить не может — только смысл.
    static let scopeTaskIntake = "task_intake"

    private static let extractTasksKey = "taskflow_ai_prompt_extract_tasks"
    private static let journalAssistKey = "taskflow_ai_prompt_journal_assist"
    private static let activityKey = "taskflow_ai_prompt_activity"
    private static let taskIntakeKey = "taskflow_ai_prompt_task_intake"

    /// Последняя ошибка сохранения — `nil`, если синхронизировано. UI
    /// показывает её рядом с полем как «не сохранено: <причина>».
    var lastSaveError: String?

    /// Штатные серверные промпты по скоупам (с сервера). Показываются
    /// placeholder'ом в окошке, чтобы владелец видел системный промпт целиком.
    var defaultPrompts: [String: String] = [:]

    /// Дефолт для скоупа — то, что уходит в модель, когда поле пустое.
    func defaultPrompt(for scope: String) -> String? {
        defaultPrompts[scope].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `true`, пока идёт фоновая синхронизация при старте.
    private(set) var isRefreshing = false

    var extractTasksPrompt: String {
        didSet { onPromptChanged(scope: Self.scopeExtractTasks, key: Self.extractTasksKey, value: extractTasksPrompt) }
    }
    var journalAssistPrompt: String {
        didSet { onPromptChanged(scope: Self.scopeJournalAssist, key: Self.journalAssistKey, value: journalAssistPrompt) }
    }
    var activityPrompt: String {
        didSet { onPromptChanged(scope: Self.scopeActivity, key: Self.activityKey, value: activityPrompt) }
    }
    var taskIntakePrompt: String {
        didSet { onPromptChanged(scope: Self.scopeTaskIntake, key: Self.taskIntakeKey, value: taskIntakePrompt) }
    }

    private let api: APIClient

    /// Инициализируется один раз — singleton, потому что к нему ходят и UI
    /// (`VoiceModelsScreen` через `@Environment`), и сервисный слой
    /// (`extractTasksFromNote` без `@Environment`-инъекции).
    private init(api: APIClient = APIClient()) {
        self.api = api
        extractTasksPrompt = UserDefaults.standard.string(forKey: Self.extractTasksKey) ?? ""
        journalAssistPrompt = UserDefaults.standard.string(forKey: Self.journalAssistKey) ?? ""
        activityPrompt = UserDefaults.standard.string(forKey: Self.activityKey) ?? ""
        taskIntakePrompt = UserDefaults.standard.string(forKey: Self.taskIntakeKey) ?? ""
    }

    /// Фоновая синхронизация с сервера. Дёргается при старте экрана настроек.
    /// Молча игнорирует сетевые ошибки — пользователь увидит локальный кеш,
    /// и когда связь появится, refresh вручную или повторное открытие экрана
    /// довыгрузит.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let payload = try await api.aiUserPrompts()
            defaultPrompts = payload.defaults
            for entry in payload.prompts {
                switch entry.scope {
                case Self.scopeExtractTasks:
                    if entry.prompt != extractTasksPrompt {
                        extractTasksPrompt = entry.prompt
                        UserDefaults.standard.set(entry.prompt, forKey: Self.extractTasksKey)
                    }
                case Self.scopeJournalAssist:
                    if entry.prompt != journalAssistPrompt {
                        journalAssistPrompt = entry.prompt
                        UserDefaults.standard.set(entry.prompt, forKey: Self.journalAssistKey)
                    }
                case Self.scopeActivity:
                    if entry.prompt != activityPrompt {
                        activityPrompt = entry.prompt
                        UserDefaults.standard.set(entry.prompt, forKey: Self.activityKey)
                    }
                case Self.scopeTaskIntake:
                    if entry.prompt != taskIntakePrompt {
                        taskIntakePrompt = entry.prompt
                        UserDefaults.standard.set(entry.prompt, forKey: Self.taskIntakeKey)
                    }
                default:
                    break
                }
            }
            lastSaveError = nil
        } catch {
            // Сеть или «API не реализован» — НЕ паникуем: локальный кеш есть.
            // Если сервер вернул 404 (карточка dcd03225 ещё не залита) — это
            // ожидаемо, флаг ошибки НЕ выставляем.
            let nsError = error as NSError
            if nsError.domain == "APIError" || nsError.code == 404 {
                return
            }
            lastSaveError = (error as? LocalizedError)?.errorDescription ?? "Не удалось синхронизировать промпты"
        }
    }

    /// Сохранить промпт для extract-tasks. Сейчас вызывается из `didSet`,
    /// но сделано отдельным методом для удобства тестов и ручного «Сохранить».
    func saveExtractTasksPrompt() async {
        await save(scope: Self.scopeExtractTasks, key: Self.extractTasksKey, value: extractTasksPrompt)
    }

    func saveJournalAssistPrompt() async {
        await save(scope: Self.scopeJournalAssist, key: Self.journalAssistKey, value: journalAssistPrompt)
    }

    func saveActivityPrompt() async {
        await save(scope: Self.scopeActivity, key: Self.activityKey, value: activityPrompt)
    }

    func saveTaskIntakePrompt() async {
        await save(scope: Self.scopeTaskIntake, key: Self.taskIntakeKey, value: taskIntakePrompt)
    }

    // MARK: - Внутреннее

    /// `didSet` срабатывает СИНХРОННО при каждом нажатии клавиши в `TextEditor`.
    /// Поэтому сам `didSet` только кладёт значение в UserDefaults (мгновенно,
    /// без сети) и запускает фоновую задачу отложенной отправки.
    private func onPromptChanged(scope: String, key: String, value: String) {
        UserDefaults.standard.set(value, forKey: key)
        lastSaveError = nil
        // Сохранение на сервер идёт через явные `save*` — это решение UI
        // (debounce 0.6с), а не дёргать сеть на каждое нажатие клавиши.
    }

    private func save(scope: String, key: String, value: String) async {
        do {
            let updated = try await api.setAIUserPrompt(scope: scope, prompt: value)
            // Сервер мог привести строку (trim, валидация) — переписываем
            // локальный кеш актуальным значением.
            UserDefaults.standard.set(updated.prompt, forKey: key)
            switch scope {
            case Self.scopeExtractTasks:
                if updated.prompt != extractTasksPrompt {
                    extractTasksPrompt = updated.prompt
                }
            case Self.scopeJournalAssist:
                if updated.prompt != journalAssistPrompt {
                    journalAssistPrompt = updated.prompt
                }
            case Self.scopeActivity:
                if updated.prompt != activityPrompt {
                    activityPrompt = updated.prompt
                }
            case Self.scopeTaskIntake:
                if updated.prompt != taskIntakePrompt {
                    taskIntakePrompt = updated.prompt
                }
            default: break
            }
            lastSaveError = nil
        } catch {
            // 404 от сервера — карточка dcd03225 ещё не залита, это не ошибка UX.
            let nsError = error as NSError
            if nsError.code == 404 {
                return
            }
            lastSaveError = (error as? LocalizedError)?.errorDescription ?? "Не удалось сохранить промпт"
        }
    }
}
