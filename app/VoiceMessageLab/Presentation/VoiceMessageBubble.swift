import SwiftUI

/// Как нарисована кнопка воспроизведения.
enum VoicePlayDisc {
    /// Белый залитый круг под треугольником — прежний вид прототипа.
    case white
    /// Круга нет вовсе: только треугольник, без фона и без обводки
    /// (владелец 21.09.2026).
    case none
}

/// Оформление пузыря голосового сообщения.
///
/// Цвета задаёт ВЫЗЫВАЮЩИЙ, а не этот файл: он собирается сразу в два
/// приложения — в TaskFlow и в отдельный прототип `VoiceMessageLab`, у
/// которого дизайн-системы TaskFlow нет. Значения по умолчанию — прежний
/// вид прототипа (заливка акцентом).
///
/// В чате вид сообщения не зависит от того, как его отправили (владелец
/// 21.09.2026): у своего голосового — та же подложка и красная обводка, что
/// у своего текстового. Чужое голосовое остаётся прежним пузырём прототипа,
/// как и раньше.
struct VoiceBubbleStyle {
    var fill: Color = .accentColor
    var stroke: Color?
    /// Треугольник воспроизведения.
    var playTint: Color = .accentColor
    var playDisc: VoicePlayDisc = .white
    /// Внутренний отступ пузыря и радиус скругления. По умолчанию — прежние
    /// числа прототипа (14 и 22). Чат передаёт СВОИ — те же, что у текстового
    /// сообщения (`TFSpacing.md` и `TFRadius.lg`): иначе иконка отправителя и
    /// текст расшифровки стоят на разных вертикалях в текстовом и голосовом
    /// сообщении (владелец 21.09.2026).
    var padding: CGFloat = 14
    var cornerRadius: CGFloat = 22
}

/// Один пузырь для прототипа и настоящего чата.
struct VoiceMessageBubble: View {
    let message: VoiceMessage
    let player: VoicePlayer
    var style = VoiceBubbleStyle()
    /// Строка отправителя (иконка + имя) ВНУТРИ пузыря — как у текстового
    /// сообщения в чате. Прототипу она не нужна и по умолчанию пуста; в чат
    /// её кладёт `RoleChatsScreen`, потому что знает, кто отправил.
    var header: AnyView?
    @State private var showsTranscript = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let header { header }
            HStack(spacing: 12) {
                Button { try? player.toggle(url: message.audioURL) } label: {
                    playGlyph
                }
                .accessibilityLabel(player.playingURL == message.audioURL ? "Пауза" : "Воспроизвести")
                WaveformView(levels: message.waveform, color: .white).frame(height: 30)
                Text(String(format: "%d:%02d", Int(message.duration) / 60, Int(message.duration) % 60))
                    .monospacedDigit().font(.subheadline)
            }
            transcript
        }
        .padding(style.padding)
        .foregroundStyle(.white)
        .background(style.fill, in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .overlay {
            if let stroke = style.stroke {
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            }
        }
        .frame(maxWidth: 330, alignment: .trailing)
    }

    /// Кнопка воспроизведения.
    ///
    /// `.none` — ровно глиф, без рамки, круга и обводки: владелец 21.09.2026 —
    /// «не надо рисовать гигантскую кнопку, чисто только треугольничек».
    /// Поэтому у такого варианта нет ни 36pt-рамки, ни фона. Сам глиф не
    /// уменьшается — прежние 20pt, дело было только в лишней рамке вокруг него.
    ///
    /// `.white` — прежний вид прототипа: белый залитый круг 36pt, глиф по
    /// центру.
    @ViewBuilder
    private var playGlyph: some View {
        let glyph = Image(systemName: player.playingURL == message.audioURL ? "pause.fill" : "play.fill")
            .font(.system(size: 20, weight: .medium))
        switch style.playDisc {
        case .white:
            glyph
                .frame(width: 36, height: 36)
                .background(Circle().fill(.white))
                .foregroundStyle(style.playTint)
        case .none:
            // У `play.fill` есть собственный боковой пробел внутри глифа
            // (около 2pt при 20pt) — без компенсации треугольник встаёт
            // правее иконки отправителя и текста, хотя рамка начинается с
            // того же края. Владелец 21.09.2026: «интервалы абсолютно
            // одинаковые, симметрия». Сдвиг постоянный: кегль глифа
            // фиксированный (20pt), от Dynamic Type пробел не зависит.
            //
            // Рамка нужна ради НАЖАТИЯ, а не вида: сам треугольник её не
            // заполняет и остаётся единственным, что видно (владелец
            // 21.09.2026: «не надо рисовать гигантскую кнопку»). Без неё
            // зона нажатия ужималась до размеров глифа (~17pt) и попасть по
            // кнопке было почти невозможно.
            glyph
                .foregroundStyle(style.playTint)
                .frame(width: 36, height: 36, alignment: .leading)
                .offset(x: -2)
        }
    }

    @ViewBuilder private var transcript: some View {
        switch message.transcript {
        case .pending:
            Label("Расшифровка…", systemImage: "waveform.badge.magnifyingglass")
                .font(.subheadline).foregroundStyle(.white.opacity(0.78))
        case .failed:
            Text("Расшифровка недоступна")
                .font(.subheadline).foregroundStyle(.white.opacity(0.78))
        case .ready(let text):
            VStack(alignment: .leading, spacing: 5) {
                Text(text)
                    .font(.body)
                    .lineLimit(showsTranscript ? nil : 2)
                    .textSelection(.enabled)
                if text.count > 120 {
                    Button(showsTranscript ? "Скрыть" : "Показать ещё") { showsTranscript.toggle() }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
            }
        }
    }
}

struct WaveformView: View {
    let levels: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let values = VoiceWaveform.sculptedSamples(
                from: VoiceWaveform.displaySamples(from: levels, slots: 48)
            )
            HStack(spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(color)
                        .frame(maxWidth: .infinity, minHeight: 2,
                               maxHeight: geometry.size.height * CGFloat(0.07 + min(0.9, level) * 0.84))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }
}
