import SwiftUI
import UIKit

/// Куда ведёт вытягивание. Семья — родитель и его дети (02.10.2026,
/// владелец: «закладки — это дети, а как вернуться к родителю?»):
/// справа лежат только дети, вглубь — справа налево; слева — родитель,
/// назад — слева направо, как системный свайп «назад».
enum TaskFamilyPullDirection {
    /// К ребёнку: входящая карточка выезжает справа поверх текущей.
    case forward
    /// К родителю: текущая карточка уезжает вправо, открывая родителя под ней.
    case back

    static func toward(_ id: String, parentID: String?) -> TaskFamilyPullDirection {
        id == parentID ? .back : .forward
    }
}

/// Состояние вытягивания соседней карточки семьи.
///
/// Отдельный `@Observable`, а не `@State` экрана (02.10.2026): смещение
/// меняется на каждом кадре жеста, и когда оно жило в `@State` корня,
/// SwiftUI каждый кадр заново считал body обеих карточек — два `List` с
/// секциями и редакторами. Теперь смещение читают только маленькие
/// модификаторы (`TaskFamilyOutgoing`, `TaskFamilyIncoming`) и колонки
/// закладок; корень перерисовывается лишь при захвате и завершении.
@MainActor
@Observable
final class TaskFamilyPull {
    /// Пройденный путь перехода (0…ширина): насколько въехал ребёнок
    /// справа или насколько уехала вправо текущая карточка по пути к родителю.
    var offset: CGFloat = 0
    var direction: TaskFamilyPullDirection = .forward
    /// Сдвиг закладок детей вправо: уезжают вместе с жестом и
    /// возвращаются своей пружиной уже после перехода.
    var tabsShift: CGFloat = 0
    /// Сдвиг закладки родителя влево: уходит под кромку, пока въезжает
    /// ребёнок, и выезжает обратно уже на новой карточке.
    var leadingShift: CGFloat = 0
    /// Закладка, за которую взялись; пока nil — второй карточки на экране нет.
    var pullingID: String?
    /// Карточка, с которой начали тянуть: по ней считается слот закладки,
    /// приклеенной к входящей карточке, даже когда выбор уже сменился.
    var originID: String?
    /// Переход принят: ждём сохранения и загрузки, доводим пружину.
    var settling = false
    /// Карточки уже поменялись местами, а превью ещё лежит сверху — до
    /// первого кадра настоящей карточки под ним.
    var handoff = false
    /// Счётчики для тактильного отклика: захват и приземление карточки.
    var captureTick = 0
    var landTick = 0

    /// Доля пройденного пути; на передаче карточек — ноль, чтобы новая
    /// настоящая карточка сразу стояла без эффектов.
    func progress(width: CGFloat) -> CGFloat {
        guard !handoff else { return 0 }
        return rawProgress(width: width)
    }

    func rawProgress(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(1, max(0, offset / width))
    }

    func follow(_ value: CGFloat) {
        offset = value
        tabsShift = min(40, value * 0.45)
        if direction == .forward {
            leadingShift = -min(TaskFamilyEdgeTabs.expandedWidth, value * 0.45)
        }
    }
}

