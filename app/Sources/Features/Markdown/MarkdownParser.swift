import Foundation

// ═══════════ Markdown → [NoteBlock] ═══════════
//
// Сфокусированный парсер для TaskFlow: тот же `NoteBlock`/`RichRun` AST,
// что и в `NoteDocument.swift` (заметки), чтобы рендер из `MarkdownText`
// работал без изменений. Поддерживает ровно то, что обещает тулбар
// карточки задачи и редактора заметки — никаких Obsidian-расширений.
//
// Блочные элементы (распознаются построчно, `#` `##` `###` `-`/`*`/`+`
// `1.` `-[ ]`/`-[x]` `>` `---` ``` ``` ```):
//   • heading 1‑3 (# …, ## …, ### …)
//   • paragraph (любая не-специальная строка)
//   • bulletItem / orderedItem / taskItem (вложенность — отступ 2 пробела)
//   • blockquote (один `>` на строку; соседние `>` сливаются)
//   • horizontalRule (`---` / `***` / `___`)
//   • codeBlock (``` ... ```; язык из строки открытия)
//
// Инлайн (внутри paragraph / heading / listItem / blockquote):
//   • **bold**, *italic*, ~~strike~~, `code`, [txt](url)
//   • экранирование символов разметки обратным слэшем (\* \_ \[ …)
//
// Что НЕ поддерживается (осознанно, чтобы не раздувать):
//   • __underline__ / ==highlight== — не стандарт маркдауна, в существующих
//     TipTap-заметках они есть; конвертер TipTap→markdown снимает эти марки
//     (см. TipTapToMarkdown.swift, потери отмечены в карточке LOCK-142).
//   • [[wikilinks]], > [!callout], --- frontmatter ---, HTML-вставки,
//     ссылки-ссылки `[txt][ref]`, жёсткий перевод строки в параграфе (двойной
//     пробел + `\n`).
//   • Списки с `start=N` — кодируются всегда с 1.

enum MarkdownParser {

    /// Корневой вход: строка → список блоков. Пустая/пробельная строка
    /// возвращает один пустой параграф — то же поведение, что у
    /// `NoteDocument.empty`, чтобы UI не различал «редактор открыт, ничего
    /// не напечатано» от «сохранено как пустой документ».
    static func parse(_ source: String) -> [NoteBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var blocks: [NoteBlock] = []
        var i = 0
        while i < lines.count {
            // Пропускаем пустые строки между блоками (они разделяют абзацы,
            // но не появляются в AST — как в TipTap).
            if lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Code block — захватывает подряд идущие строки до закрытия.
            if let (block, next) = parseCodeBlock(lines, at: i) {
                blocks.append(block); i = next; continue
            }

            // Horizontal rule.
            if let (block, next) = parseHorizontalRule(lines, at: i) {
                blocks.append(block); i = next; continue
            }

            // Heading.
            if let (block, next) = parseHeading(lines, at: i) {
                blocks.append(block); i = next; continue
            }

            // Blockquote — собираем подряд идущие строки, начинающиеся с `>`.
            if let (block, next) = parseBlockquote(lines, at: i) {
                blocks.append(block); i = next; continue
            }

            // List item (bullet / ordered / task). Подряд идущие пункты одного
            // типа и уровня — отдельные блоки (как у `NoteBlock`).
            if let (block, next) = parseListItem(lines, at: i) {
                blocks.append(block); i = next; continue
            }

            // Paragraph — все остальные непустые строки до пустой.
            if let (block, next) = parseParagraph(lines, at: i) {
                blocks.append(block); i = next; continue
            }

            // Теоретически сюда не попадаем — `parseParagraph` принимает
            // любую непустую строку. На случай регрессии — пропустим строку.
            i += 1
        }
        return blocks.isEmpty ? [NoteBlock(kind: .paragraph)] : blocks
    }

    // MARK: - Блочные элементы

