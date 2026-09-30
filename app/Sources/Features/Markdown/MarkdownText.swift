import UIKit
import SwiftUI

// ═══════════ NoteBlock ⇄ NSAttributedString ═══════════
//
// Общий рендер для всего, что работает с markdown-редактором: заметки,
// описание задачи. Не зависит от `Notes/` — модуль `Markdown/` может быть
// использован из любой фичи.
//
// `NoteBlock`/`RichRun` (в `NoteDocument.swift`) хранят СЕМАНТИКУ прогона
// (bold/italic/…/linkHref) — ровно то, что уходит в markdown. UITextView
// работает с NSAttributedString, у которого форматирование — это ВИЗУАЛЬНЫЕ
// атрибуты (шрифт, цвет, подчёркивание). Здесь — мост между двумя мирами:
// свои ключи `MarkdownMarkKey.*` хранят семантику НЕЗАВИСИМО от того, как
// она нарисована, чтобы обратное чтение (attributedText → runs) не пыталось
// «угадывать» bold по начертанию шрифта (жирный код и жирный текст
// выглядят по-разному, но семантика читается по ключу, не по виду).

/// Ключи семантических меток в `NSAttributedString`. Нужны для round-trip
/// (UITextView.attributedText → RichRun), чтобы различать «жирный текст»
/// и «жирный код» по семантике, а не по визуальному начертанию.

/// Инлайн-марка — Swift-эквивалент отдельного мультипликатора состояния
/// панели инструментов (какие кнопки подсвечены при текущем выделении).
enum InlineMark: Hashable {
    case bold, italic, underline, strike, highlight, code, link
}

enum MarkdownMarkKey {
    static let bold = NSAttributedString.Key("md.bold")
    static let italic = NSAttributedString.Key("md.italic")
    static let underline = NSAttributedString.Key("md.underline")
    static let strike = NSAttributedString.Key("md.strike")
    static let highlight = NSAttributedString.Key("md.highlight")
    static let code = NSAttributedString.Key("md.code")
    static let link = NSAttributedString.Key("md.link")
}

enum MarkdownText {
    /// Кегль тела блока — берётся из `TFFont.body` (15px), заголовки крупнее
    /// (числа спекой для блочного редактора не даны — используем шкалу
    /// `TFTextStyle`: H1=titleLarge 28px, H2=taskTitle 20px, H3=title 17px,
    /// ближайшие ступени готовой шкалы, не придуманные отдельно).
    static func baseFont(for kind: BlockKind) -> UIFont {
        switch kind {
        case .heading(1): UIFont.systemFont(ofSize: 28, weight: .bold)
        case .heading(2): UIFont.systemFont(ofSize: 20, weight: .semibold)
        case .heading(3): UIFont.systemFont(ofSize: 17, weight: .semibold)
        case .codeBlock: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        default: UIFont.systemFont(ofSize: 15, weight: .regular)
        }
    }

    /// Прогоны блока → NSAttributedString готовый для `UITextView.attributedText`.
    /// `base` перебивает кегль, выведенный из типа блока: ячейке таблицы
    /// нужен тот же `paragraph`, но шапка рисуется полужирной, а марки
    /// `bold` в её прогонах нет (в markdown-таблице шапка выделяется самой
    /// позицией, не разметкой — веб делает то же самое стилем `th`).
    static func attributedString(
        runs: [RichRun],
        blockKind: BlockKind,
        base: UIFont? = nil,
        textColor: UIColor = UIColor(Color.tfText)
    ) -> NSAttributedString {
        let base = base ?? baseFont(for: blockKind)
        let out = NSMutableAttributedString()
        for run in runs {
            guard !run.text.isEmpty else { continue }
            out.append(NSAttributedString(string: run.text, attributes: attributes(for: run, base: base, textColor: textColor)))
        }
        if out.length == 0 {
            // Пустой блок всё равно должен нести шрифт — иначе UITextView
            // печатает первый символ системным дефолтом (17pt), и кегль
            // «прыгает» после первого нажатия клавиши.
            out.append(NSAttributedString(string: "", attributes: [.font: base, .foregroundColor: textColor]))
        }
        return out
    }

