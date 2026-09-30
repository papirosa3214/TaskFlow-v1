import SwiftUI
import Observation

/// Ответ `GET /server-status` — поля сняты живым чтением серверного кода
/// (`server/src/index.ts`, роут `/api/server-status`, НЕ живым запросом —
/// он требует токен владельца, которого у исполнителя этой задачи нет и не
/// должно быть). Спека API.md полей не перечисляет («статус сервера»),
/// поэтому источник истины здесь — код сервера (правило ARCHITECTURE.md п.3).
struct ServerStatusResponse: Decodable, Sendable {
    let ok: Bool
    let uptimeSec: Int
    let commit: String?
    let commitAt: String?
    let tasksActive: Int
    let tasksTotal: Int
    let dbBytes: Int?
    let ollamaOnline: Bool
    let ollamaModel: String

    enum CodingKeys: String, CodingKey {
        case ok
        case uptimeSec = "uptime_sec"
        case commit
        case commitAt = "commit_at"
        case tasksActive = "tasks_active"
        case tasksTotal = "tasks_total"
        case dbBytes = "db_bytes"
        case ollamaOnline = "ollama_online"
        case ollamaModel = "ollama_model"
    }
}

/// Ответ `GET/POST /api/agent-service` — `server/src/routes/agent-service.ts`,
/// прочитан целиком (read-only), тело реально `{ active, enabled }`.
struct AgentServiceResponse: Decodable, Sendable {
    let active: Bool
    let enabled: Bool
}

/// `POST /agent-service` по контракту возвращает только подтверждение
/// операции (`{ ok: true }`), а не снимок службы. После успешной мутации
/// состояние перечитывается отдельным GET — это не даёт показать устаревшее
/// значение и работает, даже если systemd применяет изменение не мгновенно.
private struct AgentServiceMutationResponse: Decodable, Sendable {
    let ok: Bool
}

/// Вью-модель блока «Сервер» — spec/SCREENS-2.md §6 п.5, состояния строго по
/// факту запроса (не отвечает / грузится / успех). Отдельный `APIClient()` —
/// тот же приём, что у `TodayViewModel` (клиент `Sendable`, второй экземпляр
/// безопасен).
@MainActor
@Observable
final class ServerStatusViewModel {
    private let apiClient = APIClient()

    enum Phase: Equatable { case loading, failed, loaded }
    var phase: Phase = .loading
    var status: ServerStatusResponse?
    var agentService: AgentServiceResponse?
    var pingResult: String?
    var isPinging = false
    var agentServiceError: String?
    /// Переключение будильника — реальный `POST /agent-service`, включающий/
    /// выключающий systemd-юнит НА СЕРВЕРЕ. Задача прямо запрещает трогать
    /// настройки живого сервера — проводка написана (штатная функция экрана
    /// для владельца), но сама я её ни разу не вызвала за время работы.
    var isTogglingService = false

    func load() async {
        async let statusTask: ServerStatusResponse? = try? apiClient.request(.get, "/server-status")
        async let serviceTask: AgentServiceResponse? = try? apiClient.request(.get, "/agent-service")
        let (loadedStatus, loadedService) = await (statusTask, serviceTask)
        status = loadedStatus
        agentService = loadedService
        phase = loadedStatus == nil ? .failed : .loaded
    }

    func ping() async {
        isPinging = true
        pingResult = nil
        let start = Date()
        struct HealthResponse: Decodable { let ok: Bool }
        do {
            let health: HealthResponse = try await apiClient.request(.get, "/health")
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            pingResult = health.ok ? "⚡ \(elapsedMs) мс · 192.168.1.110 в сети" : "❌ Ошибка ответа"
        } catch {
            pingResult = "❌ Сервер недоступен"
        }
        isPinging = false
        await load()
    }

    func toggleAgentService(to enabled: Bool) async {
        guard agentService != nil else { return }
        isTogglingService = true
        struct Body: Encodable { let on: Bool }
        do {
            let response: AgentServiceMutationResponse = try await apiClient.request(.post, "/agent-service", body: Body(on: enabled))
            if response.ok {
                await load()
            } else {
                agentServiceError = "Сервер не подтвердил изменение будильника"
            }
        } catch {
            agentServiceError = "Не удалось изменить состояние будильника"
        }
        isTogglingService = false
    }
}

/// Форматтеры — буквальные порты `fmtUptime`/`fmtBytes` из
/// `src/screens/SettingsScreen.tsx` (числа/пороги 1:1, чтобы значения на
/// экране совпадали с вебом).
enum ServerStatusFormat {
    static func uptime(_ sec: Int) -> String {
        if sec < 60 { return "\(sec) с" }
        let minutes = sec / 60
        if minutes < 60 { return "\(minutes) мин" }
        let hours = minutes / 60
        if hours < 24 {
            let rest = minutes % 60
            return rest != 0 ? "\(hours) ч \(rest) мин" : "\(hours) ч"
        }
        let days = hours / 24
        let restHours = hours % 24
        return restHours != 0 ? "\(days) д \(restHours) ч" : "\(days) д"
    }

    static func bytes(_ bytes: Int) -> String {
        if bytes < 1024 * 1024 { return "\(Int((Double(bytes) / 1024).rounded())) КБ" }
        return String(format: "%.1f МБ", Double(bytes) / 1024 / 1024)
    }

