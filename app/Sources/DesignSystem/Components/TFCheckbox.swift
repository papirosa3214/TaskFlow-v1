import SwiftUI

// Спека DESIGN-TOKENS.md не даёт размеров «чекбокса» напрямую — в строке
// задачи он убран целиком (18.08.2026, §4 «Строка задачи»), а раздел
// «Изменить» подзадачи тоже без кружка-переключателя (владелец 15.08.2026,
// см. SubtaskRow в TaskFields.tsx — там подзадачи только переименовывают/
// удаляют). Числа ниже сняты с живого места, где кружок РЕАЛЬНО есть и
// переключается — `SubtaskFeed.tsx` (чек-лист подзадач на экране задачи,
// компонент `StateMark`/`DashedRing`), плюс комментарий в спеке §5
// «Индикатор «в работе» у подзадачи» с точными длительностями/масштабом.
//
// Кружок общий для ВСЕХ состояний — 21×21, не «прыгает» между ними.

/// Простой булев чекбокс — заполненный зелёный круг с галочкой (состояние
/// «готово»), не заполненный — контурное кольцо `dim`. Годится для мест, где
/// нужно именно да/нет, а не полный набор статусов подзадачи.
///
/// Два режима, и семантика у них разная:
/// - `action != nil` — интерактивный контрол, `label` обязателен по смыслу
///   (VoiceOver читает именно его);
/// - `action == nil` — чистый ИНДИКАТОР внутри строки/абзаца: смысл несёт
///   контейнер, поэтому от VoiceOver он скрыт, чтобы не плодить лишние
///   остановки чтения.
public struct TFCheckbox: View {
    let isChecked: Bool
    /// Подпись для VoiceOver. Для интерактивного режима — что именно
    /// переключает этот чекбокс.
    let label: String?
    let action: (() -> Void)?

    public init(isChecked: Bool, label: String? = nil, action: (() -> Void)? = nil) {
        self.isChecked = isChecked
        self.label = label
        self.action = action
    }

    public var body: some View {
        let mark = ZStack {
            Circle()
                .fill(isChecked ? Color.tfGreen : Color.clear)
                .overlay {
                    if !isChecked {
                        Circle().strokeBorder(Color.tfDim, lineWidth: 2)
                    }
                }
            if isChecked {
                // 12 из 21 — та же пропорция, что у StateMark в вебе (галочка мельче поля).
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 21, height: 21)

        if let action {
            Button(action: action) { mark }
                .buttonStyle(TFTapScaleStyle())
                .frame(minWidth: TFHitTarget.min, minHeight: TFHitTarget.min)
                .contentShape(Rectangle())
                .accessibilityLabel(label ?? "Отметить")
                // `isSelected` — чтобы VoiceOver читал не только «кнопка», но и
                // текущее состояние отметки.
                .accessibilityAddTraits(isChecked ? .isSelected : [])
        } else {
            mark.accessibilityHidden(true)
        }
    }
}

/// Полный статус подзадачи (`StateMark`/`DashedRing`, SubtaskFeed.tsx) — пять
/// состояний, кольцо только у «готово». Числа буквально из спеки §5:
/// цвет-волна дуги 0.8s (5 из 8 сегментов зажжено разом, 62.5% цикла),
/// пульсация 1.6s `scale(0.8571↔1.0952)` (18↔23px на базе 21px),
/// вращение обёртки 1.6s **linear** против часовой — три независимых слоя,
/// не рассинхрон. Сегменты неподвижны сами по себе, «дорисовывается» именно
/// цвет по кругу — вращается только обёртка целиком.
public enum TFSubtaskState {
    case done, running, pending, blocked, review

    /// Человекочитаемое имя состояния — подпись для VoiceOver.
    ///
    /// Пять состояний различаются ТОЛЬКО формой и цветом (кольцо/точки/
    /// треугольник/глаз + teal/orange/blue). Без этой подписи кольцо для
    /// VoiceOver немо, а «смысл только цветом» — прямое нарушение HIG.
    public var label: String {
        switch self {
        case .done: "Готово"
        case .running: "Выполняется"
        case .pending: "Ожидает"
        case .blocked: "Заблокировано"
        case .review: "На проверке"
        }
    }
}

public struct TFSubtaskStatusRing: View {
    let state: TFSubtaskState

