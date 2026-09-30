import SwiftUI
import Observation

/// LOCK-179 (этап 7): карточка провайдера и авторизация.
///
/// TaskFlow iOS НЕ хранит credentials: и API-ключ, и OAuth уходят на сервер,
/// который пишет их в Pi/vault. Здесь только инициируем flow и показываем
/// статус. Credentials с телефона не сохраняются.
@MainActor
@Observable
final class ProviderDetailViewModel {
    let providerID: String
    private let api = APIClient()

    var provider: RuntimeProvider?
    var models: [RuntimeModel] = []
    var isLoading = false
    var errorMessage: String?

    var apiKeyDraft = ""
    var isSavingKey = false

    /// Активная OAuth-сессия (если идёт). `nil` — авторизация не запущена.
    var session: AuthSession?
    var isStartingOAuth = false
    var promptDraft = ""
    var isSubmittingPrompt = false

    private var pollTask: Task<Void, Never>?

    init(providerID: String) {
        self.providerID = providerID
    }

    /// Экран ушёл — гасим опрос сессии. Отдельным методом, а не `deinit`:
    /// `deinit` у `@MainActor`-класса не имеет доступа к изолированному
    /// состоянию.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func load() async {
        if provider == nil { isLoading = true }
        defer { isLoading = false }
        do {
            async let providersTask = api.runtimeProviders()
            async let modelsTask = api.runtimeModels()
            let providers = try await providersTask
            models = (try await modelsTask).filter { $0.provider == providerID }
            provider = providers.first { $0.id == providerID }
            errorMessage = provider == nil ? "Провайдер не найден на сервере" : nil
        } catch {
            errorMessage = Self.message(error)
        }
    }

    /// Записать API-ключ на сервер (persistent в Pi).
    @discardableResult
    func saveAPIKey() async -> Bool {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        isSavingKey = true
        defer { isSavingKey = false }
        do {
            _ = try await api.startProviderAuth(provider: providerID, apiKey: key)
            apiKeyDraft = ""
            await load()
            return true
        } catch {
            errorMessage = Self.message(error)
            return false
        }
    }

    /// Старт OAuth: сервер отвечает 202, дальше опрашиваем сессию.
    func startOAuth() async {
        isStartingOAuth = true
        errorMessage = nil
        do {
            let start = try await api.startProviderAuth(provider: providerID)
            guard let sessionID = start.authSessionID else {
                // Сервер ответил как при записи ключа — значит подключение уже есть.
                await load()
                isStartingOAuth = false
                return
            }
            session = try await api.runtimeAuthSession(id: sessionID)
            startPolling(sessionID: sessionID)
        } catch {
            errorMessage = Self.message(error)
        }
        isStartingOAuth = false
    }

    private func startPolling(sessionID: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                do {
                    let updated = try await self.api.runtimeAuthSession(id: sessionID)
                    self.session = updated
                    if updated.status.isFinished {
                        if updated.status == .connected { await self.load() }
                        self.session = updated
                        break
                    }
                } catch {
                    break
                }
            }
        }
    }

    func submitPrompt() async {
        guard let session else { return }
        let value = promptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isSubmittingPrompt = true
        defer { isSubmittingPrompt = false }
        do {
            try await api.submitProviderAuthInput(sessionID: session.id, value: value)
            promptDraft = ""
        } catch {
            errorMessage = Self.message(error)
        }
    }

    func cancelSession() async {
        guard let session else { return }
        pollTask?.cancel()
        try? await api.cancelProviderAuth(sessionID: session.id)
        self.session = nil
    }

    /// URL авторизации из событий сессии.
    var authURL: URL? {
        for event in session?.events.reversed() ?? [] where event.type == "auth_url" {
            if case .string(let raw) = event.data["url"], let url = URL(string: raw) {
                return url
            }
        }
        return nil
    }

    var lastMessage: String? {
        guard let event = session?.events.last else { return nil }
        if case .string(let message) = event.data["message"], !message.isEmpty { return message }
        return nil
    }

    private static func message(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}

struct ProviderDetailScreen: View {
    let providerID: String
    @State private var viewModel: ProviderDetailViewModel
    @Environment(\.openURL) private var openURL

    init(providerID: String) {
        self.providerID = providerID
        _viewModel = State(initialValue: ProviderDetailViewModel(providerID: providerID))
    }