/// One native sheet, with an interactive horizontal transition inside it.
struct TaskFormScreen: View {
    @State private var model: TaskFormViewModel
    @State private var selectedCardID: String?
    @State private var models: [String: TaskFormViewModel] = [:]
    /// Загрузка соседних карточек: переход дожидается её через `await`,
    /// без опроса `isLoadingTask` раз в 30 мс.
    @State private var loads: [String: Task<Void, Never>] = [:]
    /// Родитель первым, за ним его дети (см. `loadScreen` в `TaskFormScreen.swift`).
    @State private var family: [ApiTask] = []
    @State private var incoming: TaskFormViewModel?
    @State private var drag = TaskFamilyPull()
    @State private var expandedSectionsByCard: [String: Set<TaskDetailSection>] = [:]
    @State private var expandedSheet = false
    @State private var requestSwitch: ((String) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let expanding: Bool

    init(taskID: String? = nil, presetDueToday: Bool = false, startDictation: Bool = false) {
        _model = State(initialValue: TaskFormViewModel(taskID: taskID, presetDueToday: presetDueToday, startDictation: startDictation))
        _selectedCardID = State(initialValue: taskID)
        expanding = false
    }

    init(expandingFrom viewModel: TaskFormViewModel) {
        _model = State(initialValue: viewModel)
        _selectedCardID = State(initialValue: nil)
        expanding = true
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let forward = drag.direction == .forward
            ZStack {
                Color.tfBackground.ignoresSafeArea()
                TaskCardContent(model: model, expanding: expanding, family: family,
                    onFamilyLoaded: receiveFamily,
                    onFamilySelected: { finishSelection($0, width: width, height: height) },
                    onSwitchAvailable: { requestSwitch = $0 },
                    onSelectionFailed: resetPull,
                    initialExpandedSections: expandedSections(for: model),
                    onExpandedSectionsChanged: { storeExpandedSections($0, for: model) })
                    .id(selectedCardID ?? "new")
                    .modifier(TaskFamilyOutgoing(drag: drag, width: width, reduceMotion: reduceMotion))
                    .overlay {
                        if drag.pullingID != nil || drag.settling {
                            Color.clear.contentShape(Rectangle()).onTapGesture {}.accessibilityHidden(true)
                        }
                    }
                    .zIndex(1)
                if let incoming, drag.pullingID != nil {
                    TaskCardContent(model: incoming, expanding: false, family: [],
                        onFamilyLoaded: { _ in }, onFamilySelected: { _ in },
                        initialExpandedSections: expandedSections(for: incoming),
                        onExpandedSectionsChanged: { storeExpandedSections($0, for: incoming) },
                        preview: true)
                        .background(Color.tfBackground.ignoresSafeArea())
                        // Скругление обычным непрерывным прямоугольником: его
                        // Core Animation режет дёшево, а правые углы и так
                        // уходят под скругления шторки и экрана. Родитель
                        // лежит под уходящей карточкой целиком — ему не нужно.
                        .clipShape(RoundedRectangle(cornerRadius: forward ? 14 : 0, style: .continuous))
                        .overlay(alignment: .leading) {
                            if forward {
                                TaskFamilyLeadingShadow()
                                attachedPullHandle(height: height)
                            }
                        }
                        .modifier(TaskFamilyIncoming(drag: drag, width: width, reduceMotion: reduceMotion))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        // К родителю: он лежит ПОД уходящей карточкой. На
                        // передаче превью поднимается наверх, пока под ним
                        // собирается настоящая карточка.
                        .zIndex(!forward && !drag.handoff ? 0 : 2)
                }
            }
            .clipped()
            .overlay(alignment: .trailing) {
                if expandedSheet && childTabs.contains(where: { $0.element.id != selectedCardID }) {
                    TaskFamilyEdgeTabs(members: childTabs, side: .trailing, selectedID: selectedCardID,
                        height: height, width: width, drag: drag,
                        prepare: prepare, capture: beginPull, select: select, cancel: resetPull)
                }
            }
            .overlay(alignment: .leading) {
                if expandedSheet, let parent = parentTab, parent.element.id != selectedCardID {
                    TaskFamilyEdgeTabs(members: [parent], side: .leading, selectedID: selectedCardID,
                        height: height, width: width, drag: drag,
                        prepare: prepare, capture: beginPull, select: select, cancel: resetPull)
                }
            }
            .background(TaskSheetExpansionProbe { expanded in
                if expandedSheet != expanded {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { expandedSheet = expanded }
                }
                if !expanded && !drag.settling && drag.pullingID != nil { resetPull() }
            })
            .sensoryFeedback(.impact(weight: .light), trigger: drag.captureTick)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.8), trigger: drag.landTick)
        }
        .background(Color.tfBackground.ignoresSafeArea())
    }

    /// Закладка родителя — только когда семья действительно есть.
    private var parentTab: (offset: Int, element: ApiTask)? {
        guard family.count > 1, let parent = family.first else { return nil }
        return (0, parent)
    }

    /// Закладки детей с их номером в семье: номер на закладке не меняется
    /// от того, какая карточка сейчас открыта.
    private var childTabs: [(offset: Int, element: ApiTask)] {
        Array(Array(family.enumerated()).dropFirst())
    }

    private func receiveFamily(_ members: [ApiTask]) {
        family = members
        if let id = model.taskID { models[id] = model }
        for member in members where member.id != model.taskID {
            _ = cardModel(for: member.id)
        }
    }

    /// Модель соседней карточки: из кэша или новая, с запущенной загрузкой.
    /// Неудачную загрузку перезапускает при следующем обращении.
    private func cardModel(for id: String) -> TaskFormViewModel {
        let candidate = models[id] ?? TaskFormViewModel(taskID: id)
        models[id] = candidate
        if candidate.loadedTask == nil && loads[id] == nil {
            candidate.isLoadingTask = true
            loads[id] = Task {
                await candidate.loadIfNeeded()
                await candidate.loadRoles()
            }
        }
        return candidate
    }

    /// Дожидается загрузки карточки; nil — открыть её не удалось.
    private func loadedCardModel(for id: String) async -> TaskFormViewModel? {
        let candidate = cardModel(for: id)
        await loads[id]?.value
        guard candidate.loadedTask != nil else {
            loads[id] = nil
            return nil
        }
        return candidate
    }

    private func prepare(_ id: String) {
        guard id != selectedCardID, !drag.settling else { return }
        incoming = cardModel(for: id)
    }

    /// Закладку захватили: вторая карточка появляется на экране.
    private func beginPull(_ id: String) {
        guard id != selectedCardID, !drag.settling else { return }
        incoming = cardModel(for: id)
        drag.direction = .toward(id, parentID: family.first?.id)
        drag.originID = selectedCardID
        drag.pullingID = id
        drag.captureTick += 1
    }

    private func select(_ id: String) {
        guard !drag.settling, id != selectedCardID, let requestSwitch else { resetPull(); return }
        drag.settling = true
        Task {
            guard await loadedCardModel(for: id) != nil else {
                model.saveErrorMessage = models[id]?.loadErrorMessage ?? "Не удалось открыть связанную карточку"
                resetPull()
                return
            }
            requestSwitch(id)
        }
    }

    private func finishSelection(_ id: String, width: CGFloat, height: CGFloat) {
        Task {
            guard let candidate = await loadedCardModel(for: id) else { resetPull(); return }
            incoming = candidate
            // Тап по закладке, без вытягивания: переход проигрывается целиком.
            if drag.pullingID == nil {
                drag.direction = .toward(id, parentID: family.first?.id)
                drag.originID = selectedCardID
                drag.pullingID = id
            }
            drag.settling = true
            // Доводка всегда одна и та же, скорость руки в неё не идёт —
            // решение владельца 16.09.2026 (см. `TFRowSwipe.settleAnimation`).
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.38, bounce: 0.04),
                          completionCriteria: .logicallyComplete) {
                drag.follow(width)
            } completion: {
                land(candidate, id: id)
            }
        }
    }

    /// Меняет карточки местами без видимого шва. Настоящая карточка
    /// собирается под превью, и превью снимается только через пару кадров,
    /// когда под ним уже нарисовано то же самое. Раньше подмена шла в одном
    /// кадре, и на последнем шаге перехода карточка могла мигнуть.
    private func land(_ candidate: TaskFormViewModel, id: String) {
        var instant = Transaction(animation: nil)
        instant.disablesAnimations = true
        withTransaction(instant) {
            drag.handoff = true
            model = candidate
            selectedCardID = id
        }
        drag.landTick += 1
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            withTransaction(instant) {
                incoming = nil
                drag.pullingID = nil
                drag.originID = nil
                drag.offset = 0
                drag.direction = .forward
                drag.handoff = false
                drag.settling = false
            }
            // Закладки новой карточки выезжают на место своей пружиной.
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.34, bounce: 0.06)) {
                drag.tabsShift = 0
                drag.leadingShift = 0
            }
        }
    }

    private func resetPull() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.3, bounce: 0.08),
                      completionCriteria: .logicallyComplete) {
            drag.follow(0)
            drag.settling = false
        } completion: {
            // За время возврата могли взяться снова — тогда ничего не трогаем.
            guard !drag.settling, drag.offset == 0 else { return }
            drag.pullingID = nil
            drag.originID = nil
            drag.direction = .forward
        }
    }

    private func expandedSections(for model: TaskFormViewModel) -> Set<TaskDetailSection> {
        guard let id = model.taskID else { return [] }
        return expandedSectionsByCard[id] ?? []
    }

    private func storeExpandedSections(_ sections: Set<TaskDetailSection>, for model: TaskFormViewModel) {
        guard let id = model.taskID else { return }
        expandedSectionsByCard[id] = sections
    }

    /// Закладки детей справа без той карточки, с которой начали тянуть.
    private var pullRemaining: [(offset: Int, element: ApiTask)] {
        let origin = drag.originID ?? selectedCardID
        return childTabs.filter { $0.element.id != origin }
    }

    @ViewBuilder
    private func attachedPullHandle(height: CGFloat) -> some View {
        let remaining = pullRemaining
        if let pullingID = drag.pullingID,
           let slot = remaining.firstIndex(where: { $0.element.id == pullingID }) {
            TaskFamilyTabShape(attachedEdge: .trailing)
                .frame(width: TaskFamilyEdgeTabs.expandedWidth,
                       height: TaskFamilyEdgeTabs.slotHeight(height: height, count: remaining.count))
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: -5)
                .overlay { TaskFamilyTabLabel(familyIndex: remaining[slot].offset) }
                .offset(x: -18, y: TaskFamilyEdgeTabs.slotCenterOffset(index: slot, count: remaining.count, height: height))
                .frame(maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Карточка уходит вглубь: чуть уменьшается и уходит под серую вуаль, во
/// второй половине пути — ещё и под цвет фона.
///
/// Раньше здесь был `blur` всего `List` и `opacity` на всю карточку: оба —
/// отдельный проход отрисовки вне экрана на каждом кадре. Масштаб и
/// полупрозрачная заливка поверх стоят почти ничего, а глубину дают ту же.
private struct TaskFamilyRecessed: ViewModifier {
    /// 0 — карточка на своём месте, 1 — полностью ушла вглубь.
    let amount: CGFloat
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let late = max(0, (amount - 0.55) / 0.45)
        content
            .scaleEffect(reduceMotion ? 1 : 1 - 0.045 * amount)
            .overlay {
                if amount > 0 {
                    ZStack {
                        Color.tfCard2.opacity((reduceMotion ? 0.06 : 0.16) * amount)
                        Color.tfBackground.opacity(reduceMotion ? 0 : 0.18 * late)
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

/// Текущая карточка во время перехода. К ребёнку — уходит вглубь под
/// въезжающий лист. К родителю — сама уезжает вправо с тенью у левой
/// кромки, открывая родителя под собой.
private struct TaskFamilyOutgoing: ViewModifier {
    let drag: TaskFamilyPull
    let width: CGFloat
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let progress = drag.progress(width: width)
        let back = drag.direction == .back && drag.pullingID != nil && !drag.handoff
        content
            .modifier(TaskFamilyRecessed(amount: back ? 0 : progress, reduceMotion: reduceMotion))
            .overlay(alignment: .leading) {
                if back && !reduceMotion { TaskFamilyLeadingShadow() }
            }
            .offset(x: back && !reduceMotion ? drag.offset : 0)
            .opacity(back && reduceMotion ? 1 - progress : 1)
    }
}

/// Вторая карточка перехода — единственное, что меняется на кадре жеста.
/// Ребёнок въезжает справа; родитель под уходящей карточкой возвращается
/// из глубины.
private struct TaskFamilyIncoming: ViewModifier {
    let drag: TaskFamilyPull
    let width: CGFloat
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let progress = drag.rawProgress(width: width)
        let forward = drag.direction == .forward
        content
            .modifier(TaskFamilyRecessed(amount: forward || drag.handoff ? 0 : 1 - progress, reduceMotion: reduceMotion))
            .offset(x: forward && !reduceMotion ? max(0, width - drag.offset) : 0)
            .opacity(forward && reduceMotion ? progress : 1)
    }
}

/// Тень переднего листа — две готовые градиентные полосы у левой кромки.
/// Прежние `.shadow` на всю карточку заставляли Core Animation на каждом
/// кадре вычислять тень по альфе всего содержимого — самая дорогая часть
/// жеста. Ближняя узкая полоса заменяет плотную тень, широкая — мягкую.
private struct TaskFamilyLeadingShadow: View {
    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.06), Color.black.opacity(0.2), Color.black.opacity(0.42)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 64)
            LinearGradient(colors: [.clear, Color.black.opacity(0.22)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 10)
        }
        .frame(width: 64)
        .offset(x: -64)
        .allowsHitTesting(false)
    }
}

/// Форма закладки: непрерывное скругление со стороны экрана, непрозрачная
/// заливка. Прежняя полупрозрачная заливка пропускала собственную тень, и
/// закладка выглядела грязной; теперь это фон шторки плюс тот же
/// полутон сверху — цвет прежний, тень под ним не видна.
private struct TaskFamilyTabShape: View {
    /// Сторона, которой закладка прилегает к кромке: справа у детей,
    /// слева у родителя.
    let attachedEdge: HorizontalEdge

    var body: some View {
        let radius = TaskFamilyEdgeTabs.cornerRadius
        let shape = attachedEdge == .trailing
            ? UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius, style: .continuous)
            : UnevenRoundedRectangle(bottomTrailingRadius: radius, topTrailingRadius: radius, style: .continuous)
        shape.fill(Color.tfBackground)
            .overlay(shape.fill(TaskFamilyEdgeTabs.fillColor))
    }
}

