import SwiftUI
import UIKit

// Вид «Три дня» — spec/SCREENS-1.md §3.5 `DayHours` (та же сетка, что у
// «Сегодня», просто три колонки вместо одной). Числа — замер владельца,
// дробные значения ЗАКОННЫ, не округляются (спека): `HOUR_H=124/3`,
// `GUTTER_W=161/3`, `SNAP_MIN=15`, `MIN_H=24`.
//
// ⚠️ Хороший кандидат в общий кирпич (нужен и «Сегодня», один день — просьба
// оркестратора учла это заранее) — здесь сделан ЛОКАЛЬНО по правилу
// контракта («не хватает чужого — сделай локально»), в отчёте предлагаю
// оркестратору поднять в `DesignSystem`.
//
// Перетаскивание — И пул («без времени» → на сетку), И уже поставленная
// плашка на новое время/день (просьба владельца 03.09.2026: «задержал и
// передвинул эту плашку по времени»). Оба случая — свой `DragGesture`,
// тот же приём, что уже проверен и работает в «Сегодня»
// (`TodayHoursView.dragGesture`), расширенный на несколько дневных колонок
// сразу: день, над которым сейчас палец, вычисляется по X внутри общего
// именованного пространства координат `upcomingHoursGrid`.
//
// ⚠️ Системный `.draggable`/`.dropDestination` ПРОБОВАЛИ первым для ОБОИХ
// случаев (там, где готово из коробки — меньше кода) — не подошло ни разу:
// сперва для уже поставленной плашки, владелец 03.09.2026: «беру просто
// как тень, но она по сетке вообще не ездит», а после переноса пула на тот
// же приём выяснилось — тень СИСТЕМНОГО drag на этом экране вообще не
// цепляет `.dropDestination` внутри `GeometryReader`+`.position()`-раскладки
// надёжно, не только у уже поставленных плашек. Оставлять два разных
// механизма на одном экране (пул системным, плашки — своим) тоже было
// ошибкой само по себе — расхождение в поведении подряд путало владельца.
// Сейчас оба источника — один и тот же `dragGesture(for:dayIndex:top:height:)`,
// `top == nil` у пула (нет исходной позиции — куда палец, туда и время).
private let baseHourH: CGFloat = 124.0 / 3.0
private let gutterW: CGFloat = 161.0 / 3.0
private let snapMin = 15
private let minBlockH: CGFloat = 24
/// Визуальный пол высоты плашки в состоянии покоя И во время перетаскивания
/// (не путать с `minBlockH` — та участвует в формуле масштаба развёрнутой
/// шкалы, `minBlockH + 3) * 4`, трогать её нельзя, поменяется зум). Владелец
/// 07.09.2026, третий заход подряд: «карточка должна быть такой же плотной,
/// а не полоска» — короткие задачи (пул без времени, 15-минутные) рисовались
/// с высотой `minBlockH` (24pt) и в покое, и на драге — визуально читались
/// как тонкая полоска, а не как карточка с телом.
private let minCardBodyHeight: CGFloat = 44
/// Технический пол высоты плашки В ПОКОЕ: только чтобы задача не схлопнулась
/// в невидимую линию и в неё можно было ткнуть. Смысловой длительности не
/// добавляет — в отличие от `minCardBodyHeight`, который подтягивал короткие
/// задачи до читаемого размера и тем врал про время (владелец 15.09.2026:
/// «надо всё честно показывать», для читаемости есть суточный вид и тумблер
/// масштаба трёхдневного).
private let minVisibleBlockHeight: CGFloat = 8
/// Видимый диапазон — ПОЛНЫЕ сутки, 00:00 сверху и 24:00 внизу.
///
/// 07.09.2026 он был урезан до 6–22 по просьбе владельца («в 6 утра всё
/// равно никто не встаёт, в час ночи никто не встаёт») — тогда ночные часы
/// были мёртвым грузом в ленте. 15.09.2026 владелец вернул полные сутки:
/// «я сокращал время, чтобы лишняя ночь не мешала, она была бесполезная —
/// сейчас она уже не бесполезная». Причина в тумблере масштаба: сжатую
/// шкалу можно окинуть целиком, и ночь больше не растягивает экран.
/// Масштаб часа при этом не меняется — его задаёт `hourHeight`.
private let startHour = 0
private let endHour = 24
/// Если сервер ещё не прислал длительность, почасовая сетка использует тот
/// же минимальный слот, что создаётся при переносе задачи: 15 минут.
private let defaultDurationMin = 15
private let rightInset: CGFloat = 6
private let colGap: CGFloat = 3

struct UpcomingHourColumn: Identifiable {
    let date: String
    let tasks: [ApiTask]
    let isToday: Bool
    var id: String { date }
}

struct UpcomingHoursView: View {
    let days: [UpcomingHourColumn]
    let projectColor: (ApiTask) -> Color
    let onTaskTap: (String) -> Void
    /// Перенесли задачу из пула ИЛИ передвинули уже поставленную — назначить
    /// дату (колонки) и время.
    let onSchedule: (String, String, String) -> Void
    /// Растянули плашку за край: новая длительность в минутах и — только для
    /// верхней ручки — новое время начала. Владелец 15.09.2026 просил задавать
    /// продолжительность прямо на сетке, «а не проваливаться в карточку».
    let onResize: ((String, String?, Int) -> Void)?
    /// Горизонтальное перелистывание диапазона: `-1` — назад, `1` — вперёд.
    /// Размер шага определяет владелец данных: один день у «Сегодня», три
    /// дня у трёхдневного режима.
    let onPage: ((Int) -> Void)?
    /// В «Сегодня → Часы» верхняя подпись дня не повторяется: контекст уже
    /// задаёт нативная шапка «Планирования». В «Трёх днях» она остаётся.
    let showsDayHeader: Bool

    /// Масштаб трёхдневной шкалы. По умолчанию мелкий — три колонки и так
    /// узкие, крупный масштаб оставляет на экране всего пару часов.
    @AppStorage("planner_three_day_expanded_timeline") private var isThreeDayExpanded = false
    /// Масштаб суточной шкалы — свой, но схема та же, что у трёхдневного:
    /// по умолчанию мелкий, кнопка увеличивает. Владелец 15.09.2026: «ему
    /// нужен как раз уменьшать, схема должна быть как и у трёхдневного».
    @AppStorage("planner_single_day_expanded_timeline") private var isSingleDayExpanded = false

