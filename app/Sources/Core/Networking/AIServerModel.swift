import Foundation

/// Выбранная владельцем серверная модель для задач ПРИЛОЖЕНИЯ (не агентов).
///
/// Сервер уже принимает модель на каждый запрос (`x-ollama-model` в заголовке
/// или `localModel` в теле), поэтому выбор делается целиком на клиенте:
/// `APIClient` подставляет заголовок, а сервер читает его там, где это уместно
/// (разбор диктовки, структурирование задачи, журнал). Пусто — не вмешиваемся,
/// сервер берёт свою модель по умолчанию. Хранится в `UserDefaults`: это
/// настройка одного владельца на этом устройстве, серверных полей не заводим.
public enum AIServerModelSetting {
    static let defaultsKey = "ai.serverModel"

    /// `nil`, когда владелец ничего не выбирал — тогда заголовок не шлём.
    public static var selected: String? {
        let value = UserDefaults.standard.string(forKey: defaultsKey)
        return (value?.isEmpty == false) ? value : nil
    }

    public static func set(_ name: String?) {
        let clean = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        UserDefaults.standard.set(clean, forKey: defaultsKey)
    }
}
