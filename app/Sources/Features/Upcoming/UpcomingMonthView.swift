import SwiftUI

// Вид «Месяц» — spec/SCREENS-1.md §3.6 `MonthGrid`: непрерывная лента недель
// (Google Calendar-style), НЕ страницы со свайпом. `MONTH_ROW_H=128`,
// `MONTH_CHIP_LIMIT=4`, подгрузка чанками `WEEKS_CHUNK=12`.
//
// ⚠️ Упрощение против веба (см. отчёт): веб догружает недели И вверх, и
// вниз через IntersectionObserver, сохраняя scrollOffset при prepend'е
// ручной коррекцией scrollTop. SwiftUI `ScrollView`/`LazyVStack` не даёт
// такого якоря без самодельной системы измерения (iOS 18 `scrollPosition`
// не покрывает «вставить контент выше текущей позиции без прыжка» для
// LazyVStack с переменной высотой строк-полос дня). Здесь — честный
// компромисс: стартовый диапазон `WEEKS_INITIAL_PAST`/`_FUTURE` пошире,
// подгрузка ТОЛЬКО вперёд (вниз) чанками при подходе к концу списка. Долистать
// в прошлое дальше стартовых 8 недель нельзя — ограничение, не молчаливое.
private let monthRowH: CGFloat = 128
private let monthChipLimit = 4
private let weeksChunk = 12

private struct UpcomingMonthWeekOffsetKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct UpcomingMonthView: View {
    let initialMonday: String
    /// Месяц, на котором должна открыться лента (обычно месяц «сегодня»).
    /// Передаётся явно из родителя: если взять месяц самой `initialMonday`,
    /// а она приходится на последние дни предыдущего месяца (как `mondayOf`
    /// от 1 числа), стартовая неделя уедет на месяц назад — открываемся
    /// на прошедшем месяце, а не на текущем.
    let initialMonth: (year: Int, month: Int)
    let byDate: [String: [ApiTask]]
    let onDayTap: (String) -> Void
    let onVisibleMonthChange: (Int, Int) -> Void

    @State private var weeks: [String] = []
    @State private var didInitialScroll = false
    @State private var reportedVisibleMonth = ""

    init(
        initialMonday: String, initialMonth: (year: Int, month: Int),
        byDate: [String: [ApiTask]],
        onDayTap: @escaping (String) -> Void,
        onVisibleMonthChange: @escaping (Int, Int) -> Void
    ) {
        self.initialMonday = initialMonday
        self.initialMonth = initialMonth
        self.byDate = byDate
        self.onDayTap = onDayTap
        self.onVisibleMonthChange = onVisibleMonthChange
    }

    var body: some View {
        // Строка «Пн Вт Ср…» вынесена НАД прокруткой, а не приклеена
        // `pinnedViews: [.sectionHeaders]` внутри неё. Приклеенная шапка
        // накрывала первую строку ленты, из-за чего прокрутку к текущему
        // месяцу когда-то просто убрали — и раздел открывался на месяц назад
        // (владелец 09.09.2026: «почему-то он всё время не центрируется на
        // том месяце, который сейчас»). Снаружи она ничего не накрывает, и
        // прокрутку можно вернуть.
        VStack(spacing: 0) {
            weekdayHeader
            monthScroll
        }
    }