private struct TaskFamilyTabLabel: View {
    let familyIndex: Int

    var body: some View {
        Group {
            if familyIndex == 0 {
                Image(systemName: "square.stack")
            } else {
                Text("\(familyIndex)")
            }
        }
        .font(.caption)
        .foregroundStyle(Color.tfSub)
    }
}

/// Колонка закладок у кромки: справа — дети, слева — родитель. Видны
/// только узкие края; остальное — прозрачная зона касания.
struct TaskFamilyEdgeTabs: View {
    static let restingWidth: CGFloat = 10
    static let expandedWidth: CGFloat = 26
    static let cornerRadius: CGFloat = 10
    static let spacing: CGFloat = 8
    static let hitWidth: CGFloat = 32
    /// Горизонтальный путь, после которого закладку считаем захваченной.
    static let captureDistance: CGFloat = 18
    /// Окно, за которое карточка догоняет палец после захвата.
    static let catchUpDuration: CFTimeInterval = 0.16
    static let fillColor = Color.tfCard2.opacity(0.48)

    /// Карточки колонки с их номером в семье.
    let members: [(offset: Int, element: ApiTask)]
    /// Кромка колонки: `.trailing` — дети, тянуть влево; `.leading` —
    /// родитель, тянуть вправо.
    let side: HorizontalEdge
    let selectedID: String?
    let height: CGFloat
    let width: CGFloat
    let drag: TaskFamilyPull
    let prepare: (String) -> Void
    let capture: (String) -> Void
    let select: (String) -> Void
    let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: String?
    @State private var captured: String?
    @State private var catchUpUntil: CFTimeInterval = 0

