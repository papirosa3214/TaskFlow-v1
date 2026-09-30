import SwiftUI

// «Уведомления» — spec/SCREENS-2.md §13, `/notifications`. Список читаю из
// общего `NotificationStore` (Environment) — прогрет при старте приложения
// и живёт по WS-событию `notification:new`, единый источник истины.
//
// ⚠️ Мутации — НЕ через `NotificationStore.markRead`. Проверено чтением
// живого `server/src/routes/notifications.ts` (только чтение, спека сама
// путей не даёт): реальные роуты — `PATCH /notifications/:id/read` (БЕЗ
// тела), `POST /notifications/read-all`, `DELETE /notifications/:id`.
// `Core/Networking/APIClient+Notifications.swift.markNotificationRead` шлёт
// `PATCH /notifications/:id` С телом `{read:true}` — такого маршрута на
// сервере нет вовсе, запрос получит 404. Использую вместо него
// `directoryMarkNotificationRead`/`directoryMarkAllNotificationsRead` из
// `Support/DirectoryAPI.swift` (уже заведены параллельным исполнителем по
// той же причине) и после успеха перезагружаю стор целиком (`load()`,
// публичный метод) — стор не даёт точечно поправить один элемент
// (`notifications` — `private(set)`), а трогать чужой файл нельзя.
// `deleteNotification` в Core адресом верен — используется как есть.
//
// В отчёте оркестратору: `NotificationStore` стоит обзавестись реальными
// `markRead`/`markAllRead`/`delete` с точечным обновлением массива — иначе
// каждое действие здесь стоит полного рефетча уведомлений.
struct NotificationsScreen: View {
    @Environment(NotificationStore.self) private var notificationStore

    @State private var route: AppRoute?
    @State private var isMarkingAllRead = false
    @State private var markAllErrorMessage: String?
    @State private var rowErrors: [String: String] = [:]

    @State private var serviceTickets: [ServiceTicketSummary] = []
    @State private var serviceTicketDetails: [String: ServiceTicketDetail] = [:]
    @State private var serviceTicketsError: String?
    @State private var isLoadingServiceTickets = false
    @State private var resolutionSheetItem: ServiceTicketResolutionItem?
    @State private var resolutionSheetTaskId: String?
    private let serviceClient = ServiceNotificationsClient()

