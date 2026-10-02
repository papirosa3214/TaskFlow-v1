import Foundation

/// Ответ роли, разложенный на куски, которые рисуются по-разному
/// (владелец 01.10.2026: таблицы, виджеты и «артефакты прямо в окне чата»).
///
/// Разбор нарочно отдельный от `MarkdownParser`: тот общий с заметками, и
/// таблица или html-блок, собранные им, при сохранении заметки превратились
/// бы в плоский текст. Здесь только чтение ответа роли.
///
/// Куски:
///   • `markdown` — обычный текст, дальше его разбирает `MarkdownParser`;
///   • `table` — таблица GitHub-вида (`| a | b |` + строка `|---|---|`);
///   • `widget` — блок ```widget с JSON: нативная карточка (`ChatWidgetView`);
///   • `html` — блок ```html: живой интерактивный артефакт (`ChatHTMLView`);
///   • `pending` — такой блок ещё дописывается (идущий ответ), вместо сырого
///     JSON/HTML показываем заглушку.
enum ChatRichSegment: Equatable {
    case markdown(String)
    case table(ChatTable)
    case widget(String)
    case html(String)
    case pending(ChatPendingKind)
}

enum ChatPendingKind: Equatable {
    case widget
    case html
}

struct ChatTable: Equatable {
    enum Alignment: Equatable { case leading, center, trailing }
    var header: [String]
    var alignments: [Alignment]
    var rows: [[String]]

    var columnCount: Int { header.count }
}

enum ChatRichContent {
    /// Языки блоков кода, которые рисуются артефактом, а не кодом.
    static let htmlLanguages: Set<String> = ["html", "artifact"]
    static let widgetLanguages: Set<String> = ["widget", "tf-widget"]

    static func split(_ text: String) -> [ChatRichSegment] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var segments: [ChatRichSegment] = []
        var buffer: [String] = []

        func flush() {
            let joined = buffer.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.markdown(joined))
            }
            buffer = []
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
                // Конец блока — строка, начинающаяся с ```.
                var j = i + 1
                while j < lines.count, !lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("```") { j += 1 }
                let closed = j < lines.count
                let body = lines[(i + 1)..<min(j, lines.count)].joined(separator: "\n")
                let special: ChatPendingKind? = htmlLanguages.contains(language)
                    ? .html
                    : widgetLanguages.contains(language) ? .widget : nil
                if let special {
                    flush()
                    if !closed {
                        segments.append(.pending(special))
                    } else {
                        segments.append(special == .html ? .html(body) : .widget(body))
                    }
                    i = closed ? j + 1 : lines.count
                    continue
                }
                // Обычный код — целиком в текст, таблицы внутри не ищем.
                let end = closed ? j : lines.count - 1
                buffer.append(contentsOf: lines[i...end])
                i = end + 1
                continue
            }

            if i + 1 < lines.count, isTableRow(line), let alignments = separatorAlignments(lines[i + 1]) {
                let header = cells(line)
                if header.count == alignments.count {
                    flush()
                    var rows: [[String]] = []
                    var j = i + 2
                    while j < lines.count, isTableRow(lines[j]) {
                        var row = cells(lines[j])
                        if row.count < header.count { row += Array(repeating: "", count: header.count - row.count) }
                        rows.append(Array(row.prefix(header.count)))
                        j += 1
                    }
                    segments.append(.table(ChatTable(header: header, alignments: alignments, rows: rows)))
                    i = j
                    continue
                }
            }

            buffer.append(line)
            i += 1
        }
        flush()
        return segments
    }

    /// Строка таблицы — есть хотя бы одна `|` вне начала/конца или она
    /// обрамлена `|` с обеих сторон.
    static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        return trimmed.hasPrefix("|") || cells(trimmed).count > 1
    }

    /// Ячейки строки: без крайних `|`, с учётом экранированного `\|`.
    static func cells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") && !trimmed.hasSuffix("\\|") { trimmed.removeLast() }
        var result: [String] = []
        var current = ""
        var escaped = false
        for ch in trimmed {
            if escaped {
                current.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "|" {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    /// Строка-разделитель `|:---|:---:|---:|` → выравнивания колонок.
    static func separatorAlignments(_ line: String) -> [ChatTable.Alignment]? {
        guard line.contains("-") else { return nil }
        let parts = cells(line)
        var result: [ChatTable.Alignment] = []
        for part in parts {
            let p = part.replacingOccurrences(of: " ", with: "")
            guard !p.isEmpty, p.allSatisfy({ $0 == "-" || $0 == ":" }), p.contains("-") else { return nil }
            let left = p.hasPrefix(":")
            let right = p.hasSuffix(":")
            result.append(left && right ? .center : right ? .trailing : .leading)
        }
        return result.isEmpty ? nil : result
    }

    /// Сколько символов текста в куске — для проявления хвоста идущего ответа.
    static func characterCount(_ segment: ChatRichSegment) -> Int {
        switch segment {
        case .markdown(let text): return text.count + 1
        case .table(let table): return (table.header + table.rows.flatMap { $0 }).reduce(0) { $0 + $1.count }
        case .widget, .html, .pending: return 0
        }
    }
}
