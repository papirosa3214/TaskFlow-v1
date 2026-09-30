import SwiftUI

/// Краткий граф совместной работы над задачей — LOCK-246, этап 10 плана
/// docs/2026-09-28-parent-child-execution-context.
///
/// Чистый SwiftUI без своих tint/background/overlay/рамок: строка живёт
/// внутри системного `Section` в `TaskFormScreen`, фон рисует список сам.
/// Рисует, только если у задачи есть УТВЕРЖДЁННЫЙ план — черновики ещё
/// ничего не запускают и путали бы владельца. У большинства задач approved
/// плана нет вовсе: тогда `body` — `EmptyView()`, как и у соседних
/// `AttemptLadderView`/`AgentOwnerActions`.
///
/// Runtime-состояние узлов — с 29.09.2026 обычные подзадачи
/// (`collaborationPlanId`/`planNodeKey`), не отдельная сущность
/// (docs/2026-09-29-role-slot-execution-integration/DESIGN.md, владелец:
/// «роли плана — это подзадачи»). У subtasks нет отдельного персистентного
/// состояния «готов к старту» (сервер стартует узел сам, как только это
/// становится верным) — «ready» здесь вычисляется на клиенте из entries
/// и edges: waiting-узел, у которого все предшественники уже done.
public struct CollaborationPlanView: View {
    let taskId: String
    /// Подзадачи карточки — она обновляет их опросом. Состояния узлов берём
    /// отсюда: своя загрузка ниже идёт один раз, и граф замирал в том виде,
    /// в каком был при открытии (владелец 01.10.2026, T05: «исследователь в
    /// работе» всю дорогу, хотя пятеро уже сдали).
    var subtasks: [ApiSubtask] = []
    /// Родитель прячет весь `Section` целиком, пока плана нет — иначе на
    /// 99% карточек без плана оставалась бы пустая секция с системными
    /// отступами. Обновляется по факту загрузки, не заранее.
    @Binding var hasApprovedPlan: Bool

    @State private var plan: ApiCollaborationPlan?
    /// Черновик, ещё не утверждённый — LOCK-249. Показывается владельцу
    /// вместе с той же графовой раскладкой, что и approved — чтобы было
    /// видно, что именно утверждаешь. Сама кнопка «Утвердить» живёт не
    /// здесь, а в меню «Ещё» карточки (владелец: там уже все действия над
    /// задачей, отдельная кнопка в теле карточки — лишняя); `id` черновика
    /// пробрасывается наружу через `pendingApprovalPlanId`, родитель зовёт
    /// API и форсирует перезагрузку этой вьюхи через `.id(...)`.
    @State private var draftPlan: ApiCollaborationPlan?
    @State private var planSubtasks: [ApiSubtask] = []
    @State private var roleTitles: [String: String] = [:]

    @Binding var pendingApprovalPlanId: String?

    @Environment(SessionStore.self) private var session
    private var isOwner: Bool { session.currentUser?.role == .owner }

    private let api = APIClient()

    public init(taskId: String, subtasks: [ApiSubtask] = [], hasApprovedPlan: Binding<Bool>, pendingApprovalPlanId: Binding<String?>) {
        self.taskId = taskId
        self.subtasks = subtasks
        self._hasApprovedPlan = hasApprovedPlan
        self._pendingApprovalPlanId = pendingApprovalPlanId
    }

    @State private var didStartLoad = false

