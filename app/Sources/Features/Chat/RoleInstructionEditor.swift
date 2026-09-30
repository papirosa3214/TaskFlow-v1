import SwiftUI

struct RoleInstructionEditor: View {
    let role: String
    let canEdit: Bool
    let service: RoleInstructionService
    @State private var block: RoleInstructionBlock
    @State private var draft: RoleInstructionDraft
    @State private var team = false
    @State private var scopeDrafts: [Bool: RoleInstructionDraft] = [:]
    @State private var history: [RoleInstructionHistory] = []
    @State private var errorText: String?
    @State private var busy = true
    @State private var showDiscard = false
    @State private var showReset = false
    @Environment(\.dismiss) private var dismiss
    init(role: String, block: RoleInstructionBlock, canEdit: Bool, service: RoleInstructionService) {
        self.role = role; self.canEdit = canEdit; self.service = service
        _block = State(initialValue: block)
        _draft = State(initialValue: RoleInstructionDraft(text: block.text, expectedVersion: block.version))
    }
    private var originalText: String { team ? (block.teamText ?? block.defaultText) : block.text }
    private var sourceLabel: String {
        switch block.scope {
        case "override": return "Личная правка роли"
        case "command_default": return "Общее правило команды"
        default: return "Исходный текст"
        }
    }
    private var modeLabels: String {
        let names = ["work":"Задача", "resume":"Продолжение", "reply":"Ответ", "review":"Проверка", "subtask":"План", "chat":"Чат", "voice":"Голос", "summary":"Сводка"]
        return block.modes.map { names[$0] ?? $0 }.joined(separator: ", ")
    }
    var body: some View {
        Form {
            Section("Источник и применение") {
                Text(block.source).textSelection(.enabled)
                Text("Режимы: " + modeLabels)
                Text("Действует: " + sourceLabel)
                if canEdit && block.editable && block.allowsTeam {
                    Picker("Область правки", selection: Binding(get: { team }, set: { value in
                            scopeDrafts[team] = draft
                            team = value
                            draft = scopeDrafts[value] ?? RoleInstructionDraft(text: value ? (block.teamText ?? block.defaultText) : block.text, expectedVersion: value ? block.commandVersion : block.version)
                        })) {
                            Text("Эта роль").tag(false)
                            Text("Вся команда").tag(true)
                        }
                        .accessibilityIdentifier("roleContext.scope")
                        .disabled(busy)
                    if team { Text("Общая правка затронет роли, у которых нет личного переопределения.") }
                }
                if !block.placeholders.isEmpty { Text("Обязательные подстановки: " + block.placeholders.map { "{\($0)}" }.joined(separator: ", ")) }
            }
            Section("Инструкция") {
                if canEdit && block.editable {
                    TextEditor(text: $draft.text).frame(minHeight: 220)
                        .disabled(busy)
                        .accessibilityIdentifier("roleContext.editor")
                } else { Text(block.text).textSelection(.enabled) }
            }
            if let errorText { Section { Text(errorText).accessibilityIdentifier("roleContext.error") } }
            if draft.hasConflict {
                Section("Инструкция изменилась на сервере") {
                    Text("Ваш текст сохранён в редакторе. Обновите версию, сравните исходный текст и затем сохраните свою правку.")
                    Button("Обновить версию, сохранить мой текст") { Task { await refresh(preserveDraft: true) } }
                        .accessibilityIdentifier("roleContext.refreshVersion")
                }
            }
            if canEdit && block.editable {
                Section {
                    Button("Сохранить") { Task { await mutate() } }
                        .disabled(busy || draft.hasConflict)
                        .accessibilityIdentifier("roleContext.save")
                    Button("Сбросить переопределение", role: .destructive) { showReset = true }
                        .disabled(busy).accessibilityIdentifier("roleContext.reset")
                    Button("История") { Task { await loadHistory() } }
                        .accessibilityIdentifier("roleContext.history")
                }
            }
            if !history.isEmpty {
                Section("История изменений") {
                    ForEach(history) { entry in
                        DisclosureGroup("Версия \(entry.version) · \(entry.action) · \(entry.at)") {
                            Text(entry.text).textSelection(.enabled)
                            Text("Автор: \(entry.byUserId)")
                            Button("Восстановить версию \(entry.version)") { Task { await mutate(action: "restore", version: entry.version) } }
                                .disabled(busy || draft.hasConflict)
                                .accessibilityIdentifier("roleContext.restore.\(entry.version)")
                        }
                    }
                }
            }
            Section("Исходный текст") { Text(block.defaultText).textSelection(.enabled) }
        }
        .navigationTitle(block.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(draft.text != originalText)
        .toolbar {
            if draft.text != originalText {
                ToolbarItem(placement: .cancellationAction) { Button("Назад") { showDiscard = true } }
            }
        }
        .interactiveDismissDisabled(draft.text != originalText)
        .confirmationDialog("Отменить несохранённую правку?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Отменить правку", role: .destructive) { dismiss() }
        }
        .confirmationDialog(team ? "Сбросить общую правку команды?" : "Сбросить правку этой роли?", isPresented: $showReset, titleVisibility: .visible) {
            Button("Сбросить", role: .destructive) { Task { await mutate(action: "reset") } }
        }
        .task { await refresh(preserveDraft: false); busy = false }
    }
    @MainActor private func refresh(preserveDraft: Bool) async {
        do {
            let context = try await service.context(role: role)
            guard let value = context.blocks?.first(where: { $0.id == block.id }) else { return }
            block = value
            draft.adoptRevision(team ? value.commandVersion : value.version)
            if !preserveDraft { draft.text = team ? (value.teamText ?? value.defaultText) : value.text }
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }
    @MainActor private func mutate(action: String = "set", version: Int? = nil) async {
        busy = true; errorText = nil
        defer { busy = false }
        do {
            try await service.mutate(role: role, block: block.id, team: team, version: draft.expectedVersion, text: draft.text, action: action, historyVersion: version)
            await refresh(preserveDraft: false)
            if !history.isEmpty { await loadHistory() }
        } catch APIError.conflict {
            draft.conflict(); errorText = "Конфликт версий. Ваш текст не потерян."
        } catch { errorText = error.localizedDescription }
    }
    @MainActor private func loadHistory() async {
        do { history = try await service.history(role: role, block: block.id, team: team) }
        catch { errorText = error.localizedDescription }
    }
}

/// The default service calls real API. DEBUG fixture is local and never writes live settings.
@MainActor
final class RoleInstructionService {
    private let api = APIClient()
    #if DEBUG
    private var fixtureRoleText = "Инструкция роли"
    private var fixtureTeamText = "Общее правило"
    private var fixtureVersion = 0
    private var fixtureTeamVersion = 0
    private var fixtureEnabled: Bool { ProcessInfo.processInfo.environment["TASKFLOW_ROLE_CONTEXT_FIXTURE"] == "1" }
    private func fixtureContext(role: String) throws -> RoleRuntimeContext {
        let blocks: [[String: Any]] = [
            ["id":"role.prompt", "title":"Инструкция роли", "group":"Роль", "scope":"original", "source":"roles.prompt", "editable":true, "text":fixtureRoleText, "defaultText":"Исходная инструкция роли", "version":fixtureVersion, "commandVersion":0, "modes":["work","chat"], "placeholders":[], "allowsTeam":false],
            ["id":"rules", "title":"Правила работы", "group":"Общие", "scope":"command_default", "source":"agentState.ts", "editable":true, "text":fixtureTeamText, "teamText":fixtureTeamText, "defaultText":"Исходное правило", "version":0, "commandVersion":fixtureTeamVersion, "modes":["work","chat"], "placeholders":[], "allowsTeam":true]
        ]
        let data = try JSONSerialization.data(withJSONObject: ["role":role,"layers":[],"blocks":blocks,"canEdit":true,"notice":"Тестовый контекст без записи на сервер"])
        return try JSONDecoder().decode(RoleRuntimeContext.self, from: data)
    }
    #endif
    func context(role: String) async throws -> RoleRuntimeContext {
        #if DEBUG
        if fixtureEnabled { return try fixtureContext(role: role) }
        #endif
        return try await api.roleRuntimeContext(role: role)
    }
    func history(role: String, block: String, team: Bool) async throws -> [RoleInstructionHistory] {
        #if DEBUG
        if fixtureEnabled { return [] }
        #endif
        return try await api.roleInstructionHistory(role: role, block: block, team: team)
    }
    func mutate(role: String, block: String, team: Bool, version: Int, text: String, action: String, historyVersion: Int?) async throws {
        #if DEBUG
        if fixtureEnabled {
            if team {
                guard version == fixtureTeamVersion else { throw APIError.conflict(message: "Версия изменилась") }
                fixtureTeamText = action == "reset" ? "Исходное правило" : text
                fixtureTeamVersion += 1
            } else {
                guard version == fixtureVersion else { throw APIError.conflict(message: "Версия изменилась") }
                fixtureRoleText = action == "reset" ? "Исходная инструкция роли" : text
                fixtureVersion += 1
            }
            return
        }
        #endif
        try await api.mutateRoleInstruction(role: role, block: block, team: team, version: version, text: text, action: action, historyVersion: historyVersion)
    }
}
