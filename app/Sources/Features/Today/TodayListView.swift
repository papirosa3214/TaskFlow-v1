import SwiftUI

// Вид «Список» — лента с вкладками. Канбан-доска убрана 15.09.2026 по
// прямому решению владельца («с ним только мучения, не получается по уму»),
// и то, что раньше было колонками, стало вкладками одной ленты.
//
// Почему именно так, а не второй прокруткой: вкладка МЕНЯЕТ СОДЕРЖИМОЕ
// единственной вертикальной прокрутки экрана. Ни `TabView`, ни
// горизонтального `ScrollView` здесь нет и быть не должно — на доске
// системная кромка затухания ломалась именно из-за вложенных прокруток, и
// владелец отдельно просил «чтобы не случилось канители, что мы не сможем
// сделать затухание». При одной прокрутке под навбаром кромку рисует
// система, без единой строчки кода.
//
// `AppleCalendarEvents` (события календаря устройства) — вне спеки Волны 1
// (`spec/NATIVE-PARTS.md` относит интеграцию с системным календарём к
// более поздней волне), здесь не рисуется.
struct TodayListView: View {
    let tab: TodayListTab
    let waitingTasks: [ApiTask]
    let overdueTasks: [ApiTask]
    let todayTasks: [ApiTask]
    let upcomingTasks: [ApiTask]
    let poolTasks: [ApiTask]
    let today: String
    let onOpen: (ApiTask) -> Void
    let onComplete: (ApiTask) -> Void
    let onDelete: (ApiTask) -> Void
    /// Заголовок секции, которая сейчас закреплена у верхней кромки, — он
    /// уезжает в шапку экрана. Пусто, когда лента в самом начале или секция
    /// всего одна: тогда в шапке остаётся название вкладки.
    var onPinnedSectionChange: (String) -> Void = { _ in }
    /// Верхняя кромка прокрутки в координатах экрана — та высота, на которой
    /// заголовок секции прилипает. Приходит от владельца прокрутки: изнутри
    /// её не вычислить, а константой брать нельзя — замер показал 122pt там,
    /// где «безопасная зона плюс навбар» давали 113pt.
    var pinEdge: CGFloat = 0

    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var taskStore
    @State private var swipeActionError: String?
    /// Верх каждого заголовка в координатах экрана. Считается, какой из них
    /// сейчас прилип к кромке: владелец 15.09.2026 просил, чтобы подзаголовки
    /// не были захардкожены, а «когда они подходят, появлялись в центре» —
    /// то есть в шапке всегда стоит та секция, которую он сейчас читает.
    @State private var sectionTops: [String: CGFloat] = [:]

    private let apiClient = APIClient()

    private var sections: [TodayListSection] {
        TodayListSection.sections(
            tab: tab,
            waiting: waitingTasks,
            overdue: overdueTasks,
            today: todayTasks,
            upcoming: upcomingTasks,
            pool: poolTasks,
            todayDate: today
        )
    }