    /// Тумблер масштаба теперь есть у обоих видов, но помнит их раздельно.
    private var isTimelineExpanded: Bool {
        get { showsDayHeader ? isThreeDayExpanded : isSingleDayExpanded }
        nonmutating set {
            if showsDayHeader { isThreeDayExpanded = newValue } else { isSingleDayExpanded = newValue }
        }
    }

    /// Масштаб шкалы общий для обоих почасовых видов: тумблер теперь есть и
    /// у суточного (владелец 15.09.2026). Раньше суточный был жёстко в
    /// крупном масштабе, и сжать его было нечем.
    private var hourHeight: CGFloat {
        let fullQuarterHourHeight = (minBlockH + 3) * 4
        return isTimelineExpanded ? fullQuarterHourHeight : baseHourH
    }

    init(
        days: [UpcomingHourColumn],
        projectColor: @escaping (ApiTask) -> Color,
        onTaskTap: @escaping (String) -> Void,
        onSchedule: @escaping (String, String, String) -> Void,
        onResize: ((String, String?, Int) -> Void)? = nil,
        onPage: ((Int) -> Void)? = nil,
        showsDayHeader: Bool = true
    ) {
        self.days = days
        self.projectColor = projectColor
        self.onTaskTap = onTaskTap
        self.onSchedule = onSchedule
        self.onResize = onResize
        self.onPage = onPage
        self.showsDayHeader = showsDayHeader
    }

    /// Растягивание плашки за край. Живёт отдельно от `DragState`: там
    /// плашка целиком едет за пальцем, здесь — стоит на месте, а двигается
    /// одна её граница.
    private struct ResizeState {
        enum Edge { case top, bottom }
        let taskID: String
        let edge: Edge
        /// Неподвижная граница: у нижней ручки это верх плашки, у верхней —
        /// её низ. От неё и считается новая длительность.
        let anchorY: CGFloat
        var top: CGFloat
        var height: CGFloat
    }

    private struct DragState {
        let taskID: String
        let title: String
        let color: Color
        let height: CGFloat
        /// Реальная ширина колонки, снятая синхронным `GeometryReader` в
        /// `dayColumn` в момент захвата — НЕ пересчитывается из `gridFrame`
        /// (та обновляется асинхронно через `PreferenceKey` и в момент
        /// самого захвата бывает ещё не готова, отсюда «плавающая
        /// четвертинка» вместо нормальной ширины, владелец 07.09.2026).
        let width: CGFloat
        /// Y верхнего края плашки в системе координат сетки (не пальца и не
        /// центра — см. заголовочный комментарий `TodayHoursView.swift`,
        /// та же логика).
        var topY: CGFloat
        var dayIndex: Int
    }

    @State private var dragState: DragState?
    @State private var resizeState: ResizeState?
    /// Плашка, которую сейчас «взяли»: зажали пальцем, она поднялась и готова
    /// двигаться. Только у неё показываются ручки длительности — владелец
    /// 15.09.2026: «эти точки не должны находиться на постоянке, они
    /// появляются, когда я зажал её, когда она стала активной». Гаснут, как
    /// только берут другую плашку или тапают по пустому месту сетки.
    @State private var activeTaskID: String?
    @State private var previewTime: String?
    @State private var gridFrame: CGRect = .zero
    /// Реальная ширина висящего пула. Нужна только ghost-плашке при
    /// перетаскивании из пула: после отказа от растягивающего
    /// `GeometryReader` она больше не равна ширине всего экрана.
    @State private var untimedPoolWidth: CGFloat = 0
    /// Смещение «где на плашке схватили» относительно её верхнего края —
    /// фиксируется один раз при старте жеста, 0 для пула (там перетаскивание
    /// системное, не через эту переменную).
    @State private var grabOffsetY: CGFloat = 0
    @State private var lastTickTime: String?
    /// Держим генераторы живыми и прогретыми (не пересоздаём на каждое
    /// срабатывание) — тот же приём, что и в `TodayHoursView`.
    @State private var grabHaptic = UIImpactFeedbackGenerator(style: .heavy)
    @State private var tickHaptic = UISelectionFeedbackGenerator()

    /// Пул сверху — то, что ещё предстоит разложить: задачи без времени и
    /// ПРОСРОЧЕННЫЕ. Владелец 15.09.2026: «для этого существует пул задач
    /// наверху — там должны отображаться просроченные и неназначенные, чтобы
    /// я мог их оттуда забрать и выставить планы».
    ///
    /// Задачи будущих дней сюда НЕ попадают — его же уточнение: «то, что на
    /// другой день ещё не наступило, зачем его показывать в дневном и
    /// трёхдневном представлении». На шкале им тоже не место: просроченные
    /// рисовались по своему времени начала на чужой дате, отчего состав
    /// суточного и трёхдневного вида расходился, а время выглядело съехавшим.
    private var untimed: [ApiTask] {
        let today = UpcomingDate.todayString()
        var seen = Set<String>()
        return days.flatMap { day in
            day.tasks.filter { task in
                // Уже стоит на шкале своего дня — в пуле ей делать нечего.
                guard !Self.belongs(task, to: day.date) else { return false }
                let due = task.dueDate ?? ""
                let needsPlanning = task.startTime == nil || due < today && !due.isEmpty
                guard needsPlanning else { return false }
                return seen.insert(task.id).inserted
            }
        }
    }