    private var remaining: [(offset: Int, element: ApiTask)] {
        members.filter { $0.element.id != selectedID }
    }

    static func slotHeight(height: CGFloat, count: Int) -> CGFloat {
        min(116, max(64, height * 0.65 / CGFloat(max(1, count)) - 8))
    }

    /// Центр слота относительно центра колонки закладок.
    static func slotCenterOffset(index: Int, count: Int, height: CGFloat) -> CGFloat {
        let slot = slotHeight(height: height, count: count)
        let total = CGFloat(count) * slot + CGFloat(max(0, count - 1)) * spacing
        return CGFloat(index) * (slot + spacing) + slot / 2 - total / 2
    }

    /// Куда докатится карточка, если отпустить её на скорости `velocity`
    /// (pt/с, по ходу перехода — положительная): та же проекция, что у
    /// `UIScrollView` с обычным замедлением.
    static func projectedDistance(velocity: CGFloat) -> CGFloat {
        let rate: CGFloat = 0.998 // UIScrollView.DecelerationRate.normal
        return velocity / 1000 * rate / (1 - rate)
    }

    /// Отпустили захваченную закладку: открыть карточку или вернуть назад.
    /// `velocity` — скорость пальца по ходу перехода (pt/с): положительная —
    /// туда же, куда тянули, отрицательная — обратно.
    static func shouldCommit(pull: CGFloat, velocity: CGFloat, width: CGFloat) -> Bool {
        // Явный бросок обратно отменяет даже далёкое вытягивание.
        guard velocity > -300 else { return false }
        return pull > width * 0.28 || pull + projectedDistance(velocity: velocity) > width * 0.5
    }

