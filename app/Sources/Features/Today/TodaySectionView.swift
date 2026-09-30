import SwiftUI

/// Раздел «Сегодня» внутри «Планирования». Шапку и выбор раздела рисует
/// `UpcomingScreen`; здесь живут только три подви́да и их фильтры.
struct TodaySectionView: View {
    @Binding var layout: TodayLayout
    /// Видимая дата почасового режима принадлежит родителю: так заголовок
    /// месяца сразу меняется при перелистывании через границу месяца.
    @Binding var activeHourDate: String
    var onAddTask: () -> Void = {}
    let plannerViewSwitcher: AnyView
    /// Тот же самый `Menu` «Показывать в разделе», что и у диапазонов —
    /// приходит из `UpcomingScreen`, где живёт его состояние (LOCK-111).
    var sectionCompositionMenu: AnyView = AnyView(EmptyView())
    var visibleProjectIds: Set<String> = []
    var showAgentTasks = false
    var showCompleted = false
    /// Название текущей вкладки списка — уезжает в системную шапку экрана.
    /// Раньше сюда же уходило название видимой колонки доски.
    var onTitleChange: (String) -> Void = { _ in }

    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(SessionStore.self) private var session

    /// Выбранная вкладка живёт между запусками — как и выбранный вид.
    @AppStorage("today_list_tab") private var listTabRaw = TodayListTab.today.rawValue
    private var listTab: TodayListTab { TodayListTab(rawValue: listTabRaw) ?? .today }

    @State private var vm = TodayViewModel()
    @State private var sheetTaskID: TodaySectionTaskID?
    @State private var rescheduleOpen = false
    @State private var rescheduleTask: ApiTask?
    @State private var rescheduleTaskIDs: [String]?

    private var today: String { TodayDate.todayString() }

    /// Заголовок секции, до которой долистали. Пока лента в начале — пусто.
    @State private var pinnedSectionTitle = ""
    /// Высота, на которой заголовок секции прилипает к шапке.
    @State private var pinEdge: CGFloat = 0

    /// Что показать в шапке: у списка — заголовок секции, которую сейчас
    /// читают, а пока ни одна не подошла к кромке — название вкладки. У
    /// почасовой сетки шапку рисует родитель по дате.
    /// Владелец 15.09.2026: «я думал, ты заголовки сделаешь динамическими —
    /// пролистываю, они в центр становятся, а они захардкоженные: здесь
    /// „Сегодня“, а у меня тут же предстоящие, это же уже не сегодня».
    private var titleForHeader: String {
        guard layout == .list else { return "" }
        return pinnedSectionTitle.isEmpty ? listTab.title : pinnedSectionTitle
    }

    private var computation: TodayComputation {
        // Разовые фильтры — свои у экрана, состав раздела — общий с
        // диапазонами и приходит параметрами (LOCK-111).
        var effectiveFilters = vm.filters
        effectiveFilters.showCompleted = showCompleted
        return TodayComputation(
            allTasks: taskStore.tasks,
            currentUser: session.currentUser,
            agents: vm.agents,
            filters: effectiveFilters,
            showAgentTasks: showAgentTasks,
            visibleProjectIds: visibleProjectIds,
            today: today,
            activeHourDate: activeHourDate,
            isLoading: taskStore.isLoading,
            isError: taskStore.errorMessage != nil
        )
    }

