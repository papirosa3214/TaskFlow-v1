import SwiftUI

// Нижняя шторка — spec/DESIGN-TOKENS.md §4 «Нижняя шторка». Реализована как
// `View`-модификатор поверх `.sheet`, чтобы экраны волны 2 подключали её одной
// строкой (`.tfBottomSheet(isPresented:) { ... }`), не пересобирая вёрстку сами.
//
// На native `.presentationDetents`/`.presentationCornerRadius` уже дают часть
// эффекта нативно (скрим, драг вниз для закрытия) — здесь докручиваем то, что
// спека требует явно: верхние углы 20px, хендл 36×4, шапка с крестиком слева.
public struct TFBottomSheetContent<Content: View>: View {
    let title: String?
    let actionTitle: String?
    let action: (() -> Void)?
    let onClose: () -> Void
    let content: Content

    public init(
        title: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
        self.onClose = onClose
        self.content = content()
    }

    /// Своего здесь больше нет ничего, кроме содержимого (09.09.2026,
    /// владелец: «просил сделать окно именно системным, чтобы мы ничего
    /// своего не рисовали, кроме содержимого»).
    ///
    /// Было: нарисованный хендл поверх спрятанного системного, своя шапка
    /// с крестиком и заголовком, своя подложка со скруглением верхних углов.
    /// Стало: системный навигационный бар — заголовок, «Закрыть» слева и
    /// кнопка действия справа рисует iOS, фон и углы шторки тоже её.
    public var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity)
                .navigationTitle(title ?? "")
                .navigationBarTitleDisplayMode(.inline)
                // Кнопки закрытия нет намеренно: шторка закрывается
                // смахиванием вниз и тапом мимо неё, как везде в приложении.
                // Слова «Закрыть» в интерфейсе не было нигде — оно появилось
                // только здесь и сразу резануло глаз владельцу (09.09.2026).
                .toolbar {
                    if let actionTitle, let action {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(actionTitle, action: action)
                        }
                    }
                }
        }
    }
}

public extension View {
    /// Подключает нижнюю шторку — системную, без своей обвязки.
    func tfBottomSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        title: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            TFBottomSheetContent(title: title, actionTitle: actionTitle, action: action, onClose: {
                isPresented.wrappedValue = false
            }, content: content)
            // Половинное и полное состояние, родной хендл. Фон, скругление
            // углов и скрим — системные: свои `presentationBackground` и
            // `presentationCornerRadius` убраны вместе с остальной обвязкой.
            // Правка общая — её видят все семь шторок на этом модификаторе
            // (настройки профиля, иконка приложения, статистика чата, фильтры
            // активности, задачи из текста заметки, перенос с «Сегодня» и из
            // разделов).
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

#Preview("Нижняя шторка") {
    TFBottomSheetContent(title: "Удалить задачу?", onClose: {}) {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            Text("«Старт нового проекта» будет удалена безвозвратно")
                .tfText(.body)
                .foregroundStyle(Color.tfSub)
            TFButton("Удалить", variant: .primary) {}
            TFButton("Отмена", variant: .secondary) {}
        }
        .padding(.bottom, TFSpacing.xl)
    }
    .background(Color.tfBackground)
}