    /// Направление перехода для этой колонки: дети тянутся влево, родитель —
    /// вправо. Смещение пальца, умноженное на него, — путь перехода.
    private var sign: CGFloat { side == .trailing ? -1 : 1 }

    private var slotHeight: CGFloat { Self.slotHeight(height: height, count: remaining.count) }

    var body: some View {
        VStack(spacing: Self.spacing) {
            ForEach(remaining, id: \.element.id) { index, member in
                // Не Button: жест дочерней кнопки в SwiftUI важнее жеста
                // колонки, кнопка забирала касание, и вытягивание пропадало —
                // работал только тап (владелец 02.10.2026: «нет выдвижения,
                // только нажимать»). Всё касание — тап и протяжку — ловит
                // распознаватель колонки ниже; для VoiceOver и XCUITest
                // закладка остаётся кнопкой через accessibility-трейт и
                // действие (XCUITest-тап приходит тем же касанием).
                TaskFamilyTabShape(attachedEdge: side)
                    .frame(width: Self.expandedWidth, height: slotHeight)
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 5 * sign)
                    .overlay {
                        if hovered == member.id { TaskFamilyTabLabel(familyIndex: index) }
                    }
                    // Выдвигается сдвигом, а не шириной: анимация
                    // смещения не пересчитывает раскладку на каждом кадре.
                    .offset(x: hovered == member.id ? 0 : -sign * (Self.expandedWidth - Self.restingWidth))
                    .frame(width: Self.hitWidth, alignment: side == .trailing ? .trailing : .leading)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { select(member.id) }
                .opacity(tabOpacity(member.id))
                .offset(x: drag.pullingID == member.id ? 0 : (side == .trailing ? drag.tabsShift : drag.leadingShift))
                .accessibilityLabel(side == .leading ? "Родительская карточка: \(member.title)" : member.title)
                .accessibilityIdentifier("task.family.\(member.id)")
            }
        }
        .frame(width: Self.hitWidth)
        .contentShape(Rectangle())
        .overlay(alignment: side == .trailing ? .topTrailing : .topLeading) { titleBubble }
        .gesture(TaskFamilyEdgeGesture(onChange: track, onEnd: finish))
        .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.05), value: hovered)
        .sensoryFeedback(.selection, trigger: hovered) { _, new in new != nil }
    }

    /// Закладка ребёнка, за которую взялись, приклеена к въезжающей
    /// карточке — в колонке её прячем. Закладка родителя остаётся на месте
    /// и тает в первые пункты пути: дальше на экране сам родитель.
    private func tabOpacity(_ id: String) -> Double {
        guard drag.pullingID == id else { return 1 }
        return side == .trailing ? 0 : Double(max(0, 1 - drag.offset / 48))
    }

    /// Название закладки под пальцем — как подпись скраббера в Фото:
    /// без неё по цифре не понять, какая карточка откроется.
    @ViewBuilder
    private var titleBubble: some View {
        if let hovered, captured == nil, drag.pullingID == nil,
           let slot = remaining.firstIndex(where: { $0.element.id == hovered }) {
            let anchor: UnitPoint = side == .trailing ? .trailing : .leading
            Text(remaining[slot].element.title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.tfText)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 2)
                .frame(width: width * 0.62, height: slotHeight, alignment: side == .trailing ? .trailing : .leading)
                .offset(x: sign * (Self.hitWidth + 8), y: CGFloat(slot) * (slotHeight + Self.spacing))
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: anchor)))
                .id(hovered)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func memberID(at y: CGFloat) -> String {
        let index = min(remaining.count - 1, max(0, Int(y / (slotHeight + Self.spacing))))
        return remaining[index].element.id
    }

    private func track(_ location: CGPoint, _ translation: CGSize) {
        guard !drag.settling, !remaining.isEmpty else { return }
        let distance = sign * translation.width
        if captured == nil {
            let id = memberID(at: location.y)
            if hovered != id { hovered = id; prepare(id) }
            guard distance > Self.captureDistance else { return }
            captured = id
            catchUpUntil = CACurrentMediaTime() + Self.catchUpDuration
            capture(id)
        }
        let pull = min(width, max(0, distance))
        // Захват случается, когда палец уже ушёл на 18 pt. Чтобы карточка
        // не прыгнула на это расстояние, первые доли секунды она догоняет
        // палец короткой интерактивной пружиной, потом идёт за ним вплотную.
        if !reduceMotion, CACurrentMediaTime() < catchUpUntil {
            withAnimation(.interactiveSpring(duration: Self.catchUpDuration)) { drag.follow(pull) }
        } else {
            drag.follow(pull)
        }
    }

    private func finish(_ translation: CGSize, _ velocity: CGFloat, _ cancelled: Bool) {
        let target = captured
        let tapped = hovered
        captured = nil
        hovered = nil
        guard !drag.settling else { return }
        guard let target else {
            if !cancelled, let tapped, abs(translation.width) < 6, abs(translation.height) < 6 {
                select(tapped)
            }
            return
        }
        if !cancelled, Self.shouldCommit(pull: drag.offset, velocity: sign * velocity, width: width) {
            select(target)
        } else {
            cancel()
        }
    }
}

