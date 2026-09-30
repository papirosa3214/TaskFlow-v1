import Foundation

/// Один день сетки «часы» — spec §3.5 `DayColumnData`. «Сегодня» всегда
/// одна колонка (3-дневный вид переехал в «Планирование» 20.08.2026, см.
/// комментарий в живом TodayScreen.tsx) — тип остался с массивом задач для
/// параллельности с сеткой, но `TodayComputation.hourDays` всегда отдаёт
/// ровно один элемент.
struct TodayHourDay {
    let date: String
    let tasks: [ApiTask]
    let isToday: Bool
}

/// Пустой снимок для первого рендера `TodayScreen` (до того как `.task(id:)`
/// пересчитает реальный). Без него `computation` нельзя объявить `@State`
/// с non-optional типом, а optional тащит `??` по всему body.
extension TodayComputation {
    static let placeholder: TodayComputation = TodayComputation(
        allTasks: [], currentUser: nil, agents: [],
        filters: .empty, today: "", activeHourDate: "",
        isLoading: false, isError: false
    )
}

/// Портирует useMemo-цепочку `TodayScreen.tsx` 1:1 (дедуп «Ждут вас» →
/// «Просрочено» → «Сегодня», разделение «искренних»/«отфильтрованных»
/// пустых множеств) — см. комментарии там же для обоснования порядка.
struct TodayComputation {
    let allTasks: [ApiTask]
    let currentUser: ApiUser?
    let agents: [ApiUser]
    let filters: TodayTaskFilters
    /// Пункт «Агентские задачи» в «Показывать в разделе» — общая настройка со
    /// всем «Планированием» (ключ `plannerShowAgentTasks`). До 09.09.2026
    /// агентские вырезались из почасовой сетки жёстко.
    let showAgentTasks: Bool
    /// Проекты из того же «Показывать в разделе». Пустой набор означает
    /// «показывать только беспроектные» — та же семантика, что у диапазонов,
    /// подменю одно на весь раздел (LOCK-111).
    let visibleProjectIds: Set<String>
    let today: String
    let activeHourDate: String
    let isLoading: Bool
    let isError: Bool

    // Результаты цепочки вычисляются один раз при создании снимка экрана.
    // Раньше это были computed properties: один проход `TodayScreen.body`
    // обращался к одним и тем же filter/sort до десятка раз, а состояние
    // липкой шапки обновляет body во время прокрутки. На длинной ленте именно
    // эта повторная работа на main thread ощущалась как микрорывки.
    let plannerTasks: [ApiTask]
    let waitingTasksAll: [ApiTask]
    let rawOverdueAll: [ApiTask]
    let rawTodayAll: [ApiTask]
    let rawUpcomingAll: [ApiTask]
    let waitingTasks: [ApiTask]
    let overdueTasks: [ApiTask]
    let todayTasks: [ApiTask]
    /// Задачи со сроком ПОЗЖЕ сегодняшнего дня. Нужны только «Доске»:
    /// в «Списке» владелец 09.09.2026 попросил ровно сегодняшний день
    /// («открыл сегодня и больше ни на что не отвлекался»), а доска — про
    /// планирование, там колонка «Предстоящие» стоит четвёртой.
    let upcomingTasks: [ApiTask]
    /// «Пул» — всё, что не попало ни в одну датированную колонку, то есть
    /// задачи без `due_date` (владелец 10.09.2026: «бессрочные, беспроектные,
    /// все оставшиеся, короче»). Состав раздела на них распространяется как на
    /// всех: скрытый проект, агентские и выполненные сюда не лезут.
    let poolTasks: [ApiTask]
    let projectOptions: [TodayFilterOption]
    let labelOptions: [TodayFilterOption]
    let assigneeOptions: (list: [TodayAssigneeOption], hasUnassigned: Bool)
    let trueEmpty: Bool
    let filteredEmpty: Bool
    let hourDays: [TodayHourDay]

