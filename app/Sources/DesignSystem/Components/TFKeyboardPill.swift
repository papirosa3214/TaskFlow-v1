import SwiftUI

// Единая стеклянная поверхность для панелей над клавиатурой/полей ввода —
// LOCK-254. Перенесено буквально из `Sources/Features/Chat/ChatVoiceComposer.swift`
// (жило там как `voiceCircleSurface()`/`voiceCapsuleSurface()`, не `private` —
// владелец 26.09.2026 уже просил тем же стеклом одеть пилюлю квик-реплаев в
// `RoleChatsScreen`), сюда — раз теперь нужна и панели форматирования Markdown
// (`MarkdownKeyboardAccessoryBar`), не только чату.
//
// На iOS 26 стекло рисует система (`glassEffect`); для iOS 18–25 остаётся
// материал.
public extension View {
    @ViewBuilder func voiceCircleSurface() -> some View {
        if #available(iOS 26.0, *) { glassEffect(.regular, in: .circle) }
        else { background(.thinMaterial, in: Circle()) }
    }

    @ViewBuilder func voiceCapsuleSurface() -> some View {
        if #available(iOS 26.0, *) { glassEffect(.regular, in: .capsule) }
        else { background(.thinMaterial, in: Capsule()) }
    }
}