    /// `commit_at` — ISO8601 с офсетом (`git log --format=%cI`), формат
    /// вывода как в вебе: «31 авг.».
    static func commitDate(_ iso: String) -> String? {
        guard let date = DateFormats.iso8601(iso) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}

/// Секция «Сервер» — spec §6 п.5, три состояния буквально по спеке: не
/// ответил / грузится / успех (с шестью строками внутри). Строки собраны на
/// `TFListRow` (не `TFFieldRow`) — сверено со скриншотом `settings.png`:
/// «Сервер»/«Локальная LLM» показывают только значение (не тап-строка,
/// `action: nil`), «Проверить связь» показывает значение И шеврон вместе
/// (шеврон дорисован вручную внутри `trailing`, раз он нужен ОДНОВРЕМЕННО
/// со значением — `TFListRow` в остальных местах их не смешивает).
struct ServerStatusSection: View {
    @State private var viewModel = ServerStatusViewModel()

    var body: some View {
        TFCard(padding: 0) {
            VStack(spacing: 0) {
                switch viewModel.phase {
                case .failed:
                    TFListRow(icon: "xmark.circle", iconStyle: .plain, title: "Сервер 192.168.1.110", trailing: AnyView(valueText("не отвечает", color: .tfCoral)), titleStyle: .action, verticalPadding: TFSpacing.xs)
                    TFDivider(inset: rowDividerInset)
                    TFListRow(icon: "arrow.clockwise", iconStyle: .plain, title: "Сервер", trailing: AnyView(Image(systemName: "arrow.clockwise")), titleStyle: .action, verticalPadding: TFSpacing.xs, action: { Task { await viewModel.load() } })
                case .loading:
                    TFListRow(icon: "server.rack", iconStyle: .plain, title: "Сервер 192.168.1.110", trailing: AnyView(valueText("проверяю связь…")), titleStyle: .action, verticalPadding: TFSpacing.xs)
                case .loaded:
                    loadedRows
                }
            }
        }
        .task { await viewModel.load() }
        .alert("Будильник", isPresented: Binding(
            get: { viewModel.agentServiceError != nil },
            set: { if !$0 { viewModel.agentServiceError = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.agentServiceError = nil }
        } message: {
            Text(viewModel.agentServiceError ?? "")
        }
    }

    @ViewBuilder
    private var loadedRows: some View {
        if let status = viewModel.status {
            TFListRow(
                // Была "waveform.path.ecg" (кардиограмма) — просьба владельца
                // 03.09.2026: «иконка вообще не про сервер» — server.rack
                // буквально изображает сервер. Зелёную точку тоже убрал по
                // его слову: этот ряд рисуется только когда `/server-status`
                // ОТВЕТИЛ (иначе — ветка `.failed` со своей иконкой и «не
                // отвечает»), так что аптайм на экране сам по себе уже
                // значит «онлайн» — отдельный сигнал был лишним.
                icon: "server.rack", iconStyle: .plain,
                title: "Сервер (192.168.1.110)",
                trailing: AnyView(valueText(ServerStatusFormat.uptime(status.uptimeSec))),
                titleStyle: .action,
                verticalPadding: TFSpacing.xs
            )
            // Строка «Локальная LLM» отсюда убрана — просьба владельца
            // 03.09.2026: «это же про интеллект, закинь её в искусственный
            // интеллект» — и она там уже реально есть (не дубль завожу, а
            // убираю настоящий): `VoiceModelsScreen.onServerSection`,
            // строка `serverModelTitle`/`serverModelValue`, тот же Ollama-
            // статус с того же /server-status. Здесь остаётся только то, что
            // именно про инфраструктуру сервера (аптайм/пинг/версия/задачи).
            TFDivider(inset: rowDividerInset)
            // «Пинг» — именно измерение задержки, а не «связь с сервером»:
            // что сервер отвечает, уже видно строкой выше (аптайм приходит
            // с того же ответа), а здесь владелец меряет только отклик.
            // Просьба владельца 20.09.2026: «надо написать просто пинг».
            TFListRow(
                icon: "bolt.fill", iconStyle: .plain,
                title: "Пинг",
                trailing: AnyView(pingAccessory),
                titleStyle: .action,
                verticalPadding: TFSpacing.xs,
                action: { Task { await viewModel.ping() } }
            )
            // Строка «Будильник (служба)» переехала в «Настройки → Сервер»
            // к остальным ручкам системы (20.09.2026, см. LOCK-187): отдельным
            // входом её больше нет — два переключателя одного рубильника
            // расходились бы в показаниях.
            TFDivider(inset: rowDividerInset)
            TFListRow(
                icon: "list.bullet", iconStyle: .plain,
                title: "Задачи",
                trailing: AnyView(valueText(status.dbBytes.map { "\(status.tasksActive) из \(status.tasksTotal) · \(ServerStatusFormat.bytes($0))" }
                    ?? "\(status.tasksActive) из \(status.tasksTotal)")),
                titleStyle: .action,
                verticalPadding: TFSpacing.xs
            )
        }
    }

    private var rowDividerInset: CGFloat { TFSpacing.lg + 40 + TFSpacing.md }

    @ViewBuilder
    private var pingAccessory: some View {
        if let pingResult = viewModel.pingResult {
            valueText(pingResult)
        } else if viewModel.isPinging {
            ProgressView()
        } else {
            Image(systemName: "arrow.clockwise")
        }
    }

    // `.lineLimit(1)` — без него длинные строки («модель · время работы»)
    // рвались посреди слова, когда не хватало горизонтального места рядом с
    // длинным заголовком (жалоба владельца 03.09.2026: «буквы в разнобой»).
    private func valueText(_ text: String, color: Color = .tfSub) -> some View {
        Text(text).tfText(.action).foregroundStyle(color).lineLimit(1).fixedSize()
    }
}
