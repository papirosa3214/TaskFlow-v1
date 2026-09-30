import SwiftUI

/// Настройки → ИИ → «Голос Секретаря»: список голосов Gemini Live, у каждого
/// ▶ — прослушать образец из бандла, тап по строке — выбрать. Выбор уходит
/// в следующий голосовой разговор (`SecretaryVoiceViewModel.start`).
struct SecretaryVoicePickerScreen: View {
    @AppStorage(SecretaryVoice.storageKey) private var selected = SecretaryVoice.default.rawValue
    @State private var player = VoicePlayer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                TFCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(SecretaryVoice.allCases) { voice in
                            if voice != SecretaryVoice.allCases.first {
                                TFDivider(inset: 56)
                            }
                            row(voice)
                        }
                    }
                }
                Text("Секретарь говорит этим голосом в живом разговоре. Новый голос — со следующего звонка.")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .padding(.horizontal, TFSpacing.lg)
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.top, TFSpacing.sm)
            .padding(.bottom, TFSpacing.xl * 2)
        }
        .tfNativeHeader("Голос Секретаря", displayMode: .inline)
        .background(Color.tfBackground)
        .onDisappear { player.stop() }
    }

    private func row(_ voice: SecretaryVoice) -> some View {
        let isPlaying = voice.sampleURL != nil && player.playingURL == voice.sampleURL
        return HStack(spacing: TFSpacing.md) {
            Button {
                if let url = voice.sampleURL { try? player.toggle(url: url) }
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: TFIconSize.sm))
                    .foregroundStyle(isPlaying ? Color.tfRed : Color.tfDim)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Остановить образец \(voice.rawValue)" : "Прослушать \(voice.rawValue)")

            Button {
                selected = voice.rawValue
            } label: {
                HStack {
                    Text(voice.title).tfText(.body).foregroundStyle(Color.tfText)
                    Spacer()
                    if selected == voice.rawValue {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.tfRed)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected == voice.rawValue ? .isSelected : [])
        }
        .padding(.leading, TFSpacing.sm)
        .padding(.trailing, TFSpacing.lg)
        .padding(.vertical, TFSpacing.xs)
    }
}
