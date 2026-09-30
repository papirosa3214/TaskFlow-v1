import SwiftUI

// Кнопки — spec/DESIGN-TOKENS.md §4 «Кнопки». Три вида, все 48px/12px радиус/15px 600.
// Нажатие — не тень/подъём, а `tap-scale` (0.94, мгновенно, без анимации на снятие);
// на native ближайший честный эквивалент — `.scaleEffect` без implicit animation delay.
public enum TFButtonVariant {
    case primary   // red-solid фон (НЕ tfRed — контраст под белый текст, см. Color+Palette)
    case secondary // card2 фон + рамка stroke
    case outline   // прозрачный фон + рамка stroke, текст sub

    var background: Color {
        switch self {
        case .primary: .tfRedSolid
        case .secondary: .tfCard2
        case .outline: .clear
        }
    }

    var foreground: Color {
        switch self {
        case .primary: .white
        case .secondary: .tfText
        case .outline: .tfSub
        }
    }

    var hasStroke: Bool {
        switch self {
        case .primary: false
        case .secondary, .outline: true
        }
    }
}

/// Полноширинная кнопка (`Button`, UI.tsx). Иконка опциональна — используется,
/// например, в «Завершить задачу» (check 16px) / «Открыть заново» (sync).
public struct TFButton: View {
    let title: String
    let icon: String?
    let variant: TFButtonVariant
    let isEnabled: Bool
    let action: () -> Void

    @State private var isPressed = false

    /// 14.09.2026, Dynamic Type: высота растёт вместе с текстом.
    /// Было жёсткое `.frame(height: 48)` — при увеличенном системном размере
    /// подпись кнопки обрезалась. Берём `minHeight`, а не `height`: базовый
    /// ритм 48 сохраняется на дефолтном размере, но при крупном тексте
    /// кнопка вырастает, а не режет содержимое.
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = TFButtonMetrics.height

    public init(
        _ title: String,
        icon: String? = nil,
        variant: TFButtonVariant = .primary,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.variant = variant
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: TFSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .tfText(.body)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .foregroundStyle(variant.foreground)
            .background(variant.background)
            .overlay {
                if variant.hasStroke {
                    RoundedRectangle(cornerRadius: TFButtonMetrics.radius)
                        .strokeBorder(Color.tfStroke, lineWidth: TFBorder.width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: TFButtonMetrics.radius))
        }
        .buttonStyle(TFTapScaleStyle())
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled)
    }
}

/// Кнопка-иконка (`background: transparent`, зона 44×44, иконка 18px) — шапка экрана,
/// действия в бейджах/строках. Отклик `tap-scale`.
///
/// 14.09.2026, a11y-аудит: `label` — ОБЯЗАТЕЛЬНЫЙ параметр, а не опция.
/// Кнопка без текста внутри нечего читать VoiceOver'у и нечем озвучить
/// Voice Control'у; раньше подпись нужно было вешать снаружи через
/// `.accessibilityLabel(...)`, и все три места вызова её просто забыли.
/// Теперь компилятор не даст создать безымянную иконочную кнопку.
public struct TFIconButton: View {
    let icon: String
    let label: String
    let size: CGFloat
    let action: () -> Void

    public init(_ icon: String, label: String, size: CGFloat = TFIconSize.sm, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(Color.tfText)
                .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(TFTapScaleStyle())
        .accessibilityLabel(label)
    }
}

/// `tap-scale`: scale(0.94) мгновенно на нажатие, без анимации на отпускание —
/// снимается «щелчком», не плавным возвратом (спека §4 «Кнопки»).
public struct TFTapScaleStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

/// `tap-row`: подсветка фона строки списка/карточки при нажатии.
public struct TFTapRowStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.04) : .clear)
    }
}

/// `tap-fade`: полноширинные CTA/текстовые ссылки — просадка непрозрачности, не масштаба.
public struct TFTapFadeStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

#Preview("Кнопки") {
    VStack(spacing: TFSpacing.md) {
        TFButton("Завершить задачу", icon: "checkmark", variant: .primary) {}
        TFButton("Открыть задачу заново", icon: "arrow.triangle.2.circlepath", variant: .secondary) {}
        TFButton("Отмена", variant: .outline) {}
        TFButton("Недоступно", variant: .primary, isEnabled: false) {}
        HStack {
            TFIconButton("line.3.horizontal.decrease", label: "Фильтры") {}
            TFIconButton("ellipsis", label: "Ещё") {}
        }
    }
    .padding()
    .background(Color.tfBackground)
}