    public var body: some View {
        // Пока plan == nil, тело ниже пустое — List не шлёт onAppear
        // пустой ячейке вовсе (проверено на устройстве 28.09.2026). Якорь
        // нулевого размера всегда присутствует в дереве, поэтому lifecycle
        // гарантированно срабатывает.
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    guard !didStartLoad else { return }
                    didStartLoad = true
                    Task { await load() }
                }
            if let draftPlan, isOwner {
                draftSection(draftPlan)
            }
            if let plan {
                content(for: plan)
            }
        }
    }

    /// Черновик целиком: та же раскладка графа, что у approved — владелец
    /// должен видеть роли и порядок ДО утверждения. Кнопка «Утвердить» —
    /// в меню «Ещё» карточки, не здесь.
    @ViewBuilder
    private func draftSection(_ draft: ApiCollaborationPlan) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Черновик плана — роли ещё не запущены")
                .tfText(.caption)
                .foregroundStyle(Color.tfOrange)
            content(for: draft)
        }
        .padding(.bottom, TFSpacing.sm)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func content(for plan: ApiCollaborationPlan) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text(Self.profileLabel(plan.profile))
                .tfText(.title)
                .fontWeight(.regular)
                .foregroundStyle(Color.tfText)
            CollaborationPlanGraph(
                entries: graphEntries(for: plan),
                edges: plan.edges
            )
        }
        .accessibilityElement(children: .contain)
    }

    /// Базовое состояние узла из его подзадачи — без «ready»: та считается
    /// отдельно в `CollaborationPlanGraph` из entries+edges (нужен полный
    /// список узлов, а не один).
    private func baseState(for subtask: ApiSubtask?) -> String {
        guard let subtask else { return "waiting" }
        if subtask.done { return "accepted" }
        switch subtask.agentState {
        case .inProgress: return "active"
        case .blocked: return "blocked"
        case .review: return "review"
        case .todo, .none: return "waiting"
        }
    }

    private func graphEntries(for plan: ApiCollaborationPlan) -> [CollaborationPlanGraph.Entry] {
        let fresh = subtasks.filter { $0.collaborationPlanId == plan.id }
        let source = fresh.isEmpty ? planSubtasks : fresh
        return plan.nodes.map { node in
            let subtask = source.first { $0.planNodeKey == node.slotKey }
            return .init(
                slotKey: node.slotKey,
                roleKey: node.roleKey,
                title: graphTitle(for: node.roleKey),
                state: baseState(for: subtask)
            )
        }
    }

    private func graphTitle(for roleKey: String) -> String {
        switch roleKey {
        case "designer": "Дизайнер"
        case "critic_verifier": "Критик"
        default: title(for: roleKey)
        }
    }

    private func title(for roleKey: String) -> String {
        roleTitles[roleKey] ?? roleKey
    }

    private func load() async {
        async let plansTask = api.collaborationPlans(taskId: taskId)
        async let subtasksTask = api.subtasks(taskId: taskId)
        async let rolesTask = api.roles()
        guard let plans = try? await plansTask else { return }
        planSubtasks = ((try? await subtasksTask) ?? []).filter { $0.collaborationPlanId != nil }
        if let roles = try? await rolesTask {
            roleTitles = Dictionary(uniqueKeysWithValues: roles.map { ($0.role, $0.title) })
        }
        plan = plans.first { $0.status == "approved" }
        draftPlan = plans.first { $0.status == "draft" }
        // Название биндинга осталось прежним (LOCK-247), но с LOCK-249 он
        // также открывает секцию под черновик, ожидающий утверждения
        // владельцем — не только под уже approved план.
        hasApprovedPlan = plan != nil || (draftPlan != nil && isOwner)
        pendingApprovalPlanId = isOwner ? draftPlan?.id : nil
    }

    private static func profileLabel(_ profile: String) -> String {
        switch profile {
        case "single_executor": "Один исполнитель"
        case "research": "Исследование"
        case "delivery": "Доставка"
        case "full_cycle": "Полный цикл"
        case "manual": "Вручную"
        default: profile
        }
    }
}

/// Компактная схема зависимостей approved-плана. Подписываем только состояние
/// роли: источник ожидания считывается по входящим линиям, поэтому текст не
/// дублирует сам граф.
private struct CollaborationPlanGraph: View {
    struct Entry: Identifiable {
        let slotKey: String
        let roleKey: String
        let title: String
        /// waiting | ready | active | blocked | review | accepted. `ready`
        /// сюда не приходит напрямую (см. `CollaborationPlanView.baseState`)
        /// — считается ниже, в `readyState(for:)`, из entries+edges.
        let state: String

        var id: String { slotKey }
    }

    let entries: [Entry]
    let edges: [ApiCollaborationPlanEdge]

    private let nodeHeight: CGFloat = 64
    private let fullCycleRoles: Set<String> = [
        "researcher", "analyst", "architect", "designer", "builder", "qa", "critic_verifier"
    ]