    private static func parseCodeBlock(_ lines: [String], at i: Int) -> (NoteBlock, Int)? {
        let open = lines[i].trimmingCharacters(in: .whitespaces)
        guard open.hasPrefix("```") else { return nil }
        let lang = String(open.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var collected: [String] = []
        var j = i + 1
        while j < lines.count {
            if lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("```") { break }
            collected.append(lines[j])
            j += 1
        }
        guard j < lines.count else {
            // Нет закрытия — трактуем открытие как обычный текст, откатываемся
            // (так безопаснее, чем молча потерять содержимое).
            return nil
        }
        let text = collected.joined(separator: "\n")
        let block = NoteBlock(kind: .codeBlock(language: lang.isEmpty ? nil : lang),
                              runs: [RichRun(text: text)])
        return (block, j + 1)
    }

    private static func parseHorizontalRule(_ lines: [String], at i: Int) -> (NoteBlock, Int)? {
        let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }
        let chars = Set(trimmed)
        guard chars == Set(["-"]) || chars == Set(["*"]) || chars == Set(["_"]) else { return nil }
        return (NoteBlock(kind: .horizontalRule), i + 1)
    }

    private static func parseHeading(_ lines: [String], at i: Int) -> (NoteBlock, Int)? {
        let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
        var level = 0
        var rest = trimmed
        while rest.hasPrefix("#") { level += 1; rest = String(rest.dropFirst()) }
        guard level >= 1, rest.first == " " else { return nil }
        // H4–H6 не отбрасываем — тулбар даёт только H1–H3, но если в документ
        // попало что-то глубже (например, вставка через агента), клампим до H3,
        // чтобы текст остался заголовком, а не упал в обычный параграф.
        let clamped = min(max(level, 1), 3)
        let text = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        let runs = parseInline(text)
        return (NoteBlock(kind: .heading(level: clamped), runs: runs), i + 1)
    }

    private static func parseBlockquote(_ lines: [String], at i: Int) -> (NoteBlock, Int)? {
        guard lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") else { return nil }
        var collected: [String] = []
        var j = i
        while j < lines.count {
            let t = lines[j].trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix(">") else { break }
            let body = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
            collected.append(body)
            j += 1
        }
        // Сливаем содержимое в один параграф-внутри-цитаты (TipTap так же:
        // несколько `> абзац` подряд склеиваются в один `blockquote`).
        let text = collected.joined(separator: "\n")
        return (NoteBlock(kind: .blockquote, runs: parseInline(text)), j)
    }

    private static func parseListItem(_ lines: [String], at i: Int) -> (NoteBlock, Int)? {
        let raw = lines[i]
        let indent = leadingSpaces(raw)
        guard indent % 2 == 0 else { return nil }
        let level = indent / 2
        let body = String(raw.dropFirst(indent))
        let (kind, rest) = listPrefix(body)
        guard let kind else { return nil }
        let runs = parseInline(rest.trimmingCharacters(in: .whitespaces))
        return (NoteBlock(kind: kind, level: level, runs: runs), i + 1)
    }

    private static func parseParagraph(_ lines: [String], at i: Int) -> (NoteBlock, Int)? {
        var collected: [String] = []
        var j = i
        while j < lines.count {
            let raw = lines[j]
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { break }
            // Если строка — это «следующий» блочный элемент, отдаём его тому,
            // кто его разбирает; сами собираем только текст до первого блочного.
            if j > i, isBlockStart(lines[j]) { break }
            collected.append(raw)
            j += 1
        }
        guard !collected.isEmpty else { return nil }
        let text = collected.joined(separator: "\n")
        return (NoteBlock(kind: .paragraph, runs: parseInline(text)), j)
    }

