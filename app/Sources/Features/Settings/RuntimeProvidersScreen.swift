import SwiftUI
import Observation

/// LOCK-179 (этап 6): «Модели и провайдеры» — серверный AI. Отделено от
/// «На устройстве» (`VoiceModelsScreen`, локальные модели и диктовка).
///
/// Данные — только с TaskFlow Server / Pi Runtime (`GET /api/runtime/providers`,
/// `/api/runtime/models`). Клиент не хранит credentials и не решает, какая
/// модель «правильная».
@MainActor
@Observable
final class RuntimeProvidersViewModel {
    private let api = APIClient()

    var providers: [RuntimeProvider] = []
    var models: [RuntimeModel] = []
    var isLoading = false
    var errorMessage: String?

    func load() async {
        if providers.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            async let providersTask = api.runtimeProviders()
            async let modelsTask = api.runtimeModels()
            providers = try await providersTask
            models = try await modelsTask
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func models(for providerID: String) -> [RuntimeModel] {
        models.filter { $0.provider == providerID }
    }
}

struct RuntimeProvidersScreen: View {
    @State private var viewModel = RuntimeProvidersViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.xl) {
                TFErrorBanner(viewModel.errorMessage)

                providersSection
                modelsSection
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.vertical, TFSpacing.lg)
        }
        .background(Color.tfBackground)
        .tfNativeHeader("Модели и провайдеры")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Провайдеры")
            if viewModel.isLoading && viewModel.providers.isEmpty {
                TFLoading(.block)
            }
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.providers.enumerated()), id: \.element.id) { index, provider in
                        if index > 0 { TFDivider(inset: rowDividerInset) }
                        NavigationLink(value: AppRoute.providerDetail(providerID: provider.id)) {
                            providerRow(provider)
                        }
                        .buttonStyle(.plain)
                    }
                    if !viewModel.isLoading && viewModel.providers.isEmpty {
                        Text("Сервер не вернул провайдеров")
                            .tfText(.action)
                            .foregroundStyle(Color.tfDim)
                            .padding(TFSpacing.md)
                    }
                }
            }
        }
    }

    private func providerRow(_ provider: RuntimeProvider) -> some View {
        HStack(spacing: TFSpacing.md) {
            Circle()
                .fill(statusColor(provider.status))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .tfText(.action)
                    .foregroundStyle(Color.tfText)
                Text(authLabel(provider))
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
            }
            Spacer(minLength: TFSpacing.sm)
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundStyle(Color.tfDim)
        }
        .padding(.horizontal, TFSpacing.lg)
        .frame(minHeight: TFField.height)
        .contentShape(Rectangle())
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Доступные модели")
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.models.enumerated()), id: \.element.uid) { index, model in
                        if index > 0 { TFDivider(inset: rowDividerInset) }
                        HStack(spacing: TFSpacing.md) {
                            Image(systemName: model.available ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(model.available ? Color.tfGreen : Color.tfDim)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName)
                                    .tfText(.action)
                                    .foregroundStyle(Color.tfText)
                                Text(model.provider)
                                    .tfText(.caption)
                                    .foregroundStyle(Color.tfSub)
                            }
                            Spacer(minLength: TFSpacing.sm)
                            if !model.available {
                                Text("нет доступа")
                                    .tfText(.caption)
                                    .foregroundStyle(Color.tfDim)
                            }
                        }
                        .padding(.horizontal, TFSpacing.lg)
                        .frame(minHeight: TFField.height)
                    }
                    if !viewModel.isLoading && viewModel.models.isEmpty {
                        Text("Сервер не вернул моделей")
                            .tfText(.action)
                            .foregroundStyle(Color.tfDim)
                            .padding(TFSpacing.md)
                    }
                }
            }
        }
    }

    private func statusColor(_ status: ProviderStatus) -> Color {
        switch status {
        case .connected: .tfGreen
        case .disconnected: .tfDim
        case .expired: .tfOrange
        case .unknown: .tfDim
        }
    }

    private func authLabel(_ provider: RuntimeProvider) -> String {
        switch provider.authType {
        case .oauth: "OAuth"
        case .apiKey: "API-ключ"
        default: provider.status.title
        }
    }

    private var rowDividerInset: CGFloat { TFSpacing.lg + 8 + TFSpacing.md }
}
