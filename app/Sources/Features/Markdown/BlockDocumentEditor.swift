import SwiftUI
import UIKit

// ═══════════ Общий блочный редактор (заметка И описание задачи) ═══════════
//
// Одно и то же поле ввода, одни и те же строки блоков, одна и та же лента
// над клавиатурой — в заметке и в форме задачи. До этого редакторов было
// два: движок заметок (`NoteBlockTextView` + `NoteBlockRow` +
// `NoteEditorViewModel`) и отдельный `MarkdownEditorView` для описания
// задачи с урезанным набором возможностей (без маркеров списков, без
// разбивки блока по Enter, без слияния по Backspace, без подсветки активных
// кнопок и без диктовки). Владелец 13.09.2026: «сделайте один единый формат,
// чтобы блок над клавиатурой вставал точно так же». `MarkdownEditorView`
// удалён, остался этот компонент.
//
// Кто чем владеет:
//   • документ (`[NoteBlock]`) живёт во вью-модели вызывающего экрана и
//     приходит сюда `@Binding`;
//   • структурные правки (Enter/Backspace/тип блока/таблица) — чистые
//     функции `BlockDocumentOps` над `inout [NoteBlock]`, общие для обоих
//     экранов (у заметки их же зовёт `NoteEditorViewModel`, добавляя
//     автосохранение);
//   • лента над клавиатурой — один `MarkdownKeyboardAccessoryHost` на
//     редактор, назначается `inputAccessoryView` каждому `UITextView`.

/// Куда поставить курсор после структурной правки (разбивка блока, слияние,
/// вставка разделителя/строки таблицы). Читает и сбрасывает сам редактор.
struct PendingBlockFocus: Equatable {
    let blockID: UUID
    let position: NoteCursorPosition
}

// MARK: - Операции над документом

/// Структурные правки документа как чистые функции: ничего не знают ни про
/// SwiftUI, ни про сохранение на сервер. Заметка зовёт их из своей
/// вью-модели (и дописывает `scheduleSave()`), описание задачи — прямо из
/// редактора. Раньше эта логика существовала только внутри
/// `NoteEditorViewModel`, из-за чего описание задачи жило без неё вовсе.
enum BlockDocumentOps {
    static func index(of blockID: UUID?, in blocks: [NoteBlock]) -> Int? {
        guard let blockID else { return nil }
        return blocks.firstIndex { $0.id == blockID }
    }

    /// Правка текста блока — приходит и от печати (делегат UITextView), и от
    /// переключателей марок на ленте. `blockID` может быть идентификатором
    /// ЯЧЕЙКИ таблицы: своего блока в документе у неё нет, поэтому разбор
    /// здесь, а не отдельным методом — звонящие знают ровно один id, тот,
    /// что лежит в `NoteEditorFocusState.blockID`.
    static func updateRuns(_ blocks: inout [NoteBlock], blockID: UUID, runs: [RichRun]) {
        if let idx = index(of: blockID, in: blocks) {
            blocks[idx].runs = runs
            return
        }
        updateTableCell(&blocks, cellID: blockID, runs: runs)
    }

    static func toggleHeading(_ blocks: inout [NoteBlock], level: Int, blockID: UUID?) {
        guard let idx = index(of: blockID, in: blocks) else { return }
        if case .heading(let current) = blocks[idx].kind, current == level {
            blocks[idx].kind = .paragraph
        } else {
            blocks[idx].kind = .heading(level: level)
        }
    }

    enum ListToggle { case bullet, ordered, task }

