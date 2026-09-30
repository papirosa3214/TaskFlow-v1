import SwiftUI
import UIKit

// ═══════════ Тулбар пометок над клавиатурой (общий) ═══════════
//
// Один экземпляр ленты на экран — НЕ по одному на блок. Когда фокус
// переходит между блоками, аксессуар не пересоздаётся, клавиатура просто
// продолжает показывать тот же view — это и есть «единым целым с клавиатурой»,
// нативное поведение UIKit `inputAccessoryView`, которое просил владелец
// (LOCK-140/141, заметки про «чёрный блюр»). Один экземпляр ленты делится
// между блоками заметки И описанием задачи — раньше был дубль (LOCK-142,
// мой самописный `MarkdownToolbar` с урезанным набором кнопок).
//
// Происхождение: лента была написана для заметок (`NoteBlockTextView.swift`,
// `NoteKeyboardAccessoryBar`). Сейчас переехала сюда и переименована;
// единственное изменение по сравнению с оригиналом — пара
// `(viewModel, focus)` свернулась в один `MarkdownKeyboardHost`-протокол,
// чтобы заметки и карточка задачи могли делиться одной реализацией UI.

/// Контракт между лентой пометок и редактором. Единственная реализация —
/// `BlockDocumentKeyboardHost`: он же обслуживает и заметку, и описание
/// задачи (раньше адаптеров было два, с разным поведением одних и тех же
/// кнопок). Протокол оставлен точкой расширения для будущих полей.
@MainActor
protocol MarkdownKeyboardHost: AnyObject {
    /// Текущие активные марки на выделении (для подсветки кнопок B/I/…).
    var activeMarks: Set<InlineMark> { get }
    /// Текущий kind фокусированного блока (для подсветки H1/H2/H3/…).
    var currentBlockKind: BlockKind? { get }

    /// Переключить инлайн-марк на выделении. Если выделения нет — хост
    /// сам решает (вставить маркеры вокруг / ничего).
    func toggleMark(_ mark: InlineMark)
    /// Привести фокусированный блок к указанному kind. Переключение из
    /// того же kind обратно в `.paragraph` — на совести хоста.
    func setBlockKind(_ kind: BlockKind)
    /// Вставить горизонтальную линию после текущего блока. Опционально
    /// (задаче не нужна — дефолт no-op).
    func insertHorizontalRule()

    /// Скрыть клавиатуру (отдельная кнопка слева на ленте).
    func dismissKeyboard()

    /// Диктовка — кнопка справа. Если хост не поддерживает
    /// (`supportsDictation == false`), кнопка не рисуется.
    var supportsDictation: Bool { get }
    var isRecordingDictation: Bool { get }
    /// Живой уровень громкости записи (0…1) — для анимации амплитуды
    /// (`VoiceBarsView`) в кнопке микрофона, LOCK-254. `0`, если хост
    /// диктовку не поддерживает или запись не идёт.
    var dictationLevel: Double { get }
    func toggleDictation() async
}

extension MarkdownKeyboardHost {
    var supportsDictation: Bool { false }
    var isRecordingDictation: Bool { false }
    var dictationLevel: Double { 0 }
    func toggleDictation() async {}
    func insertHorizontalRule() {}
}

/// Лента пометок (spec §2.1) + диктовка (spec §0.7) — содержимое
/// `inputAccessoryView`. Кнопки слева направо:
///  • скрыть клавиатуру
///  • лента (inline-марки → заголовки → списки → цитата / код-блок / hr)
///  • микрофон (если хост поддерживает)
struct MarkdownKeyboardAccessoryBar: View {
    let host: MarkdownKeyboardHost

    var body: some View {
        // LOCK-254: единая стеклянная капсула вместо плоского фона НА КНОПКАХ
        // + ручной линии-разделителя сверху (`Color.tfStroke`, владелец
        // воспринял её как непонятную «полосу»). Кнопки внутри капсулы —
        // плоские, без собственного `.ultraThinMaterial`/`Circle()`: стекло
        // теперь только у внешней капсулы (владелец: «не кругляшок в
        // кругляшке»).
        //
        HStack(spacing: TFSpacing.sm) {
            dismissKeyboardButton
            toolbar
            if host.supportsDictation { micButton }
        }
        .padding(.horizontal, TFSpacing.sm)
        .padding(.vertical, TFSpacing.xs)
        .voiceCapsuleSurface()
        // Отделяем стеклянную Capsule от верхней кромки клавиатуры, не меняя
        // высоту аксессуара и тап-зоны её кнопок.
        .offset(y: -4)
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.vertical, TFSpacing.sm)
        .frame(height: MarkdownKeyboardAccessoryHost.height)
        .frame(maxWidth: .infinity)
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                toolbarButton("bold", active: host.activeMarks.contains(.bold)) {
                    host.toggleMark(.bold)
                }
                toolbarButton("italic", active: host.activeMarks.contains(.italic)) {
                    host.toggleMark(.italic)
                }
                toolbarButton("underline", active: host.activeMarks.contains(.underline)) {
                    host.toggleMark(.underline)
                }
                toolbarButton("strikethrough", active: host.activeMarks.contains(.strike)) {
                    host.toggleMark(.strike)
                }
                toolbarButton("highlighter", active: host.activeMarks.contains(.highlight)) {
                    host.toggleMark(.highlight)
                }
                toolbarButton("curlybraces", active: host.activeMarks.contains(.code)) {
                    host.toggleMark(.code)
                }
                toolbarButton("link", active: host.activeMarks.contains(.link)) {
                    host.toggleMark(.link)
                }