    private static func isBlockStart(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") || trimmed.hasPrefix(">") || trimmed.hasPrefix("```") {
            return true
        }
        if trimmed == "---" || trimmed == "***" || trimmed == "___" { return true }
        let indent = leadingSpaces(line)
        if indent % 2 == 0 {
            let body = String(line.dropFirst(indent))
            if listPrefix(body).kind != nil { return true }
        }
        return false
    }

    // MARK: - Списки

    private static func listPrefix(_ body: String) -> (kind: BlockKind?, rest: String) {
        // `- [ ] ` / `- [x] ` / `- [X] ` — task.
        if body.hasPrefix("- [ ] ") || body.hasPrefix("- [x] ") || body.hasPrefix("- [X] ") {
            let checked = body.hasPrefix("- [x] ") || body.hasPrefix("- [X] ")
            return (.taskItem(checked: checked), String(body.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        }
        // `- ` / `* ` / `+ ` — bullet.
        if body.hasPrefix("- ") || body.hasPrefix("* ") || body.hasPrefix("+ ") {
            return (.bulletItem, String(body.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }
        // `1. ` / `1) ` — ordered.
        if let dot = body.firstIndex(of: "."), body[body.startIndex..<dot].allSatisfy(\.isNumber) {
            let after = body.index(after: dot)
            if after < body.endIndex, body[after] == " " {
                return (.orderedItem, String(body[body.index(after: after)...]).trimmingCharacters(in: .whitespaces))
            }
        }
        if let paren = body.firstIndex(of: ")"), body[body.startIndex..<paren].allSatisfy(\.isNumber) {
            return (.orderedItem, String(body[body.index(after: paren)...]).trimmingCharacters(in: .whitespaces))
        }
        return (nil, body)
    }

    private static func leadingSpaces(_ s: String) -> Int {
        var n = 0
        for ch in s {
            if ch == " " { n += 1 } else { break }
        }
        return n
    }

    // MARK: - Инлайн

    /// Параграф/заголовок/пункт → массив `RichRun`. Распознаёт **bold**,
    /// *italic*, ~~strike~~, `code`, [txt](url). Экранирование — обратный
    /// слэш перед символом разметки; внутри `code` и url экранирование
    /// игнорируется. Соседние text-ноды с одним и тем же набором марок
    /// склеиваются — не плодим runs.
    static func parseInline(_ source: String) -> [RichRun] {
        var runs: [RichRun] = []
        var text = ""
        let marks = MarkSet()

        func flush() {
            if text.isEmpty { return }
            runs.append(RichRun(
                text: text,
                bold: marks.bold,
                italic: marks.italic,
                strike: marks.strike,
                code: marks.code,
                linkHref: marks.link
            ))
            text = ""
        }

        var i = source.startIndex
        while i < source.endIndex {
            let ch = source[i]
            // Экранированный символ — пропускаем слэш, кладём сам символ.
            if ch == "\\", let next = source.index(i, offsetBy: 1, limitedBy: source.endIndex), next < source.endIndex {
                let escaped = source[next]
                if isPunctuation(escaped) {
                    text.append(escaped)
                    i = source.index(after: next)
                    continue
                }
            }
            // `code` — non-greedy до следующего backtick. Внутри — сырой
            // текст без дальнейшей разметки (CommonMark).
            if ch == "`" {
                if let close = source.range(of: "`", range: source.index(after: i)..<source.endIndex) {
                    flush()
                    let inner = String(source[source.index(after: i)..<close.lowerBound])
                    runs.append(RichRun(text: inner, code: true))
                    i = close.upperBound
                    continue
                }
            }
            // **[bold]** — ровно два * по краям, без третьего подряд.
            if ch == "*", let close = matchDelimited(source, at: i, delim: "*", length: 2, allowItalicInside: true) {
                flush()
                let contentStart = source.index(close.lowerBound, offsetBy: 2, limitedBy: source.endIndex) ?? close.upperBound
                // close.upperBound указывает на позицию ПОСЛЕ закрывающего
                // разделителя — отступаем назад на длину, чтобы исключить
                // сам разделитель из inner (раньше он туда попадал).
                let contentEnd = source.index(close.upperBound, offsetBy: -2, limitedBy: close.lowerBound) ?? close.upperBound
                let inner = String(source[contentStart..<contentEnd])
                runs.append(contentsOf: parseInline(inner)
                    .map { var r = $0; r.bold = true; return r })
                i = close.upperBound
                continue
            }
            // *[italic]* — одиночные *.
            if ch == "*", let close = matchDelimited(source, at: i, delim: "*", length: 1, allowItalicInside: false) {
                flush()
                let contentStart = source.index(after: close.lowerBound)
                let contentEnd = source.index(close.upperBound, offsetBy: -1, limitedBy: close.lowerBound) ?? close.upperBound
                let inner = String(source[contentStart..<contentEnd])
                runs.append(contentsOf: parseInline(inner)
                    .map { var r = $0; r.italic = true; return r })
                i = close.upperBound
                continue
            }
            // ~~[strike]~~
            if ch == "~", let close = matchDelimited(source, at: i, delim: "~", length: 2, allowItalicInside: false) {
                flush()
                let contentStart = source.index(close.lowerBound, offsetBy: 2, limitedBy: source.endIndex) ?? close.upperBound
                let contentEnd = source.index(close.upperBound, offsetBy: -2, limitedBy: close.lowerBound) ?? close.upperBound
                let inner = String(source[contentStart..<contentEnd])
                runs.append(contentsOf: parseInline(inner)
                    .map { var r = $0; r.strike = true; return r })
                i = close.upperBound
                continue
            }
            // [txt](url) — ссылка. Текст внутри `[]` парсится как инлайн (без
            // рекурсии ссылок), URL — буквально между `(` и `)`, без самих скобок.
            if ch == "[", let mid = source[i...].firstIndex(of: "]"),
               let paren = source[source.index(after: mid)..<source.endIndex].firstIndex(of: ")"),
               source[source.index(after: mid)..<paren].hasPrefix("(") {
                flush()
                let labelStart = source.index(after: i)
                let labelEnd = mid
                let urlStart = source.index(after: source.index(after: mid)) // пропускаем "("
                let label = String(source[labelStart..<labelEnd])
                let url = String(source[urlStart..<paren])
                runs.append(contentsOf: parseInline(label)
                    .map { var r = $0; r.linkHref = url; return r })
                i = source.index(after: paren)
                continue
            }
            text.append(ch)
            i = source.index(after: i)
        }
        flush()
        return runs
    }

    /// Ищет закрывающий разделитель (run из `length` одинаковых символов)
    /// с теми же правилами, что в CommonMark: открывающий и закрывающий
    /// разделители окружены пробелами/punctuation или границами строки.
    /// `allowItalicInside=true` — для `**` (внутри может быть `*italic*`).
    private static func matchDelimited(_ source: String, at start: String.Index, delim: Character, length: Int, allowItalicInside: Bool) -> Range<String.Index>? {
        let end = source.endIndex
        var j = source.index(start, offsetBy: length, limitedBy: end) ?? end
        while j < end {
            // Закрытие — `length` одинаковых символов подряд.
            var k = j
            var count = 0
            while k < end, source[k] == delim, count < length {
                k = source.index(after: k); count += 1
            }
            guard count == length else {
                // Не хватило — двигаем j на одну позицию и пробуем снова.
                j = source.index(after: j); continue
            }
            // Границы (CommonMark): слева и справа от разделителей не должно
            // быть «обычных» символов — иначе это просто символы в слове.
            let leftOK = isBoundary(source, before: start)
                || source[start] == delim && !isAlphanumeric(source, before: start)
            let rightOK = isBoundary(source, at: k)
                || (source.index(k, offsetBy: -1, limitedBy: start).map { source[$0] == delim } ?? false)
            if !(leftOK && rightOK) {
                j = source.index(after: j); continue
            }
            _ = allowItalicInside
            return start..<k
        }
        return nil
    }

    private static func isBoundary(_ s: String, before i: String.Index) -> Bool {
        guard let prev = s.index(i, offsetBy: -1, limitedBy: s.startIndex), prev >= s.startIndex else { return true }
        let ch = s[prev]
        return ch.isWhitespace || ch.isNewline || isPunctuation(ch)
    }

    private static func isBoundary(_ s: String, at i: String.Index) -> Bool {
        guard i < s.endIndex else { return true }
        let ch = s[i]
        return ch.isWhitespace || ch.isNewline || isPunctuation(ch)
    }

    private static func isAlphanumeric(_ s: String, before i: String.Index) -> Bool {
        guard let prev = s.index(i, offsetBy: -1, limitedBy: s.startIndex), prev >= s.startIndex else { return false }
        return s[prev].isLetter || s[prev].isNumber
    }

    private static func isPunctuation(_ ch: Character) -> Bool {
        // CommonMark punctuation: набор ASCII-символов, которые могут
        // экранироваться. Сюда же добавим скобки/звёздочки — без этого
        // экранирование не работало бы.
        switch ch {
        case "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/",
             ":", ";", "<", "=", ">", "?", "@", "[", "\\", "]", "^", "_", "`", "{", "|",
             "}", "~":
            return true
        default:
            return false
        }
    }

    /// Внутренний снимок набора активных марок при проходе по инлайну.
    private struct MarkSet {
        var bold = false
        var italic = false
        var strike = false
        var code = false
        var link: String? = nil
    }
}