    static func toggleList(_ blocks: inout [NoteBlock], kind: ListToggle, blockID: UUID?) {
        guard let idx = index(of: blockID, in: blocks) else { return }
        let current = blocks[idx].kind
        let isSame: Bool
        switch (kind, current) {
        case (.bullet, .bulletItem), (.ordered, .orderedItem), (.task, .taskItem): isSame = true
        default: isSame = false
        }
        if isSame {
            blocks[idx].kind = .paragraph
            blocks[idx].level = 0
        } else {
            switch kind {
            case .bullet: blocks[idx].kind = .bulletItem
            case .ordered: blocks[idx].kind = .orderedItem
            case .task: blocks[idx].kind = .taskItem(checked: false)
            }
        }
    }

    static func toggleQuote(_ blocks: inout [NoteBlock], blockID: UUID?) {
        guard let idx = index(of: blockID, in: blocks) else { return }
        blocks[idx].kind = (blocks[idx].kind == .blockquote) ? .paragraph : .blockquote
    }

    /// Текст переносится как ЕДИНЫЙ прогон без марок в обе стороны (модель
    /// `NoteBlock` хранит codeBlock так же) — инлайн-форматирование
    /// параграфа при входе в код теряется, ровно как в вебе.
    static func toggleCodeBlock(_ blocks: inout [NoteBlock], blockID: UUID?) {
        guard let idx = index(of: blockID, in: blocks) else { return }
        let block = blocks[idx]
        if case .codeBlock = block.kind {
            blocks[idx].kind = .paragraph
        } else {
            blocks[idx].kind = .codeBlock(language: nil)
        }
        blocks[idx].runs = [RichRun(text: block.plainText)]
    }

    @discardableResult
    static func insertHorizontalRule(_ blocks: inout [NoteBlock], afterBlockID: UUID?) -> PendingBlockFocus? {
        guard let idx = index(of: afterBlockID, in: blocks) else { return nil }
        let hr = NoteBlock(kind: .horizontalRule)
        let paragraph = NoteBlock(kind: .paragraph)
        blocks.insert(contentsOf: [hr, paragraph], at: idx + 1)
        return PendingBlockFocus(blockID: paragraph.id, position: .start)
    }

    static func toggleTaskChecked(_ blocks: inout [NoteBlock], blockID: UUID) {
        guard let idx = index(of: blockID, in: blocks),
              case .taskItem(let checked) = blocks[idx].kind else { return }
        blocks[idx].kind = .taskItem(checked: !checked)
    }

    /// Enter внутри блока — раскладка зависит от типа (см. комментарий у
    /// `NoteBlockTextView.Coordinator.shouldChangeTextIn`; блок кода сюда не
    /// доходит вовсе, перенос там литеральный).
    @discardableResult
    static func handleSplit(_ blocks: inout [NoteBlock], blockID: UUID, atUTF16Offset offset: Int) -> PendingBlockFocus? {
        guard let idx = index(of: blockID, in: blocks) else { return nil }
        let block = blocks[idx]
        let (before, after) = MarkdownText.splitRuns(block.runs, atUTF16Offset: offset)

        switch block.kind {
        case .bulletItem, .orderedItem, .taskItem:
            let beforeEmpty = before.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if beforeEmpty && after.isEmpty {
                // Enter на пустом пункте списка — конвенция редакторов
                // списков: выходим из списка вместо создания пустого пункта.
                blocks[idx].kind = .paragraph
                blocks[idx].level = 0
                return PendingBlockFocus(blockID: block.id, position: .start)
            }
            blocks[idx].runs = before
            var newKind = block.kind
            if case .taskItem = newKind { newKind = .taskItem(checked: false) }
            let newBlock = NoteBlock(kind: newKind, level: block.level, runs: after)
            blocks.insert(newBlock, at: idx + 1)
            return PendingBlockFocus(blockID: newBlock.id, position: .start)

        case .blockquote:
            blocks[idx].runs = before
            let newBlock = NoteBlock(kind: .blockquote, runs: after)
            blocks.insert(newBlock, at: idx + 1)
            return PendingBlockFocus(blockID: newBlock.id, position: .start)

        default:
            // Параграф и заголовок — Enter в заголовке продолжает обычным
            // параграфом, а не повторным заголовком. `horizontalRule` сюда
            // не попадает: у него нет текстового поля.
            blocks[idx].runs = before
            let newBlock = NoteBlock(kind: .paragraph, runs: after)
            blocks.insert(newBlock, at: idx + 1)
            return PendingBlockFocus(blockID: newBlock.id, position: .start)
        }
    }