    /// Задача принадлежит дню, если у неё есть время начала и её дата —
    /// это дата колонки.
    private static func belongs(_ task: ApiTask, to date: String) -> Bool {
        task.startTime != nil && (task.dueDate ?? "") == date
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack(alignment: .topLeading) {
                    ScrollView {
                        gridBody
                    }
                    .tfHoursNativeTopScrollEdge()
                    .onAppear {
                        // Автопрокрутка к текущему часу с запасом 120px сверху
                        // (спека §3.5), зажатая видимым диапазоном (владелец
                        // 07.09.2026: сетка теперь только startHour...endHour).
                        let hour = Calendar.current.component(.hour, from: Date())
                        let anchor = min(max(hour - 1, startHour), endHour)
                        DispatchQueue.main.async {
                            withAnimation { proxy.scrollTo("hour-\(anchor)", anchor: .top) }
                        }
                    }

                    // Шапка дней и пул — два отдельных плавающих окна над
                    // прокруткой, а не строки `VStack`: часы проходят под
                    // ними, поэтому системное scroll-edge затухание остаётся
                    // видно. Владелец 16.09.2026 попросил того же и для дней
                    // недели — «в то же плавающее окно, но чтобы они
                    // обособлены были от пула задач».
                    VStack(spacing: TFSpacing.sm) {
                        if showsDayHeader {
                            UpcomingDayColumnsHeader(days: days)
                        }
                        if !untimed.isEmpty {
                            untimedPool
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .zIndex(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            // Тумблер масштаба нужен обоим почасовым видам — владелец
            // 15.09.2026: «эту кнопку масштаба пусть она будет и в
            // однодневном виде». Раньше он висел только на трёхдневном.
            ToolbarItem(placement: .topBarLeading) {
                Button { isTimelineExpanded.toggle() } label: {
                    Image(systemName: isTimelineExpanded
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel(isTimelineExpanded ? "Сжать временную шкалу" : "Расширить временную шкалу")
            }
        }
        .gesture(
            UpcomingRangePageGesture { translation, velocity in
                guard let onPage, dragState == nil else { return }
                // Короткий медленный сдвиг остаётся случайным касанием. Для
                // флика учитываем скорость, как у системных paging-жестов.
                let projected = translation + velocity * 0.12
                guard abs(translation) >= 45 || abs(projected) >= 90 else { return }
                onPage(projected < 0 ? 1 : -1)
                UISelectionFeedbackGenerator().selectionChanged()
            }
        )
    }

    private var gridBody: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                gridRows
                HStack(spacing: 0) {
                    Color.clear.frame(width: gutterW)
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        dayColumn(day, index: index)
                    }
                }
                nowLine
                previewLine
            }
            .frame(width: geo.size.width, height: hourHeight * CGFloat(endHour - startHour), alignment: .topLeading)
            .onAppear {
                grabHaptic.prepare()
                tickHaptic.prepare()
                gridFrame = geo.frame(in: .global)
            }
            // Геометрия сетки снимается прямо из `GeometryReader`, а не через
            // `PreferenceKey`: значение по preference до жеста не доезжало —
            // в момент захвата `gridFrame` был пустым (0×0), ширина колонки
            // падала на страховку `max(80, …)` вместо реальных ~116pt, и
            // ghost с детекцией дня уезжали тем сильнее, чем правее колонка
            // (владелец 07.09.2026: «на второй ложится 60/40, на третьей
            // 80/20»). Замерено `NSLog` на симуляторе.
            .onChange(of: geo.frame(in: .global)) { _, newValue in
                gridFrame = newValue
            }
        }
        .frame(height: hourHeight * CGFloat(endHour - startHour))
        .overlay(alignment: .topLeading) {
            if let dragState {
                // Ширина ghost — из `dragState.width` (снята синхронно в
                // момент захвата, см. `DragState`). X-смещение по колонке —
                // из измеренной ширины сетки; заглушки «не меньше 80pt» тут
                // больше нет, именно она давала уезжающий вправо ghost.
                let columnWidth = Self.columnWidth(gridWidth: gridFrame.width, gutter: gutterW, dayCount: days.count)
                ghostView(dragState, width: dragState.width)
                    .offset(x: gutterW + CGFloat(dragState.dayIndex) * columnWidth, y: dragState.topY)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Пул задач без времени

    /// Пул расположен в overlay над сеткой, а не в потоке `VStack`: свободные
    /// части вокруг карточки прозрачны, и сетка прокручивается под ней.
    /// Боковой отступ локален пулу — сетку с тремя колонками не ужимаем.
    private var untimedPool: some View {
        // Первый вариант берёт естественную ширину текста: одна короткая
        // задача не превращается в полосу на весь экран. Для длинной записи
        // `ViewThatFits` выбирает второй, ограниченный шириной контейнера.
        // Фон рисуется до внешнего выравнивания, поэтому нет растянутой
        // подложки за карточкой.
        ViewThatFits(in: .horizontal) {
            untimedPoolCard
                .fixedSize(horizontal: true, vertical: false)
            untimedPoolCard
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: UpcomingUntimedPoolWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(UpcomingUntimedPoolWidthKey.self) { untimedPoolWidth = $0 }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TFSpacing.lg)
        .padding(.bottom, TFSpacing.md)
    }

    private var untimedPoolCard: some View {
        // Пул прокручивается ВНУТРИ себя и занимает не больше пары строк.
        // Владелец 15.09.2026: «пул занял четыре часа, мне приспичило на
        // 7 утра что-то назначить — как я туда назначу?». Высота была
        // ограничена и раньше, но без прокрутки: всё, что не поместилось,
        // становилось недоступным. Сворачивать целиком он же и забраковал —
        // «а если мне нужна конкретная задача, а она не появляется в узком
        // виде»: при прокрутке доступны все, а утренние часы открыты.
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                ForEach(Array(untimed.enumerated()), id: \.element.id) { index, task in
                    if index > 0 { TFDivider() }
                    UpcomingUntimedRow(task: task)
                        .opacity(dragState?.taskID == task.id ? 0.3 : 1)
                        .gesture(dragGesture(for: task, dayIndex: 0, top: nil, height: minBlockH, width: max(untimedPoolWidth, 1)))
                        .onTapGesture { if dragState == nil { onTaskTap(task.id) } }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: Self.poolMaxHeight)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
        .tfShadow(TFShadow.dropdown)
    }

    // MARK: - Сетка часов

    private var gridRows: some View {
        VStack(spacing: 0) {
            ForEach(startHour...endHour, id: \.self) { h in
                HStack(alignment: .top, spacing: 0) {
                    Text(String(format: "%02d:00", h))
                        .tfText(.micro)
                        .monospacedDigit()
                        .foregroundStyle(Color.tfDim)
                        .frame(width: gutterW, alignment: .trailing)
                        .padding(.trailing, 6)
                        .offset(y: -6)
                    Rectangle().fill(Color.tfStroke).frame(height: TFBorder.width)
                }
                .frame(height: h < endHour ? hourHeight : 0, alignment: .top)
                .id("hour-\(h)")
            }
        }
    }

    private func dayColumn(_ day: UpcomingHourColumn, index: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(Self.layoutDay(day.tasks.filter { Self.belongs($0, to: day.date) }, hourHeight: hourHeight)) { block in
                    let isDragged = dragState?.taskID == block.task.id
                    // Пока тянут край — плашка живёт по размеру из жеста, а не
                    // по раскладке: та пересчитается только после сохранения.
                    let resize = resizeState?.taskID == block.task.id ? resizeState : nil
                    let blockTop = resize?.top ?? block.top
                    let blockHeight = resize?.height ?? block.height
                    UpcomingTimedBlock(
                        task: block.task,
                        color: projectColor(block.task),
                        durKnown: block.durKnown
                    )
                        .frame(width: Self.blockWidth(colWidth: geo.size.width, totalCols: block.totalCols))
                        .frame(height: blockHeight)
                        // Обрезаем по заданной высоте: заголовок с отступами
                        // не даёт карточке стать ниже своей строки, и короткие
                        // задачи в уменьшенном масштабе всё равно выглядели
                        // крупнее, чем длятся. Теперь высота плашки — это
                        // ровно её время, а текст просто не помещается.
                        .clipped()
                        // Владелец 07.09.2026: «вся плашка исчезает, надо
                        // чтобы тень оставалась на старом месте» — приглушаем
                        // вместо полного скрытия.
                        .opacity(isDragged ? 0.35 : 1)
                        .contentShape(Rectangle())
                        // `HoursDragGesture` — свой `UIGestureRecognizerRepresentable`,
                        // см. заголовочный комментарий структуры ниже по файлу.
                        .gesture(dragGesture(for: block.task, dayIndex: index, top: block.top, height: block.height, width: Self.blockWidth(colWidth: geo.size.width, totalCols: block.totalCols)))
                        .onTapGesture {
                            if dragState == nil {
                                activeTaskID = nil
                                onTaskTap(block.task.id)
                            }
                        }
                        // `.position()` обязан идти ПОСЛЕДНИМ: он отдаёт
                        // родителю размер всего контейнера вместо размера
                        // плашки, и любой `.gesture`/`.onTapGesture`,
                        // навешанный ПОСЛЕ него, ловит касание по всей сетке,
                        // а не по видимой плашке.
                        .position(
                            x: Self.blockLeft(colWidth: geo.size.width, col: block.col, totalCols: block.totalCols)
                                + Self.blockWidth(colWidth: geo.size.width, totalCols: block.totalCols) / 2,
                            y: blockTop + blockHeight / 2
                        )
                }

                // Ручки ставятся по КООРДИНАТЕ ВРЕМЕНИ, а не привязкой к углам
                // плашки (владелец 15.09.2026: «соотнеси эти точки
                // исключительно к графику времени — у тебя же в карточке
                // чёткое время»). `block.top` и `block.top + height` — это и
                // есть начало и конец задачи на шкале, поэтому кружки садятся
                // ровно на них и ни на какой текст не наползают.
                // Отдельным проходом поверх всех плашек: иначе соседний блок
                // перекрывал бы ручку нижележащего.
                ForEach(Self.layoutDay(day.tasks.filter { Self.belongs($0, to: day.date) }, hourHeight: hourHeight)) { block in
                    let resize = resizeState?.taskID == block.task.id ? resizeState : nil
                    let blockTop = resize?.top ?? block.top
                    let blockHeight = resize?.height ?? block.height
                    let left = Self.blockLeft(colWidth: geo.size.width, col: block.col, totalCols: block.totalCols)
                    let width = Self.blockWidth(colWidth: geo.size.width, totalCols: block.totalCols)
                    // Верхняя — справа, нижняя — слева, по диагонали, как в
                    // системном Календаре. По горизонтали чуть внутрь от
                    // самого угла: так аккуратнее и метка не висит на отбивке
                    // между колонками (владелец 15.09.2026).
                    // Хвататься можно за ВЕСЬ край плашки, а не только за
                    // кружок: владелец 15.09.2026 — «не делай обязательным
                    // хвататься за этот кругляшок, очень неудобно; они просто
                    // показывают границы, а хвататься хотя бы за краешек».
                    // Поэтому зона захвата — полоса во всю ширину плашки,
                    // а кружок остался меткой и жеста на себе не несёт.
                    resizeGrabBand(for: block.task, edge: .top, top: blockTop, height: blockHeight)
                        .frame(width: width, height: Self.grabBandHeight)
                        .position(x: left + width / 2, y: blockTop)
                    resizeGrabBand(for: block.task, edge: .bottom, top: blockTop, height: blockHeight)
                        .frame(width: width, height: Self.grabBandHeight)
                        .position(x: left + width / 2, y: blockTop + blockHeight)

                    resizeMarker(for: block.task, edge: .top)
                        .position(x: left + width - Self.handleInset, y: blockTop)
                    resizeMarker(for: block.task, edge: .bottom)
                        .position(x: left + Self.handleInset, y: blockTop + blockHeight)
                }
            }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(Color.tfStroke).frame(width: TFBorder.width) }
    }

    // MARK: - Растягивание плашки за край

    /// Невидимая полоса захвата вдоль всего края плашки. Именно она несёт
    /// жест: тянуть можно за любую точку края, а не прицеливаться в кружок.
    /// Показывается только у взятой плашки — и у той, чей край прямо сейчас
    /// тянут, иначе полоса пропадала бы посреди собственного жеста.
    @ViewBuilder
    private func resizeGrabBand(for task: ApiTask, edge: ResizeState.Edge, top: CGFloat, height: CGFloat) -> some View {
        if isResizable(task) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(resizeGesture(for: task, edge: edge, top: top, height: height))
                .accessibilityLabel(edge == .top ? "Изменить начало: \(task.title)" : "Изменить длительность: \(task.title)")
        }
    }

    /// Кружок-метка границы: только показывает, где край и за что тянуть,
    /// жеста на себе не несёт (владелец 15.09.2026: «они просто показывают,
    /// что вот их границы»). Как в системном Календаре.
    @ViewBuilder
    private func resizeMarker(for task: ApiTask, edge: ResizeState.Edge) -> some View {
        if isResizable(task) {
            let dragging = resizeState?.taskID == task.id && resizeState?.edge == edge
            Circle()
                .fill(Color.white)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 0.5))
                .frame(width: dragging ? 12 : 9, height: dragging ? 12 : 9)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// Тянуть можно только взятую плашку со временем: у пула ещё нет ни
    /// начала, ни конца — растягивать нечего.
    private func isResizable(_ task: ApiTask) -> Bool {
        guard onResize != nil, task.startTime != nil else { return false }
        return activeTaskID == task.id || resizeState?.taskID == task.id
    }

    /// Тот же распознаватель, что и у переноса: SwiftUI-жесты в этой сетке
    /// дерутся со скроллом (прецедент 07.09.2026). Удержание короче, чем у
    /// переноса, — ручка маленькая и специально нащупывается пальцем, ждать
    /// от неё полной задержки утомительно.
    private func resizeGesture(for task: ApiTask, edge: ResizeState.Edge, top: CGFloat, height: CGFloat) -> some UIGestureRecognizerRepresentable {
        HoursDragGesture(
            minimumPressDuration: Self.resizeHoldSeconds,
            onBegin: { _ in
                grabHaptic.impactOccurred()
                grabHaptic.prepare()
                lastTickTime = nil
                let state = ResizeState(
                    taskID: task.id,
                    edge: edge,
                    anchorY: edge == .bottom ? top : top + height,
                    top: top,
                    height: height
                )
                resizeState = state
                // Та же красная метка на шкале, что и при переносе плашки:
                // владелец 15.09.2026 просил видеть время и при растягивании,
                // «а не так, на глаз». Показывается время ТОЙ границы, за
                // которую тянут, — она и меняется.
                let time = Self.edgeTime(of: state, hourHeight: hourHeight)
                previewTime = time
                lastTickTime = time
            },
            onChange: { point in
                guard var state = resizeState, state.taskID == task.id else { return }
                apply(&state, fingerY: point.y - gridFrame.minY)
                resizeState = state
                let time = Self.edgeTime(of: state, hourHeight: hourHeight)
                previewTime = time
                if time != lastTickTime {
                    lastTickTime = time
                    tickHaptic.selectionChanged()
                    tickHaptic.prepare()
                }
            },
            onEnd: { point in
                guard var state = resizeState, state.taskID == task.id else { return }
                apply(&state, fingerY: point.y - gridFrame.minY)
                resizeState = nil
                previewTime = nil
                lastTickTime = nil
                let minutes = Self.minutes(fromHeight: state.height, hourHeight: hourHeight)
                // Начало сдвигает только верхняя ручка: у нижней конец едет,
                // а старт остаётся там же, где и был.
                let newStart = edge == .top ? Self.timeFromOffset(state.top, hourHeight: hourHeight) : nil
                onResize?(task.id, newStart, minutes)
            },
            onCancel: {
                guard resizeState?.taskID == task.id else { return }
                resizeState = nil
                previewTime = nil
                lastTickTime = nil
            }
        )
    }

    /// Двигает одну границу вслед за пальцем, вторую держит на месте и не даёт
    /// плашке стать короче минимального слота.
    private func apply(_ state: inout ResizeState, fingerY: CGFloat) {
        let minH = CGFloat(snapMin) / 60 * hourHeight
        switch state.edge {
        case .bottom:
            let bottom = max(fingerY, state.anchorY + minH)
            state.top = state.anchorY
            state.height = Self.snapped(bottom - state.anchorY, hourHeight: hourHeight, minimum: minH)
        case .top:
            let newTop = min(fingerY, state.anchorY - minH)
            let snappedHeight = Self.snapped(state.anchorY - newTop, hourHeight: hourHeight, minimum: minH)
            state.height = snappedHeight
            state.top = state.anchorY - snappedHeight
        }
    }

    /// Время подвижной границы: у нижней ручки это конец задачи, у верхней —
    /// её начало. Именно оно и едет по шкале красной меткой.
    private static func edgeTime(of state: ResizeState, hourHeight: CGFloat) -> String {
        let y = state.edge == .top ? state.top : state.top + state.height
        return timeFromOffset(y, hourHeight: hourHeight)
    }

    /// Высота, округлённая до шага сетки (те же 15 минут, что у переноса).
    private static func snapped(_ height: CGFloat, hourHeight: CGFloat, minimum: CGFloat) -> CGFloat {
        let step = CGFloat(snapMin) / 60 * hourHeight
        guard step > 0 else { return max(height, minimum) }
        return max((height / step).rounded() * step, minimum)
    }

    /// Высота плашки в минутах — то, что уходит на сервер как длительность.
    private static func minutes(fromHeight height: CGFloat, hourHeight: CGFloat) -> Int {
        guard hourHeight > 0 else { return snapMin }
        let raw = Double(height / hourHeight) * 60
        let snappedValue = (raw / Double(snapMin)).rounded() * Double(snapMin)
        return max(Int(snappedValue), snapMin)
    }

    // MARK: - Перетаскивание — И пул, И уже поставленная плашка (см. заголовочный комментарий файла)

    /// `dayIndex` — исходное значение, только для конструктора `DragState`
    /// (пул им не владеет, передаёт 0 — сразу же на первом обновлении
    /// пересчитывается из X пальца). `top` — верхний край плашки ДО
    /// перетаскивания (`block.top`), нужен только чтобы вычислить точку
    /// захвата один раз в начале жеста; `nil` у пула (задача ещё без
    /// времени, точки захвата нет — куда палец, туда и время).
    ///
    /// Владелец 07.09.2026, живой тест на iPhone Air: SwiftUI-жест
    /// (`LongPressGesture.sequenced(before: DragGesture)`, что через
    /// `.gesture`, что через `.simultaneousGesture`) не давал `ScrollView`
    /// прокручиваться, если палец стартовал прямо на карточке — тот же
    /// диагноз, что уже задокументирован в `HorizontalPan.swift` для свайпа
    /// строки. Решение оттуда же: `UIGestureRecognizerRepresentable` поверх
    /// `UILongPressGestureRecognizer` — он САМ проваливается, если палец
    /// уходит дальше `allowableMovement` (по умолчанию 10pt) до истечения
    /// `minimumPressDuration`, отдавая касание `ScrollView`; после успешного
    /// распознавания `.changed` как обычно несёт текущую позицию пальца без
    /// ограничения на смещение — то самое «зажал, потом веди».
    private static let dragHoldSeconds: Double = 0.25
    /// Ручка длительности хватается быстрее, чем плашка целиком: по ней
    /// специально целятся пальцем, и полная задержка переноса ощущается как
    /// «не реагирует». Меньше делать нельзя — жест начнёт перехватывать
    /// вертикальную прокрутку сетки.
    private static let resizeHoldSeconds: Double = 0.12
    /// Потолок высоты пула. Две строки с запасом: дальше он начинает
    /// закрывать утренние часы, на которые как раз и надо что-то ставить.
    private static let poolMaxHeight: CGFloat = 88
    /// Насколько метка границы отступает от бокового края плашки внутрь.
    private static let handleInset: CGFloat = 10
    /// Высота полосы захвата вдоль края: половина внутрь плашки, половина
    /// наружу. Меньше делать нельзя — в край перестанет попадать палец.
    private static let grabBandHeight: CGFloat = 26

    /// Ширина дневной колонки. 0 означает «сетка ещё не измерена» — раньше
    /// вместо этого возвращалась заглушка в 80pt, и промах молча уезжал в
    /// геометрию (см. комментарий у `onChange` в `gridBody`).
    static func columnWidth(gridWidth: CGFloat, gutter: CGFloat, dayCount: Int) -> CGFloat {
        guard dayCount > 0, gridWidth > gutter else { return 0 }
        return (gridWidth - gutter) / CGFloat(dayCount)
    }

    /// `width` — реальная ширина колонки/пула в точке вызова, снятая
    /// СИНХРОННЫМ `GeometryReader` (`dayColumn` уже его имеет; пул — своим,
    /// см. `untimedPool`), а не пересчитанная из асинхронного `gridFrame`.
    private func dragGesture(for task: ApiTask, dayIndex: Int, top: CGFloat?, height: CGFloat, width: CGFloat) -> some UIGestureRecognizerRepresentable {
        func columnAndDay(_ point: CGPoint) -> (fingerY: CGFloat, overDay: Int) {
            let fingerX = point.x - gridFrame.minX
            let fingerY = point.y - gridFrame.minY
            let columnWidth = Self.columnWidth(gridWidth: gridFrame.width, gutter: gutterW, dayCount: days.count)
            // Сетку ещё не измерили — день не пересчитываем, иначе плашка
            // прыгнет в колонку, посчитанную по выдуманной ширине.
            guard columnWidth > 0 else { return (fingerY, dragState?.dayIndex ?? dayIndex) }
            let overDay = min(max(Int((fingerX - gutterW) / columnWidth), 0), max(days.count - 1, 0))
            return (fingerY, overDay)
        }
        return HoursDragGesture(
            minimumPressDuration: Self.dragHoldSeconds,
            onBegin: { point in
                let (fingerY, overDay) = columnAndDay(point)
                grabOffsetY = top.map { fingerY - $0 } ?? 0
                lastTickTime = nil
                // Зажали плашку — она «взята»: у неё показываются ручки
                // длительности, у остальных гаснут.
                activeTaskID = task.id
                grabHaptic.impactOccurred()
                grabHaptic.prepare()
                dragState = DragState(
                    taskID: task.id, title: task.title, color: projectColor(task),
                    height: max(minBlockH, height), width: width, topY: fingerY - grabOffsetY, dayIndex: overDay
                )
                let time = Self.timeFromOffset(fingerY - grabOffsetY, hourHeight: hourHeight)
                previewTime = time
                lastTickTime = time
            },
            onChange: { point in
                guard dragState?.taskID == task.id else { return }
                let (fingerY, overDay) = columnAndDay(point)
                dragState?.topY = fingerY - grabOffsetY
                dragState?.dayIndex = overDay
                let time = Self.timeFromOffset(fingerY - grabOffsetY, hourHeight: hourHeight)
                previewTime = time
                if time != lastTickTime {
                    lastTickTime = time
                    tickHaptic.selectionChanged()
                    tickHaptic.prepare()
                }
            },
            onEnd: { point in
                guard dragState?.taskID == task.id else { return }
                let (fingerY, overDay) = columnAndDay(point)
                let topY = fingerY - grabOffsetY
                dragState = nil
                previewTime = nil
                guard topY >= -hourHeight, days.indices.contains(overDay) else { return }
                onSchedule(task.id, days[overDay].date, Self.timeFromOffset(topY, hourHeight: hourHeight))
            },
            onCancel: {
                guard dragState?.taskID == task.id else { return }
                dragState = nil
                previewTime = nil
            }
        )
    }

    /// Ghost рисуется не тоньше `minCardBodyHeight`, тот же порог, что у
    /// плашки в покое (`layoutDay`) — реальная (снапнутая) высота на
    /// итоговое размещение не влияет.
    private func ghostView(_ state: DragState, width: CGFloat) -> some View {
        Text(state.title)
            .tfText(.meta)
            .foregroundStyle(Color.tfHourChipInk)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: width, height: max(minCardBodyHeight, state.height), alignment: .topLeading)
            .background(state.color)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.sm))
            .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
            .scaleEffect(1.015)
    }

    @ViewBuilder
    private var nowLine: some View {
        let now = Date()
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        let hour = comps.hour ?? 0
        // Видимый диапазон теперь startHour...endHour, а не сутки целиком
        // (владелец 07.09.2026) — вне этого окна линия просто не рисуется.
        if hour >= startHour, hour < endHour {
            let pos = CGFloat(hour - startHour) * hourHeight + CGFloat(comps.minute ?? 0) / 60 * hourHeight
            HStack(spacing: 4) {
                Text(String(format: "%02d:%02d", hour, comps.minute ?? 0))
                    .tfText(.micro)
                    .monospacedDigit()
                    .foregroundStyle(Color.tfRed)
                    .frame(width: gutterW, alignment: .trailing)
                    .background(Color.tfBackground)
                Circle().fill(Color.tfRed).frame(width: 7, height: 7)
                Rectangle().fill(Color.tfRed).frame(height: 1.5)
            }
            .offset(y: pos - 4)
            .allowsHitTesting(false)
        }
    }

    /// Точка + время во время перетаскивания, БЕЗ линии через всю сетку —
    /// владелец 07.09.2026: «зачем ты мне приебашил этот лазер на весь
    /// экран, я просил только точечку с цифрами». Раньше `previewTime`
    /// считался, но нигде не рисовался вообще.
    @ViewBuilder
    private var previewLine: some View {
        if let preview = previewTime, let minutes = Self.minutesFrom(preview) {
            let pos = CGFloat(minutes - startHour * 60) / 60 * hourHeight
            HStack(spacing: 4) {
                Text(preview)
                    .tfText(.micro)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.tfRed)
                    .frame(width: gutterW, alignment: .trailing)
                    .background(Color.tfBackground)
                Circle().fill(Color.tfRed).frame(width: 7, height: 7)
            }
            .fixedSize()
            .offset(y: pos - 4)
            .allowsHitTesting(false)
        }
    }

    private static func minutesFrom(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    // MARK: - Раскладка перекрывающихся задач (`layoutDay`, DayHours.tsx)

    private struct PlacedBlock: Identifiable {
        let task: ApiTask
        let top: CGFloat
        let height: CGFloat
        let col: Int
        let totalCols: Int
        let durKnown: Bool
        var id: String { task.id }
    }

    private static func hoursFromTime(_ t: String?) -> Double? {
        guard let (h, m) = DateFormats.localTimeComponents(t) else { return nil }
        return Double(h) + Double(m) / 60
    }

    /// Смещение от верха сетки (0 = `startHour`) → «ЧЧ:ММ», зажатое видимым
    /// диапазоном `startHour...endHour` (владелец 07.09.2026).
    private static func timeFromOffset(_ px: CGFloat, hourHeight: CGFloat) -> String {
        let raw = (px / hourHeight) * 60
        let snapped = (raw / CGFloat(snapMin)).rounded() * CGFloat(snapMin)
        let startMin = CGFloat(startHour * 60)
        let endMin = CGFloat(endHour * 60)
        let clamped = min(max(snapped + startMin, startMin), endMin - CGFloat(snapMin))
        let h = Int(clamped) / 60
        let m = Int(clamped) % 60
        return String(format: "%02d:%02d", h, m)
    }

    private static func blockWidth(colWidth: CGFloat, totalCols: Int) -> CGFloat {
        let totalGap = CGFloat(totalCols - 1) * colGap
        return max(4, (colWidth - rightInset - totalGap) / CGFloat(totalCols))
    }

    private static func blockLeft(colWidth: CGFloat, col: Int, totalCols: Int) -> CGFloat {
        col == 0 ? 0 : blockWidth(colWidth: colWidth, totalCols: totalCols) * CGFloat(col) + CGFloat(col) * colGap
    }

    private static func layoutDay(_ tasks: [ApiTask], hourHeight: CGFloat) -> [PlacedBlock] {
        struct Item { let task: ApiTask; let start: Double; let end: Double; let durKnown: Bool }
        let items = tasks.compactMap { t -> Item? in
            guard let start = hoursFromTime(t.startTime) else { return nil }
            let durKnown = t.durationMin != nil
            let dur = Double(t.durationMin ?? defaultDurationMin)
            return Item(task: t, start: start, end: start + dur / 60, durKnown: durKnown)
        }.sorted { $0.start != $1.start ? $0.start < $1.start : $0.end < $1.end }

        var placed: [PlacedBlock] = []
        var cluster: [Item] = []
        var clusterEnd = -Double.infinity

        func flush() {
            guard !cluster.isEmpty else { return }
            var colEnds: [Double] = []
            var colOf: [Int] = []
            for item in cluster {
                if let idx = colEnds.firstIndex(where: { $0 <= item.start }) {
                    colEnds[idx] = item.end
                    colOf.append(idx)
                } else {
                    colOf.append(colEnds.count)
                    colEnds.append(item.end)
                }
            }
            let cols = colEnds.count
            for (i, item) in cluster.enumerated() {
                // Задачи ДО `startHour` (глубокая ночь) прижимаются к верху
                // сетки вместо отрицательных координат (владелец 07.09.2026).
                let hoursFromTop = item.start - Double(startHour)
                placed.append(PlacedBlock(
                    task: item.task,
                    // Ни смещения сверху, ни вычета снизу: координаты плашки
                    // — это ровно её время. Прежние «+1 сверху, −3 снизу»
                    // задумывались как зазор между соседними карточками, но
                    // это фиксированные точки, а не минуты: в уменьшенном
                    // трёхдневном масштабе (час = 41pt) они съедали у
                    // 15-минутной задачи треть высоты, и сетка продолжала
                    // врать даже после снятия минимальной высоты — владелец
                    // 15.09.2026: «ну а в уменьшенном масштабе врёт… на трёх
                    // днях». Зазор теперь даёт скругление углов карточки.
                    top: CGFloat(max(0, hoursFromTop * Double(hourHeight))),
                    // Высота = РЕАЛЬНАЯ длительность, без подтягивания коротких
                    // задач до читаемого размера. Владелец 15.09.2026: «в каком
                    // это плане читаемая карточка? на то у меня и суточный вид,
                    // там они увеличены, и на трёхдневном есть тумблер масштаба
                    // — тут надо всё честно показывать». Раньше действовал пол
                    // `minCardBodyHeight` (44pt), и в мелком трёхдневном
                    // масштабе 15-минутная задача занимала 44pt, то есть
                    // выглядела ЧАСОМ — при часе в 41pt. Отсюда и было
                    // расхождение между двумя видами.
                    height: max(minVisibleBlockHeight, CGFloat((item.end - item.start) * Double(hourHeight))),
                    col: colOf[i],
                    totalCols: cols,
                    durKnown: item.durKnown
                ))
            }
            cluster = []
        }

        for item in items {
            if !cluster.isEmpty, item.start >= clusterEnd {
                flush()
                clusterEnd = -Double.infinity
            }
            cluster.append(item)
            clusterEnd = max(clusterEnd, item.end)
        }
        flush()
        return placed
    }
}

