import SwiftUI

enum VoiceBarsMotion {
    static func shouldPauseTimeline(reduceMotion: Bool, isSmooth: Bool) -> Bool {
        reduceMotion && !isSmooth
    }

    static func smoothBarCount(width: Double, barWidth: Double, spacing: Double) -> Int {
        guard width > 0, barWidth > 0, spacing >= 0 else { return 0 }
        return max(1, Int((width + spacing) / (barWidth + spacing)))
    }

    static func smoothHeight(
        level: Double,
        bar: Int,
        count: Int,
        time: Double,
        sensitivity: Double = 1,
        barWidth: Double = 3,
        maxHeight: Double = 28
    ) -> Double {
        let normalizedLevel = min(max(level, 0), 1)
        let position = Double(bar) / Double(max(count - 1, 1))
        let phase = position * 6 * .pi - time * 1.4
        let syllable = 0.18 + 0.82 * pow(max(0, sin(phase)), 1.15)
        let texture = 0.76 + 0.14 * sin(Double(bar) * 1.7 + time * 0.6)
            + 0.10 * sin(Double(bar) * 0.61 - time * 0.32)
        let signal = min(1, 0.11 + normalizedLevel * 0.89 * max(0, sensitivity))
        let height = maxHeight * signal * syllable * texture
        return min(maxHeight, max(barWidth, height))
    }

    static func amplitudeFactor(bar: Int, time: Double, smooth: Bool) -> Double {
        guard smooth else {
            return 0.72 + 0.28 * (sin(time * 7 + Double(bar) * 1.7) + 1) / 2
        }
        return 0.94 + 0.06 * (sin(time * 2.8 + Double(bar) * 0.8) + 1) / 2
    }
}

/// Пять вертикальных полосок-капсул, которые «дышат» громкостью голоса
/// (владелец 26.09.2026, вариант B). Один компонент на голосовой разговор с
/// Секретарём и на запись голосового в чате — чтобы вели себя одинаково.
/// `level` — 0…1 (тот же масштаб, что `VoiceWaveform.microphoneLevel`);
/// `isWaiting` — тихое «подключаюсь»: полоски короткие, бегущая волна.
struct VoiceBarsView: View {
    var level: Double
    var color: Color
    /// Владелец 26.09.2026: полоска в покое — `color` (тёмный тон), на пике
    /// амплитуды (чем выше сама полоска сейчас) — подмешивается этот цвет
    /// (яркий тон). `nil` — прежнее поведение, сплошной `color` без подмеса.
    var peakColor: Color? = nil
    var isWaiting = false
    var barWidth: CGFloat = 16
    var spacing: CGFloat = 10
    var maxHeight: CGFloat = 140
    var isSmooth = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Средняя выше крайних — силуэт голоса, а не ровная гребёнка.
    private static let weights: [Double] = [0.5, 0.78, 1, 0.78, 0.5]

    var body: some View {
        TimelineView(.animation(paused: VoiceBarsMotion.shouldPauseTimeline(
            reduceMotion: reduceMotion,
            isSmooth: isSmooth
        ))) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            if isSmooth {
                GeometryReader { geometry in
                    let count = VoiceBarsMotion.smoothBarCount(
                        width: Double(geometry.size.width),
                        barWidth: Double(barWidth),
                        spacing: Double(spacing)
                    )
                    HStack(spacing: spacing) {
                        ForEach(0..<count, id: \.self) { i in
                            let h = VoiceBarsMotion.smoothHeight(
                                level: level,
                                bar: i,
                                count: count,
                                time: t,
                                sensitivity: 2,
                                barWidth: Double(barWidth),
                                maxHeight: Double(maxHeight)
                            )
                            Capsule()
                                .fill(barColor(height: h))
                                .frame(width: barWidth, height: CGFloat(h))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: maxHeight)
            } else {
                HStack(spacing: spacing) {
                    ForEach(Self.weights.indices, id: \.self) { i in
                        let h = height(bar: i, time: t)
                        Capsule()
                            .fill(barColor(height: Double(h)))
                            .frame(width: barWidth, height: h)
                    }
                }
                .frame(height: maxHeight)
            }
        }
        .animation(
            isSmooth ? .easeInOut(duration: 0.14) : .spring(duration: 0.18, bounce: 0.2),
            value: level
        )
        .animation(.easeInOut(duration: 0.3), value: color)
        .accessibilityHidden(true)
    }

    /// Доля роста этой полоски сейчас относительно её собственного диапазона
    /// (`barWidth`…`maxHeight`) — 0 в покое, 1 на максимуме амплитуды.
    private func barColor(height h: Double) -> Color {
        guard let peakColor else { return color }
        let span = Double(maxHeight) - Double(barWidth)
        let fraction = span > 0 ? min(max((h - Double(barWidth)) / span, 0), 1) : 0
        return color.mix(with: peakColor, by: fraction)
    }

    private func height(bar i: Int, time t: Double) -> CGFloat {
        if isWaiting {
            let wave = reduceMotion ? 0 : (sin(t * 4 - Double(i) * 0.8) + 1) / 2
            return barWidth + CGFloat(wave) * barWidth * 0.8
        }
        let jitter = reduceMotion ? 1 : VoiceBarsMotion.amplitudeFactor(bar: i, time: t, smooth: isSmooth)
        let clamped = min(max(level, 0), 1)
        let span = maxHeight - barWidth
        return barWidth + CGFloat(clamped * Self.weights[i] * jitter) * span
    }
}