    /// Backspace на пустом выделении в самом начале блока.
    @discardableResult
    static func handleBackspaceAtStart(_ blocks: inout [NoteBlock], blockID: UUID) -> PendingBlockFocus? {
        guard let idx = index(of: blockID, in: blocks) else { return nil }
        let block = blocks[idx]

        if !isPlainParagraph(block.kind) {
            // Не-параграф — сперва разжаловать в параграф (второй Backspace
            // уже сольёт его с предыдущим блоком). Конвенция Notion/Bear.
            blocks[idx].kind = .paragraph
            blocks[idx].level = 0
            return nil
        }

        guard idx > 0 else { return nil } // первый блок документа — сливать не с чем
        let prevIdx = idx - 1

        if case .horizontalRule = blocks[prevIdx].kind {
            // У разделителя нет текстового поля — Backspace в блоке сразу
            // после него удаляет саму линию, а не «сливается» с ней.
            blocks.remove(at: prevIdx)
            return PendingBlockFocus(blockID: block.id, position: .start)
        }

        let boundary = blocks[prevIdx].runs.reduce(0) { $0 + ($1.text as NSString).length }
        blocks[prevIdx].runs += block.runs
        let prevID = blocks[prevIdx].id
        blocks.remove(at: idx)
        return PendingBlockFocus(blockID: prevID, position: .offset(boundary))
    }

    private static func isPlainParagraph(_ kind: BlockKind) -> Bool {
        if case .paragraph = kind { return true }
        return false
    }

    // MARK: Таблицы

    /// Адрес ячейки в документе. Ищем перебором, а не держим индекс рядом с
    /// фокусом: таблиц в заметке единицы, а лишнее состояние рассинхронится
    /// на первой же правке соседнего блока.
    static func tableLocation(of cellID: UUID, in blocks: [NoteBlock]) -> (block: Int, row: Int, column: Int)? {
        for (blockIdx, block) in blocks.enumerated() {
            guard case .table(let rows) = block.kind else { continue }
            for (rowIdx, row) in rows.enumerated() {
                if let columnIdx = row.cells.firstIndex(where: { $0.id == cellID }) {
                    return (blockIdx, rowIdx, columnIdx)
                }
            }
        }
        return nil
    }

    private static func updateTableCell(_ blocks: inout [NoteBlock], cellID: UUID, runs: [RichRun]) {
        guard let loc = tableLocation(of: cellID, in: blocks),
              case .table(var rows) = blocks[loc.block].kind else { return }
        rows[loc.row].cells[loc.column].runs = runs
        blocks[loc.block].kind = .table(rows: rows)
    }

    /// Новая строка всегда обычная, не шапка: шапка в markdown ровно одна —
    /// первая, и вторая строка-шапка при выгрузке всё равно стала бы обычной.
    @discardableResult
    static func insertTableRow(_ blocks: inout [NoteBlock], below cellID: UUID) -> PendingBlockFocus? {
        guard let loc = tableLocation(of: cellID, in: blocks),
              case .table(var rows) = blocks[loc.block].kind else { return nil }
        let width = max(rows.map(\.cells.count).max() ?? 1, 1)
        let newRow = NoteTableRow(cells: (0..<width).map { _ in NoteTableCell(runs: [], isHeader: false) })
        rows.insert(newRow, at: loc.row + 1)
        blocks[loc.block].kind = .table(rows: rows)
        return PendingBlockFocus(blockID: newRow.cells[min(loc.column, width - 1)].id, position: .start)
    }