    init(
        allTasks: [ApiTask], currentUser: ApiUser?, agents: [ApiUser],
        filters: TodayTaskFilters, showAgentTasks: Bool = false,
        visibleProjectIds: Set<String> = [], today: String,
        activeHourDate: String, isLoading: Bool, isError: Bool
    ) {
        self.allTasks = allTasks
        self.currentUser = currentUser
        self.agents = agents
        self.filters = filters
        self.showAgentTasks = showAgentTasks
        self.visibleProjectIds = visibleProjectIds
        self.today = today
        self.activeHourDate = activeHourDate
        self.isLoading = isLoading
        self.isError = isError

        // Состав раздела — общий с диапазонами (одно подменю на всё
        // «Планирование», LOCK-111). Беспроектные проходят всегда.
        let planner = allTasks.filter { task in
            guard let projectID = task.projectId else { return true }
            return visibleProjectIds.contains(projectID)
        }
        plannerTasks = planner

        let plannerPartition = Self.partitionOverdueToday(planner, today: today)
        let waitingAll = Self.waitingTasks(from: planner, currentUser: currentUser)
        let upcomingAll = Self.upcoming(from: planner, today: today)
        let poolAll = planner.filter { ($0.dueDate ?? "").isEmpty }
        waitingTasksAll = waitingAll
        rawOverdueAll = plannerPartition.overdue
        rawTodayAll = plannerPartition.todayTasks
        rawUpcomingAll = upcomingAll

        let filteredWaiting = TodayFilterEngine.filter(waitingAll, filters)
        let filteredOverdue = TodayFilterEngine.filter(plannerPartition.overdue, filters)
        let filteredToday = TodayFilterEngine.filter(plannerPartition.todayTasks, filters)
        let filteredUpcoming = TodayFilterEngine.filter(upcomingAll, filters)
        let filteredPool = TodayFilterEngine.filter(poolAll, filters)
        let waitingIDs = Set(filteredWaiting.map(\.id))
        waitingTasks = filteredWaiting
        overdueTasks = filteredOverdue.filter { !waitingIDs.contains($0.id) }
        todayTasks = filteredToday.filter { !waitingIDs.contains($0.id) }
        upcomingTasks = filteredUpcoming.filter { !waitingIDs.contains($0.id) }
        poolTasks = filteredPool.filter { !waitingIDs.contains($0.id) }

        projectOptions = TodayFilterEngine.projectOptions(allTasks)
        labelOptions = TodayFilterEngine.labelOptions(allTasks)
        assigneeOptions = TodayFilterEngine.assigneeOptions(allTasks)

        let truePartition = plannerPartition
        // Иллюстрация «пусто» живёт только в «Списке», а он с 09.09.2026
        // показывает ровно сегодняшний день — поэтому и пустота считается по
        // сегодняшним задачам, а не по всему разделу (раньше в счёт шли ещё
        // «Просрочено» и «Ждут вас», но их в списке больше нет).
        let isTrulyEmpty = !isLoading && !isError && truePartition.todayTasks.isEmpty
        trueEmpty = isTrulyEmpty
        filteredEmpty = !isTrulyEmpty && !isLoading && !isError && todayTasks.isEmpty

        let combined: [ApiTask]
        if activeHourDate == today {
            var seen = Set<String>()
            combined = (filteredWaiting + todayTasks + overdueTasks).filter { seen.insert($0.id).inserted }
        } else {
            combined = planner.filter { $0.dueDate == activeHourDate }
        }
        hourDays = [TodayHourDay(
            date: activeHourDate,
            tasks: combined.filter { showAgentTasks || !TodayTaskOwner.isAgentAssigned($0, agents) },
            isToday: activeHourDate == today
        )]

        // Колонки канбан-доски раньше собирались здесь же. Доска удалена
        // 15.09.2026 по решению владельца («раз мы уже её не используем,
        // сноси»), а наборы задач остались: теперь по ним раскладываются
        // секции вкладок списка (`TodayListSection`).
    }

    /// Задачи без project_id (Входящие) — всегда; проектные — только opt-in
    /// (spec §3.10). Исключение: пока пользователь ни разу не открывал этот
    /// выбор, показываем ВСЁ — иначе свежепоставленное приложение встречает
    /// пустым экраном при полном списке задач на сервере.
    private static func partitionOverdueToday(_ tasks: [ApiTask], today: String) -> (overdue: [ApiTask], todayTasks: [ApiTask]) {
        let overdue = tasks
            .filter { ($0.dueDate ?? "") != "" && $0.dueDate! < today }
            .sorted { ($0.dueDate ?? "") < ($1.dueDate ?? "") }
        let todayTasks = tasks.filter { $0.dueDate == today }
        return (overdue, todayTasks)
    }

    /// Строго позже сегодняшнего дня. Бессрочные сюда не попадают: у них
    /// `due_date` пуст, а пустая строка меньше любой даты.
    private static func upcoming(from tasks: [ApiTask], today: String) -> [ApiTask] {
        tasks
            .filter { ($0.dueDate ?? "") > today }
            .sorted { ($0.dueDate ?? "") < ($1.dueDate ?? "") }
    }

    private static func waitingTasks(from tasks: [ApiTask], currentUser: ApiUser?) -> [ApiTask] {
        guard currentUser != nil else { return [] }
        return tasks
            .filter { TodayTaskOwner.isWaitingForUser($0, currentUser) }
            .sorted { TodayTaskOwner.waitingSort($0, $1) }
    }

}
