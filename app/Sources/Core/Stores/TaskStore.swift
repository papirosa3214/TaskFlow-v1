import Foundation
import Observation

/// Стор задач — загрузка, кэш в памяти, оптимистичные изменения с откатом,
/// приём реалтайм-событий. spec/API.md §8: у веба списки инвалидируются
/// целиком при любой мутации (react-query, довольно грубо) — здесь сделано
/// ТОЧЕЧНО (заменить/добавить/убрать один элемент), это не расхождение с
/// контрактом сервера, только другая (более дешёвая) стратегия кэша на
/// стороне клиента, спека явно разрешает это решать автору клиента.
@MainActor
@Observable
public final class TaskStore {
    public private(set) var tasks: [ApiTask] = []
    /// Тот же список, но С ДОЧЕРНИМИ (`include_children`). Только для плиток
    /// «Обзора» и «Работы агентов»: работу там ведут именно дочерние, а в
    /// `tasks` сервер кладёт лишь те из них, у кого есть проект — дочерняя
    /// «в работе» в плитках не считалась (владелец 22.09.2026). `tasks` не
    /// расширяем: иначе дочерние вывалились бы строками во все списки.
    public private(set) var agentWorkTasks: [ApiTask] = []
    public private(set) var isLoading = false
    public var errorMessage: String?

    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// `silent` — обновление в фоне, без спиннера. Нужно для рефетча после
    /// переподключения: спиннер вставлялся блоком в начало ленты, список
    /// прыгал, и владелец видел это как «экран моргает сам по себе».
    public func load(silent: Bool = false) async {
        if !silent { isLoading = true }
        errorMessage = nil
        defer { if !silent { isLoading = false } }
        async let withChildren = apiClient.tasks(includeChildren: true)
        do {
            tasks = try await apiClient.tasks()
        } catch is CancellationError {
            // Экран перезапросил список раньше, чем доехал предыдущий заход
            // (смена формата «Список»/«Один день», быстрый повторный вход) —
            // отмена штатная, банер «Сеть недоступна» тут ни при чём.
        } catch {
            errorMessage = Self.message(for: error)
        }
        do {
            agentWorkTasks = try await withChildren
        } catch is CancellationError {
            // см. комментарий выше
        } catch {
            errorMessage = errorMessage ?? Self.message(for: error)
        }
    }

    /// Партиальная правка с оптимистичным откликом: локальная копия меняется
    /// СРАЗУ через `apply`, запрос уходит в фоне; при ошибке — откат к
    /// снимку до правки (spec §8: у веба это точечный приём, не универсальный,
    /// используется в первую очередь для быстрых визуальных изменений вроде
    /// перетаскивания — здесь доступен любому вызывающему коду).
    @discardableResult
    public func patch(taskId: String, fields: [String: JSONValue], apply: (inout ApiTask) -> Void) async -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return false }
        let snapshot = tasks[index]
        apply(&tasks[index])
        do {
            let updated = try await apiClient.patchTask(id: taskId, fields: fields)
            if let freshIndex = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[freshIndex] = updated
            }
            return true
        } catch {
            // Сервер не знает такой задачи — значит наш список протух: её
            // успели удалить в другом месте, а строка ещё висит на экране.
            // Пугать этим владельца незачем (15.09.2026: «пишет, что она
            // удалена, но она не удалена» — путаница шла именно отсюда):
            // просто убираем строку и подтягиваем свежий список.
            if Self.isMissingRecord(error) {
                tasks.removeAll { $0.id == taskId }
                await load(silent: true)
                return false
            }
            if let freshIndex = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[freshIndex] = snapshot
            }
            errorMessage = Self.message(for: error)
            return false
        }
    }

    @discardableResult
    public func create(_ payload: APIClient.NewTaskRequest) async -> ApiTask? {
        do {
            let created = try await apiClient.createTask(payload)
            tasks.append(created)
            return created
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    @discardableResult
    public func delete(taskId: String) async -> Bool {
        let snapshot = tasks
        tasks.removeAll { $0.id == taskId }
        do {
            try await apiClient.deleteTask(id: taskId)
            return true
        } catch {
            // Задачи на сервере уже нет — цель удаления и так достигнута,
            // возвращать строку на экран и ругаться незачем.
            if Self.isMissingRecord(error) { return true }
            tasks = snapshot
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// Приём событий `RealtimeClient.onEvent` — вызывающая сторона (обычно
    /// `TaskFlowApp`) подписывает этот метод один раз при старте.
    public func apply(_ event: RealtimeEvent) {
        switch event {
        case .taskCreated(let task), .taskUpdated(let task), .taskCompleted(let task), .taskState(let task):
            upsert(task)
        case .taskDeleted(let id):
            tasks.removeAll { $0.id == id }
            agentWorkTasks.removeAll { $0.id == id }
        default:
            break
        }
    }

    /// После восстановления связи (`RealtimeClient.onReconnected`) — сервер
    /// не хранит очередь пропущенного за время разрыва (spec §4.2), поэтому
    /// полный рефетч, а не точечная синхронизация.
    public func refreshAfterReconnect() async {
        await load(silent: true)
    }

    private func upsert(_ task: ApiTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        if let index = agentWorkTasks.firstIndex(where: { $0.id == task.id }) {
            agentWorkTasks[index] = task
        } else {
            agentWorkTasks.append(task)
        }
    }

    private static func message(for error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }

    /// Сервер сказал именно «такой записи нет». Отсутствующий МАРШРУТ сюда
    /// не относится: по нему выводы о судьбе задачи делать нельзя — запись
    /// жива, это у сервера нет нужной ручки.
    private static func isMissingRecord(_ error: Error) -> Bool {
        if case .notFound = (error as? APIError) { return true }
        return false
    }
}
