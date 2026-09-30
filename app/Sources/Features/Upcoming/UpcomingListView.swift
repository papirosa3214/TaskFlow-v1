import SwiftUI

// Вид «Список» — spec/SCREENS-1.md §5.2 + живой `UpcomingScreen.tsx`.
// Лента-выборщик даты (месяц/полоса недели) сверху + список задач по дням
// со sticky-заголовками.
//
// ⚠️ Упрощение против веба (см. отчёт): переключение месяц↔неделя там —
// вертикальный свайп «за краюшек» с измеренной CSS-анимацией высоты
// (`calDragStart`/`changeMode`, `CAL_DRAG_THRESHOLD=48`) — DOM-специфичный
// приём, у которого нет прямого SwiftUI-аналога тем же путём. Здесь —
// тап по названию месяца/полосе (шеврон разворота) со `withAnimation`,
// поведение то же (месяц ⇄ неделя), жест другой.
private let swipeStripPx: CGFloat = 45 // порог свайпа полосы недели (спека §5.2)

struct UpcomingListView: View {
    let tasks: [ApiTask]
    @Binding var selectedDate: String?
    let onTaskTap: (String) -> Void
    let onEditTask: (String) -> Void
    let onDeleteTask: (String) -> Void
    let onRescheduleTask: (ApiTask) -> Void

    @State private var calMode: CalMode = .month
    @State private var pickerYear: Int
    @State private var pickerMonth: Int
    @State private var activeWeekMonday: String

    private enum CalMode { case month, week }

    init(
        tasks: [ApiTask], selectedDate: Binding<String?>,
        onTaskTap: @escaping (String) -> Void, onEditTask: @escaping (String) -> Void, onDeleteTask: @escaping (String) -> Void, onRescheduleTask: @escaping (ApiTask) -> Void
    ) {
        self.tasks = tasks
        self._selectedDate = selectedDate
        self.onTaskTap = onTaskTap
        self.onEditTask = onEditTask
        self.onDeleteTask = onDeleteTask
        self.onRescheduleTask = onRescheduleTask
        let today = UpcomingDate.todayString()
        let (y, m) = UpcomingDate.yearMonth(today)
        _pickerYear = State(initialValue: y)
        _pickerMonth = State(initialValue: m)
        _activeWeekMonday = State(initialValue: UpcomingDate.mondayOf(today))
    }

    private var groupedTasks: [String: [ApiTask]] {
        UpcomingDate.groupByDate(tasks)
    }

    /// `visibleDates` (spec): выбранная дата — только она; иначе только даты,
    /// на которые реально есть задачи.
    ///
    /// Было: непрерывная лента 365 дней вперёд от сегодня (пустые дни всё
    /// равно не рисуются — `if !dayTasks.isEmpty` ниже режет их до `EmptyView`)
    /// + сами задачи. 364 холостых итерации `ForEach` ничего не рисовали, но
    /// `LazyVStack` всё равно резервировал под них место при оценке высоты —
    /// отсюда просьба владельца 03.09.2026: «зазор между сеткой и первым
    /// событием» (десятки лишних пунктов вперёд до первой настоящей секции).
    private var visibleDates: [String] {
        if let selectedDate { return [selectedDate] }
        return groupedTasks.keys.sorted()
    }

    var body: some View {
        list
    }

    /// Лента-выборщик — не сосед списка сверху, а `safeAreaInset` на самом
    /// `ScrollView` (не на обёртке `Group`/`if-else` — там `.safeAreaInset`
    /// задваивал отступ, ScrollView начинался на добрые 60pt ниже, чем
    /// заканчивалась сама лента: просьба владельца 03.09.2026, «зазор между
    /// сеткой и первым событием»). Список резервирует ей место, но визуально
    /// продолжает уходить под неё при скролле — тот же эффект затухания, что
    /// и у плашек дат ниже.
    @ViewBuilder
    private var header: some View {
        VStack(spacing: 0) {
            calendarStrip
            if let selectedDate { selectedPill(selectedDate) }
        }
        .background(
            TFHeaderBackdrop(tail: 20, opacity: 0.9)
                .padding(.bottom, -20)
        )
    }

    // MARK: - Лента-выборщик