    var body: some View {
        // Урок 2026-09-25 (чёрные треугольники в углах системной клавиатуры,
        // iOS 26): фон одним слоем на самом верху тела экрана, `ZStack` +
        // `.ignoresSafeArea()` без ограничения edges.
        ZStack {
            Color.tfBackground.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: TFSpacing.xl) {
                    TFErrorBanner(viewModel.errorMessage)

                    if let provider = viewModel.provider {
                        statusSection(provider)
                        if provider.supportsAPIKey { apiKeySection }
                        if provider.supportsOAuth { oauthSection }
                        if viewModel.session != nil { sessionSection }
                        modelsSection
                    } else if viewModel.isLoading {
                        TFLoading(.block)
                    }
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.vertical, TFSpacing.lg)
            }
        }
        .tfNativeHeader(viewModel.provider?.name ?? "Провайдер")
        .task { await viewModel.load() }
        .onDisappear { viewModel.stopPolling() }
    }

    private func statusSection(_ provider: RuntimeProvider) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Авторизация")
            TFCard {
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    HStack(spacing: TFSpacing.sm) {
                        Circle()
                            .fill(provider.status == .connected ? Color.tfGreen : Color.tfDim)
                            .frame(width: 8, height: 8)
                        Text(provider.status.title)
                            .tfText(.body)
                            .foregroundStyle(Color.tfText)
                    }
                    Text("Credentials хранятся на сервере в Pi и на iPhone не сохраняются.")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                }
            }
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("API-ключ")
            TFCard {
                VStack(alignment: .leading, spacing: TFSpacing.md) {
                    TFTextField("Вставьте ключ провайдера", text: $viewModel.apiKeyDraft, icon: "key.fill")
                    Button {
                        Task { _ = await viewModel.saveAPIKey() }
                    } label: {
                        Text(viewModel.isSavingKey ? "Сохраняю…" : "Сохранить ключ")
                            .tfText(.row).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, TFSpacing.lg)
                            .frame(height: 44)
                            .background(Color.tfRedSolid)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                    }
                    .buttonStyle(TFTapScaleStyle())
                    .disabled(viewModel.isSavingKey
                              || viewModel.apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var oauthSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("OAuth")
            TFCard {
                VStack(alignment: .leading, spacing: TFSpacing.md) {
                    Text("Откроется системный браузер. После входа провайдер подтвердит доступ — вернитесь в приложение, статус обновится сам.")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                    Button {
                        Task { await viewModel.startOAuth() }
                    } label: {
                        Text(viewModel.provider?.status == .connected ? "Переподключить" : "Подключить через браузер")
                            .tfText(.row).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, TFSpacing.lg)
                            .frame(height: 44)
                            .background(Color.tfRedSolid)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                    }
                    .buttonStyle(TFTapScaleStyle())
                    .disabled(viewModel.isStartingOAuth)
                }
            }
        }
    }

    @ViewBuilder
    private var sessionSection: some View {
        if let session = viewModel.session {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                TFSectionHeader("Подключение")
                TFCard {
                    VStack(alignment: .leading, spacing: TFSpacing.md) {
                        Text(session.status.title)
                            .tfText(.action)
                            .foregroundStyle(Color.tfText)
                        if let message = viewModel.lastMessage {
                            Text(message)
                                .tfText(.caption)
                                .foregroundStyle(Color.tfSub)
                        }
                        if let url = viewModel.authURL {
                            Button {
                                openURL(url)
                            } label: {
                                Text("Открыть браузер")
                                    .tfText(.row).fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, TFSpacing.lg)
                                    .frame(height: 44)
                                    .background(Color.tfBlue)
                                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                            }
                            .buttonStyle(TFTapScaleStyle())
                        }
                        if let prompt = session.currentPrompt {
                            Text(prompt.message)
                                .tfText(.action)
                                .foregroundStyle(Color.tfText)
                            TFTextField(prompt.placeholder ?? "Введите значение", text: $viewModel.promptDraft)
                            Button {
                                Task { await viewModel.submitPrompt() }
                            } label: {
                                Text("Отправить")
                                    .tfText(.row).fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, TFSpacing.lg)
                                    .frame(height: 44)
                                    .background(Color.tfRedSolid)
                                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                            }
                            .buttonStyle(TFTapScaleStyle())
                            .disabled(viewModel.isSubmittingPrompt
                                      || viewModel.promptDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if !session.status.isFinished {
                            Button("Отменить") { Task { await viewModel.cancelSession() } }
                                .tfText(.action)
                                .foregroundStyle(Color.tfSub)
                        }
                    }
                }
            }
        }
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Модели")
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.models.enumerated()), id: \.element.uid) { index, model in
                        if index > 0 { TFDivider(inset: rowDividerInset) }
                        HStack {
                            Text(model.displayName)
                                .tfText(.action)
                                .foregroundStyle(Color.tfText)
                            Spacer()
                            if !model.available {
                                Text("нет доступа")
                                    .tfText(.caption)
                                    .foregroundStyle(Color.tfDim)
                            }
                        }
                        .padding(.horizontal, TFSpacing.lg)
                        .frame(minHeight: TFField.height)
                    }
                    if viewModel.models.isEmpty {
                        Text("Модели не найдены")
                            .tfText(.action)
                            .foregroundStyle(Color.tfDim)
                            .padding(TFSpacing.md)
                    }
                }
            }
        }
    }

    private var rowDividerInset: CGFloat { TFSpacing.lg }
}
