import SwiftUI
import Observation

/// LOCK-180 (этап 8): простой статус Pi Runtime. Не пользовательский раздел —
/// строка внутри «Настройки → Сервер».
///
/// Показываем только здравое: online/offline, версия, сколько провайдеров и
/// моделей, когда проверяли. Ни credentials, ни auth.json, ни докер-внутренности
/// наружу не выносятся — их тут и нет.
@MainActor
@Observable
final class RuntimeStatusViewModel {
    private let api = APIClient()

    var status: RuntimeStatus?
    var providers: [RuntimeProvider] = []
    var models: [RuntimeModel] = []
    var isLoading = false
    var errorMessage: String?
    var lastCheckedAt: Date?

    func load() async {
        if status == nil { isLoading = true }
        defer { isLoading = false }
        do {
            async let statusTask = api.runtimeStatus()
            async let providersTask = api.runtimeProviders()
            async let modelsTask = api.runtimeModels()
            status = try await statusTask
            providers = (try? await providersTask) ?? providers
            models = (try? await modelsTask) ?? models
            lastCheckedAt = Date()
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    var connectedProviders: Int { providers.filter { $0.status == .connected }.count }
    var availableModels: Int { models.filter { $0.available }.count }
}

struct RuntimeStatusScreen: View {
    @State private var viewModel = RuntimeStatusViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.xl) {
                TFErrorBanner(viewModel.errorMessage)

                if viewModel.isLoading && viewModel.status == nil {
                    TFLoading(.block)
                }

                if let status = viewModel.status {
                    TFCard(padding: 0) {
                        VStack(spacing: 0) {
                            statusRow(status)
                            TFDivider(inset: rowDividerInset)
                            infoRow(icon: "number", title: "Версия", value: status.version)
                            TFDivider(inset: rowDividerInset)
                            infoRow(
                                icon: "shippingbox",
                                title: "Провайдеры",
                                value: "\(viewModel.connectedProviders) из \(viewModel.providers.count) подключены"
                            )
                            TFDivider(inset: rowDividerInset)
                            infoRow(
                                icon: "cpu",
                                title: "Модели",
                                value: "\(viewModel.availableModels) из \(viewModel.models.count) доступны"
                            )
                            if let checked = viewModel.lastCheckedAt {
                                TFDivider(inset: rowDividerInset)
                                infoRow(icon: "clock", title: "Проверено", value: RelativeTime.relative(from: checked))
                            }
                        }
                    }

                    Text("Pi — общий исполнитель всех ролей. В обычной работе приложения он не показывается: вы видите роль и модель, а не runtime.")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                        .padding(.horizontal, TFSpacing.sm)
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.vertical, TFSpacing.lg)
        }
        .background(Color.tfBackground)
        .tfNativeHeader("Pi Runtime")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func statusRow(_ status: RuntimeStatus) -> some View {
        HStack(spacing: TFSpacing.md) {
            Circle()
                .fill(status.isOnline ? Color.tfGreen : Color.tfDim)
                .frame(width: 8, height: 8)
            Text(status.statusTitle)
                .tfText(.body)
                .foregroundStyle(Color.tfText)
            Spacer()
        }
        .padding(.horizontal, TFSpacing.lg)
        .frame(minHeight: TFField.height)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: TFSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: TFIconSize.sm))
                .foregroundStyle(Color.tfDim)
                .frame(width: 22)
            Text(title)
                .tfText(.action)
                .foregroundStyle(Color.tfText)
            Spacer()
            Text(value)
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, TFSpacing.lg)
        .frame(minHeight: TFField.height)
    }

    private var rowDividerInset: CGFloat { TFSpacing.lg + 22 + TFSpacing.md }
}

/// Строка «Pi Runtime» внутри «Настройки → Сервер» — статус и число моделей
/// без открытия отдельного экрана. Намеренно без своей карточки: живёт внутри
/// карточки секции «Сервер».
struct RuntimeStatusRow: View {
    @State private var viewModel = RuntimeStatusViewModel()

    var body: some View {
        NavigationLink(value: AppRoute.runtimeStatus) {
            TFListRow(
                icon: "bolt.horizontal.circle",
                iconStyle: .plain,
                title: "Pi Runtime",
                trailing: AnyView(valueText),
                titleStyle: .action,
                verticalPadding: TFSpacing.xs
            )
        }
        .buttonStyle(.plain)
        .task { if viewModel.status == nil { await viewModel.load() } }
    }

    @ViewBuilder
    private var valueText: some View {
        if let status = viewModel.status {
            HStack(spacing: 6) {
                Circle()
                    .fill(status.isOnline ? Color.tfGreen : Color.tfDim)
                    .frame(width: 7, height: 7)
                Text("\(status.statusTitle) · \(viewModel.models.count) моделей")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.tfDim)
            }
        } else if viewModel.isLoading {
            ProgressView()
        } else {
            HStack(spacing: 4) {
                Text("недоступен").tfText(.action).foregroundStyle(Color.tfDim)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.tfDim)
            }
        }
    }
}
