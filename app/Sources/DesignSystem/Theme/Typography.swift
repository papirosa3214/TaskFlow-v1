import SwiftUI

// Типографика — шкала из 10 ступеней, spec/DESIGN-TOKENS.md §2.
// Гарнитура одна системная (San Francisco = `Font.system` на native, свой шрифт не заводим).
//
// НЕ перенесено с веба сознательно:
// - фиксированный line-height title-large (32px вместо обычных 1.x) — это
//   защита от обрезки выносных букв браузерным рендерером; SwiftUI текст
//   так не обрезает, поэтому берём обычный `.lineSpacing`, не жёсткий box;
// - letter-spacing (`tracking`) перенесён как есть числом из спеки — там,
//   где на устройстве не будет заметен зазор, можно убрать (спека сама
//   оговаривает это как «эффект уже несёт SF Pro»).
//
// Правило проекта: 16px (`.tfInput`) — ТОЛЬКО для текстовых полей (защита
// от системного зума iOS при фокусе на iOS-вебе; на native зума нет, но
// ступень держим зарезервированной, чтобы визуальный язык не расходился
// с вебом и будущими экранами).
//
// ─────────────────────────────────────────────────────────────────────────
// 14.09.2026, Dynamic Type (a11y-аудит).
//
// БЫЛО: все ступени — статические `Font.system(size:)`. Такой шрифт НЕ
// масштабируется под системный размер текста, а Apple в документации
// `Font.system(size:weight:design:)` никаких гарантий масштабирования и не
// даёт. Итог: пользователь, выкрутивший «Крупный текст», видел ровно тот же
// кегль, что и все остальные — при том что это требование WCAG 1.4.4
// (Resize Text) и одна из строк диагностики HIG.
//
// СТАЛО: каждая ступень объявлена через `@ScaledMetric(relativeTo:)` со
// СВОИМ базовым кеглем и своей системной кривой. На дефолтном размере
// текста `@ScaledMetric` возвращает ровно базовое значение — поэтому
// визуальный язык и вся вёрстка остаются БУКВАЛЬНО прежними, а масштаб
// появляется только когда пользователь его просит.
//
// Почему не семантические `.body`/`.headline`: они дают другие кегли
// (`.body` = 17 против наших 15), то есть поехал бы весь дизайн. `relativeTo:`
// берёт у системного стиля только КРИВУЮ масштабирования, а размер оставляет
// наш — это и нужно.
//
// Одна модификация закрывает 342 вызова `.tfText(...)` в 61 файле: сигнатура
// не изменилась, места вызова трогать не пришлось.
// ─────────────────────────────────────────────────────────────────────────

public enum TFFont {
    /// Заголовок корневого экрана (`ScreenHeader variant="large"`).
    public static let titleLarge = Font.system(size: 28, weight: .bold)
    public static let titleLargeTracking: CGFloat = -0.84

    /// Заголовок карточки задачи.
    public static let taskTitle = Font.system(size: 20, weight: .semibold)
    public static let taskTitleTracking: CGFloat = -0.40

    /// Заголовок вторичного экрана/шторки (`variant="compact"`), «Готово» в навбаре.
    public static let title = Font.system(size: 17, weight: .semibold)
    public static let titleTracking: CGFloat = -0.20

    /// ТОЛЬКО текстовые поля — см. предупреждение выше.
    public static let input = Font.system(size: 16, weight: .regular)
    public static let inputTracking: CGFloat = -0.10

    /// Основной текст, название задачи в строке, редактор Дневника.
    public static let body = Font.system(size: 15, weight: .regular)
    public static let bodyTracking: CGFloat = -0.03

    /// Строка списка, пункт меню.
    public static let row = Font.system(size: 14, weight: .regular)

    /// Вторичное действие, подпись под строкой, описание задачи.
    public static let action = Font.system(size: 13, weight: .regular)
    public static let actionTracking: CGFloat = 0.10

    /// Мета-данные, статусы, счётчики, подпись пункта меню создания.
    public static let meta = Font.system(size: 12, weight: .medium)
    public static let metaTracking: CGFloat = 0.14

    /// Мелкая подпись, бейджи/пилюли строки задачи.
    public static let caption = Font.system(size: 11, weight: .medium)
    public static let captionTracking: CGFloat = 0.20

    /// Совсем мелкое: буквы недели, деления графика, счётчик на таббаре.
    public static let micro = Font.system(size: 10, weight: .medium)
    public static let microTracking: CGFloat = 0.25
}

/// Готовые модификаторы «размер + трекинг одним вызовом» — большинство мест
/// в UI используют пару размер/трекинг вместе, дублировать их на каждом Text не нужно.
///
/// ⚠️ Статический шрифт: НЕ масштабируется под Dynamic Type. Для нового кода
/// предпочитайте `.tfText(...)` (масштабируемый) или объявите свой
/// `@ScaledMetric`. Оставлено для склейки `Text` через `+`, где нужен именно
/// `Font`, а не `View`.
public extension Text {
    func tfStyle(_ font: Font, tracking: CGFloat = 0) -> Text {
        self.font(font).tracking(tracking)
    }
}

public enum TFTextStyle {
    case titleLarge, taskTitle, title, input, body, row, action, meta, caption, micro

