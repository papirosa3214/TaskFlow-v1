import Foundation
import Observation

/// Вид экрана «Сегодня» — persist в `taskLayout.today` (spec §4.4).
/// Режим `board` (канбан-доска) убран 15.09.2026 по прямому решению
/// владельца: «вообще уберем этот канбан, с ним только мучения — давай
/// просто сделаем список, а в списке будут вкладки». Вместо колонок доски
/// у списка появились вкладки `TodayListTab`. Сам `TodayBoardView.swift`
/// не удалён и лежит в дереве.
enum TodayLayout: String, CaseIterable {
    case list, hours
}

/// Вкладка списка «Сегодня» — что именно лежит в ленте. Состав задан
/// владельцем 15.09.2026 дословно: входящие это нераспределённые задачи без
/// даты; вторая вкладка — просроченные и ждущие его; третья — сегодня плюс
/// ближайшее будущее, «чтобы я видел, что сегодня и что ближайшее будущее».
enum TodayListTab: String, CaseIterable, Identifiable {
    case inbox, attention, today

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "Входящие"
        case .attention: "Ждут вас"
        case .today: "Сегодня"
        }
    }

    /// Название в пунктах ЛЕВОЙ кнопки шапки. Там ширины хватает, поэтому
    /// вкладка называется полным своим составом через слэш (владелец
    /// 15.09.2026: «через слэш тут место как раз позволяет — сегодня дробь
    /// предстоящие, ждут вас дробь просроченные, входящие не надо, входящие
    /// мне понятно»). Короткий `title` остаётся для шапки экрана — туда
    /// длинная строка не влезет.
    var menuTitle: String {
        switch self {
        case .inbox: "Входящие"
        case .attention: "Ждут вас / Просроченные"
        case .today: "Сегодня / Предстоящие"
        }
    }

    var icon: String {
        switch self {
        case .inbox: "tray"
        case .attention: "exclamationmark.circle"
        case .today: "list.bullet"
        }
    }
}

/// Вью-модель «Сегодня» — собирает данные из общих сторов (`TaskStore`/
/// `ProjectStore`/`SessionStore`, инъекция через `@Environment` в App/)
/// и локальное состояние экрана (фильтры, вид, офсет дня в «часах»).
///
/// Список агентов НЕ приходит ни из одного общего стора (в Core нет
/// `AgentStore` — только сырой метод `APIClient.agents()`), а нужен для
/// `isAgentAssignedTask` (задачи агентов исключаются из «часов», spec §5.1)
/// и для `isWaitingForUser`. Здесь заведён свой `APIClient()` — он
/// `Sendable` и без состояния (токен читает из Keychain на каждый запрос,
/// см. комментарий в `Core/Networking/APIClient.swift`), поэтому второй
/// экземпляр безопасен и не конфликтует с тем, что держит `TaskFlowApp`.
@MainActor
@Observable
final class TodayViewModel {
    private let apiClient = APIClient()

    var agents: [ApiUser] = []
    var filters = TodayTaskFilters.empty
    var layout: TodayLayout {
        didSet { UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutKey) }
    }
    var hourDateOffset = 0

    private static let layoutKey = "taskflow_today_layout"

    init() {
        layout = TodayLayout(rawValue: UserDefaults.standard.string(forKey: Self.layoutKey) ?? "") ?? .list
    }

    func loadAgentsIfNeeded() async {
        guard agents.isEmpty else { return }
        agents = (try? await apiClient.agents()) ?? []
    }
}