    private var calendarStrip: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: TFDuration.slow)) {
                        calMode = calMode == .month ? .week : .month
                    }
                } label: {
                    HStack(spacing: 4) {
                        // Единственная строка месяца на всю ленту (была дублем:
                        // до 03.09.2026 у недельной полосы была ЕЩЁ своя строка
                        // месяца — по факту актуальная для показанной недели,
                        // а эта не обновлялась при свайпе недель — visible
                        // баг «два месяца наверху». Теперь одна строка следит
                        // за активным режимом сама.
                        Text(headerMonthLabel)
                            .tfText(.row)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.tfText)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.tfText)
                            .rotationEffect(.degrees(calMode == .week ? 180 : 0))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            // Было .xs — просьба владельца 03.09.2026: слишком тесно сразу под
            // шапкой, дать вздохнуть. Цвет — тоже по просьбе: не красный акцент,
            // нейтральный текстовый, как заголовок «Планирование» над ним.
            .padding(.top, TFSpacing.md)
            // Отступ до сетки снизу — с размер шрифта строки месяца (14pt),
            // тоже по просьбе владельца (была вплотную, без зазора).
            .padding(.bottom, 14)

            if calMode == .month {
                monthGrid
            } else {
                weekStrip
            }
        }
        .animation(.easeInOut(duration: TFDuration.slow), value: calMode)
    }

    /// В режиме месяца — месяц просматриваемой сетки (`pickerMonth/Year`); в
    /// режиме недели — месяц реально показанной недели (`activeWeekMonday`),
    /// который меняется свайпом и не совпадает с `pickerMonth` после свайпа
    /// через границу месяца.
    /// Полное название месяца («Сентябрь», не «Сент.») — просьба владельца 03.09.2026.
    private var headerMonthLabel: String {
        switch calMode {
        case .month:
            return "\(UpcomingDate.monthsNom[pickerMonth]) \(pickerYear) г."
        case .week:
            let (year, month) = UpcomingDate.weekMonth(monday: activeWeekMonday)
            return "\(UpcomingDate.monthsNom[month]) \(year) г."
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(UpcomingDate.weekdaysUpper, id: \.self) { w in
                    Text(w).tfText(.caption).foregroundStyle(Color.tfSub).frame(maxWidth: .infinity)
                }
            }
            let days = UpcomingDate.monthGridDates(year: pickerYear, month: pickerMonth)
            let rows = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { ds in
                        bigDayCell(ds)
                    }
                }
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private func bigDayCell(_ ds: String) -> some View {
        let today = UpcomingDate.todayString()
        let isToday = ds == today
        let isSelected = ds == selectedDate
        let filled = isSelected || isToday
        let (_, month) = UpcomingDate.yearMonth(ds)
        let dim = month != pickerMonth
        let hasTasks = !(groupedTasks[ds] ?? []).isEmpty
        let firstOfMonth = UpcomingDate.day(ds) == 1

        return Button {
            selectedDate = isSelected ? nil : ds
        } label: {
            VStack(spacing: 2) {
                if firstOfMonth {
                    Text(UpcomingDate.monthsAbbrDot[month])
                        .tfText(.micro)
                        .foregroundStyle(filled ? Color.tfRed : Color.tfSub)
                }
                Text("\(UpcomingDate.day(ds))")
                    .tfText(.input)
                    .monospacedDigit()
                    .fontWeight(filled ? .semibold : .regular)
                    // «Сегодня» — сплошной круг (осталось как было). «Выбрано» —
                    // не такой же круг, а мягкий бейдж: просьба владельца
                    // 03.09.2026, два разных состояния не должны выглядеть
                    // одинаково.
                    .foregroundStyle(isToday ? Color.tfRed : (isSelected ? Color.tfRed : (dim ? Color.tfDim.opacity(0.5) : Color.tfText)))
                    .frame(width: 30, height: 30)
                    .background {
                        if isToday {
                            EmptyView()
                        } else if isSelected {
                            RoundedRectangle(cornerRadius: TFRadius.md).fill(Color.tfRed.opacity(0.15))
                        }
                    }
                if hasTasks && !filled {
                    Circle().fill(Color.tfRed).frame(width: 4, height: 4)
                } else {
                    Color.clear.frame(width: 4, height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
        }
        .buttonStyle(TFTapScaleStyle())
    }

    private var weekStrip: some View {
        let days = (0..<7).map { UpcomingDate.addDays(activeWeekMonday, $0) }
        let today = UpcomingDate.todayString()
        return VStack(spacing: 2) {
            HStack(spacing: TFSpacing.xs) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, ds in
                    let isToday = ds == today
                    let isSelected = ds == selectedDate
                    let hasTasks = !(groupedTasks[ds] ?? []).isEmpty
                    Button {
                        selectedDate = isSelected ? nil : ds
                    } label: {
                        VStack(spacing: 2) {
                            Text(["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"][UpcomingDate.jsWeekday(ds)])
                                .tfText(.micro)
                                .textCase(.uppercase)
                                .foregroundStyle(isToday || isSelected ? Color.tfRed : Color.tfSub)
                            Text("\(UpcomingDate.day(ds))")
                                .tfText(.body)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(isToday ? Color.tfRed : (isSelected ? Color.tfRed : Color.tfText))
                                .frame(width: 28, height: 28)
                            if hasTasks && !isToday {
                                Circle().fill(Color.tfRed).frame(width: 4, height: 4)
                            } else {
                                Color.clear.frame(width: 4, height: 4)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.bottom, TFSpacing.sm)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) >= swipeStripPx, abs(dx) > abs(dy) * 1.3 else { return }
                        withAnimation { activeWeekMonday = UpcomingDate.addDays(activeWeekMonday, dx < 0 ? 7 : -7) }
                    }
            )
        }
        .padding(.top, TFSpacing.xs)
    }

    private func selectedPill(_ date: String) -> some View {
        Button { selectedDate = nil } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar").font(.system(size: TFIconSize.xs))
                Text(UpcomingDate.formatFullDate(date))
                Spacer()
                Image(systemName: "xmark").font(.system(size: TFIconSize.xs))
            }
            .tfText(.action)
            .foregroundStyle(Color.tfRed)
            .padding(.horizontal, TFSpacing.md).padding(.vertical, 8)
            .background(Color.tfRed.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.top, TFSpacing.md)
    }

    // MARK: - Список

    @ViewBuilder
    private var list: some View {
        if let selectedDate, (groupedTasks[selectedDate] ?? []).isEmpty {
                // maxHeight + alignment: .top — без этого короткая строка
                // центрировалась по всей высоте экрана, а вместе с ней «падала»
                // вниз и лента-календарь над ней (просьба владельца 03.09.2026:
                // «календарь вниз спадает, непонятно почему»).
                Text("Нет задач на эту дату")
                    .tfText(.body)
                    .foregroundStyle(Color.tfDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 40)
                    .safeAreaInset(edge: .top, spacing: 0) { header }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: selectedDate == nil ? [.sectionHeaders] : []) {
                        ForEach(visibleDates, id: \.self) { date in
                            let dayTasks = groupedTasks[date] ?? []
                            if selectedDate != nil || !dayTasks.isEmpty {
                                Section {
                                    ForEach(dayTasks, id: \.id) { task in
                                        UpcomingTaskRow(
                                            task: task,
                                            onOpen: { onTaskTap(task.id) },
                                            onComplete: { /* TODO: завершить задачу через taskStore */ },
                                            onDelete: { onDeleteTask(task.id) }
                                        )
                                    }
                                } header: {
                                    if selectedDate == nil {
                                        dateHeader(date)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, TFSpacing.md)
                }
                .safeAreaInset(edge: .top, spacing: 0) { header }
            }
    }

    private func dateHeader(_ date: String) -> some View {
        Text(UpcomingDate.formatFullDate(date))
            // Было 13pt/.semibold/tfSub (tfRed для сегодня) — просьба владельца
            // 03.09.2026: всем без исключения белым, покрупнее и пожирнее.
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.tfText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.vertical, 6)
        // Без подложки вообще — просьба владельца 03.09.2026, тот же приём,
        // что у соседних подзаголовков секций в TodayListView.header(_:):
        // прилипает, но полностью прозрачный, никакого фона под текстом.
    }
}