    /// Столбец добавляется во ВСЕ строки сразу, иначе таблица станет рваной.
    @discardableResult
    static func insertTableColumn(_ blocks: inout [NoteBlock], after cellID: UUID) -> PendingBlockFocus? {
        guard let loc = tableLocation(of: cellID, in: blocks),
              case .table(var rows) = blocks[loc.block].kind else { return nil }
        for rowIdx in rows.indices {
            let isHeader = rows[rowIdx].cells.first?.isHeader ?? false
            let at = min(loc.column + 1, rows[rowIdx].cells.count)
            rows[rowIdx].cells.insert(NoteTableCell(runs: [], isHeader: isHeader), at: at)
        }
        blocks[loc.block].kind = .table(rows: rows)
        let target = rows[loc.row].cells[min(loc.column + 1, rows[loc.row].cells.count - 1)]
        return PendingBlockFocus(blockID: target.id, position: .start)
    }

    static func deleteTableRow(_ blocks: inout [NoteBlock], containing cellID: UUID) {
        guard let loc = tableLocation(of: cellID, in: blocks),
              case .table(var rows) = blocks[loc.block].kind else { return }
        rows.remove(at: loc.row)
        applyTable(&blocks, rows: rows, at: loc.block)
    }

    static func deleteTableColumn(_ blocks: inout [NoteBlock], containing cellID: UUID) {
        guard let loc = tableLocation(of: cellID, in: blocks),
              case .table(var rows) = blocks[loc.block].kind else { return }
        for rowIdx in rows.indices where loc.column < rows[rowIdx].cells.count {
            rows[rowIdx].cells.remove(at: loc.column)
        }
        rows.removeAll { $0.cells.isEmpty }
        applyTable(&blocks, rows: rows, at: loc.block)
    }

    /// Таблица без строк (или из которой вынули последний столбец) — уже не
    /// таблица: блок уходит целиком. Если он был единственным, на его месте
    /// остаётся пустой параграф — документу без блоков некуда ставить курсор.
    private static func applyTable(_ blocks: inout [NoteBlock], rows: [NoteTableRow], at blockIdx: Int) {
        if rows.isEmpty {
            blocks.remove(at: blockIdx)
            if blocks.isEmpty { blocks = [NoteBlock(kind: .paragraph)] }
        } else {
            blocks[blockIdx].kind = .table(rows: rows)
        }
    }
}

// MARK: - Мост «лента клавиатуры → документ»

/// Лента над клавиатурой живёт в UIKit (`inputAccessoryView`), вне дерева
/// SwiftUI, и создаётся ОДИН раз на редактор — значит её хост не может
/// держать `@Binding` из тела View (тот пересобирается на каждый рендер).
/// Мост — стабильная ссылка: редактор кладёт сюда доступ к своему документу,
/// хост ленты зовёт `mutate` и не знает, чей это документ.
@MainActor
final class BlockDocumentBridge {
    var read: () -> [NoteBlock] = { [] }
    var write: ([NoteBlock]) -> Void = { _ in }
    var setPendingFocus: (PendingBlockFocus?) -> Void = { _ in }

    func mutate(_ body: (inout [NoteBlock]) -> PendingBlockFocus?) {
        var blocks = read()
        let pending = body(&blocks)
        write(blocks)
        if let pending { setPendingFocus(pending) }
    }
}

/// Адаптер документа к общей ленте пометок. Один на оба экрана: раньше у
/// заметок был свой (`NoteEditorKeyboardHost` вокруг `NoteEditorViewModel`),
/// а у карточки задачи — свой, с другим поведением тех же кнопок.
@MainActor
final class BlockDocumentKeyboardHost: MarkdownKeyboardHost {
    private let bridge: BlockDocumentBridge
    private let focus: NoteEditorFocusState
    private let dictation: DictationEngine
    private let dictationEnabled: Bool

