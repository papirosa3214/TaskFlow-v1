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
    @State private var roleOptions: [PlanRoleOption] = []
    /// Живой план (01.10.2026): открытый лист шага / редактора.
    @State private var sheet: PlanSheet?
    @State private var isApplying = false
    @State private var errorMessage: String?

    private enum PlanSheet: Identifiable {
        case detail(planID: String, slot: String)
        case add(planID: String)
        case edit(planID: String, slot: String)

        var id: String {
            switch self {
            case .detail(let plan, let slot): "detail-\(plan)-\(slot)"
            case .add(let plan): "add-\(plan)"
            case .edit(let plan, let slot): "edit-\(plan)-\(slot)"
            }
        }
    }

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
        .sheet(item: $sheet) { sheet in
            sheetView(sheet)
        }
        .alert("План не изменён", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Живой план: листы и правки

    @ViewBuilder
    private func sheetView(_ sheet: PlanSheet) -> some View {
        switch sheet {
        case .detail(let planID, let slot):
            if let plan = planWith(planID), let node = plan.nodes.first(where: { $0.slotKey == slot }) {
                let subtask = subtaskFor(plan: plan, slot: slot)
                PlanStepDetailSheet(
                    node: node,
                    plan: plan,
                    subtask: subtask,
                    roleTitle: graphTitle(for:),
                    stateLabel: Self.stateLabel(node.isSkipped ? "skipped" : baseState(for: subtask, plan: plan)),
                    isEditable: isEditable(node, in: plan),
                    onEdit: { self.sheet = .edit(planID: planID, slot: slot) },
                    onSkip: { reason in
                        self.sheet = nil
                        Task { await apply(ApiPlanOp(op: "skip_step", slotKey: slot, reason: reason), to: plan) }
                    },
                    onRemove: {
                        self.sheet = nil
                        Task { await apply(ApiPlanOp(op: "remove_step", slotKey: slot), to: plan) }
                    }
                )
                .presentationDetents([.medium, .large])
            }
        case .add(let planID):
            if let plan = planWith(planID) {
                editor(.add, plan: plan)
            }
        case .edit(let planID, let slot):
            if let plan = planWith(planID), let node = plan.nodes.first(where: { $0.slotKey == slot }) {
                editor(.edit(node), plan: plan)
            }
        }
    }

    private func editor(_ mode: PlanStepEditorSheet.Mode, plan: ApiCollaborationPlan) -> some View {
        PlanStepEditorSheet(
            mode: mode,
            plan: plan,
            roles: roleOptions.isEmpty
                ? Array(Set(plan.nodes.map(\.roleKey))).sorted().map { PlanRoleOption(key: $0, title: graphTitle(for: $0)) }
                : roleOptions,
            pendingSlots: Set(plan.nodes.filter { isEditable($0, in: plan) }.map(\.slotKey)),
            roleTitle: graphTitle(for:),
            onSave: { op in Task { await apply(op, to: plan) } }
        )
    }

    private func planWith(_ id: String) -> ApiCollaborationPlan? {
        if plan?.id == id { return plan }
        if draftPlan?.id == id { return draftPlan }
        return nil
    }

    private func subtaskFor(plan: ApiCollaborationPlan, slot: String) -> ApiSubtask? {
        let fresh = subtasks.filter { $0.collaborationPlanId == plan.id }
        let source = fresh.isEmpty ? planSubtasks : fresh
        return source.first { $0.planNodeKey == slot }
    }

    /// Менять можно только неначатый шаг и только владельцу: у черновика —
    /// любой, у запущенного — без галочки и без состояния работы.
    private func isEditable(_ node: ApiCollaborationPlanNode, in plan: ApiCollaborationPlan) -> Bool {
        guard isOwner, !node.isSkipped else { return false }
        if plan.status != "approved" { return true }
        guard let subtask = subtaskFor(plan: plan, slot: node.slotKey) else { return true }
        return !subtask.done && subtask.agentState == nil
    }

    private func canAddSteps(to plan: ApiCollaborationPlan) -> Bool {
        guard isOwner else { return false }
        if plan.status != "approved" { return true }
        // Сданный целиком план не растёт: новую работу — отдельной задачей.
        return plan.nodes.contains { node in
            !node.isSkipped && !(subtaskFor(plan: plan, slot: node.slotKey)?.done ?? false)
        }
    }

    private func apply(_ op: ApiPlanOp, to plan: ApiCollaborationPlan) async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            let updated = try await api.applyCollaborationPlanOps(taskId: taskId, planId: plan.id,
                                                                  baseVersion: plan.version, ops: [op])
            replace(updated)
            await reloadSubtasks()
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    private func decide(_ proposal: ApiPlanProposal, approve: Bool, in plan: ApiCollaborationPlan) async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            let updated = try await api.decideCollaborationPlanProposal(taskId: taskId, planId: plan.id,
                                                                        proposalId: proposal.id, approve: approve)
            replace(updated)
            await reloadSubtasks()
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    private func replace(_ updated: ApiCollaborationPlan) {
        withAnimation(.snappy(duration: 0.25)) {
            if plan?.id == updated.id { plan = updated }
            if draftPlan?.id == updated.id { draftPlan = updated }
        }
    }

    private func reloadSubtasks() async {
        if let fresh = try? await api.subtasks(taskId: taskId) {
            planSubtasks = fresh.filter { $0.collaborationPlanId != nil }
        }
    }

    // MARK: - Предложения ролей и «Добавить шаг»

    @ViewBuilder
    private func ownerControls(for plan: ApiCollaborationPlan) -> some View {
        if isOwner {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                ForEach(plan.pendingProposals ?? []) { proposal in
                    proposalCard(proposal, plan: plan)
                }
                if canAddSteps(to: plan) {
                    Button {
                        sheet = .add(planID: plan.id)
                    } label: {
                        Label("Добавить шаг", systemImage: "plus.circle")
                            .tfText(.action)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isApplying)
                    .accessibilityIdentifier("plan-add-step")
                }
            }
            .padding(.top, TFSpacing.xs)
        }
    }

    private func proposalCard(_ proposal: ApiPlanProposal, plan: ApiCollaborationPlan) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text("\(proposal.actorName ?? "Роль") предлагает изменить план")
                .tfText(.action)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tfText)
            ForEach(Array(proposal.ops.enumerated()), id: \.offset) { _, op in
                Text(Self.describe(op, title: graphTitle(for:)))
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
            }
            if let reason = proposal.reason, !reason.isEmpty {
                Text(reason)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
            }
            HStack(spacing: TFSpacing.md) {
                Button("Одобрить") { Task { await decide(proposal, approve: true, in: plan) } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.tfGreen)
                Button("Отклонить", role: .destructive) { Task { await decide(proposal, approve: false, in: plan) } }
                    .buttonStyle(.bordered)
            }
            .disabled(isApplying)
            .controlSize(.small)
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: TFRadius.lg))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan-proposal")
    }

    static func describe(_ op: ApiPlanOp, title: (String) -> String) -> String {
        switch op.op {
        case "add_step": return "Новый шаг — \(title(op.roleKey ?? "")): \(op.expectedResult ?? "")"
        case "rework": return "Доработка — \(title(op.roleKey ?? "builder")): \(op.defects ?? "")"
        case "skip_step": return "Пропустить шаг: \(op.reason ?? "")"
        case "remove_step": return "Удалить шаг"
        default: return "Изменить шаг"
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
                edges: plan.edges,
                onTap: { slot in sheet = .detail(planID: plan.id, slot: slot) }
            )
            ownerControls(for: plan)
        }
        .accessibilityElement(children: .contain)
    }

    /// Базовое состояние узла из его подзадачи — без «ready»: та считается
    /// отдельно в `CollaborationPlanGraph` из entries+edges (нужен полный
    /// список узлов, а не один).
    private func baseState(for subtask: ApiSubtask?, plan: ApiCollaborationPlan) -> String {
        guard plan.status == "approved", let subtask else { return "waiting" }
        if subtask.done { return "accepted" }
        switch subtask.agentState {
        case .inProgress: return "active"
        case .blocked: return "blocked"
        case .review: return "review"
        case .todo, .none: return "waiting"
        }
    }

    private func graphEntries(for plan: ApiCollaborationPlan) -> [CollaborationPlanGraph.Entry] {
        plan.nodes.map { node in
            let subtask = subtaskFor(plan: plan, slot: node.slotKey)
            return .init(
                slotKey: node.slotKey,
                roleKey: node.roleKey,
                title: graphTitle(for: node.roleKey),
                state: node.isSkipped ? "skipped" : baseState(for: subtask, plan: plan),
                badge: Self.badge(for: node)
            )
        }
    }

    /// Пометка шага, который не из исходного шаблона.
    private static func badge(for node: ApiCollaborationPlanNode) -> String? {
        switch node.origin {
        case "role": return "добавлен ролью"
        case "rework": return "доработка \(node.iteration ?? 1)"
        default: return nil
        }
    }

    static func stateLabel(_ state: String) -> String {
        switch state {
        case "waiting": "Ждёт"
        case "ready": "Готов к старту"
        case "active": "В работе"
        case "blocked": "Заблокирован"
        case "review": "На проверке"
        case "accepted": "Принято"
        case "skipped": "Пропущен"
        default: state
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
            roleTitles = Dictionary(roles.map { ($0.role, $0.title) }, uniquingKeysWith: { first, _ in first })
            roleOptions = roles.map { PlanRoleOption(key: $0.role, title: graphTitle(for: $0.role)) }
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
        case "product_feature": "Продуктовая фича"
        case "bug_regression": "Баг или регрессия"
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
        /// «добавлен ролью», «доработка 1» — шаг не из исходного шаблона.
        var badge: String?

        var id: String { slotKey }
    }

    let entries: [Entry]
    let edges: [ApiCollaborationPlanEdge]
    /// Тап по шагу — подробности и правка (живой план, 01.10.2026).
    var onTap: (String) -> Void = { _ in }

    private let nodeHeight: CGFloat = 64
    private let rowStep: CGFloat = 88

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
                let places = layout(width: proxy.size.width)
                let centers = places.mapValues { $0.center }

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
                        if let place = places[entry.slotKey] {
                            Button { onTap(entry.slotKey) } label: {
                                node(entry, state: displayState(entry, ready: ready))
                            }
                            .buttonStyle(.plain)
                            .frame(width: place.width, height: nodeHeight)
                            .position(place.center)
                            .accessibilityIdentifier("plan-node-\(entry.slotKey)")
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
                Text(entry.badge.map { "\(stateLabel(state)) · \($0)" } ?? stateLabel(state))
                    .tfText(.caption)
                    .foregroundStyle(stateColor(state))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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

    /// Уровень шага — самый длинный путь от корня: шаги одного уровня идут
    /// параллельно и стоят в одном ряду. Раскладка годится для любого плана,
    /// в том числе достроенного по ходу (раньше — только для full_cycle,
    /// остальное вытягивалось в колонку).
    private var levels: [String: Int] {
        var memo: [String: Int] = [:]
        let incoming = Dictionary(grouping: edges, by: \.toSlotKey)
        func level(_ slot: String, _ path: Set<String>) -> Int {
            if let known = memo[slot] { return known }
            guard !path.contains(slot) else { return 0 }
            let preds = incoming[slot]?.map(\.fromSlotKey) ?? []
            let value = preds.map { level($0, path.union([slot])) + 1 }.max() ?? 0
            memo[slot] = value
            return value
        }
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.slotKey, level($0.slotKey, [])) })
    }

    private var graphHeight: CGFloat {
        let rows = (levels.values.max() ?? 0) + 1
        return nodeHeight + CGFloat(rows - 1) * rowStep
    }

    private func layout(width: CGFloat) -> [String: (center: CGPoint, width: CGFloat)] {
        let levelOf = levels
        let rows = Dictionary(grouping: entries, by: { levelOf[$0.slotKey] ?? 0 })
        var result: [String: (center: CGPoint, width: CGFloat)] = [:]
        for (row, items) in rows {
            let count = CGFloat(items.count)
            let gap = TFSpacing.sm
            let nodeWidth = max(96, min(164, (width - gap * (count - 1)) / count))
            let total = nodeWidth * count + gap * (count - 1)
            var x = (width - total) / 2 + nodeWidth / 2
            let y = nodeHeight / 2 + CGFloat(row) * rowStep
            for item in items {
                result[item.slotKey] = (CGPoint(x: x, y: y), nodeWidth)
                x += nodeWidth + gap
            }
        }
        return result
    }

    private func initials(for title: String) -> String {
        let words = title.split(separator: " ")
        return words.prefix(2).compactMap(\.first).map(String.init).joined()
    }

    private func stateLabel(_ state: String) -> String {
        CollaborationPlanView.stateLabel(state)
    }

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "ready": .tfGreen
        case "active": .tfOrange
        case "blocked": .tfOrange
        case "review": .tfBlue
        case "accepted": .tfGreen
        case "skipped": .tfDim
        default: .tfSub
        }
    }
}
