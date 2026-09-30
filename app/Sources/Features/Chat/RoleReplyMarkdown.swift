import SwiftUI

/// Ответ роли с разметкой (владелец 27.09.2026, LOCK-230): в 1:1-чате ответ
/// идёт плоским текстом, как в окне Claude Code, и `**жирный**`, списки, код
/// показываются по-человечески, а не звёздочками. Разбор — существующий
/// `MarkdownParser` заметок (только чтение): второго парсера не заводим.
struct RoleReplyMarkdown: View {
    let text: String
    var color: Color = .tfText
    /// Проявление хвоста у идущего ответа (30.09.2026); nil — готовый текст.
    var fade: RoleTextFade?

    var body: some View {
        let segments = ChatRichContent.split(text)
        if segments.count == 1, case .markdown = segments[0] {
            markdownBody(text)
        } else if segments.isEmpty {
            markdownBody(text)
        } else {
            // Таблицы, виджеты и артефакты (владелец 01.10.2026) — своими
            // видами; текст между ними — как раньше. Хвост идущего ответа
            // проявляется по всему тексту, а не у каждого куска отдельно.
            let after = Self.charactersAfterSegments(segments)
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    segmentView(segment, fade: fade?.shifted(by: after[index]))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func charactersAfterSegments(_ segments: [ChatRichSegment]) -> [Int] {
        var result = Array(repeating: 0, count: segments.count)
        var sum = 0
        for index in segments.indices.reversed() {
            result[index] = sum
            sum += ChatRichContent.characterCount(segments[index])
        }
        return result
    }

    @ViewBuilder
    private func segmentView(_ segment: ChatRichSegment, fade: RoleTextFade?) -> some View {
        switch segment {
        case .markdown(let part):
            RoleReplyMarkdown(text: part, color: color, fade: fade)
        case .table(let table):
            ChatTableView(table: table, color: color)
        case .widget(let json):
            ChatWidgetView(json: json)
        case .html(let html):
            ChatHTMLView(html: html)
        case .pending(let kind):
            HStack(spacing: TFSpacing.sm) {
                ProgressView()
                Text(kind == .html ? "Собираю интерактив…" : "Готовлю виджет…")
                    .font(.subheadline)
                    .foregroundStyle(Color.tfSub)
            }
            .padding(TFSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.xl))
        }
    }

    @ViewBuilder
    private func markdownBody(_ text: String) -> some View {
        let blocks = Self.numbered(MarkdownParser.parse(text))
        let after = fade == nil ? [] : Self.charactersAfter(blocks.map(\.block))
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            // Индекс, а не id блока: парсер раздаёт новые UUID на каждый
            // разбор, а живой текст разбирается заново каждые 150 мс.
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, item in
                blockView(item.block, number: item.number, fade: fade?.shifted(by: after[index]))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Сколько символов идёт после каждого блока — хвост проявляется по
    /// всему тексту, а не у каждого абзаца отдельно.
    static func charactersAfter(_ blocks: [NoteBlock]) -> [Int] {
        var result = Array(repeating: 0, count: blocks.count)
        var sum = 0
        for index in blocks.indices.reversed() {
            result[index] = sum
            sum += blocks[index].runs.reduce(0) { $0 + $1.text.count } + 1
        }
        return result
    }

    /// Номер у пунктов нумерованного списка: подряд идущие на одном уровне.
    static func numbered(_ blocks: [NoteBlock]) -> [(block: NoteBlock, number: Int)] {
        var counters: [Int: Int] = [:]
        var result: [(NoteBlock, Int)] = []
        for block in blocks {
            if case .orderedItem = block.kind {
                let next = (counters[block.level] ?? 0) + 1
                counters[block.level] = next
                counters = counters.filter { $0.key <= block.level }
                result.append((block, next))
            } else {
                if !block.kind.isListItem { counters = [:] }
                result.append((block, 0))
            }
        }
        return result
    }

    @ViewBuilder
    private func blockView(_ block: NoteBlock, number: Int, fade: RoleTextFade?) -> some View {
        switch block.kind {
        case .paragraph:
            inline(block.runs, fade: fade)
        case .heading(let level):
            inline(block.runs, fade: fade)
                .font(level <= 1 ? .title3.weight(.semibold) : .headline)
                .padding(.top, TFSpacing.xs)
        case .bulletItem:
            listRow(marker: Text("•"), block: block, fade: fade)
        case .orderedItem:
            listRow(marker: Text("\(number)."), block: block, fade: fade)
        case .taskItem(let checked):
            listRow(marker: Text(Image(systemName: checked ? "checkmark.square" : "square")), block: block, fade: fade)
        case .blockquote:
            HStack(alignment: .top, spacing: TFSpacing.sm) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.tfStroke)
                    .frame(width: 3)
                inline(block.runs, fade: fade)
                    .foregroundStyle(Color.tfSub)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .codeBlock:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.runs.map(\.text).joined())
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(color)
                    .roleReveal(fade)
                    .padding(TFSpacing.md)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tfCard)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
        case .horizontalRule:
            Divider()
        case .table:
            // Из текста таблицы парсер не собирает (только из заметок) —
            // таблицы ответа разбирает ChatRichContent. На всякий случай
            // показываем строки текстом.
            Text(block.runs.map(\.text).joined())
                .foregroundStyle(color)
        }
    }
}