    var body: some View {
        let visible = sections
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            TFErrorBanner(swipeActionError, variant: .inline)
                .padding(.horizontal, TFSpacing.lg)

            if visible.isEmpty {
                TFEmptyState(icon: nil, text: emptyText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, TFSpacing.xl)
            } else {
                ForEach(visible) { section in
                    Section {
                        ForEach(section.tasks) { task in
                            row(task, overdue: section.marksOverdue)
                        }
                    } header: {
                        // Единственная секция вкладки заголовка не получает:
                        // он дублировал бы название самой вкладки в шапке.
                        if visible.count > 1 {
                            header(section)
                                .background(sectionTopReader(section))
                        }
                    }
                }
            }
        }
    }

    /// Замеряет верх заголовка секции в координатах экрана.
    private func sectionTopReader(_ section: TodayListSection) -> some View {
        GeometryReader { proxy in
            Color.clear
                .onGeometryChange(for: CGFloat.self) { _ in
                    proxy.frame(in: .global).minY
                } action: { top in
                    // Считаем по свежему снимку: присвоенный `@State` в этом
                    // же проходе ещё содержит прошлое значение.
                    var tops = sectionTops
                    tops[section.id] = top
                    sectionTops = tops
                    reportPinnedSection(with: tops)
                }
        }
    }

    /// Прилипший заголовок стоит ровно у кромки прокрутки, а те, что ниже,
    /// ещё не дошли. Значит текущая секция — самая нижняя из тех, чей верх
    /// уже не ниже кромки. Пока до кромки не дошла ни одна, в шапке остаётся
    /// название вкладки.
    private func reportPinnedSection(with tops: [String: CGFloat]) {
        let visible = sections
        guard visible.count > 1, pinEdge > 0 else {
            onPinnedSectionChange("")
            return
        }
        // Закреплённый заголовок стоит ровно на верхней кромке прокрутки,
        // ушедшие наверх — выше неё, не дошедшие — ниже. Значит нужен
        // последний из тех, кто кромку уже достиг. Допуск в пару точек:
        // у прилипшего заголовка верх подрагивает на доли точки.
        let edge = pinEdge + 2
        let passed = visible.filter { (tops[$0.id] ?? .greatestFiniteMagnitude) <= edge }
        onPinnedSectionChange(passed.last?.title ?? "")
    }

    private var emptyText: String {
        switch tab {
        case .inbox: "Нераспределённых задач нет"
        case .attention: "Вас ничего не ждёт"
        case .today: "На сегодня и ближайшие дни задач нет"
        }
    }

    private func row(_ task: ApiTask, overdue: Bool) -> some View {
        let swipeAction = TodayTaskSwipeAction.action(
            for: task,
            isOwner: session.currentUser?.role == .owner,
            currentUserID: session.currentUser?.id
        )
        return TodayTaskRow(task: task, overdue: overdue,
                            onOpen: { onOpen(task) },
                            onDelete: { onDelete(task) },
                            swipeAction: swipeAction,
                            onSwipeAction: {
                                guard let swipeAction else { return }
                                Task { await perform(swipeAction, for: task) }
                            })
    }

    private func perform(_ action: TodayTaskSwipeAction, for task: ApiTask) async {
        swipeActionError = nil
        do {
            switch action {
            case .complete:
                onComplete(task)
            case .acceptReview:
                try await apiClient.approveCurrentTaskVersion(taskID: task.id)
                _ = try await apiClient.setTaskAgentState(id: task.id, state: nil)
                _ = try await apiClient.patchTask(id: task.id, fields: ["status": .string("completed")])
                await taskStore.load(silent: true)
            case .markReadyForPickup:
                // «Запустить» — тем же путём, что в карточке и в чате Секретаря.
                if task.parentId == nil {
                    try await apiClient.startDraft(taskID: task.id)
                } else {
                    _ = try await apiClient.patchTask(id: task.id, fields: ["ready_for_pickup": .bool(true)])
                }
                await taskStore.load(silent: true)
            }
        } catch is CancellationError {
            // Экран пересобрался (смена формата «Список»/«Один день» и
            // т.п.) быстрее, чем действие успело доехать — запрос отменился
            // штатно, показывать баннер не о чем.
        } catch {
            swipeActionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func header(_ section: TodayListSection) -> some View {
        HStack(spacing: 6) {
            if let icon = section.icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(section.color)
            }
            // Владелец 15.09.2026: «подзаголовки чуть-чуть покрупнее шрифт
            // сделай и белым их, чтобы они выделялись, а то прям они как
            // будто бы не подзаголовки, а спрятались так тускленько».
            // Поэтому ступень типографики выше (.title → .taskTitle) и
            // основной цвет текста вместо приглушённого `section.color`.
            Text(section.title)
                .tfText(.taskTitle)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tfText)
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Состав секций

struct TodayListSection: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String?
    let color: Color
    let tasks: [ApiTask]
    /// Строки рисуются «просроченными» — красная дата, как было на доске.
    let marksOverdue: Bool

    static func == (lhs: TodayListSection, rhs: TodayListSection) -> Bool {
        lhs.id == rhs.id && lhs.tasks.map(\.id) == rhs.tasks.map(\.id)
    }

    /// Единственное место, где решается состав вкладок. Наборы задач сюда
    /// приходят уже посчитанными и дедуплицированными в `TodayComputation`
    /// («Ждут вас» вычтены из остальных) — пересчитывать их здесь нельзя,
    /// иначе одна задача покажется в двух секциях.
    static func sections(
        tab: TodayListTab,
        waiting: [ApiTask],
        overdue: [ApiTask],
        today: [ApiTask],
        upcoming: [ApiTask],
        pool: [ApiTask],
        todayDate: String
    ) -> [TodayListSection] {
        let all: [TodayListSection]
        switch tab {
        case .inbox:
            // «Входящие — это и есть без даты, они не распределены»
            // (владелец 15.09.2026).
            all = [.init(id: "pool", title: "Входящие", icon: nil,
                         color: .tfSub, tasks: pool, marksOverdue: false)]
        case .attention:
            all = [
                .init(id: "waiting", title: "Ждут вас", icon: nil,
                      color: .tfSub, tasks: waiting, marksOverdue: false),
                .init(id: "overdue", title: "Просрочено", icon: nil,
                      color: .tfRed, tasks: overdue, marksOverdue: true)
            ]
        case .today:
            all = [
                .init(id: "today", title: TodayDate.formatDueLabel(todayDate), icon: nil,
                      color: .tfSub, tasks: today, marksOverdue: false),
                .init(id: "upcoming", title: "Предстоящие", icon: nil,
                      color: .tfSub, tasks: upcoming, marksOverdue: false)
            ]
        }
        return all.filter { !$0.tasks.isEmpty }
    }
}