    public init(_ state: TFSubtaskState) {
        self.state = state
    }

    public var body: some View {
        ZStack {
            switch state {
            case .done:
                Circle()
                    .fill(Color.tfGreen)
                    .overlay(Circle().strokeBorder(Color.tfGreen, lineWidth: 2))
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
            case .running:
                // Была `DashedRing(active: true)` (пунктирное кольцо, волна
                // цвета по кругу) — просьба владельца 03.09.2026: назвал
                // конкретную иконку из `icones` (`svg-spinners--12-dots-
                // scale-rotate`) для замены. SwiftUI не рендерит SVG сама
                // (в проекте нет декодера) — тот же рисунок 12 точек по
                // кругу, каждая гаснет/уменьшается по мере отставания от
                // «головы» волны, пересобран нативными фигурами.
                DotsScaleRotate()
            case .pending:
                DashedRing(active: false)
            case .blocked:
                // text-orange — тот же цвет, что «заблокировано» в статусе задачи наверху (не coral: тот = «агент пропал»).
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 21))
                    .foregroundStyle(Color.tfOrange)
            case .review:
                // text-blue — тот же цвет, что «на проверке» в статусе задачи наверху.
                Image(systemName: "eye")
                    .font(.system(size: 21))
                    .foregroundStyle(Color.tfBlue)
            }
        }
        .frame(width: 21, height: 21)
        // Кольцо передаёт состояние формой и цветом — единственный способ
        // сделать это доступным для VoiceOver.
        .accessibilityLabel(state.label)
    }
}

/// Пунктирное кольцо из 8 сегментов, реализация `DashedRing` под `trim(from:to:)`
/// (спека §5 прямо называет это native-эквивалентом `stroke-dashoffset`).
/// Точные углы сегментов веба (atan2 от центра, шаг 45°) на native не нужны —
/// `Circle().trim` кладёт сегменты равномерно сама; воспроизводим ЧИСЛА
/// (длительности, доля дуги, направления вращения), не пиксельные пути SVG.
///
/// Три слоя считаются от времени через `TimelineView(.animation)`, а не через
/// `withAnimation` на дискретном `@State`: SwiftUI анимирует только animatable-
/// модификаторы через интерполяцию, а чтение состояния в теле `body` (чтобы
/// решить, какой сегмент зажечь) в момент вызова `withAnimation` сразу видит
/// целевое значение — «змейка» дискретных withAnimation-шагов на деле стояла
/// на месте. От времени кадра — честно непрерывно.
private struct DashedRing: View {
    let active: Bool

    private let segmentCount = 8
    private let litFraction = 5.0 / 8.0 // 5 из 8 сегментов зажжены разом
    private let rotationPeriod: Double = 1.6   // dash-spin, linear
    private let pulsePeriod: Double = 1.6      // dash-pulse, ease-in-out туда-обратно
    private let glowPeriod: Double = 0.8       // dash-glow, «змейка» по кругу