/// Перетаскивание карточки/плашки на почасовой сетке — тот же приём, что
/// `HorizontalPan` (см. заголовочный комментарий этого файла и
/// `HorizontalPan.swift`): SwiftUI `DragGesture`/`.simultaneousGesture`
/// объявляют себя хозяином касания раньше, чем `ScrollView` успевает решить,
/// прокрутка это или нет, и список не листается пальцем по карточке ни в
/// одном варианте (владелец 07.09.2026, живой тест на iPhone Air). Здесь
/// вместо своего распознавателя — штатный `UILongPressGestureRecognizer`:
/// он сам проваливается на движении больше `allowableMovement` до истечения
/// `minimumPressDuration`, отдавая касание `ScrollView`, а после успешного
/// распознавания продолжает нести текущую позицию пальца в `.changed` без
/// ограничения на смещение.
private struct HoursDragGesture: UIGestureRecognizerRepresentable {
    let minimumPressDuration: Double
    let onBegin: (CGPoint) -> Void
    let onChange: (CGPoint) -> Void
    let onEnd: (CGPoint) -> Void
    let onCancel: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumPressDuration
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let point = context.converter.location(in: .global)
        switch recognizer.state {
        case .began:
            // Владелец 07.09.2026: «скролл да, но лозит весь экран, я хочу
            // двигать карточку, а двигаю весь экран» — до успешного
            // распознавания прокрутке НЕ мешаем (быстрый свайп должен
            // скроллить), но как только жест реально начался (палец
            // удержан, карточка захвачена), прокрутку глушим на время
            // перетаскивания. `isScrollEnabled = false` — штатный способ
            // остановить `UIScrollView` целиком (не только его собственный
            // `panGestureRecognizer`), надёжнее точечного переключения
            // одного распознавателя.
            Self.enclosingScrollView(of: recognizer.view)?.isScrollEnabled = false
            onBegin(point)
        case .changed:
            onChange(point)
        case .ended:
            Self.enclosingScrollView(of: recognizer.view)?.isScrollEnabled = true
            onEnd(point)
        case .cancelled, .failed:
            Self.enclosingScrollView(of: recognizer.view)?.isScrollEnabled = true
            onCancel()
        default:
            break
        }
    }

    /// Владелец 07.09.2026, диагностика через unified log: `recognizer.view`
    /// у `UIGestureRecognizerRepresentable` — это ХОСТИНГ-VIEW всего экрана
    /// целиком (`frame = 402x874`, весь экран), а не маленькая вьюха
    /// карточки. Реальный `UIScrollView` от SwiftUI `ScrollView` — ПОТОМОК
    /// этого хостинга, а не предок: поиск вверх по `.superview` (как было)
    /// гарантированно возвращал `nil`, отсюда скролл не глушился ни разу.
    /// Ищем вниз по `.subviews` (BFS от самого хостинга).
    private static func enclosingScrollView(of view: UIView?) -> UIScrollView? {
        guard let root = view else { return nil }
        var queue: [UIView] = [root]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if let scrollView = current as? UIScrollView { return scrollView }
            queue.append(contentsOf: current.subviews)
        }
        return nil
    }

    /// До момента `.began` прокрутке не мешаем — тот же приём, что у
    /// `HorizontalPan.Coordinator`; сама блокировка активной прокрутки — в
    /// `handleUIGestureRecognizerAction` выше, через `isScrollEnabled`.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// Перелистывание временного диапазона поверх вертикального ScrollView.