    private var monthScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(weeks.enumerated()), id: \.element) { index, monday in
                        weekBlock(monday: monday, index: index)
                            .id(monday)
                    }
                }
            }
            .coordinateSpace(name: "upcomingMonthScroll")
            .onPreferenceChange(UpcomingMonthWeekOffsetKey.self) { offsets in
                // LazyVStack заранее создаёт строки ниже экрана. Заголовок
                // должен отражать первую реально видимую календарную неделю.
                let headerHeight: CGFloat = 24
                guard let monday = offsets
                    .filter({ $0.value <= headerHeight })
                    .max(by: { $0.value < $1.value })?
                    .key else { return }

                let (year, month) = UpcomingDate.yearMonth(monday)
                let key = "\(year)-\(month)"
                guard reportedVisibleMonth != key else { return }
                reportedVisibleMonth = key
                onVisibleMonthChange(year, month)
            }
            .onAppear {
                if weeks.isEmpty { weeks = Self.buildInitialWeeks(around: initialMonday, initialMonth: initialMonth) }
            }
            // Прокрутка отдельно от построения ленты: строки создаёт
            // `LazyVStack`, и в том же проходе, где `weeks` только присвоены,
            // целевой строки ещё нет — `scrollTo` уходит в никуда.
            .onChange(of: weeks) { _, list in
                guard !didInitialScroll, !list.isEmpty else { return }
                didInitialScroll = true
                let target = Self.firstWeekMondayOfMonth(year: initialMonth.year, month: initialMonth.month)
                DispatchQueue.main.async {
                    proxy.scrollTo(target, anchor: .top)
                    onVisibleMonthChange(initialMonth.year, initialMonth.month)
                }
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(UpcomingDate.weekdaysShort, id: \.self) { w in
                Text(w).tfText(.micro).foregroundStyle(Color.tfDim).frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, TFSpacing.xs)
        .background(Color.tfBackground)
    }

    private func weekBlock(monday: String, index: Int) -> some View {
        let days = (0..<7).map { UpcomingDate.addDays(monday, $0) }
        let monthStartIndex = days.firstIndex { UpcomingDate.day($0) == 1 }
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { ds in
                    monthDayCell(ds)
                }
            }
            .frame(height: monthRowH)
            .overlay(alignment: .topLeading) {
                if let monthStartIndex {
                    GeometryReader { proxy in
                        Path { path in
                            let boundaryX = proxy.size.width * CGFloat(monthStartIndex) / 7
                            path.move(to: CGPoint(x: 0, y: proxy.size.height))
                            path.addLine(to: CGPoint(x: boundaryX, y: proxy.size.height))
                            path.addLine(to: CGPoint(x: boundaryX, y: 0))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
                        }
                        .stroke(Color.tfRed.opacity(0.72), lineWidth: TFBorder.width)
                    }
                    .allowsHitTesting(false)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: UpcomingMonthWeekOffsetKey.self,
                        value: [monday: proxy.frame(in: .named("upcomingMonthScroll")).minY]
                    )
                }
            }
            .onAppear {
                // Подгрузка чанком вперёд, когда до конца списка осталось < 6 недель.
                if index >= weeks.count - 6 {
                    let extra = (1...weeksChunk).map { UpcomingDate.addDays(weeks[weeks.count - 1], $0 * 7) }
                    if !extra.isEmpty, weeks.last != extra.last {
                        weeks.append(contentsOf: extra)
                    }
                }
            }
        }
    }

    private func monthDayCell(_ ds: String) -> some View {
        let today = UpcomingDate.todayString()
        let isToday = ds == today
        let startsMonth = UpcomingDate.day(ds) == 1
        let tasks = byDate[ds] ?? []
        let shown = Array(tasks.prefix(monthChipLimit))
        let rest = tasks.count - shown.count

        return VStack(spacing: 2) {
            Text("\(UpcomingDate.day(ds))")
                .tfText(.meta)
                .monospacedDigit()
                .fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(isToday ? .white : (startsMonth ? Color.tfRed : Color.tfText))
                .frame(minWidth: isToday ? 18 : nil, minHeight: isToday ? 18 : nil)
                .background(isToday ? Circle().fill(Color.tfRed) : nil)

            ForEach(shown, id: \.id) { task in
                UpcomingTaskChip(task: task, compact: true) { onDayTap(ds) }
            }
            if rest > 0 {
                Text("+\(rest)").tfText(.micro).foregroundStyle(Color.tfDim)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: monthRowH, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { onDayTap(ds) }
    }

    private static func buildInitialWeeks(around initialMonday: String, initialMonth: (year: Int, month: Int)) -> [String] {
        // Лента шире одного месяца: 4 строки назад и 20 вперёд от строки с
        // 1-м числом `initialMonth`. Открывается раздел НЕ в начале ленты —
        // прокрутка ставит на строку текущего месяца (см. `onChange(of:
        // weeks)`), а четыре строки до неё лежат запасом для листания назад.
        let firstWeekMonday = firstWeekMondayOfMonth(year: initialMonth.year, month: initialMonth.month)
        let weeksBefore = 4
        let weeksAfter = 20
        let start = UpcomingDate.addDays(firstWeekMonday, -weeksBefore * 7)
        return (0..<(weeksBefore + weeksAfter + 1)).map { UpcomingDate.addDays(start, $0 * 7) }
    }

    /// Понедельник недели, содержащей 1-е число месяца `(year, month)`
    /// (0-based). Стартовая точка ленты — отдельно от `weekMonth`,
    /// которая считает «доминирующий» месяц по четвергу.
    private static func firstWeekMondayOfMonth(year: Int, month: Int) -> String {
        var comps = DateComponents()
        comps.year = year; comps.month = month + 1; comps.day = 1
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let firstOf = cal.date(from: comps) else { return "" }
        let firstOfStr = UpcomingDate.calendarDateString(firstOf)
        return UpcomingDate.mondayOf(firstOfStr)
    }
}