/// Жест колонки закладок на UIKit, а не на SwiftUI `DragGesture`.
///
/// `DragGesture(minimumDistance: 0)` через `.simultaneousGesture` делил
/// касание со скроллом карточки и с жестом самой шторки: у края карточка
/// то листалась вместе с вытягиванием, то шторка начинала сворачиваться
/// (тот же класс проблемы, что описан в `HorizontalPan.swift`). Здесь
/// касание колонки целиком наше с первого кадра: удержание с нулевой
/// длительностью начинается сразу и не даёт параллельно стартовать чужим
/// панорамам. Тап по закладке тоже разбирается здесь.
private struct TaskFamilyEdgeGesture: UIGestureRecognizerRepresentable {
    /// Положение пальца в координатах колонки и смещение от точки касания.
    let onChange: (CGPoint, CGSize) -> Void
    /// Итог: смещение, скорость по X (pt/с) и признак отмены системой.
    let onEnd: (CGSize, CGFloat, Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0
        recognizer.allowableMovement = .greatestFiniteMagnitude
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let point = context.converter.location(in: .local)
        let coordinator = context.coordinator
        let now = CACurrentMediaTime()
        switch recognizer.state {
        case .began:
            coordinator.begin(at: point, time: now)
            onChange(point, .zero)
        case .changed:
            coordinator.sample(point, time: now)
            onChange(point, coordinator.translation(to: point))
        case .ended:
            coordinator.sample(point, time: now)
            onEnd(coordinator.translation(to: point), coordinator.velocityX, false)
        case .cancelled, .failed:
            onEnd(coordinator.translation(to: point), 0, true)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var start: CGPoint = .zero
        private var last: CGPoint = .zero
        private var lastTime: CFTimeInterval = 0
        /// Сглаженная скорость по X, pt/с.
        private(set) var velocityX: CGFloat = 0

        func begin(at point: CGPoint, time: CFTimeInterval) {
            start = point
            last = point
            lastTime = time
            velocityX = 0
        }

        func sample(_ point: CGPoint, time: CFTimeInterval) {
            let elapsed = time - lastTime
            guard elapsed > 0.001 else { return }
            let instant = (point.x - last.x) / elapsed
            velocityX = velocityX * 0.3 + instant * 0.7
            last = point
            lastTime = time
        }

        func translation(to point: CGPoint) -> CGSize {
            CGSize(width: point.x - start.x, height: point.y - start.y)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            false
        }

        /// Скролл карточки и панорама шторки ждут, пока колонка откажется от
        /// касания, — а она не отказывается, пока палец на ней.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer
        }
    }
}

