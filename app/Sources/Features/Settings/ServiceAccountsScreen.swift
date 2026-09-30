import SwiftUI
import UIKit
import Observation

/// LOCK-181 (этап 9): старая механика `ApiUser`/API-токена перенесена сюда из
/// «Команды» и больше не называется «агентом». Это сервисные учётки-личности
/// со своими ключами доступа — инфраструктура, а не участники команды ролей.
///
/// Контракт не менялся: `GET/POST /api/agents`, `PUT /api/agents/:id/api-token`,
/// `POST /api/agents/:id/rotate-token`, rename/delete — те же маршруты, что были
/// на экране «Команда» (LOCK-146). Здесь только новая прописка.
@MainActor
@Observable
final class ServiceAccountsViewModel {
    private let api = APIClient()

    private(set) var accounts: [ApiUser] = []
    private(set) var isLoading = false
    var listErrorMessage: String?
    var createErrorMessage: String?
    var renameErrorMessage: String?

    var isOwner = false
    private(set) var issuedToken: (agentID: String, name: String, token: String)?
    private(set) var expandedAccountID: String?
    private(set) var tokenDrafts: [String: String] = [:]
    private(set) var revealedTokenIDs: Set<String> = []

    func configure(currentUser: ApiUser?) {
        isOwner = currentUser?.role == .owner
    }

    /// Что получает подключившийся MCP-клиент — с сервера, не копией.
    private(set) var manifest: MCPManifest?
    private(set) var rules: [String] = []

    func loadClientInfo() async {
        async let manifest = try? api.mcpManifest()
        async let rules = try? api.agentRules()
        self.manifest = await manifest
        self.rules = await rules ?? []
    }

    func load() async {
        if accounts.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            // Учётки ролей (`role_*`) и Секретаря — логины самих ролей, ключами
            // которых управляет сервер; им место на «Команде», не здесь.
            accounts = try await api.agents().filter {
                $0.type == .ai && !$0.id.hasPrefix("role_") && $0.id != "u-secretary"
            }
            listErrorMessage = nil
        } catch {
            listErrorMessage = Self.message(error)
        }
    }

    func toggleExpand(_ id: String) {
        if expandedAccountID == id {
            expandedAccountID = nil
            tokenDrafts.removeValue(forKey: id)
            revealedTokenIDs.remove(id)
        } else {
            expandedAccountID = id
        }
    }

    func isExpanded(_ id: String) -> Bool { expandedAccountID == id }

    func create(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        createErrorMessage = nil
        do {
            let response = try await api.inviteAgentFixed(name: trimmed)
            issuedToken = (response.agent.id, response.agent.name, response.apiToken)
            await load()
        } catch {
            createErrorMessage = Self.message(error)
        }
    }

    func dismissIssuedToken() { issuedToken = nil }

    func realToken(for id: String) -> String? {
        guard let issued = issuedToken, issued.agentID == id else { return nil }
        return issued.token
    }

    func updateTokenDraft(_ id: String, value: String) {
        if value.isEmpty { tokenDrafts.removeValue(forKey: id) } else { tokenDrafts[id] = value }
    }

    func tokenDraft(for id: String) -> String { tokenDrafts[id] ?? "" }

    func toggleTokenReveal(_ id: String) {
        if revealedTokenIDs.contains(id) { revealedTokenIDs.remove(id) } else { revealedTokenIDs.insert(id) }
    }

    func isTokenRevealed(_ id: String) -> Bool { revealedTokenIDs.contains(id) }

    @discardableResult
    func saveToken(_ id: String) async -> Bool {
        let trimmed = tokenDraft(for: id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try await api.saveAgentApiToken(agentId: id, token: trimmed)
            issuedToken = (id, accounts.first { $0.id == id }?.name ?? "", trimmed)
            tokenDrafts.removeValue(forKey: id)
            return true
        } catch {
            listErrorMessage = Self.message(error)
            return false
        }
    }

    @discardableResult
    func rotateToken(_ id: String) async -> Bool {
        do {
            let response = try await api.rotateAgentApiToken(agentId: id)
            issuedToken = (response.agentId, response.name, response.apiToken)
            revealedTokenIDs.insert(id)
            return true
        } catch {
            listErrorMessage = Self.message(error)
            return false
        }
    }

    func rename(id: String, name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        renameErrorMessage = nil
        do {
            _ = try await api.renameAgentFixed(id: id, name: trimmed)
            await load()
            return true
        } catch {
            renameErrorMessage = Self.message(error)
            return false
        }
    }

    func delete(_ account: ApiUser) async {
        do {
            try await api.deleteAgent(id: account.id)
            await load()
        } catch {
            listErrorMessage = Self.message(error)
        }
    }

    private static func message(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}