/// Таблица из ответа роли (`| a | b |`): шапка, чередование строк,
/// выравнивание колонок из строки-разделителя, горизонтальная прокрутка для
/// широких таблиц. Ячейки понимают инлайн-разметку (**жирный**, `код`, ссылки).
struct ChatTableView: View {
    let table: ChatTable
    var color: Color = .tfText

    /// Шире — перенос строки внутри ячейки, а не бесконечная колонка.
    private static let maxCellWidth: CGFloat = 220

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Модификатор на самом GridRow превратил бы строку в одну
                // ячейку — фон задаётся каждой ячейке.
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, title in
                        cell(title, column: column, background: Color.tfCard2)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, value in
                            cell(value, column: column,
                                 background: rowIndex.isMultiple(of: 2) ? Color.clear : Color.tfCard2.opacity(0.45))
                                .font(.subheadline)
                        }
                    }
                }
            }
            .background(Color.tfCard)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: TFRadius.lg).strokeBorder(Color.tfStroke, lineWidth: TFBorder.width))
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func cell(_ text: String, column: Int, background: Color) -> some View {
        let alignment = column < table.alignments.count ? table.alignments[column] : .leading
        return Text(RoleReplyMarkdown.attributed(MarkdownParser.parseInline(text)))
            .foregroundStyle(color)
            .multilineTextAlignment(alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: Self.maxCellWidth,
                   alignment: alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
            .padding(.horizontal, TFSpacing.md)
            .padding(.vertical, TFSpacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
            .background(background)
            .gridColumnAlignment(alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
    }

    private func listRow(marker: Text, block: NoteBlock, fade: RoleTextFade?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            marker
                .foregroundStyle(Color.tfSub)
                .frame(minWidth: 14, alignment: .trailing)
            inline(block.runs, fade: fade)
        }
        .padding(.leading, CGFloat(block.level) * TFSpacing.lg)
    }

    private func inline(_ runs: [RichRun], fade: RoleTextFade?) -> some View {
        Text(Self.attributed(runs))
            .foregroundStyle(color)
            .roleReveal(fade)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Прогоны с марками → `AttributedString`: жирный/курсив/код/зачёркнутый
    /// через `inlinePresentationIntent` (его понимает `Text`), ссылка — `link`.
    static func attributed(_ runs: [RichRun]) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            var intent: InlinePresentationIntent = []
            if run.bold { intent.insert(.stronglyEmphasized) }
            if run.italic { intent.insert(.emphasized) }
            if run.code { intent.insert(.code) }
            if run.strike { intent.insert(.strikethrough) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if run.underline { piece.underlineStyle = .single }
            if let href = run.linkHref, let url = URL(string: href) { piece.link = url }
            result += piece
        }
        return result
    }
}