/// Reads the actual system-sheet detent, independent of keyboard height.
private struct TaskSheetExpansionProbe: UIViewRepresentable {
    let update: (Bool) -> Void
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) { view.update = update; view.check() }
    final class ProbeView: UIView {
        var update: ((Bool) -> Void)?
        private var lastReported: Bool?
        private func report(_ expanded: Bool) {
            guard lastReported != expanded else { return }
            lastReported = expanded
            DispatchQueue.main.async { [weak self] in self?.update?(expanded) }
        }
        override func layoutSubviews() { super.layoutSubviews(); check() }
        override func didMoveToWindow() { super.didMoveToWindow(); check() }
        func check() {
            guard window != nil else { return }
            var responder: UIResponder? = self
            while let next = responder?.next {
                responder = next
                if let controller = next as? UIViewController {
                    var ancestor: UIViewController? = controller
                    while let current = ancestor {
                        if current.presentingViewController != nil,
                           let sheet = current.presentationController as? UISheetPresentationController,
                           sheet.containerView != nil {
                            let expanded = sheet.selectedDetentIdentifier == .large
                            report(expanded)
                            return
                        }
                        ancestor = current.parent
                    }
                    // A full-screen/pushed card has no partial detent.
                    report(true)
                    return
                }
            }
        }
    }
}

/// Invisible intent target prevents the text view from summoning the keyboard.
struct CardTextEditGate: ViewModifier {
    let enabled: Bool
    let identifier: String
    var text: String = ""
    let arm: () -> Void

    func body(content: Content) -> some View {
        content
            .environment(\.documentTextEditable, enabled)
            .accessibilityHidden(!enabled)
            .overlay {
                if !enabled {
                    Button(action: arm) { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(text.isEmpty ? "Показать редактирование" : text)
                        .accessibilityHint("Показать карандаш для редактирования")
                        .accessibilityIdentifier("task.arm.\(identifier)")
                }
            }
    }
}
