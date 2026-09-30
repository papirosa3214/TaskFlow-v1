import SwiftUI

/// Роль в выборе исполнителя шага.
struct PlanRoleOption: Identifiable, Hashable {
    let key: String
    let title: String
    var id: String { key }
}

/// Шаг живого плана глазами владельца (01.10.2026): что делает роль, чего
/// ждёт, кто и зачем добавил шаг, и — пока шаг не начат — правка,
/// пропуск, удаление. Сданный и идущий шаг только читается: это история.
struct PlanStepDetailSheet: View {
    let node: ApiCollaborationPlanNode
    let plan: ApiCollaborationPlan
    let subtask: ApiSubtask?
    let roleTitle: (String) -> String
    let stateLabel: String
    let isEditable: Bool
    let onEdit: () -> Void
    let onSkip: (String) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSkipPromptOpen = false
    @State private var skipReason = ""
    @State private var isRemoveConfirmOpen = false

    private var predecessors: [String] {
        plan.edges.filter { $0.toSlotKey == node.slotKey }.map(\.fromSlotKey)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Роль", value: roleTitle(node.roleKey))
                    LabeledContent("Состояние", value: stateLabel)
                    if let iteration = node.iteration, iteration > 0 {
                        LabeledContent("Круг доработки", value: "\(iteration)")
                    }
                }
                Section("Что сдать") {
                    Text(node.expectedResult)
                }
                if let instructions = node.instructions, !instructions.isEmpty {
                    Section("Задание") { Text(instructions) }
                }
                if !predecessors.isEmpty {
                    Section("Начнётся после") {
                        ForEach(predecessors, id: \.self) { slot in
                            Text(title(of: slot))
                        }
                    }
                }
                if let origin = originLine {
                    Section("Откуда шаг") {
                        Text(origin)
                        if let reason = node.addedReason, !reason.isEmpty {
                            Text(reason).foregroundStyle(Color.tfSub)
                        }
                    }
                }
                if let reason = node.skipReason {
                    Section("Пропущен") { Text(reason) }
                }
                if let result = subtask?.result, !result.isEmpty, !node.isSkipped {
                    Section("Результат") { Text(result) }
                }
                if isEditable {
                    Section {
                        Button { onEdit() } label: { Label("Изменить шаг", systemImage: "pencil") }
                            .accessibilityIdentifier("plan-step-edit")
                        if plan.status == "approved" {
                            Button { isSkipPromptOpen = true } label: { Label("Пропустить", systemImage: "forward") }
                                .accessibilityIdentifier("plan-step-skip")
                        }
                        Button(role: .destructive) { isRemoveConfirmOpen = true } label: {
                            Label("Удалить шаг", systemImage: "trash")
                        }
                        .accessibilityIdentifier("plan-step-remove")
                    } footer: {
                        Text("Шаг ещё не начат — его можно менять. Порядок сохранится: те, кто ждал этот шаг, будут ждать его предшественников.")
                    }
                }
            }
            .navigationTitle(roleTitle(node.roleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .alert("Почему пропускаем?", isPresented: $isSkipPromptOpen) {
                TextField("Причина", text: $skipReason)
                Button("Пропустить") { onSkip(skipReason) }
                    .disabled(skipReason.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Пропуск виден в плане отдельно от сдачи — причина нужна, чтобы потом было понятно, почему шаг не делали.")
            }
            .confirmationDialog("Удалить шаг «\(roleTitle(node.roleKey))»?", isPresented: $isRemoveConfirmOpen, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { onRemove() }
            }
        }
    }

    private var originLine: String? {
        switch node.origin {
        case "role": return "Добавила роль: \(addedByTitle)"
        case "rework": return "Доработка по замечаниям: \(addedByTitle)"
        case "owner": return "Добавили вы"
        default: return nil
        }
    }

    private var addedByTitle: String {
        guard let id = node.addedBy else { return "—" }
        return id.hasPrefix("role_") ? roleTitle(String(id.dropFirst(5))) : id
    }

    private func title(of slot: String) -> String {
        guard let other = plan.nodes.first(where: { $0.slotKey == slot }) else { return slot }
        return "\(roleTitle(other.roleKey)) — \(other.expectedResult)"
    }
}