///
/// Используется тот же направленный UIKit-recognizer, что у свайпов строк:
/// он проваливается при вертикальном движении и не отбирает прокрутку. Если
/// касание началось на карточке, paging ждёт исход собственного long-press:
/// быстрый горизонтальный свайп перелистывает, а удержание с переносом
/// карточки получает жест целиком и не меняет дату после отпускания.
private struct UpcomingRangePageGesture: UIGestureRecognizerRepresentable {
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> HorizontalPanRecognizer {
        let recognizer = HorizontalPanRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: HorizontalPanRecognizer, context: Context) {
        switch recognizer.state {
        case .ended:
            onEnded(recognizer.horizontalTranslation, recognizer.velocity(in: recognizer.view).x)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer is UILongPressGestureRecognizer
        }
    }
}

private extension View {
    @ViewBuilder
    func tfHoursNativeTopScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

/// Заголовок колонок дня — уходит в `ScreenHeader.below` (спека §3.5, `DayColumnsHeader`).
struct UpcomingDayColumnsHeader: View {
    let days: [UpcomingHourColumn]

    /// Высота окна. Задана явно: внутри ручная раскладка, своей высоты у
    /// неё нет.
    private static let height: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            // Подписи занимают всю ширину сетки, без боковых полей, поэтому
            // центр колонки считается прямо в её координатах.
            let columnWidth = (proxy.size.width - gutterW) / CGFloat(max(days.count, 1))
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                Text(UpcomingDate.formatDayColumnLabel(day.date))
                    .tfText(.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(day.isToday ? Color.tfRed : Color.tfSub)
                    .position(
                        x: gutterW + columnWidth * (CGFloat(index) + 0.5),
                        y: proxy.size.height / 2
                    )
            }
        }
        .frame(height: Self.height)
        // Никакой подложки: владелец 16.09.2026 — «мне не нужна вот эта
        // полоска, мне нужно, чтобы я видел только среда и число». Голый
        // текст поверх сетки; часы проходят под ним и затухают у кромки
        // прокрутки сами.
        .allowsHitTesting(false)
    }
}