    /// waiting-узел, у которого предшественники (если есть) все уже done
    /// ("accepted") — сервер такой узел стартует сам почти мгновенно,
    /// «ready» здесь наблюдается только в окне до автостарта или если
    /// автостарт сорвался (тогда есть ручной POST /api/subtasks/:id/run —
    /// см. planSubtaskAdmission.ts). Артефактные edges с явным
    /// start_condition="accepted" клиент отличить от «сдано, но не
    /// принято» не может (нет статуса версии артефакта) — упрощение,
    /// сознательно принятое ради того, чтобы не тащить сюда ещё один
    /// запрос ради редкого случая.
    private func readyStates() -> Set<String> {
        let byKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.slotKey, $0) })
        var ready: Set<String> = []
        for entry in entries where entry.state == "waiting" {
            let incoming = edges.filter { $0.toSlotKey == entry.slotKey }
            let satisfied = incoming.isEmpty || incoming.allSatisfy { byKey[$0.fromSlotKey]?.state == "accepted" }
            if satisfied { ready.insert(entry.slotKey) }
        }
        return ready
    }

    private func displayState(_ entry: Entry, ready: Set<String>) -> String {
        ready.contains(entry.slotKey) ? "ready" : entry.state
    }

    var body: some View {
        let ready = readyStates()
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            HStack(spacing: TFSpacing.xs) {
                Text("\(ready.count) готов к старту")
                    .tfText(.action)
                    .foregroundStyle(Color.tfGreen)
                Text("•")
                    .tfText(.action)
                    .foregroundStyle(Color.tfDim)
                Text("\(entries.filter { $0.state == "active" }.count) в работе")
                    .tfText(.action)
                    .foregroundStyle(Color.tfOrange)
            }

            GeometryReader { proxy in
                let nodeWidth = min(164, (proxy.size.width - TFSpacing.sm) / 2)
                let centers = centers(in: proxy.size, nodeWidth: nodeWidth)

                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for edge in edges {
                            guard let from = centers[edge.fromSlotKey], let to = centers[edge.toSlotKey] else { continue }
                            var path = Path()
                            path.move(to: from)
                            if abs(from.y - to.y) < 1 {
                                path.addLine(to: to)
                            } else {
                                let middleY = (from.y + to.y) / 2
                                path.addLine(to: CGPoint(x: from.x, y: middleY))
                                path.addLine(to: CGPoint(x: to.x, y: middleY))
                                path.addLine(to: to)
                            }
                            let isReadyPath = ready.contains(edge.fromSlotKey)
                            context.stroke(
                                path,
                                with: .color(isReadyPath ? Color.tfGreen.opacity(0.8) : Color.tfDim.opacity(0.65)),
                                lineWidth: isReadyPath ? 1.5 : 1
                            )
                        }
                    }

                    ForEach(entries) { entry in
                        if let center = centers[entry.slotKey] {
                            node(entry, state: displayState(entry, ready: ready))
                                .frame(width: nodeWidth, height: nodeHeight)
                                .position(center)
                        }
                    }
                }
            }
            .frame(height: graphHeight)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Граф зависимостей плана совместной работы")
        }
    }

    @ViewBuilder
    private func node(_ entry: Entry, state: String) -> some View {
        HStack(spacing: TFSpacing.sm) {
            TFAvatar(
                size: .lg,
                initials: initials(for: entry.title),
                tint: Color.tfCard2,
                accessibilityLabel: "Аватар: \(entry.title)",
                userID: "role_\(entry.roleKey)"
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .tfText(.action)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(stateLabel(state))
                    .tfText(.caption)
                    .foregroundStyle(stateColor(state))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TFSpacing.sm)
        .background {
            RoundedRectangle(cornerRadius: TFRadius.lg)
                .fill(Color.tfCard2)
            if state == "ready" {
                RoundedRectangle(cornerRadius: TFRadius.lg)
                    .fill(Color.tfGreen.opacity(0.07))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: TFRadius.lg)
                .stroke(state == "ready" ? Color.tfGreen.opacity(0.55) : Color.tfDim.opacity(0.3), lineWidth: 1)
        }
    }

    private var isFullCycle: Bool {
        Set(entries.map(\.roleKey)) == fullCycleRoles
    }

    private var graphHeight: CGFloat {
        isFullCycle ? 374 : max(96, CGFloat(entries.count) * 78)
    }

    private func centers(in size: CGSize, nodeWidth: CGFloat) -> [String: CGPoint] {
        if isFullCycle {
            let left = nodeWidth / 2
            let right = size.width - nodeWidth / 2
            let middle = size.width / 2
            let rows: [String: CGPoint] = [
                "researcher": CGPoint(x: left, y: 32),
                "analyst": CGPoint(x: right, y: 32),
                "architect": CGPoint(x: left, y: 136),
                "designer": CGPoint(x: right, y: 136),
                "builder": CGPoint(x: middle, y: 236),
                "qa": CGPoint(x: left, y: 342),
                "critic_verifier": CGPoint(x: right, y: 342)
            ]
            return Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
                rows[entry.roleKey].map { (entry.slotKey, $0) }
            })
        }

        return Dictionary(uniqueKeysWithValues: entries.enumerated().map { index, entry in
            (entry.slotKey, CGPoint(x: size.width / 2, y: 32 + CGFloat(index) * 78))
        })
    }

    private func initials(for title: String) -> String {
        let words = title.split(separator: " ")
        return words.prefix(2).compactMap(\.first).map(String.init).joined()
    }

    private func stateLabel(_ state: String) -> String {
        switch state {
        case "waiting": "Ждёт"
        case "ready": "Готов к старту"
        case "active": "В работе"
        case "blocked": "Заблокирован"
        case "review": "На проверке"
        case "accepted": "Принято"
        default: state
        }
    }

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "ready": .tfGreen
        case "active": .tfOrange
        case "blocked": .tfOrange
        case "review": .tfBlue
        case "accepted": .tfGreen
        default: .tfSub
        }
    }
}