/// Новый шаг или правка неначатого: роль, что сдать, задание, после каких
/// шагов начинать (и, для нового, каких ещё не начатых шагов он раньше).
struct PlanStepEditorSheet: View {
    enum Mode: Equatable {
        case add
        case edit(ApiCollaborationPlanNode)
    }

    let mode: Mode
    let plan: ApiCollaborationPlan
    let roles: [PlanRoleOption]
    /// Шаги, которые ещё не начаты, — только перед ними можно вставить новый.
    let pendingSlots: Set<String>
    let roleTitle: (String) -> String
    let onSave: (ApiPlanOp) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var roleKey = ""
    @State private var expectedResult = ""
    @State private var instructions = ""
    @State private var after: Set<String> = []
    @State private var before: Set<String> = []

    private var editedSlot: String? {
        if case .edit(let node) = mode { return node.slotKey }
        return nil
    }

    private var otherNodes: [ApiCollaborationPlanNode] {
        plan.nodes.filter { $0.slotKey != editedSlot && !$0.isSkipped }
    }

    private var canSave: Bool {
        !roleKey.isEmpty && !expectedResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Роль", selection: $roleKey) {
                        ForEach(roles) { role in
                            Text(role.title).tag(role.key)
                        }
                    }
                    .accessibilityIdentifier("plan-step-role")
                    TextField("Что сдать", text: $expectedResult, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("plan-step-expected")
                    TextField("Задание (необязательно)", text: $instructions, axis: .vertical)
                        .lineLimit(2...8)
                }
                if !otherNodes.isEmpty {
                    Section {
                        ForEach(otherNodes) { node in
                            Toggle(isOn: binding(node.slotKey, in: $after)) {
                                stepLabel(node)
                            }
                        }
                    } header: {
                        Text("Начать после")
                    } footer: {
                        Text("Ничего не выбрано — шаг начнётся сразу, параллельно остальным.")
                    }
                }
                if mode == .add {
                    let candidates = otherNodes.filter { pendingSlots.contains($0.slotKey) && !after.contains($0.slotKey) }
                    if !candidates.isEmpty {
                        Section {
                            ForEach(candidates) { node in
                                Toggle(isOn: binding(node.slotKey, in: $before)) {
                                    stepLabel(node)
                                }
                            }
                        } header: {
                            Text("Раньше шагов")
                        } footer: {
                            Text("Эти шаги дождутся нового. Например, дизайнер между аналитиком и разработчиком.")
                        }
                    }
                }
            }
            .navigationTitle(mode == .add ? "Новый шаг" : "Шаг плана")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("plan-step-save")
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func stepLabel(_ node: ApiCollaborationPlanNode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(roleTitle(node.roleKey))
            Text(node.expectedResult)
                .font(.caption)
                .foregroundStyle(Color.tfSub)
                .lineLimit(2)
        }
    }

    private func binding(_ slot: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(slot) },
            set: { on in
                if on { set.wrappedValue.insert(slot) } else { set.wrappedValue.remove(slot) }
            }
        )
    }

    private func fill() {
        switch mode {
        case .add:
            roleKey = roles.first?.key ?? ""
        case .edit(let node):
            roleKey = node.roleKey
            expectedResult = node.expectedResult
            instructions = node.instructions ?? ""
            after = Set(plan.edges.filter { $0.toSlotKey == node.slotKey }.map(\.fromSlotKey))
        }
    }

    private func save() {
        let expected = expectedResult.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let orderedAfter = plan.nodes.map(\.slotKey).filter { after.contains($0) }
        switch mode {
        case .add:
            onSave(ApiPlanOp(op: "add_step", roleKey: roleKey, expectedResult: expected,
                             instructions: task.isEmpty ? nil : task, after: orderedAfter,
                             before: plan.nodes.map(\.slotKey).filter { before.contains($0) }))
        case .edit(let node):
            onSave(ApiPlanOp(op: "update_step", slotKey: node.slotKey, roleKey: roleKey, expectedResult: expected,
                             instructions: task, after: orderedAfter))
        }
        dismiss()
    }
}