    var body: some View {
        let c = computation
        Group {
            if layout == .hours {
                hoursContent(c: c)
            } else {
                // Одна вертикальная прокрутка на весь список — вкладка лишь
                // меняет её содержимое. Второго уровня прокрутки здесь нет
                // намеренно: именно вложенные прокрутки доски ломали
                // системное затухание у шапки.
                ScrollView {
                    listContent(c: c)
                }
                .refreshable { await taskStore.load(silent: true) }
                // Высота, на которой заголовок секции прилипает к шапке.
                // Изнутри прокрутки её не видно (там безопасная зона уже
                // нулевая), поэтому меряем снаружи и отдаём списку.
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).minY + proxy.safeAreaInsets.top
                } action: { pinEdge = $0 }
            }
        }
        .onAppear { onTitleChange(titleForHeader) }
        .onChange(of: listTab) { _, newTab in
            // Сменили вкладку — прежняя секция больше ни при чём, шапка
            // возвращается к названию вкладки, пока не долистают до секции.
            pinnedSectionTitle = ""
            onTitleChange(layout == .list ? newTab.title : "")
        }
        .onChange(of: layout) { _, _ in onTitleChange(titleForHeader) }
        .toolbar {
            // Вкладки списка живут на ЛЕВОЙ кнопке шапки (её рисует
            // `UpcomingScreen`), справа остаются фильтр и выбор раздела —
            // владелец 15.09.2026 отдельно попросил не заводить здесь третью
            // кнопку, а использовать левую.
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    filterMenu(c: c).tfPlannerWideControl()
                    plannerViewSwitcher.tfPlannerWideControl()
                }
            }
        }
        .task { await vm.loadAgentsIfNeeded() }
        .sheet(item: $sheetTaskID) { wrapped in
            NavigationStack { TaskFormScreen(taskID: wrapped.id) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .tfBottomSheet(isPresented: $rescheduleOpen, title: "Срок") {
            RescheduleSheetContent(
                taskIds: rescheduleTaskIDs ?? rescheduleTask.map { [$0.id] } ?? c.overdueTasks.map(\.id),
                taskStore: taskStore,
                onClose: {
                    rescheduleTask = nil
                    rescheduleTaskIDs = nil
                    rescheduleOpen = false
                }
            )
        }
        .onChange(of: rescheduleOpen) { _, open in
            if !open {
                rescheduleTask = nil
                rescheduleTaskIDs = nil
            }
        }
    }

    @ViewBuilder
    private func listContent(c: TodayComputation) -> some View {
        VStack(spacing: 0) {
            // Иллюстрация «совсем пусто» — только на сегодняшней вкладке:
            // на «Входящих» и «Ждут вас» своя пустота со своим текстом.
            if c.trueEmpty && listTab == .today {
                TodayEmptyIllustration()
            } else {
                if taskStore.isLoading && taskStore.tasks.isEmpty {
                    TFLoading(.block)
                }
                TFErrorBanner(taskStore.errorMessage, variant: .inline)
                    .padding(.horizontal, TFSpacing.lg)

                TodayListView(
                    tab: listTab,
                    waitingTasks: c.waitingTasks,
                    overdueTasks: c.overdueTasks,
                    todayTasks: c.todayTasks,
                    upcomingTasks: c.upcomingTasks,
                    poolTasks: c.poolTasks,
                    today: today,
                    onOpen: { sheetTaskID = TodaySectionTaskID(id: $0.id) },
                    onComplete: { task in
                        Task {
                            await taskStore.patch(taskId: task.id, fields: ["status": .string("completed")]) { _ in }
                        }
                    },
                    onDelete: { task in Task { await taskStore.delete(taskId: task.id) } },
                    onPinnedSectionChange: { title in
                        guard title != pinnedSectionTitle else { return }
                        pinnedSectionTitle = title
                        // Считаем от свежего значения, а не от `titleForHeader`:
                        // присвоенный `@State` в этом же проходе ещё старый.
                        onTitleChange(title.isEmpty ? listTab.title : title)
                    },
                    pinEdge: pinEdge
                )
            }
        }
        .padding(.bottom, TFSpacing.lg)
    }

    @ViewBuilder
    private func hoursContent(c: TodayComputation) -> some View {
        if c.hourDays.isEmpty {
            TFLoading(.block)
        } else {
            let hourDay = c.hourDays[0]
            UpcomingHoursView(
                days: [UpcomingHourColumn(date: hourDay.date, tasks: hourDay.tasks, isToday: hourDay.isToday)],
                projectColor: { task in
                    guard let id = task.projectId,
                          let project = projectStore.projects.first(where: { $0.id == id }) else { return Color(hex: TFHexDefault.unassigned) }
                    return project.color.map { Color(hex: $0) } ?? Color(hex: TFHexDefault.unassigned)
                },
                onTaskTap: { sheetTaskID = TodaySectionTaskID(id: $0) },
                onSchedule: { id, date, time in
                    Task {
                        let existing = taskStore.tasks.first(where: { $0.id == id })
                        var fields: [String: JSONValue] = ["start_time": .string(time), "due_date": .string(date)]
                        if existing?.durationMin == nil { fields["duration_min"] = .number(15) }
                        await taskStore.patch(taskId: id, fields: fields) { _ in }
                    }
                },
                // Растянули плашку за край — длительность (и начало, если
                // тянули за верх) уходят на сервер сразу, без карточки.
                onResize: { id, startTime, minutes in
                    Task {
                        var fields: [String: JSONValue] = ["duration_min": .number(Double(minutes))]
                        if let startTime { fields["start_time"] = .string(startTime) }
                        await taskStore.patch(taskId: id, fields: fields) { _ in }
                    }
                },
                onPage: { direction in
                    activeHourDate = TodayDate.addDays(activeHourDate, direction)
                },
                showsDayHeader: false
            )
        }
    }

    private func filterMenu(c: TodayComputation) -> some View {
        Menu {
            Menu {
                filterOption("Все проекты", selected: vm.filters.projectId == nil) { vm.filters.projectId = nil }
                if c.projectOptions.isEmpty { Text("Нет задач с проектом") }
                else {
                    ForEach(c.projectOptions) { option in
                        filterOption(option.label, selected: vm.filters.projectId == option.id) { vm.filters.projectId = option.id }
                    }
                }
            } label: { Label("Проект", systemImage: "folder") }

            Menu {
                filterOption("Все метки", selected: vm.filters.labelId == nil) { vm.filters.labelId = nil }
                if c.labelOptions.isEmpty { Text("Нет задач с метками") }
                else {
                    ForEach(c.labelOptions) { option in
                        filterOption(option.label, selected: vm.filters.labelId == option.id) { vm.filters.labelId = option.id }
                    }
                }
            } label: { Label("Метка", systemImage: "tag") }

            Menu {
                filterOption("Все исполнители", selected: vm.filters.assigneeKey == nil) { vm.filters.assigneeKey = nil }
                if c.assigneeOptions.hasUnassigned {
                    filterOption("Без исполнителя", selected: vm.filters.assigneeKey == "__none") { vm.filters.assigneeKey = "__none" }
                }
                if c.assigneeOptions.list.isEmpty && !c.assigneeOptions.hasUnassigned { Text("Нет данных об исполнителях") }
                else {
                    ForEach(c.assigneeOptions.list) { option in
                        filterOption(option.name, selected: vm.filters.assigneeKey == option.id) { vm.filters.assigneeKey = option.id }
                    }
                }
            } label: { Label("Исполнитель", systemImage: "person") }

            Divider()

            // «Выполненные» живут внутри этого подменю вместе с проектами и
            // агентскими — состав раздела общий с диапазонами, отдельного
            // переключателя здесь больше нет.
            sectionCompositionMenu

            if vm.filters.isActive {
                Divider()
                Button(role: .destructive) { vm.filters = .empty } label: {
                    Label("Сбросить фильтры", systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            TFPlannerToolbarIcon(systemName: "line.3.horizontal.decrease", tint: vm.filters.isActive ? .tfRed : .tfSub)
        }
        .accessibilityLabel("Фильтры")
        .accessibilityIdentifier("today.filters")
    }

    private func filterOption(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
    }

    // Режим «Выбрать задачи» с массовым переносом срока и удалением жил
    // ТОЛЬКО на доске (LOCK-129) и ушёл вместе с ней: строка списка галочки
    // выбора не рисует, а переделывать её — значит лезть в свежие правки
    // свайпов (LOCK-157/158). Владельцу об этом сказано отдельно; если
    // массовые действия нужны в списке, это отдельная задача.
}

private struct TodaySectionTaskID: Identifiable {
    let id: String
}
