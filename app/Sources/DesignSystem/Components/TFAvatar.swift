import SwiftUI

// Аватар (`Avatar`, UI.tsx) — spec/DESIGN-TOKENS.md §4.
// Два принципиально разных вида в зависимости от наличия фото:
// - фото — радиус 8px (`rounded-lg`), НЕ круг, `object-fit: contain`
//   (вписывается целиком, не обрезает) — осознанное решение 18.08.2026,
//   круглая обрезка давала «кругляш» на фото с прозрачным фоном;
// - инициалы-заглушка — круг, фон = цвет пользователя или `#A6A6A6`,
//   шрифт `size × 0.43`, вес 600, белый текст.
public struct TFAvatar: View {
    public enum Size: CGFloat {
        case xs = 18   // строка карточки доски
        case sm = 20   // строка задачи в списке
        case md = 30
        case lg = 32   // размер по умолчанию
        /// Строка списка чатов (`RoleChatsScreen`) — 21.09.2026, LOCK-195:
        /// там аватар ведущий элемент строки, а не спутник текста.
        case xl = 44
        /// Списки задач: роль читается отдельной колонкой рядом с тремя
        /// строками содержания, а не теряется в одной строке заголовка.
        case taskList = 60
    }

    let size: Size
    /// nil — показываем инициалы-заглушку.
    let image: Image?
    /// Stable account ID for bundled agent artwork (e.g. `role_qa`, `u-secretary`).
    let userID: String?
    let initials: String
    let tint: Color
    /// Подпись для VoiceOver. `nil` — собирается из инициалов.
    ///
    /// 14.09.2026, a11y-аудит: раньше метки не было ВООБЩЕ, и VoiceOver читал
    /// инициалы как россыпь отдельных букв («М», «К») без указания, что это
    /// исполнитель. В строках задач имя больше нигде не выводится — аватар
    /// единственный носитель этой информации, поэтому молчать он не имеет права.
    /// Вызывающий может передать своё (например, настоящее имя, если оно есть).
    let accessibilityLabel: String?

    /// 14.09.2026, Dynamic Type: кружок растёт вместе с текстом строки.
    ///
    /// HIG прямо просит этого — «Increase the size of meaningful interface
    /// icons as font size increases»: аватар здесь не украшение, он несёт
    /// информацию об исполнителе (имя в строке задачи больше нигде не выведено).
    /// Кривая взята от `subheadline` — той же ступени, что у основного текста
    /// строки, поэтому аватар и подпись растут синхронно.
    ///
    /// На дефолтном размере коэффициент равен 1.0, то есть круг остаётся ровно
    /// 18/20/30/32 — визуально не меняется НИЧЕГО. Дальше растёт по системной
    /// кривой и упирается в общий потолок приложения (`xxxLarge` в
    /// `TaskFlowApp`), где даёт 1.40×.
    ///
    /// База именно 100, а не 1: `UIFontMetrics.scaledValue(for:)` округляет
    /// результат, и на базе «1» рост схлопнулся бы обратно в 1.0. Проценты
    /// от округления не страдают.
    @ScaledMetric(relativeTo: .subheadline) private var scalePercent: CGFloat = 100

    private var growth: CGFloat { scalePercent / 100 }
    /// Сторона квадрата/диаметр круга — база ступени, умноженная на рост.
    private var side: CGFloat { (size.rawValue * growth).rounded() }
    /// Радиус фото-варианта держим пропорцией к стороне (в спеке 8pt на 32pt),
    /// иначе на выросшем аватаре скругление выглядит слишком мелким.
    private var cornerRadius: CGFloat { (TFRadius.md * growth).rounded() }
    private var resolvedAccessibilityLabel: String {
        if let accessibilityLabel { return accessibilityLabel }
        return initials.isEmpty ? "Аватар" : "Аватар: \(initials)"
    }

    public init(
        size: Size = .lg,
        image: Image? = nil,
        initials: String,
        tint: Color = Color(hex: TFHexDefault.unassigned),
        accessibilityLabel: String? = nil,
        userID: String? = nil
    ) {
        self.size = size
        self.image = image
        self.userID = userID
        self.initials = initials
        self.tint = tint
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        Group {
            if let asset = RoleAvatarAsset.imageName(forUserID: userID) {
                Image(asset)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(Circle())
            } else if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit) // object-fit: contain
                    .frame(width: side, height: side)
                    .background(Color.tfCard2)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: side, height: side)
                    .overlay {
                        // Пропорция 0.43 от спек — считается от РАСТУЩЕЙ стороны,
                        // поэтому инициалы увеличиваются вместе с кружком.
                        Text(initials)
                            .font(.system(size: side * 0.43, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        // Один элемент, а не круг + буквы по отдельности: `children: .ignore`
        // глушит внутренние тексты, дальше читается только наша метка.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resolvedAccessibilityLabel)
    }
}

#Preview("Аватары") {
    HStack(alignment: .center, spacing: TFSpacing.md) {
        TFAvatar(size: .xs, initials: "МК", tint: .tfBlue)
        TFAvatar(size: .sm, initials: "МК", tint: .tfPurple)
        TFAvatar(size: .md, initials: "МК", tint: .tfTeal)
        TFAvatar(size: .lg, initials: "МК")
    }
    .padding()
    .background(Color.tfBackground)
}
