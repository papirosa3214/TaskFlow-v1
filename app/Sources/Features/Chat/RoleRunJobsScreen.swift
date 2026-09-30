import SwiftUI

/// «Запуски агентов» — очередь запусков ролей (LOCK-208).
///
/// С 23.09.2026 сервер будит роль не напрямую, а через очередь
/// `role_run_jobs`: каждый повод (назначение, комментарий владельца, сдача
/// на проверку, продолжение захода) лежит записью до конца. Экран
/// показывает, что сейчас в очереди и в работе, и что закончилось —
/// чтобы владелец видел работу агентов вживую, а не угадывал по тишине.
///
/// Данные — `GET /api/role-run-jobs`, раз в 5 с, пока экран открыт.
/// Названия задач и ролей в записи нет: берём из стора задач и каталога
/// ролей, недостающую карточку дочитываем по id.
struct RoleRunJobsScreen: View {
    @Environment(TaskStore.self) private var taskStore
    @State private var jobs: [RoleRunJob] = []
    @State private var roleTitles: [String: String] = [:]
    @State private var fetchedTasks: [String: ApiTask] = [:]
    @State private var missingTasks: Set<String> = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var busyJobID: String?

    private let api = APIClient()

    private var activeJobs: [RoleRunJob] { jobs.filter(\.isActive) }
    private var finishedJobs: [RoleRunJob] { jobs.filter { !$0.isActive } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.lg) {
                TFErrorBanner(loadError.map { _ in "Не удалось загрузить запуски" })

                if isLoading && jobs.isEmpty {
                    TFLoading(.block)
                } else if jobs.isEmpty {
                    TFEmptyState(
                        icon: "bolt.horizontal",
                        text: "Запусков пока нет",
                        description: "Здесь появится агент, как только ему назначат задачу"
                    )
                } else {
                    section("Сейчас", jobs: activeJobs, emptyText: "Сейчас никто не работает")
                    if !finishedJobs.isEmpty {
                        section("Недавние", jobs: finishedJobs, emptyText: nil)
                    }
                }
            }
            .padding(.vertical, TFSpacing.lg)
        }
        .background(Color.tfBackground)
        .tfNativeHeader("Запуски агентов")
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .alert("Не получилось", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Секции

    @ViewBuilder
    private func section(_ title: String, jobs: [RoleRunJob], emptyText: String?) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader(title)
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                        if index > 0 { TFDivider(inset: TFSpacing.lg) }
                        row(job)
                    }
                    if jobs.isEmpty, let emptyText {
                        Text(emptyText)
                            .tfText(.action)
                            .foregroundStyle(Color.tfDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(TFSpacing.lg)
                    }
                }
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private func row(_ job: RoleRunJob) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            NavigationLink(value: AppRoute.taskDetail(taskID: job.taskId)) {
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                        Text(taskTitle(job.taskId))
                            .tfText(.row)
                            .foregroundStyle(missingTasks.contains(job.taskId) ? Color.tfDim : Color.tfText)
                            .lineLimit(2)
                        Spacer(minLength: TFSpacing.sm)
                        Text(Self.statusTitle(job.status))
                            .tfText(.meta)
                            .foregroundStyle(Self.statusColor(job.status))
                    }
                    Text(metaLine(job))
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                    if let error = job.lastError, !error.isEmpty, job.status != "succeeded" {
                        Text(error)
                            .tfText(.meta)
                            .foregroundStyle(Color.tfRed)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(missingTasks.contains(job.taskId))

            // «Повторить» — только упавшим и отменённым. Пропущенный сервер
            // пропустил намеренно (карточка заблокирована, повод устарел):
            // кнопка под каждым была бы шумом и поводом разбудить агента зря.
            if showsRetry(job) || job.canCancel {
                Button {
                    Task { await act(on: job) }
                } label: {
                    Text(showsRetry(job) ? "Повторить" : "Отменить")
                        .tfText(.action)
                }
                .buttonStyle(.borderless)
                .disabled(busyJobID != nil)
            }
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.md)
    }

    private func showsRetry(_ job: RoleRunJob) -> Bool {
        job.canRetry && job.status != "skipped"
    }

    // MARK: - Подписи

    private func taskTitle(_ id: String) -> String {
        if let task = taskStore.agentWorkTasks.first(where: { $0.id == id })
            ?? taskStore.tasks.first(where: { $0.id == id })
            ?? fetchedTasks[id] {
            return task.title
        }
        return missingTasks.contains(id) ? "Карточка удалена" : "Карточка…"
    }

    /// «Разработчик · назначение · 22:15 · попытка 2 из 3».
    private func metaLine(_ job: RoleRunJob) -> String {
        var parts: [String] = []
        if let role = roleTitle(for: job.taskId) { parts.append(role) }
        parts.append(Self.reasonTitle(job.reason))
        if let date = DateFormats.sqliteUTC(job.updatedAt) {
            parts.append(Self.timeText(date))
        }
        if job.attempts > 1 || job.status == "retry_wait" || job.status == "dead" {
            parts.append("попытка \(job.attempts) из \(job.maxAttempts)")
        }
        return parts.joined(separator: " · ")
    }

    private func roleTitle(for taskID: String) -> String? {
        let task = taskStore.agentWorkTasks.first(where: { $0.id == taskID })
            ?? taskStore.tasks.first(where: { $0.id == taskID })
            ?? fetchedTasks[taskID]
        guard let task else { return nil }
        let key = task.effectiveRole
            ?? task.assigneeId.flatMap { $0.hasPrefix("role_") ? String($0.dropFirst(5)) : nil }
        guard let key else { return nil }
        return roleTitles[key] ?? key
    }

    private static func statusTitle(_ status: String) -> String {
        switch status {
        case "queued": "В очереди"
        case "running": "Работает"
        case "retry_wait": "Ждёт повтора"
        case "succeeded": "Готово"
        case "skipped": "Не понадобился"
        case "dead": "Упал"
        case "cancelled": "Отменён"
        default: status
        }
    }

    private static func statusColor(_ status: String) -> Color {
        switch status {
        case "running": .tfBlue
        case "retry_wait": .tfOrange
        case "succeeded": .tfGreen
        case "dead": .tfRed
        default: .tfSub
        }
    }

    private static func reasonTitle(_ reason: String) -> String {
        switch reason {
        case "assigned": "назначение"
        case "commented": "комментарий"
        case "review": "проверка"
        case "after_run": "продолжение"
        default: reason
        }
    }

    /// Сегодня — «22:35», раньше — «23.09 22:35» (как в списке чатов).
    private static func timeText(_ date: Date) -> String {
        Calendar.autoupdatingCurrent.isDateInToday(date)
            ? clock.string(from: date)
            : dayClock.string(from: date)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM HH:mm"
        return formatter
    }()

    // MARK: - Данные

    private func load() async {
        defer { isLoading = false }
        do {
            jobs = try await api.roleRunJobs()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            return
        }
        if roleTitles.isEmpty, let roles = try? await api.roles(all: true) {
            roleTitles = Dictionary(roles.map { ($0.role, $0.title) }, uniquingKeysWith: { first, _ in first })
        }
        // Карточки, которых нет в сторе (закрытые, чужой проект), — по одной.
        let known = Set(taskStore.agentWorkTasks.map(\.id))
            .union(taskStore.tasks.map(\.id))
            .union(fetchedTasks.keys)
            .union(missingTasks)
        for id in Set(jobs.map(\.taskId)).subtracting(known) {
            if let task = try? await api.task(id: id) {
                fetchedTasks[id] = task
            } else {
                missingTasks.insert(id)
            }
        }
    }

    private func act(on job: RoleRunJob) async {
        busyJobID = job.id
        defer { busyJobID = nil }
        do {
            if job.canRetry {
                try await api.retryRoleRunJob(id: job.id)
            } else {
                try await api.cancelRoleRunJob(id: job.id)
            }
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