// ═══════════ [NoteBlock] → Markdown ═══════════
//
// Зеркало парсера: тот же набор блоков и марок, обратное направление.
// Используется и при сохранении документа, и при миграции TipTap-JSON
// (TipTapToMarkdown переводит AST в markdown, а не сохраняет напрямую —
// чтобы можно было положиться на единый кодер для всего).
//
// Чего осознанно НЕ делает:
//   • underline / highlight → НЕ кодируются (Obsidian-специфика, см.
//     комментарий у `MarkdownParser.parse`). Если в AST они остались после
//     миграции старых TipTap-заметок, текст просто выйдет без марки — потери
//     отмечены в карточке LOCK-142.
//   • tables → кодируются как обычный текст по ячейкам (TipTapToMarkdown
//     сам решает, как именно раскладывать; см. там).
//   • nested blockquote не поддерживается — TipTap у нас их не создаёт.

enum MarkdownEncoder {

    static func encode(_ blocks: [NoteBlock]) -> String {
        var out: [String] = []
        for block in blocks {
            switch block.kind {
            case .paragraph:
                out.append(encodeInline(block.runs))

            case .heading(let level):
                let hashes = String(repeating: "#", count: max(1, min(level, 3)))
                out.append("\(hashes) \(encodeInline(block.runs))")

            case .bulletItem:
                let indent = String(repeating: "  ", count: block.level)
                out.append("\(indent)- \(encodeInline(block.runs))")

            case .orderedItem:
                let indent = String(repeating: "  ", count: block.level)
                out.append("\(indent)1. \(encodeInline(block.runs))")

            case .taskItem(let checked):
                let indent = String(repeating: "  ", count: block.level)
                let mark = checked ? "[x]" : "[ ]"
                out.append("\(indent)- \(mark) \(encodeInline(block.runs))")

            case .blockquote:
                // Каждая строка текста получает свой `>` — чтобы переносы внутри
                // цитаты не терялись при повторном парсинге.
                let body = encodeInline(block.runs)
                let quoted = body.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "> \($0)" }
                    .joined(separator: "\n")
                out.append(quoted)

            case .horizontalRule:
                out.append("---")

            case .codeBlock(let language):
                let lang = language ?? ""
                let body = block.runs.first?.text ?? ""
                out.append("```\(lang)\n\(body)\n```")

            case .table:
                // Таблица сериализуется плоско: каждая ячейка = параграф
                // с пометкой (TipTapToMarkdown делает свой формат, тут мы
                // оставляем заглушку чтобы не потерять текст совсем).
                for row in tableRows(block) {
                    for cell in row.cells {
                        out.append(encodeInline(cell.runs))
                    }
                }
            }
        }
        // Блоки разделяются пустой строкой — CommonMark.
        return out.joined(separator: "\n\n")
    }

    /// Прогон → строка с экранированием спецсимволов маркдауна в обычном
    /// тексте (но НЕ внутри `code`/url — там содержимое литерально).
    static func encodeInline(_ runs: [RichRun]) -> String {
        var out = ""
        for run in runs {
            if run.code {
                out.append("`\(run.text)`")
                continue
            }
            if let href = run.linkHref, !href.isEmpty {
                let label = applyMarks(run, escaping: true)
                out.append("[\(label)](\(href))")
                continue
            }
            out.append(applyMarks(run, escaping: true))
        }
        return out
    }

    private static func applyMarks(_ run: RichRun, escaping: Bool) -> String {
        let raw = escaping ? escape(run.text) : run.text
        var s = raw
        if run.italic { s = "*\(s)*" }
        if run.bold { s = "**\(s)**" }
        if run.strike { s = "~~\(s)~~" }
        return s
    }

    /// Экранируем символы, которые в «обычном» инлайне могут начать разметку.
    /// Делается ДО applyMarks — чтобы `*` внутри `**bold**` не экранировался
    /// (это уже разделитель). Внутри `code` и url экранирование не идёт
    /// (см. encodeInline).
    private static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "\\", "`", "*", "_", "{", "}", "[", "]", "(", ")",
                 "#", "+", "-", ".", "!", "|", "<", ">", "~":
                out.append("\\")
                out.append(ch)
            default:
                out.append(ch)
            }
        }
        return out
    }

    private static func tableRows(_ block: NoteBlock) -> [NoteTableRow] {
        if case .table(let rows) = block.kind { return rows }
        return []
    }
}