    init(
        bridge: BlockDocumentBridge,
        focus: NoteEditorFocusState,
        dictation: DictationEngine = .shared,
        dictationEnabled: Bool = true
    ) {
        self.bridge = bridge
        self.focus = focus
        self.dictation = dictation
        self.dictationEnabled = dictationEnabled
    }

    // MARK: Состояние

    var activeMarks: Set<InlineMark> { focus.activeMarks }

    var currentBlockKind: BlockKind? {
        guard let id = focus.blockID,
              let idx = BlockDocumentOps.index(of: id, in: bridge.read())
        else { return nil }
        return bridge.read()[idx].kind
    }

    var supportsDictation: Bool { dictationEnabled }

    var isRecordingDictation: Bool {
        if case .recording = dictation.recordingState { return true }
        return false
    }

    var dictationLevel: Double { dictation.currentLevel }

    // MARK: Действия

    func toggleMark(_ mark: InlineMark) {
        guard let id = focus.blockID, let ctrl = focus.controller else { return }
        switch mark {
        case .bold: ctrl.toggleBold()
        case .italic: ctrl.toggleItalic()
        case .underline: ctrl.toggleUnderline()
        case .strike: ctrl.toggleStrike()
        case .highlight: ctrl.toggleHighlight()
        case .code: ctrl.toggleCode()
        case .link:
            // Ссылка — отдельный обработчик (нужен URL через prompt), не
            // сводится к «переключить марку»: сам alert живёт на редакторе.
            if let href = ctrl.currentLinkHref, !href.isEmpty {
                ctrl.removeLink()
            } else if ctrl.hasSelection {
                focus.linkPromptText = "https://"
                focus.showLinkPrompt = true
                return // prompt отработает и обновит runs отдельным путём
            } else {
                return
            }
        }
        focus.activeMarks = ctrl.activeMarks
        let runs = ctrl.currentRuns()
        bridge.mutate { blocks in
            BlockDocumentOps.updateRuns(&blocks, blockID: id, runs: runs)
            return nil
        }
    }

    func setBlockKind(_ kind: BlockKind) {
        guard let id = focus.blockID else { return }
        bridge.mutate { blocks in
            switch kind {
            case .heading(let level):
                BlockDocumentOps.toggleHeading(&blocks, level: level, blockID: id)
            case .bulletItem:
                BlockDocumentOps.toggleList(&blocks, kind: .bullet, blockID: id)
            case .orderedItem:
                BlockDocumentOps.toggleList(&blocks, kind: .ordered, blockID: id)
            case .taskItem:
                BlockDocumentOps.toggleList(&blocks, kind: .task, blockID: id)
            case .blockquote:
                BlockDocumentOps.toggleQuote(&blocks, blockID: id)
            case .codeBlock:
                BlockDocumentOps.toggleCodeBlock(&blocks, blockID: id)
            case .paragraph, .horizontalRule, .table:
                break // не вызывается из ленты
            }
            return nil
        }
    }

    func insertHorizontalRule() {
        let id = focus.blockID
        bridge.mutate { BlockDocumentOps.insertHorizontalRule(&$0, afterBlockID: id) }
    }

    func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    func toggleDictation() async {
        switch dictation.recordingState {
        case .idle, .failed:
            await dictation.startRecording()
        case .recording:
            guard let text = await dictation.stopRecordingAndTranscribe(),
                  let id = focus.blockID, let ctrl = focus.controller
            else { return }
            ctrl.insertPlainParagraph(text)
            let runs = ctrl.currentRuns()
            bridge.mutate { blocks in
                BlockDocumentOps.updateRuns(&blocks, blockID: id, runs: runs)
                return nil
            }
        case .transcribing:
            break
        }
    }
}

// MARK: - Сам редактор