    /// Базовый кегль ступени — то, что видно на дефолтном размере текста.
    var baseSize: CGFloat {
        switch self {
        case .titleLarge: 28
        case .taskTitle: 20
        case .title: 17
        case .input: 16
        case .body: 15
        case .row: 14
        case .action: 13
        case .meta: 12
        case .caption: 11
        case .micro: 10
        }
    }

    /// Системный стиль, чью КРИВУЮ масштабирования берём. Размер остаётся
    /// наш (`baseSize`) — от системного стиля нужен только характер роста.
    var relativeTo: Font.TextStyle {
        switch self {
        case .titleLarge: .title       // 28
        case .taskTitle: .title3       // 20
        case .title: .headline         // 17
        case .input: .callout          // 16
        case .body: .subheadline       // 15
        case .row: .footnote           // 13 → 14 близко
        case .action: .footnote        // 13
        case .meta: .caption           // 12
        case .caption: .caption2       // 11
        case .micro: .caption2         // 11 → 10 близко
        }
    }

    var weight: Font.Weight {
        switch self {
        case .titleLarge: .bold
        case .taskTitle: .semibold
        case .title: .semibold
        case .input: .regular
        case .body: .regular
        case .row: .regular
        case .action: .regular
        case .meta: .medium
        case .caption: .medium
        case .micro: .medium
        }
    }

    var tracking: CGFloat {
        switch self {
        case .titleLarge: TFFont.titleLargeTracking
        case .taskTitle: TFFont.taskTitleTracking
        case .title: TFFont.titleTracking
        case .input: TFFont.inputTracking
        case .body: TFFont.bodyTracking
        case .row: 0
        case .action: TFFont.actionTracking
        case .meta: TFFont.metaTracking
        case .caption: TFFont.captionTracking
        case .micro: TFFont.microTracking
        }
    }
}

/// Применяет ступень шкалы с масштабированием под Dynamic Type.
///
/// Каждая ступень — отдельный `@ScaledMetric` со своим `relativeTo`. Держать
/// их все в одном модификаторе нужно потому, что `relativeTo:` задаётся
/// статически при объявлении свойства и не может выбираться по `style`
/// в рантайме. Свойство, которое не соответствует текущей ступени, просто
/// не читается — стоимость нулевая.
private struct TFTextStyleModifier: ViewModifier {
    let style: TFTextStyle

    @ScaledMetric(relativeTo: .title)      private var titleLargeSize: CGFloat = 28
    @ScaledMetric(relativeTo: .title3)     private var taskTitleSize: CGFloat = 20
    @ScaledMetric(relativeTo: .headline)   private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .callout)    private var inputSize: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var bodySize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote)   private var rowSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote)   private var actionSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption)    private var metaSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2)   private var captionSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption2)   private var microSize: CGFloat = 10

    private var scaledSize: CGFloat {
        switch style {
        case .titleLarge: titleLargeSize
        case .taskTitle: taskTitleSize
        case .title: titleSize
        case .input: inputSize
        case .body: bodySize
        case .row: rowSize
        case .action: actionSize
        case .meta: metaSize
        case .caption: captionSize
        case .micro: microSize
        }
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: scaledSize, weight: style.weight))
            .tracking(style.tracking)
    }
}

public extension View {
    /// Применяет ступень шкалы (шрифт + трекинг) целиком. Цвет текста задаётся отдельно —
    /// шкала про размер/начертание, а не про то, где текст первичный/вторичный.
    ///
    /// Кегль масштабируется под Dynamic Type: на дефолтном размере текста
    /// значение равно базовому (`TFTextStyle.baseSize`), при увеличенном —
    /// растёт по системной кривой.
    func tfText(_ style: TFTextStyle) -> some View {
        modifier(TFTextStyleModifier(style: style))
    }

    /// Моноширинный кегль с масштабированием под Dynamic Type.
    ///
    /// `.tfText` здесь не годится: он ставит `design: .default`, а моноширинный
    /// нужен там, где цифры обязаны не «плясать» по ширине (время в таймлайне,
    /// кодовые метки). API принимает базовый кегль и системный стиль, чью кривую
    /// масштабирования взять — `ScaledMetric(wrappedValue:relativeTo:)` даёт
    /// задать `relativeTo` в рантайме, чего `@ScaledMetric` в объявлении не умеет.
    ///
    /// `active: false` не навязывает шрифт вовсе (`.font(nil)`), поэтому
    /// модификатор можно ставить В КОНЕЦ цепочки поверх `.tfText(...)` и
    /// включать моноширинный только по условию — иначе более поздний `.font`
    /// затрёт `.tfText` (ровно этот баг и был в `AgentRow`: `.font(monospaced
    /// ? … : nil)` стоял ДО `.tfText(.body)`, и флаг не работал никогда).
    func tfMonospaced(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo: Font.TextStyle = .body,
        active: Bool = true
    ) -> some View {
        modifier(TFMonospacedModifier(size: size, weight: weight, relativeTo: relativeTo, active: active))
    }
}

private struct TFMonospacedModifier: ViewModifier {
    @ScaledMetric private var scaled: CGFloat
    private let weight: Font.Weight
    private let active: Bool

    init(size: CGFloat, weight: Font.Weight, relativeTo: Font.TextStyle, active: Bool) {
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
        self.weight = weight
        self.active = active
    }

    func body(content: Content) -> some View {
        content.font(active ? .system(size: scaled, weight: weight, design: .monospaced) : nil)
    }
}