                divider

                headingButton(1)
                headingButton(2)
                headingButton(3)

                divider

                toolbarButton("list.bullet", active: isBlockKind { if case .bulletItem = $0 { true } else { false } }) {
                    host.setBlockKind(.bulletItem)
                }
                toolbarButton("list.number", active: isBlockKind { if case .orderedItem = $0 { true } else { false } }) {
                    host.setBlockKind(.orderedItem)
                }
                toolbarButton("checklist", active: isBlockKind { if case .taskItem = $0 { true } else { false } }) {
                    host.setBlockKind(.taskItem(checked: false))
                }

                divider

                toolbarButton("quote.opening", active: isBlockKind { $0 == .blockquote }) {
                    host.setBlockKind(.blockquote)
                }
                toolbarButton("chevron.left.forwardslash.chevron.right", active: isBlockKind { if case .codeBlock = $0 { true } else { false } }) {
                    host.setBlockKind(.codeBlock(language: nil))
                }
                toolbarButton("minus", active: false) {
                    host.insertHorizontalRule()
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.tfStroke).frame(width: TFBorder.width, height: 20).padding(.horizontal, TFSpacing.xs)
    }

    private func tapHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func toolbarButton(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            tapHaptic()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(active ? Color.tfRed : Color.tfSub)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(TFTapScaleStyle())
    }

    private func headingButton(_ level: Int) -> some View {
        let active = isBlockKind { if case .heading(let l) = $0 { l == level } else { false } }
        return Button {
            tapHaptic()
            host.setBlockKind(.heading(level: level))
        } label: {
            Text("H\(level)")
                .tfText(.action)
                .fontWeight(.bold)
                .foregroundStyle(active ? Color.tfRed : Color.tfSub)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(TFTapScaleStyle())
    }

    private func isBlockKind(_ predicate: (BlockKind) -> Bool) -> Bool {
        guard let kind = host.currentBlockKind else { return false }
        return predicate(kind)
    }

    /// Слева — владелец 03.09.2026: «не хватает этого момента». Глобальный
    /// `resignFirstResponder` — лента сама не знает, какой блок сейчас
    /// первый респондер, а `sendAction(nil,…)` находит его сам, как
    /// системная «спрятать клавиатуру» в любом iOS-приложении.
    private var dismissKeyboardButton: some View {
        Button {
            tapHaptic()
            host.dismissKeyboard()
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 18))
                .foregroundStyle(Color.tfText)
                .frame(width: TFHitTarget.min, height: TFHitTarget.min)
        }
        .buttonStyle(TFTapScaleStyle())
        .accessibilityLabel("Скрыть клавиатуру")
    }

    /// Во время записи — та же `VoiceBarsView`, что и запись голосового
    /// сообщения в чате (`ChatVoiceComposer.swift`), с тем же набором
    /// величин (LOCK-254, владелец 30.09.2026: «посмотри, как в чате...
    /// вырежи оттуда кусок, вставь сюда»). `host.dictationLevel` — реальный
    /// уровень громкости из `DictationEngine.currentLevel`, не декоративная
    /// анимация.
    private var micButton: some View {
        Button {
            tapHaptic()
            Task { await host.toggleDictation() }
        } label: {
            if host.isRecordingDictation {
                VoiceBarsView(
                    level: host.dictationLevel,
                    color: Color.tfRed.mix(with: .black, by: 0.55), peakColor: Color.tfRed,
                    barWidth: 3, spacing: 2, maxHeight: 20, isSmooth: true
                )
                .frame(width: TFHitTarget.min, height: TFHitTarget.min)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.tfText)
                    .frame(width: TFHitTarget.min, height: TFHitTarget.min)
            }
        }
        .buttonStyle(TFTapScaleStyle())
    }
}

/// `inputAccessoryView` живёт по системным правилам UIKit, а не SwiftUI —
/// один и тот же `UIHostingController` назначается ВСЕМ `UITextView`
/// редактора (заметки ИЛИ карточки задачи). Когда фокус переходит между
/// блоками, аксессуар не пересоздаётся — клавиатура просто продолжает
/// показывать тот же view, то самое «единым целым с клавиатурой».
@MainActor
final class MarkdownKeyboardAccessoryHost {
    static let height: CGFloat = 52

    private let hosting: UIHostingController<MarkdownKeyboardAccessoryBar>
    var view: UIView { hosting.view }

    init(host: MarkdownKeyboardHost) {
        hosting = UIHostingController(rootView: MarkdownKeyboardAccessoryBar(host: host))
        hosting.view.backgroundColor = .clear
        hosting.view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: Self.height)
        hosting.view.autoresizingMask = [.flexibleWidth]
    }
}
