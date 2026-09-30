import Foundation

/// Живая активность агента по задаче — `server/src/routes/activity.ts`.
public extension APIClient {

    /// Чем агент занят прямо сейчас.
    ///
    /// Сам факт запроса — сигнал серверу «на карточку смотрят»: по нему он
    /// решает, звать ли локальную модель за пересказом (иначе она молотила бы
    /// над задачами, которых никто не открывал). Поэтому опрашивать нужно,
    /// пока карточка открыта, а не один раз при появлении.
    func taskActivity(taskId: String) async throws -> ApiTaskActivity {
        try await request(.get, "/tasks/\(taskId)/activity")
    }
}