    static func attributes(
        for run: RichRun,
        base: UIFont,
        textColor: UIColor = UIColor(Color.tfText)
    ) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [:]
        attrs[.font] = font(base: base, bold: run.bold, italic: run.italic, code: run.code)
        attrs[.foregroundColor] = (run.linkHref?.isEmpty == false) ? UIColor(Color.tfRed) : textColor
        if run.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if run.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if run.code {
            attrs[.backgroundColor] = UIColor(Color.tfCard2)
        } else if run.highlight {
            attrs[.backgroundColor] = UIColor(Color.tfYellow).withAlphaComponent(0.35)
        }
        if run.bold { attrs[MarkdownMarkKey.bold] = true }
        if run.italic { attrs[MarkdownMarkKey.italic] = true }
        if run.underline { attrs[MarkdownMarkKey.underline] = true }
        if run.strike { attrs[MarkdownMarkKey.strike] = true }
        if run.highlight { attrs[MarkdownMarkKey.highlight] = true }
        if run.code { attrs[MarkdownMarkKey.code] = true }
        if let href = run.linkHref, !href.isEmpty { attrs[MarkdownMarkKey.link] = href }
        return attrs
    }

    private static func font(base: UIFont, bold: Bool, italic: Bool, code: Bool) -> UIFont {
        if code {
            // Инлайн-код — свой моноширинный кегль независимо от кегля блока
            // (веб рисует `<code>` фиксированным размером внутри любого блока).
            var f = UIFont.monospacedSystemFont(ofSize: 13, weight: bold ? .bold : .regular)
            if italic { f = f.withTraits(.traitItalic) ?? f }
            return f
        }
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard !traits.isEmpty, let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }

    /// NSAttributedString (из `UITextView.attributedText`) → `[RichRun]`.
    /// Читает СЕМАНТИЧЕСКИЕ ключи (`MarkdownMarkKey.*`), не визуальные — так
    /// «жирный код» и «жирный текст» декодируются в одинаково `bold: true`
    /// независимо от того, что зрительно выглядят по-разному.
    static func runs(from attributed: NSAttributedString) -> [RichRun] {
        guard attributed.length > 0 else { return [] }
        var runs: [RichRun] = []
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
            let text = (attributed.string as NSString).substring(with: range)
            guard !text.isEmpty else { return }
            runs.append(RichRun(
                text: text,
                bold: (attrs[MarkdownMarkKey.bold] as? Bool) ?? false,
                italic: (attrs[MarkdownMarkKey.italic] as? Bool) ?? false,
                underline: (attrs[MarkdownMarkKey.underline] as? Bool) ?? false,
                strike: (attrs[MarkdownMarkKey.strike] as? Bool) ?? false,
                highlight: (attrs[MarkdownMarkKey.highlight] as? Bool) ?? false,
                code: (attrs[MarkdownMarkKey.code] as? Bool) ?? false,
                linkHref: attrs[MarkdownMarkKey.link] as? String
            ))
        }
        return runs
    }

    /// Режет массив прогонов по смещению в UTF-16 (то, чем оперирует
    /// `NSRange`/`UITextView`) — используется при Enter (разбить блок на
    /// два по позиции курсора). Считаем именно UTF-16, а не `Character`,
    /// чтобы смещение из `UITextView.selectedRange` совпадало 1:1 без
    /// пересчёта на суррогатные пары/эмодзи.
    static func splitRuns(_ runs: [RichRun], atUTF16Offset offset: Int) -> (before: [RichRun], after: [RichRun]) {
        var before: [RichRun] = []
        var after: [RichRun] = []
        var consumed = 0
        for run in runs {
            let ns = run.text as NSString
            let len = ns.length
            if consumed + len <= offset {
                before.append(run)
                consumed += len
            } else if consumed >= offset {
                after.append(run)
            } else {
                let local = offset - consumed
                let leftText = ns.substring(to: local)
                let rightText = ns.substring(from: local)
                var left = run; left.text = leftText
                var right = run; right.text = rightText
                if !leftText.isEmpty { before.append(left) }
                if !rightText.isEmpty { after.append(right) }
                consumed = offset
            }
        }
        return (before, after)
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)) else { return nil }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
