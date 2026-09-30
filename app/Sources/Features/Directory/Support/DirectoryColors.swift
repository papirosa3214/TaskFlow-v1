import SwiftUI

// Палитры цвета проекта/метки — сняты ДОСЛОВНО с `src/lib/projectColors.ts`
// (`PROJECT_COLORS`) и `src/screens/LabelsScreen.tsx` (`LABEL_COLORS`), не
// подобраны из акцентов DesignSystem: набор пересекается с `tf*`-токенами в
// 6 из 7 значений, но `#8FBF9F` там отсутствует, и порядок/дефолт (первый
// элемент — цвет по умолчанию для новой сущности) у двух палитр разный —
// веб-комментарий прямо говорит, что это осознанное расхождение, не
// случайный дубль для сведения.
enum DirectoryColors {
    /// Дефолт — `#4A9FD8` (первый элемент), как у нового проекта в вебе.
    static let project: [String] = [
        "#4A9FD8", "#A78BFA", "#E44332", "#FF9A14", "#FF7A8A", "#8FBF9F", "#35B8A3",
    ]

    /// Дефолт — `#FF7A8A` (первый элемент), как у новой метки в вебе.
    static let label: [String] = [
        "#FF7A8A", "#4A9FD8", "#A78BFA", "#E44332", "#FF9A14", "#8FBF9F", "#35B8A3",
    ]
}

/// Ряд цветовых кружков-свотчей — `ColorSwatches` (ProjectsScreen.tsx /
/// LabelsScreen.tsx): выбранный обведён белым кольцом 2px с отступом 2px.
/// Размер разный по месту в вебе (24px у проектов, 26px у меток) — не унифицирую,
/// параметр `size` передаётся вызывающим экраном 1:1 со значением в его файле.
struct DirectoryColorSwatches: View {
    let colors: [String]
    @Binding var selected: String
    var size: CGFloat = 24
    /// Просьба владельца 03.09.2026 (метки): «RGB-шкала, а не только
    /// выделенные цвета — чтобы сам выбирал вплоть до оттенков». Фиксный
    /// набор — 1:1 веб (см. комментарий у `DirectoryColors`), трогать его
    /// не стал; добавил ЕЩЁ один кружок сверх — нативный `ColorPicker`
    /// (спектр/RGB-ползунки/hex, всё системное, без своего UI). По умолчанию
    /// выключено — не меняет `ProjectsScreen`, который этого не просил.
    var allowsCustomColor: Bool = false

    var body: some View {
        HStack(spacing: TFSpacing.sm) {
            ForEach(colors, id: \.self) { hex in
                Button {
                    selected = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: size, height: size)
                        .overlay {
                            if selected.lowercased() == hex.lowercased() {
                                Circle().strokeBorder(Color.white, lineWidth: 2)
                                    .padding(-2) // outline-offset: 2px в вебе — кольцо СНАРУЖИ кружка, не по его краю
                            }
                        }
                }
                .buttonStyle(TFTapScaleStyle())
            }
            if allowsCustomColor {
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { Color(hex: selected) },
                        set: { selected = $0.toHex() }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: size, height: size)
            }
        }
    }
}