    var body: some View {
        if active {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ring(rotationDeg: rotation(t), scale: pulse(t), glowPhase: glow(t))
            }
        } else {
            ring(rotationDeg: 0, scale: 1, glowPhase: nil)
        }
    }

    private func ring(rotationDeg: Double, scale: CGFloat, glowPhase: Double?) -> some View {
        ZStack {
            ForEach(0..<segmentCount, id: \.self) { i in
                segment(index: i, glowPhase: glowPhase)
            }
        }
        .frame(width: 21, height: 21)
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotationDeg))
    }

    private func segment(index: Int, glowPhase: Double?) -> some View {
        let start = Double(index) / Double(segmentCount)
        let span = 0.35 / Double(segmentCount) // короткая дуга, промежутки между сегментами (14° приём из веба)
        let lit = glowPhase.map { litSegment(index, glowPhase: $0) } ?? false
        return Circle()
            .trim(from: start, to: start + span)
            .stroke(
                lit ? Color.tfText.opacity(0.9) : Color.tfDim,
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
    }

    private func litSegment(_ index: Int, glowPhase: Double) -> Bool {
        // Волна «змейкой» по кругу: окно из 5 соседних сегментов, сдвигается фазой 0..1.
        let offset = Int(glowPhase * Double(segmentCount)) % segmentCount
        let rel = (index - offset + segmentCount) % segmentCount
        return Double(rel) < Double(segmentCount) * litFraction
    }

    /// Вращение обёртки — 1.6s linear, против часовой (отрицательный угол).
    private func rotation(_ t: TimeInterval) -> Double {
        let phase = (t.truncatingRemainder(dividingBy: rotationPeriod)) / rotationPeriod
        return -360 * phase
    }

    /// Пульсация — 1.6s ease-in-out туда-обратно, scale(0.8571↔1.0952) = 18↔23px на базе 21px.
    private func pulse(_ t: TimeInterval) -> CGFloat {
        let half = pulsePeriod / 2
        let phase = (t.truncatingRemainder(dividingBy: pulsePeriod)) / half // 0..2
        let triangle = phase <= 1 ? phase : 2 - phase // 0→1→0, треугольная волна
        let eased = triangle * triangle * (3 - 2 * triangle) // smoothstep ≈ ease-in-out
        let minScale: CGFloat = 18.0 / 21.0  // 0.8571
        let maxScale: CGFloat = 23.0 / 21.0  // 1.0952
        return minScale + (maxScale - minScale) * CGFloat(eased)
    }

    /// Цвет-волна — 0.8s, фаза 0..1 по кругу.
    private func glow(_ t: TimeInterval) -> Double {
        (t.truncatingRemainder(dividingBy: glowPeriod)) / glowPeriod
    }
}

/// 12 точек по кругу, «голова» волны полная и яркая, хвост гаснет и
/// уменьшается — та же идея, что у `icones`/Iconify `svg-spinners--12-dots-
/// scale-rotate` (просьба владельца 03.09.2026, точный SVG не тянем — в
/// проекте нет SVG-рендерера, пересобрано нативными фигурами на том же
/// `TimelineView(.animation)`, что и `DashedRing`, тот же приём — читаем
/// время кадра, не дискретный `@State`).
private struct DotsScaleRotate: View {
    private let dotCount = 12
    private let period: Double = 1.2 // один оборот волны

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let progress = (t.truncatingRemainder(dividingBy: period)) / period

            ZStack {
                ForEach(0..<dotCount, id: \.self) { i in
                    dot(index: i, progress: progress)
                }
            }
            .frame(width: 21, height: 21)
        }
    }

    private func dot(index: Int, progress: Double) -> some View {
        let angle = Angle.degrees(Double(index) / Double(dotCount) * 360)
        // Фаза этой точки относительно «головы» волны — 0 у головы (ярко),
        // 1 у хвоста (тускло/мелко), волна бежит по кругу против часовой.
        var phase = progress - Double(index) / Double(dotCount)
        phase = phase.truncatingRemainder(dividingBy: 1)
        if phase < 0 { phase += 1 }
        let intensity = 1 - phase

        return Circle()
            .fill(Color.tfText)
            .frame(width: 3.4, height: 3.4)
            .scaleEffect(0.35 + 0.65 * intensity)
            .opacity(0.2 + 0.8 * intensity)
            .offset(y: -9)
            .rotationEffect(angle)
    }
}

#Preview("Чекбоксы") {
    VStack(alignment: .leading, spacing: TFSpacing.lg) {
        HStack(spacing: TFSpacing.md) {
            TFCheckbox(isChecked: false)
            TFCheckbox(isChecked: true)
        }
        HStack(spacing: TFSpacing.lg) {
            TFSubtaskStatusRing(.done)
            TFSubtaskStatusRing(.running)
            TFSubtaskStatusRing(.pending)
            TFSubtaskStatusRing(.blocked)
            TFSubtaskStatusRing(.review)
        }
    }
    .padding()
    .background(Color.tfBackground)
}