/// Список блоков документа: у каждого свой `UITextView`, у всех — одна и та
/// же лента над клавиатурой. Не заводит ни скролла, ни шапки: вызывающий
/// кладёт его куда хочет — в `ScrollView` (заметка) или в строку `List`
/// (карточка задачи). Отсюда и одинаковый вид на обоих экранах.
struct BlockDocumentEditor: View {
    @Binding var blocks: [NoteBlock]
    /// Фокус, живые метки и запрос ссылки. Снаружи — потому что заметке он
    /// нужен и самой (меню AI работает с выделением в фокусном блоке).
    @Bindable var focus: NoteEditorFocusState
    /// Текст-подсказка в первом блоке пустого документа.
    var placeholder: String?
    var supportsDictation: Bool = true
    /// Переопределение тела применяется только там, где вызывающий явно
    /// просит компактную типографику (описание задачи); заметки её не задают.
    var baseFontOverride: UIFont? = nil
    var textColor: UIColor = UIColor(Color.tfText)
    /// Документ изменился — вызывающий ставит сюда своё сохранение.
    var onEdit: () -> Void = {}

    @State private var controllerStore = NoteBlockControllerStore()
    @State private var accessoryHost: MarkdownKeyboardAccessoryHost?
    @State private var bridge = BlockDocumentBridge()
    @State private var pendingFocus: PendingBlockFocus?
    /// Удаление строки или столбца таблицы ждёт подтверждения: отмены в
    /// редакторе нет вовсе, а вместе со строкой уходит весь её текст.
    @State private var tableDelete: TableDeleteRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                row(for: block)
            }
        }
        .task {
            bridge.read = { blocks }
            bridge.write = { newBlocks in
                blocks = newBlocks
                onEdit()
            }
            bridge.setPendingFocus = { pendingFocus = $0 }
            if accessoryHost == nil {
                accessoryHost = MarkdownKeyboardAccessoryHost(
                    host: BlockDocumentKeyboardHost(
                        bridge: bridge,
                        focus: focus,
                        dictationEnabled: supportsDictation
                    )
                )
            }
        }
        .onChange(of: pendingFocus) { _, pending in
            guard let pending else { return }
            // Строка ещё не успела появиться в SwiftUI-дереве на этот же тик
            // (вставка/удаление блока только что попала в документ) —
            // небольшая отсрочка вместо гонки с `onAppear` новой строки.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                controllerStore.controller(for: pending.blockID).focus(cursorAt: pending.position)
                pendingFocus = nil
            }
        }
        .alert("Адрес ссылки", isPresented: $focus.showLinkPrompt) {
            TextField("https://", text: $focus.linkPromptText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Отмена", role: .cancel) {}
            Button("Применить") { applyLinkFromPrompt() }
        }
        .alert(
            tableDelete?.target == .column ? "Удалить столбец?" : "Удалить строку?",
            isPresented: Binding(get: { tableDelete != nil }, set: { if !$0 { tableDelete = nil } }),
            presenting: tableDelete
        ) { request in
            Button("Отмена", role: .cancel) { tableDelete = nil }
            Button("Удалить", role: .destructive) {
                mutate { blocks in
                    switch request.target {
                    case .row: BlockDocumentOps.deleteTableRow(&blocks, containing: request.cellID)
                    case .column: BlockDocumentOps.deleteTableColumn(&blocks, containing: request.cellID)
                    }
                    return nil
                }
                tableDelete = nil
            }
        } message: { request in
            Text(request.target == .column
                 ? "Столбец исчезнет во всех строках вместе с текстом. Действие нельзя отменить."
                 : "Строка исчезнет вместе с текстом. Действие нельзя отменить.")
        }
    }

    @ViewBuilder
    private func row(for block: NoteBlock) -> some View {
        // Таблица — единственный блок, у которого текстовых полей много (по
        // одному на ячейку), поэтому она не проходит через `NoteBlockRow` с
        // его единственным контроллером, а берёт из `controllerStore` по
        // контроллеру на ячейку.
        if case .table(let rows) = block.kind {
            NoteTableBlock(
                rows: rows,
                controllerStore: controllerStore,
                accessoryView: accessoryHost?.view,
                onChange: updateRuns,
                onFocus: focusCell,
                onBlur: blurCell,
                onMarksChange: { id, marks in if focus.blockID == id { focus.activeMarks = marks } },
                onInsertRow: { cellID in mutate { BlockDocumentOps.insertTableRow(&$0, below: cellID) } },
                onInsertColumn: { cellID in mutate { BlockDocumentOps.insertTableColumn(&$0, after: cellID) } },
                onDeleteRow: { tableDelete = TableDeleteRequest(target: .row, cellID: $0) },
                onDeleteColumn: { tableDelete = TableDeleteRequest(target: .column, cellID: $0) }
            )
            .padding(.vertical, TFSpacing.xs)
        } else {
            NoteBlockRow(
                block: block,
                orderedIndex: orderedIndex(for: block),
                placeholder: placeholderText(for: block),
                controller: controllerStore.controller(for: block.id),
                accessoryView: accessoryHost?.view,
                baseFontOverride: baseFontOverride,
                textColor: textColor,
                onChange: updateRuns,
                onFocus: focusCell,
                onBlur: blurCell,
                onMarksChange: { id, marks in if focus.blockID == id { focus.activeMarks = marks } },
                onSplit: { id, offset in mutate { BlockDocumentOps.handleSplit(&$0, blockID: id, atUTF16Offset: offset) } },
                onBackspaceAtStart: { id in mutate { BlockDocumentOps.handleBackspaceAtStart(&$0, blockID: id) } },
                onToggleChecked: {
                    mutate { blocks in
                        BlockDocumentOps.toggleTaskChecked(&blocks, blockID: block.id)
                        return nil
                    }
                }
            )
        }
    }

    // MARK: - Правки

    private func mutate(_ body: (inout [NoteBlock]) -> PendingBlockFocus?) {
        var copy = blocks
        let pending = body(&copy)
        blocks = copy
        onEdit()
        if let pending { pendingFocus = pending }
    }

    private func updateRuns(_ id: UUID, _ runs: [RichRun]) {
        mutate { blocks in
            BlockDocumentOps.updateRuns(&blocks, blockID: id, runs: runs)
            return nil
        }
    }

    /// Фокус/расфокус текстового поля — общий обработчик для блоков и для
    /// ячеек таблицы: ленте важен только текущий контроллер, а «блок это или
    /// ячейка» разбирает `BlockDocumentOps.updateRuns` по самому id.
    private func focusCell(_ id: UUID, _ controller: NoteBlockTextController) {
        focus.blockID = id
        focus.controller = controller
        focus.activeMarks = controller.activeMarks
    }

    private func blurCell(_ id: UUID) {
        guard focus.blockID == id else { return }
        focus.blockID = nil
        focus.controller = nil
        focus.activeMarks = []
    }

    private func applyLinkFromPrompt() {
        guard let id = focus.blockID, let ctrl = focus.controller else { return }
        let trimmed = focus.linkPromptText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "https://" else { return }
        ctrl.applyLink(href: trimmed)
        focus.activeMarks = ctrl.activeMarks
        updateRuns(id, ctrl.currentRuns())
    }

    // MARK: - Вспомогательное

    /// Подсказка показывается только в первом блоке и только пока документ
    /// пуст целиком — иначе она мигала бы в каждом опустевшем абзаце.
    private func placeholderText(for block: NoteBlock) -> String? {
        guard let placeholder,
              block.id == blocks.first?.id,
              blocks.allSatisfy({ $0.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { return nil }
        return placeholder
    }

    /// Порядковый номер для нумерованного списка — считает соседей того же
    /// уровня НАЗАД от текущего блока до первого «не такого же» соседа.
    private func orderedIndex(for block: NoteBlock) -> Int? {
        guard case .orderedItem = block.kind,
              let idx = blocks.firstIndex(where: { $0.id == block.id })
        else { return nil }
        var count = 1
        var i = idx - 1
        while i >= 0 {
            let b = blocks[i]
            guard case .orderedItem = b.kind, b.level == block.level else { break }
            count += 1
            i -= 1
        }
        return count
    }
}

// MARK: - Строка блока

/// Один блок документа — декорация слева (маркер/номер/чекбокс/полоса
/// цитаты) + сам текстовый движок (`NoteBlockTextView`). Разделитель
/// (`horizontalRule`) — не текстовый блок вовсе, просто линия.
struct NoteBlockRow: View {
    let block: NoteBlock
    let orderedIndex: Int?
    let placeholder: String?
    let controller: NoteBlockTextController
    /// `inputAccessoryView` (лента форматирования + микрофон), один и тот же
    /// объект на все блоки редактора — см. `BlockDocumentEditor.accessoryHost`.
    let accessoryView: UIView?
    let baseFontOverride: UIFont?
    let textColor: UIColor

    let onChange: (UUID, [RichRun]) -> Void
    let onFocus: (UUID, NoteBlockTextController) -> Void
    let onBlur: (UUID) -> Void
    let onMarksChange: (UUID, Set<InlineMark>) -> Void
    let onSplit: (UUID, Int) -> Void
    let onBackspaceAtStart: (UUID) -> Void
    let onToggleChecked: () -> Void

    var body: some View {
        if case .horizontalRule = block.kind {
            Rectangle()
                .fill(Color.tfStroke)
                .frame(height: TFBorder.width)
                .padding(.vertical, TFSpacing.md)
        } else {
            HStack(alignment: .top, spacing: TFSpacing.sm) {
                leading
                ZStack(alignment: .topLeading) {
                    if let placeholder {
                        Text(placeholder)
                            .tfText(.body)
                            .foregroundStyle(Color.tfDim)
                            .allowsHitTesting(false)
                    }
                    NoteBlockTextView(
                        blockID: block.id, runs: block.runs, blockKind: block.kind, controller: controller,
                        accessoryView: accessoryView, baseFontOverride: baseFontOverride, textColor: textColor,
                        onChange: onChange, onFocus: onFocus, onBlur: onBlur, onMarksChange: onMarksChange,
                        onSplit: onSplit, onBackspaceAtStart: onBackspaceAtStart
                    )
                }
            }
            .padding(.leading, CGFloat(block.level) * 18 + quoteBarInset)
            .overlay(alignment: .leading) {
                if case .blockquote = block.kind {
                    Rectangle().fill(Color.tfStroke).frame(width: 3)
                }
            }
            .padding(.vertical, block.kind.isListItem ? 2 : 4)
            .background {
                if case .codeBlock = block.kind {
                    RoundedRectangle(cornerRadius: TFRadius.md).fill(Color.tfCard2)
                        .padding(.vertical, 1)
                }
            }
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch block.kind {
        case .bulletItem:
            Circle().fill(Color.tfSub).frame(width: 5, height: 5).padding(.top, 9)
        case .orderedItem:
            Text("\(orderedIndex ?? 1).")
                .tfText(.body)
                .foregroundStyle(Color.tfSub)
                .frame(minWidth: 20, alignment: .trailing)
        case .taskItem(let checked):
            TFCheckbox(
                isChecked: checked,
                label: checked ? "Снять отметку с пункта" : "Отметить пункт выполненным",
                action: onToggleChecked
            )
        default:
            EmptyView()
        }
    }

    private var quoteBarInset: CGFloat {
        if case .blockquote = block.kind { return TFSpacing.sm }
        return 0
    }
}

/// Что именно сносим из таблицы и от какой ячейки считаем.
struct TableDeleteRequest {
    enum Target { case row, column }
    let target: Target
    let cellID: UUID
}
