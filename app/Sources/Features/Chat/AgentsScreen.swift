import SwiftUI

/// «Команда» — плоский список сотрудников-ролей (LOCK-176 → переделан в
/// LOCK-183, дополнен в LOCK-205).
///
/// Данные — `GET /api/roles?all=1`: владелец видит и отключённые, чтобы
/// было что включить обратно. Список делится на две секции (включённые
/// сверху, отключённые — внизу), Pi и провайдеры наружу не выносятся.
struct AgentsScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var taskStore
    @State private var viewModel = AgentsViewModel()
    @State private var editorMode: RoleEditorSheet.Mode?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.lg) {
                TFErrorBanner(viewModel.listErrorMessage.map { _ in "Не удалось загрузить команду" })

                if !viewModel.summaryText.isEmpty {
                    Text(viewModel.summaryText)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                }

                if let ready = viewModel.runtimeReady, !ready, !viewModel.profiles.isEmpty {
                    runtimeDownBanner
                }

                if viewModel.isOwner {
                    runJobsEntry
                    memoryEntry
                }
                enabledSection
                if !viewModel.disabledProfiles.isEmpty {
                    disabledSection
                }
                roleInfoSection
            }
            .padding(.vertical, TFSpacing.lg)
        }
        .background(Color.tfBackground)
        .tfNativeHeader("Команда")
        .toolbar {
            // Кнопка «+» есть только у владельца — это единственный, кто
            // может создать роль. `agentProfile(id:)` маршрут остаётся в
            // `AppRoute`, но из «Команды» теперь не открывается: правка
            // идёт через тот же лист, что и создание.
            if viewModel.isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorMode = .create
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Новая роль")
                }
            }
        }
        .task {
            viewModel.configure(currentUser: session.currentUser)
            viewModel.start()
        }
        .onDisappear { viewModel.stop() }
        .sheet(item: $editorMode) { mode in
            RoleEditorSheet(mode: mode, viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var runtimeDownBanner: some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.tfOrange)
            Text("Исполнитель не запущен — роли не начнут работу, пока служба не поднимется.")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            Spacer(minLength: 0)
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    /// Вход в очередь запусков ролей (LOCK-208) — только владельцу: сервер
    /// остальным отвечает `403`. Строка как в «Настройках» (`navRow`).
    private var runJobsEntry: some View {
        TFCard(padding: 0) {
            NavigationLink(value: AppRoute.roleRunJobs) {
                TFListRow(
                    icon: "bolt.horizontal", iconStyle: .plain, title: "Запуски агентов",
                    trailing: AnyView(
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.tfDim)
                    ),
                    titleStyle: .action, verticalPadding: TFSpacing.xs
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    /// Вход в память ролей (02.10.2026): что роли запомнили, файлы,
    /// правка и закрепление — только владельцу.
    private var memoryEntry: some View {
        TFCard(padding: 0) {
            NavigationLink(value: AppRoute.memory) {
                TFListRow(
                    icon: "brain", iconStyle: .plain, title: "Память команды",
                    trailing: AnyView(
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.tfDim)
                    ),
                    titleStyle: .action, verticalPadding: TFSpacing.xs
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("memory-entry")
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private var enabledSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("В команде")
            teamCard(profiles: viewModel.enabledProfiles)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private var disabledSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Отключённые")
            teamCard(profiles: viewModel.disabledProfiles, dimmed: true)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    /// Список ролей внутри одной карточки — `dimmed` затемняет строки
    /// отключённых, чтобы отделить их от рабочих без отдельной визуальной
    /// ветки в дизайн-системе.
    private func teamCard(profiles: [RoleProfile], dimmed: Bool = false) -> some View {
        TFCard(padding: 0) {
            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.profiles.isEmpty {
                    TFLoading(.block)
                }
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 {
                        TFDivider(inset: TFSpacing.lg + 36 + TFSpacing.md)
                    }
                    row(for: profile, dimmed: dimmed)
                }
                if !viewModel.isLoading && profiles.isEmpty {
                    Text("Нет ролей")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                        .padding(TFSpacing.md)
                }
            }
        }
    }

    /// Тап открывает лист правки — для всех ролей одинаково. Внутри листа
    /// действия («Сохранить», «Отключить/Включить») есть только у владельца:
    /// сервер отдаёт `403` на «не владелец», и UI не показывает то, что
    /// всё равно упрётся в ошибку.
    @ViewBuilder
    private func row(for profile: RoleProfile, dimmed: Bool) -> some View {
        if viewModel.isOwner {
            Button {
                editorMode = .edit(profile)
            } label: {
                AgentRow(profile: profile, currentTask: currentTask(for: profile))
            }
            .buttonStyle(.plain)
            .opacity(dimmed ? 0.55 : 1)
        } else {
            NavigationLink(value: AppRoute.agentProfile(id: profile.role)) {
                AgentRow(profile: profile, currentTask: currentTask(for: profile))
            }
            .buttonStyle(.plain)
            .opacity(dimmed ? 0.55 : 1)
        }
    }

    /// Текущая задача роли из общего стора — для названия и времени. Ищем по
    /// id из профиля, чтобы не путать с просто назначенными задачами.
    private func currentTask(for profile: RoleProfile) -> ApiTask? {
        guard let id = profile.currentTask?.id else { return nil }
        return taskStore.tasks.first { $0.id == id }
    }

    private var roleInfoSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Роль агента")
            TFCard {
                VStack(alignment: .leading, spacing: TFSpacing.md) {
                    roleInfoRow(color: .tfRed, name: "Владелец", text: "полный доступ ко всем задачам и настройкам")
                    roleInfoRow(color: .tfBlue, name: "Оркестратор", text: "ведёт работу ботов: заводит и правит любые задачи и проекты, назначает исполнителей, но ничего не удаляет")
                    roleInfoRow(color: .tfPurple, name: "Агент", text: "может редактировать назначенные задачи, добавлять комментарии, отмечать выполнение")
                    roleInfoRow(color: .tfDim, name: "Наблюдатель", text: "только просмотр")
                }
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private func roleInfoRow(color: Color, name: String, text: String) -> some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            Text(name)
                .tfText(.meta)
                .foregroundStyle(color)
                .padding(.horizontal, TFSpacing.sm)
                .padding(.vertical, 2)
                .background(color.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
            Text(text)
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
        }
    }
}