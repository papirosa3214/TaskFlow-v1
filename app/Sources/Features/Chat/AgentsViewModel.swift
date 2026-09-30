import Foundation
import Observation

/// Состояние экрана «Команда» (LOCK-176, переделан в LOCK-183).
///
/// Список — профили ролей (`GET /api/roles`): исполнитель есть роль, Pi и
/// прочая машинерия в обычном UI не показываются. Модель роли правится
/// через `PUT /api/runtime/routing/:role`.
///
/// Раскрытия строки больше нет: тап открывает отдельный экран профиля
/// (`AgentProfileScreen`), здесь живёт только список и сводка.
@MainActor
@Observable
final class AgentsViewModel {
    private(set) var profiles: [RoleProfile] = []
    private(set) var isLoading = false
    var listErrorMessage: String?

    private(set) var isOwner = false

    /// Каталог моделей Pi — нужен редактору модели роли (на экране профиля).
    private(set) var models: [RuntimeModel] = []
    private(set) var modelsLoading = false
    var modelsErrorMessage: String?

    private let api = APIClient()
    private var pollTask: Task<Void, Never>?

    func configure(currentUser: ApiUser?) {
        isOwner = currentUser?.role == .owner
    }

    /// Жив ли исполнитель — общий признак на список.
    var runtimeReady: Bool? { profiles.first?.runtimeReady }

    /// Раз в 15с — статус роли и текущая задача живые, как в вебе.
    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.load()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func load() async {
        if profiles.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            // `all=1` нужен экрану «Команда»: владелец должен видеть и
            // отключённые роли, чтобы было что включить обратно. Для
            // отображения их прячем отдельным списком (LOCK-205).
            profiles = try await api.roles(all: true)
            listErrorMessage = nil
        } catch {
            listErrorMessage = Self.message(for: error)
        }
    }

    func profile(for role: String) -> RoleProfile? {
        profiles.first { $0.role == role }
    }

    // MARK: - Сводка

    /// Кто чем занят прямо сейчас. «На проверке» — отдельное состояние от
    /// `status`: сервер считает роль `working` только для in_progress/blocked,
    /// а задача на ревью у роли выглядит как готовая — поэтому смотрим ещё и
    /// на состояние текущей задачи.
    struct Summary: Equatable {
        var working = 0
        var review = 0
        var free = 0
        var blocked = 0
        var unavailable = 0
    }

    var summary: Summary {
        var s = Summary()
        for profile in profiles {
            let state = profile.currentTask?.state
            switch profile.status {
            case .working:
                s.working += 1
            case .blocked:
                s.blocked += 1
            case .unavailable:
                s.unavailable += 1
            case .ready:
                if state == "review" { s.review += 1 } else { s.free += 1 }
            case .unknown:
                s.unavailable += 1
            }
        }
        return s
    }

    /// «3 работают · 1 на проверке · 4 свободны». Нулевые части не показываем.
    var summaryText: String {
        let s = summary
        var parts: [String] = []
        if s.working > 0 { parts.append("\(s.working) \(Self.verb(s.working, "работает", "работают"))") }
        if s.review > 0 { parts.append("\(s.review) на проверке") }
        if s.free > 0 { parts.append("\(s.free) \(Self.verb(s.free, "свободен", "свободны"))") }
        if s.blocked > 0 { parts.append("\(s.blocked) \(Self.verb(s.blocked, "заблокирован", "заблокированы"))") }
        if s.unavailable > 0 { parts.append("\(s.unavailable) \(Self.verb(s.unavailable, "недоступен", "недоступны"))") }
        return parts.joined(separator: " · ")
    }

    private static func verb(_ n: Int, _ one: String, _ many: String) -> String {
        n == 1 ? one : many
    }

    // MARK: - Модель роли

    func loadModelsIfNeeded() async {
        guard models.isEmpty, !modelsLoading else { return }
        modelsLoading = true
        modelsErrorMessage = nil
        defer { modelsLoading = false }
        do {
            models = try await api.runtimeModels()
        } catch {
            modelsErrorMessage = Self.message(for: error)
        }
    }

    @discardableResult
    /// Модель роли. Резервные модели убраны (20.09.2026): они нигде не
    /// использовались и ни на что не влияли — подробная причина в
    /// `AgentProfileScreen.modelMenuRow`. Серверу отправляем пустой список,
    /// он затирает оставшиеся с прежних времён резервные.
    func updateModelPolicy(role: String, primary: String) async -> Bool {
        do {
            _ = try await api.updateRuntimeRouting(role: role, primary: primary, fallbacks: [])
            await load()
            return true
        } catch {
            listErrorMessage = Self.message(for: error)
            return false
        }
    }

    // MARK: - LOCK-205: создание / правка / включение-выключение роли

    /// Разделённые списки для экрана: включённые сверху, отключённые —
    /// отдельной секцией, чтобы владелец видел, что можно вернуть.
    var enabledProfiles: [RoleProfile] {
        profiles.filter { $0.isEnabled }
    }

    var disabledProfiles: [RoleProfile] {
        profiles.filter { !$0.isEnabled }
    }

    /// Только владелец может завести роль. После успеха список подгружается
    /// заново: серверная сортировка и кэш `refreshRoles()` живут на стороне
    /// сервера, клиент видит правду только через `GET /api/roles?all=1`.
    func createRole(key: String, title: String, summary: String?, prompt: String?) async -> Bool {
        do {
            let profile = try await api.createRole(key: key, title: title, summary: summary, prompt: prompt)
            profiles.append(profile)
            await load()
            return true
        } catch {
            listErrorMessage = Self.message(for: error)
            return false
        }
    }

    /// Правка роли. Все, кроме `role`, опциональны — сервер требует, чтобы
    /// хотя бы одно поле было передано (иначе 422). `prompt: .keep` —
    /// поле в PATCH не отправляется.
    func patchRole(role: String, title: String?, summary: String?, prompt: APIClient.PromptChange, enabled: Bool? = nil) async -> Bool {
        do {
            _ = try await api.patchRole(role: role, title: title, summary: summary, prompt: prompt, enabled: enabled)
            await load()
            return true
        } catch {
            listErrorMessage = Self.message(for: error)
            return false
        }
    }

    /// Включить / отключить роль. Отдельной кнопкой в листе правки — для
    /// владельца это «архив», который виден скрытно и достаётся обратно
    /// (`?all=1`).
    func setRoleEnabled(role: String, enabled: Bool) async -> Bool {
        await patchRole(role: role, title: nil, summary: nil, prompt: .keep, enabled: enabled)
    }

    private static func message(for error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