struct ServiceAccountsScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel = ServiceAccountsViewModel()

    @State private var isCreateFormOpen = false
    @State private var newName = ""
    @State private var pendingDelete: ApiUser?
    @State private var isKeyCopied = false
    @State private var expandedInfo: ClientInfoRow?

    var body: some View {
        // Урок 2026-09-25 (чёрные треугольники в углах системной клавиатуры,
        // iOS 26): фон одним слоем на самом верху тела экрана, `ZStack` +
        // `.ignoresSafeArea()` без ограничения edges.
        ZStack {
            Color.tfBackground.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: TFSpacing.xl) {
                    TFErrorBanner(viewModel.listErrorMessage.map { _ in "Не удалось загрузить сервисные учётки" })

                    Text("Подключение сторонних ИИ-агентов и программ к TaskFlow по протоколу MCP (Model Context Protocol): Гермес, Claude Code, DSH и любой другой MCP-клиент. Подключившийся получает инструкцию и инструменты ниже и работает под своей учёткой с отдельным ключом. Роли TaskFlow сюда не относятся — их запускает сам сервер, и набор у них шире.")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)

                    clientInfoSection

                    if let issued = viewModel.issuedToken {
                        issuedTokenCard(issued)
                    } else if isCreateFormOpen {
                        createForm
                    } else {
                        createButton
                    }

                    accountsSection
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.vertical, TFSpacing.lg)
            }
        }
        .tfNativeHeader("Сервер MCP")
        .task {
            viewModel.configure(currentUser: session.currentUser)
            async let accounts: Void = viewModel.load()
            async let info: Void = viewModel.loadClientInfo()
            _ = await (accounts, info)
        }
        .alert("Удалить учётку «\(pendingDelete?.name ?? "")»?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Удалить", role: .destructive) {
                if let account = pendingDelete { Task { await viewModel.delete(account) } }
                pendingDelete = nil
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Ключ доступа перестанет работать. Если за учёткой остались задачи, сервер откажет.")
        }
        .alert("Переименовать учётку", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Имя", text: $renameDraft)
            Button("Сохранить") {
                if let account = renameTarget {
                    Task { _ = await viewModel.rename(id: account.id, name: renameDraft) }
                }
                renameTarget = nil
            }
            Button("Отмена", role: .cancel) { renameTarget = nil }
        } message: {
            Text(viewModel.renameErrorMessage ?? "")
        }
    }

    private var createButton: some View {
        Button { isCreateFormOpen = true } label: {
            HStack(spacing: TFSpacing.md) {
                Image(systemName: "plus")
                    .foregroundStyle(Color.tfRed)
                Text("Завести сервисную учётку")
                    .tfText(.row)
                    .foregroundStyle(Color.tfText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, TFSpacing.lg)
            .padding(.vertical, TFSpacing.md)
            .overlay {
                RoundedRectangle(cornerRadius: TFRadius.xl)
                    .strokeBorder(Color.tfStroke, style: StrokeStyle(lineWidth: TFBorder.width, dash: [5]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TFTapRowStyle())
    }

    private var createForm: some View {
        TFCard {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                TFTextField("Имя учётки", text: $newName)
                TFErrorBanner(viewModel.createErrorMessage, variant: .block)
                HStack(spacing: TFSpacing.sm) {
                    Button {
                        Task {
                            await viewModel.create(name: newName)
                            if viewModel.issuedToken != nil {
                                newName = ""
                                isCreateFormOpen = false
                            }
                        }
                    } label: {
                        Text("Завести")
                            .tfText(.row).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, TFSpacing.lg)
                            .frame(height: 44)
                            .background(Color.tfRedSolid)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                    }
                    .buttonStyle(TFTapScaleStyle())
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("Отмена") { isCreateFormOpen = false; newName = "" }
                        .tfText(.row)
                        .foregroundStyle(Color.tfSub)
                }
            }
        }
    }

    private func issuedTokenCard(_ issued: (agentID: String, name: String, token: String)) -> some View {
        TFCard {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                Text("Ключ для «\(issued.name)»")
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                Text("Показывается один раз. Потом можно только выпустить новый.")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                Text(issued.token)
                    .tfMonospaced(12, relativeTo: .caption)
                    .foregroundStyle(Color.tfText)
                    .padding(TFSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.tfCard2)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                    .textSelection(.enabled)
                HStack(spacing: TFSpacing.sm) {
                    Button {
                        UIPasteboard.general.string = issued.token
                        isKeyCopied = true
                    } label: {
                        Text(isKeyCopied ? "Скопировано" : "Скопировать")
                            .tfText(.row).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, TFSpacing.lg)
                            .frame(height: 44)
                            .background(Color.tfRedSolid)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                    }
                    .buttonStyle(TFTapScaleStyle())
                    Button("Готово") { viewModel.dismissIssuedToken(); isKeyCopied = false }
                        .tfText(.row)
                        .foregroundStyle(Color.tfSub)
                }
            }
        }
    }

    // MARK: - Что получает подключившийся

    private enum ClientInfoRow { case instructions, tools, rules }

    private var clientInfoSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Что получает подключившийся")
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    infoRow(.instructions, title: "Инструкция при подключении", count: nil)
                    TFDivider(inset: TFSpacing.lg)
                    infoRow(.tools, title: "Инструменты", count: viewModel.manifest?.tools.count)
                    TFDivider(inset: TFSpacing.lg)
                    infoRow(.rules, title: "Полные правила", count: viewModel.rules.isEmpty ? nil : viewModel.rules.count)
                }
            }
        }
    }

    @ViewBuilder
    private func infoRow(_ row: ClientInfoRow, title: String, count: Int?) -> some View {
        let isOpen = expandedInfo == row
        VStack(alignment: .leading, spacing: 0) {
            Button { expandedInfo = isOpen ? nil : row } label: {
                HStack(spacing: TFSpacing.md) {
                    Text(title).tfText(.body).foregroundStyle(Color.tfText)
                    Spacer(minLength: TFSpacing.sm)
                    if let count {
                        Text("\(count)").tfText(.action).foregroundStyle(Color.tfDim)
                    }
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.tfDim)
                }
                .padding(.horizontal, TFSpacing.lg)
                .frame(minHeight: TFField.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                infoContent(row)
                    .padding(.horizontal, TFSpacing.lg)
                    .padding(.bottom, TFSpacing.md)
            }
        }
    }

    @ViewBuilder
    private func infoContent(_ row: ClientInfoRow) -> some View {
        switch row {
        case .instructions:
            if let text = viewModel.manifest?.instructions {
                Text(text)
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .textSelection(.enabled)
            } else {
                unavailable
            }
        case .tools:
            if let tools = viewModel.manifest?.tools {
                VStack(alignment: .leading, spacing: TFSpacing.md) {
                    ForEach(tools) { tool in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.name)
                                .tfMonospaced(12, relativeTo: .caption)
                                .foregroundStyle(Color.tfText)
                            Text(tool.description)
                                .tfText(.action)
                                .foregroundStyle(Color.tfSub)
                        }
                    }
                }
                .textSelection(.enabled)
            } else {
                unavailable
            }
        case .rules:
            if viewModel.rules.isEmpty {
                unavailable
            } else {
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    ForEach(Array(viewModel.rules.enumerated()), id: \.offset) { index, rule in
                        Text("\(index + 1). \(rule)")
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                    }
                }
                .textSelection(.enabled)
            }
        }
    }

    private var unavailable: some View {
        Text("Не удалось получить с сервера")
            .tfText(.action)
            .foregroundStyle(Color.tfDim)
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Учётки")
            if viewModel.isLoading && viewModel.accounts.isEmpty {
                TFLoading(.block)
            }
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.accounts.enumerated()), id: \.element.id) { index, account in
                        if index > 0 { TFDivider(inset: rowDividerInset) }
                        accountRow(account)
                    }
                    if !viewModel.isLoading && viewModel.accounts.isEmpty {
                        Text("Сервисных учёток нет")
                            .tfText(.action)
                            .foregroundStyle(Color.tfDim)
                            .padding(TFSpacing.md)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func accountRow(_ account: ApiUser) -> some View {
        VStack(spacing: 0) {
            let content = HStack(spacing: TFSpacing.md) {
                Circle()
                    .fill(Color(hex: account.avatarColor ?? TFHexDefault.unassigned))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(account.initials ?? "?")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name).tfText(.body).foregroundStyle(Color.tfText).lineLimit(1)
                    Text(account.id)
                        .tfMonospaced(11, relativeTo: .caption)
                        .foregroundStyle(Color.tfDim)
                        .lineLimit(1)
                }
                Spacer(minLength: TFSpacing.sm)
                Image(systemName: viewModel.isExpanded(account.id) ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.tfDim)
            }
            .padding(.horizontal, TFSpacing.lg)
            .frame(minHeight: TFField.height)
            .contentShape(Rectangle())

            if viewModel.isOwner {
                Button { viewModel.toggleExpand(account.id) } label: { content }
                    .buttonStyle(.plain)
            } else {
                content
            }

            if viewModel.isExpanded(account.id) {
                expandedPanel(account)
            }
        }
    }

    @ViewBuilder
    private func expandedPanel(_ account: ApiUser) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            if let token = viewModel.realToken(for: account.id) {
                HStack(spacing: TFSpacing.sm) {
                    Text(viewModel.isTokenRevealed(account.id) ? token : "•••• •••• ••••")
                        .tfMonospaced(13, relativeTo: .footnote)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button { viewModel.toggleTokenReveal(account.id) } label: {
                        Image(systemName: viewModel.isTokenRevealed(account.id) ? "eye.slash" : "eye")
                            .foregroundStyle(Color.tfDim)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                TFTextField("Введите ключ вручную", text: Binding(
                    get: { viewModel.tokenDraft(for: account.id) },
                    set: { viewModel.updateTokenDraft(account.id, value: $0) }
                ), icon: "key.fill")
                HStack(spacing: TFSpacing.sm) {
                    Button { Task { _ = await viewModel.saveToken(account.id) } } label: {
                        Text("Сохранить")
                            .tfText(.row).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, TFSpacing.lg)
                            .frame(height: 36)
                            .background(Color.tfRedSolid)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                    }
                    .buttonStyle(TFTapScaleStyle())
                    .disabled(viewModel.tokenDraft(for: account.id).trimmingCharacters(in: .whitespaces).isEmpty)

                    Button { Task { _ = await viewModel.rotateToken(account.id) } } label: {
                        Text("Выпустить новый")
                            .tfText(.row)
                            .foregroundStyle(Color.tfSub)
                            .padding(.horizontal, TFSpacing.lg)
                            .frame(height: 36)
                            .background(Color.tfCard2)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                    }
                    .buttonStyle(TFTapScaleStyle())
                }
            }

            if viewModel.isOwner {
                HStack(spacing: TFSpacing.lg) {
                    Button("Переименовать") { rename(account) }
                        .tfText(.action)
                        .foregroundStyle(Color.tfBlue)
                    Button("Удалить") { pendingDelete = account }
                        .tfText(.action)
                        .foregroundStyle(Color.tfRed)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.bottom, TFSpacing.md)
    }

    private func rename(_ account: ApiUser) {
        renameDraft = account.name
        renameTarget = account
    }

    @State private var renameTarget: ApiUser?
    @State private var renameDraft = ""

    private var rowDividerInset: CGFloat { TFSpacing.lg + 36 + TFSpacing.md }
}