/// Плашка задачи без времени в пуле — spec §3.5, `UntimedRow`.
/// Раньше был `Button` — тот же конфликт Button+`DragGesture`, что и у
/// `UpcomingTimedBlock` (см. её комментарий). Тап и перетаскивание
/// навешаны в `untimedPool` двумя независимыми модификаторами.
private struct UpcomingUntimedRow: View {
    let task: ApiTask

    var body: some View {
        HStack(spacing: 8) {
            if task.priority <= 3, let p = TaskPriority(rawValue: task.priority) {
                TFPriorityArrows(p)
            }
            if !task.subtasks.isEmpty {
                Text("\(task.subtasks.count { $0.done })/\(task.subtasks.count)")
                    .tfText(.caption).monospacedDigit().foregroundStyle(Color.tfDim)
            }
            Text(task.title)
                .tfText(.action)
                .foregroundStyle(task.status == .completed ? Color.tfSub : Color.tfText)
                .strikethrough(task.status == .completed)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Замер фона выбранного `ViewThatFits`-варианта. `GeometryReader` живёт
/// только фоном и поэтому не резервирует для пула высоту, как это делал
/// прежний корневой `GeometryReader`.
private struct UpcomingUntimedPoolWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Плашка задачи на сетке — сплошная заливка цветом проекта, тёмный текст
/// (WCAG-аудит §3.5: белый текст не проходит норму ни на одном цвете палитры).
/// Раньше был `Button` — владелец 03.09.2026, после `.draggable`/
/// `.dropDestination` на уже поставленной плашке: «беру как тень, но не
/// ездит» (системный drag не отслеживал перетаскивание внутри
/// `.position()`-блока надёжно). Заменено на свой `DragGesture`, тот же
/// проверенный приём, что уже в «Сегодня» (`TodayHoursView`) — там ровно
/// по той же причине тап сделан `.onTapGesture` снаружи, а не `Button`
/// внутри (Button конкурирует с `DragGesture` за жест на одном и том же
/// касании). Тап и жест перетаскивания теперь оба навешаны в `dayColumn`.
private struct UpcomingTimedBlock: View {
    let task: ApiTask
    let color: Color
    let durKnown: Bool

    var body: some View {
        Text(task.title)
            .tfText(.meta)
            .foregroundStyle(Color.tfHourChipInk)
            .strikethrough(task.status == .completed)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color)
            .opacity(task.status == .completed ? 0.5 : 1)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.sm))
            .mask(alignment: .top) {
                if durKnown {
                    Rectangle()
                } else {
                    LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom)
                }
            }
    }
}

/// Живая рамка трёхдневной сетки в общем именованном пространстве
/// «upcomingHoursGrid». Перетаскивание из пула «без времени» целится по этой
/// рамке (в т.ч. колонка дня по X); кэш, снятый в `onAppear`, устаревал после
/// автопрокрутки сетки к текущему часу. Фоновый `GeometryReader` обновляет
/// рамку при скролле, а не только при смене размера.