    private let apiClient = APIClient()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.sm) {
                TFErrorBanner(notificationStore.errorMessage, variant: .inline)
                TFErrorBanner(markAllErrorMessage, variant: .inline)
                TFCard(padding: 0) {
                    VStack(spacing: 0) {
                        NavigationLink {
                            serverNotificationsPage
                        } label: {
                            TFListRow(
                                icon: "server.rack",
                                iconStyle: .plain,
                                title: "Серверные уведомления",
                                subtitle: "Работа сервисов, сбои и результаты диагностики",
                                trailing: AnyView(
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.tfDim)
                                ),
                                titleStyle: .body,
                                verticalPadding: TFSpacing.md
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("notifications.server-section")
                    }
                }

                if !visibleNotifications.isEmpty {
                    TFCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(visibleNotifications.enumerated()), id: \.element.id) { idx, n in
                                notificationRow(n)
                                if idx < visibleNotifications.count - 1 { TFDivider() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.top, TFSpacing.md)
            .padding(.bottom, TFSpacing.xl)
        }
        .refreshable {
            await notificationStore.load()
            await loadServiceTickets()
        }
        .background(Color.tfBackground)
        // Штатная SwiftUI-шапка (`tfNativeHeader`, просьба владельца
        // 03.09.2026 — «нативные кнопки везде одним элементом»). Была своя
        // ZStack-шапка ради текстовой кнопки «Прочитать все» — системный
        // toolbar принимает текстовую кнопку точно так же, как иконку,
        // отдельный слот под это не нужен был вовсе.
        .tfNativeHeader("Уведомления")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await markAllRead() }
                } label: {
                    Text("Прочитать все")
                }
                .disabled(isMarkingAllRead || allRead)
            }
        }
        .navigationDestination(item: $route) { routeDestination($0) }
        .task {
            await notificationStore.load()
            await loadServiceTickets()
        }
    }

    // Владелец 27.09: серверные сводки — самостоятельная страница.
    private var serverNotificationsPage: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.sm) {
                TFErrorBanner(serviceTicketsError, variant: .inline)
                if isLoadingServiceTickets && serviceTickets.isEmpty {
                    ProgressView("Загрузка серверных уведомлений")
                } else if serviceTickets.isEmpty && serviceTicketsError == nil {
                    Text("Серверных уведомлений пока нет")
                } else {
                    ForEach(serviceTickets) { summary in
                        NotificationTicketCard(
                            summary: summary,
                            detail: serviceTicketDetails[summary.id],
                            onOpenTask: { route = .taskDetail(taskID: $0) },
                            onTapResolutionItem: { item in
                                let fallbackTaskId = serviceTicketDetails[summary.id]?.diagnosticTaskId
                                guard let taskId = item.taskId ?? fallbackTaskId else { return }
                                resolutionSheetItem = item
                                resolutionSheetTaskId = taskId
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.top, TFSpacing.md)
            .padding(.bottom, TFSpacing.xl)
        }
        .background(Color.tfBackground)
        .tfNativeHeader("Серверные уведомления")
        .refreshable { await loadServiceTickets() }
        .sheet(item: $resolutionSheetItem) { item in
            ServiceTicketResolutionSheet(
                item: item,
                taskId: resolutionSheetTaskId ?? "",
                onSubmitted: {
                    resolutionSheetItem = nil
                    resolutionSheetTaskId = nil
                }
            )
        }
    }

    private var allRead: Bool { notificationStore.notifications.allSatisfy(\.read) }

    /// Владелец 27.09.2026: скрываем системный шум, который дублирует то, что
    /// уже видно в «Активности» или на самой доске задач — тут это только про
    /// то, что рисуется на экране, чтение/бейдж непрочитанных на сервере не
    /// трогаем:
    /// - `auto_diagnostic_card` — авто-создание карточки диагностики
    ///   (`inboxTriageWatcher.ts`), шум при любом сбое на .110;
    /// - `agent_watch` — сторож «висит без проекта/исполнителя», не по делу
    ///   в ленте уведомлений, видно и так на доске;
    /// - `commented` — «X прокомментировал: Y» (`subtasks.ts`/`agent-state.ts`),
    ///   уже видно в живой ленте задачи;
    /// - `agent_state` — «Задача заблокирована/на проверке» и т.п. смена
    ///   статуса, тоже уже видно в живой ленте.
    /// Вердикты и назначения также остаются в ленте активности.
    /// `completed` — владелец 27.09.2026 вернул обратно, показываем как есть.
    private static let hiddenNotificationTypes: Set<String> = [
        "auto_diagnostic_card", "agent_watch", "commented", "agent_state", "reviewed", "assigned",
    ]

    private var visibleNotifications: [ApiNotification] {
        notificationStore.notifications.filter { !Self.hiddenNotificationTypes.contains($0.type) }
    }

    // MARK: - Строка уведомления

    private func notificationRow(_ n: ApiNotification) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: TFSpacing.md) {
                avatar(n)

                Button {
                    Task { await open(n) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.text ?? "").tfText(.row).foregroundStyle(Color.tfText)
                        if let title = n.taskTitle, !title.isEmpty {
                            Text(title).tfText(.action).foregroundStyle(Color.tfSub).lineLimit(1)
                        }
                        Text(dateLine(n)).tfText(.meta).foregroundStyle(Color.tfDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TFTapRowStyle())

                HStack(spacing: TFSpacing.xs) {
                    if !n.read {
                        Circle().fill(Color.tfRed).frame(width: 8, height: 8)
                    }
                    Button {
                        Task { await delete(n) }
                    } label: {
                        Image(systemName: "trash").font(.system(size: TFIconSize.sm)).foregroundStyle(Color.tfDim)
                            .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                    }
                    .accessibilityLabel("Удалить")
                    .buttonStyle(TFTapScaleStyle())
                }
            }
            if let error = rowErrors[n.id] {
                TFErrorBanner(error, variant: .inline).padding(.leading, 36 + TFSpacing.md)
            }
        }
        .padding(.horizontal, TFSpacing.md)
        .padding(.vertical, TFSpacing.sm + 2)
    }

    @ViewBuilder
    private func avatar(_ n: ApiNotification) -> some View {
        let hasActor = n.actorId != nil && !(n.actorName ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        if hasActor {
            Circle()
                .fill(n.actorColor.map { Color(hex: $0) } ?? Color(hex: TFHexDefault.unassigned))
                .frame(width: 36, height: 36)
                .overlay {
                    Text(n.actorInitials ?? "?").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                }
        } else {
            Circle()
                .fill(Color.tfCard2)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "gearshape").font(.system(size: 17)).foregroundStyle(Color.tfDim)
                }
        }
    }

    private func dateLine(_ n: ApiNotification) -> String {
        guard let date = n.createdAtDate else { return "" }
        return "\(DirectoryDate.relative(date)) · \(DirectoryDate.absolute(date))"
    }

    // MARK: - Действия

    private func open(_ n: ApiNotification) async {
        rowErrors[n.id] = nil
        if !n.read {
            do {
                try await apiClient.directoryMarkNotificationRead(id: n.id)
                await notificationStore.load()
            } catch {
                rowErrors[n.id] = "Не удалось отметить прочитанным"
            }
        }
        guard let taskId = n.taskId else { return }
        // Тап по уведомлению на уже удалённую задачу раньше вёл на мёртвый
        // экран «Задача не найдена» — тупик, владелец 27.09.2026. Проверяем
        // существование перед переходом; если задачи нет — остаёмся в списке
        // и показываем это прямо в строке (там уже сохранено `taskTitle`).
        do {
            _ = try await apiClient.task(id: taskId)
            route = .taskDetail(taskID: taskId)
        } catch {
            rowErrors[n.id] = "Задача удалена или недоступна"
        }
    }

    private func delete(_ n: ApiNotification) async {
        rowErrors[n.id] = nil
        do {
            try await apiClient.deleteNotification(id: n.id)
            await notificationStore.load()
        } catch {
            rowErrors[n.id] = "Не удалось удалить уведомление"
        }
    }

    private func loadServiceTickets() async {
        // `.task` (первичная загрузка) и `.refreshable` (pull-to-refresh) оба
        // зовут этот метод — без гварда они бы мутировали одни и те же
        // `@State`-массивы одновременно (найдено финальным ревью LOCK-227,
        // Minor: "нет in-flight guard").
        guard !isLoadingServiceTickets else { return }
        isLoadingServiceTickets = true
        defer { isLoadingServiceTickets = false }

        serviceTicketsError = nil
        // Локальный календарный день устройства, НЕ UTC — иначе ночью по
        // Москве (UTC+3) сегодняшние тикеты запрашиваются как "вчера" (см.
        // `ServiceTicketDate.localDayString`, Critical #1 финального ревью).
        let today = ServiceTicketDate.localDayString()
        do {
            let list = try await serviceClient.fetchInbox(date: today)
            serviceTickets = list
            for summary in list where serviceTicketDetails[summary.id] == nil {
                // Сбой ОДНОГО тикета не должен обрывать загрузку деталей для
                // всех остальных и показывать общий баннер ошибки поверх уже
                // отрисованного списка — карточка и так падает на fallback
                // `summary.snippet`, когда `detail` не пришёл (Important #2
                // финального ревью).
                do {
                    let raw = try await serviceClient.fetchRaw(path: summary.path)
                    if let detail = ServiceTicketMarkdownParser.parse(raw) {
                        serviceTicketDetails[summary.id] = detail
                    }
                } catch {
                    continue
                }
            }
        } catch {
            serviceTicketsError = "Не удалось загрузить сводки сторонних сервисов"
        }
    }

    private func markAllRead() async {
        guard !isMarkingAllRead, !allRead else { return }
        isMarkingAllRead = true
        markAllErrorMessage = nil
        defer { isMarkingAllRead = false }
        do {
            try await apiClient.directoryMarkAllNotificationsRead()
            await notificationStore.load()
        } catch {
            markAllErrorMessage = "Не удалось отметить все прочитанными"
        }
    }
}
