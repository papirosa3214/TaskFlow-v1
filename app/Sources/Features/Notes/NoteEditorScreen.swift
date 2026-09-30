import SwiftUI
import UIKit

// ═══════════ NoteEditorScreen — редактор заметки (spec/SCREENS-2.md §2) ═══════════
//
// Имя и параметр — контракт `INTEGRATION.md` буквально: `NoteEditorScreen(noteID:)`.
//
// Архитектура тела: документ соседа (`NoteDocument.swift`) — плоский массив
// `[NoteBlock]`, поэтому редактор — это СПИСОК блоков, у каждого свой
// `UITextView` (`NoteBlockTextView.swift`), а не один текстовый холст на
// весь документ. Из этого решения вытекают все упрощения ниже (названы по
// месту): выделение для меню AI не переходит границы блока, «пересечь Enter
// два блока одним нажатием» невозможно и т.п. — компромисс в пользу того,
// что формат хранения (JSON блоков-с-прогонами) остаётся честным зеркалом
// TipTap-документа веба, без придумывания промежуточного формата.
struct NoteEditorScreen: View {
    let noteID: String

    @State private var viewModel: NoteEditorViewModel
    @Environment(\.dismiss) private var dismiss

    /// Фокус блока, живые метки форматирования и запрос ссылки — теперь на
    /// отдельном `@Observable`, не здесь: `MarkdownKeyboardAccessoryBar` (лента
    /// форматирования + микрофон) с 03.09.2026 живёт ВНЕ дерева этого экрана,
    /// как `inputAccessoryView` каждого блочного `UITextView` (см.
    /// `NoteBlockTextView.swift`) — обычный `@State` этого View ей не виден,
    /// нужен общий объект-ссылка. Подробности — `NoteEditorFocusState`.
    @State private var focus = NoteEditorFocusState()

    @State private var showMovePicker = false
    @State private var showDeleteConfirm = false

    init(noteID: String) {
        self.noteID = noteID
        self._viewModel = State(initialValue: NoteEditorViewModel(noteID: noteID))
    }

    var body: some View {
        // Урок 2026-09-25 (чёрные треугольники в углах системной клавиатуры,
        // iOS 26): фон нужен ОДНИМ слоем на самом верху тела экрана, через
        // `ZStack` + `.ignoresSafeArea()` без ограничения edges (регион
        // `.keyboard` входит в `.all` по умолчанию) — не через `.background`
        // на внутреннем контейнере, до угла клавиатуры он не достаёт.
        ZStack {
            Color.tfBackground.ignoresSafeArea()
            content
        }
        // Раньше формат-панель сидела статично у верха экрана, а микрофон
        // плавал `.overlay` отдельным кружком поверх текста — владелец
        // 03.09.2026: «прилепить ленту к верху клавиатуры» + на живом
        // устройстве (не симулятор) кружок микрофона рисовался ТРЁМЯ копиями
        // сразу, пока открыта клавиатура (скриншот). Первая попытка чинить
        // это через `.safeAreaInset(edge: .bottom)` не решила дело: это
        // всё ещё СВОЙ, SwiftUI-уровня слой, который клавиатура не двигает
        // как часть себя — он просто пере-анимируется отдельно и в моменте
        // выглядит как «две клавиатуры» (владелец, тем же вечером: «панель
        // тоже двигается... а такого не должно быть»). Правильный нативный
        // способ — реальный `inputAccessoryView` каждого блочного
        // `UITextView` (см. `NoteBlockTextView.swift`, `accessoryHost`
        // ниже): тогда лента — буквально часть клавиатуры для UIKit,
        // отдельного слоя для рассинхронизации просто не существует.
        // Была своя ZStack-шапка (крестик, «✨», «…» в попапах) поверх ещё и
        // системного .navigationTitle(.large) — та же двойная шапка, что
        // чинили весь день (просьба владельца 03.09.2026: «нативные кнопки
        // везде одним элементом»). Теперь tfNativeHeader + toolbar, попапы —
        // нативный Menu, тем же приёмом, что у фильтров «Сегодня».
        //
        // ⚠️ Изначально AI и «Ещё» были ДВУМЯ отдельными ToolbarItem с Menu
        // (как задумано по спеке — разные пиктограммы). На живом кадре
        // (iOS 26.5 Simulator) это давало два бага сразу: заголовок «Новая
        // заметка» пропадал целиком, а иконка каждого Menu отрисовывалась
        // счетверённо/строенно в схлопнутом виде (проверено idb describe-all:
        // в дереве доступности реально ОДНА кнопка — это чисто рендер-баг
        // «Liquid Glass» тулбара на запушенном .inline экране, не логическая
        // ошибка; смена содержимого меню, задержка скриншота на 8+ сек и
        // прямой тап по иконке — на исход не влияли, тап открывал меню
        // корректно). Баг воспроизводится и с одним-единственным Menu-айтемом
        // в toolbar этого пуш-экрана — то есть дело не в паре соседних Menu.
        // Слияние в один Menu не убирает баг отрисовки иконки, но убирает
        // пропажу заголовка (в один Menu упирается тот же приём, что у
        // рабочего kebabMenu в NotesScreen.swift) — берём это компромиссом,
        // как более лёгкий вариант, чем два отдельных Menu.
        // Было имя самой заметки (спека §2: «заголовком становится первый
        // непустой блок… или "Новая заметка"») — владелец 03.09.2026:
        // «между кнопкой назад и троеточием не название заметки, а раздел
        // «База знаний» — то же название, что у списка документов; название
        // самой заметки намеренно не дублируется в системной шапке.
        .tfNativeHeader("База знаний", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { combinedMenu }
        }
        .task { await viewModel.load() }
        .onDisappear { viewModel.flushOnExit() }
        .alert("Удалить заметку\(deleteTitleSuffix)?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) { Task { await performDelete() } }
        } message: {
            Text("Действие нельзя отменить.")
        }
        .sheet(isPresented: $showMovePicker) {
            FolderPickerSheet(folders: viewModel.folders, title: "Переместить в папку") { folderID in
                Task { await viewModel.moveToFolder(folderID) }
            }
        }
        .tfBottomSheet(isPresented: $viewModel.showExtractedTasksSheet, title: "Задачи из текста") {
            NoteExtractedTasksSheetContent(tasks: viewModel.extractedTasks) {
                viewModel.showExtractedTasksSheet = false
            }
        }
        .sheet(item: Binding(
            get: { viewModel.createdDraftTask.map { DraftTaskRef(id: $0.taskID) } },
            set: { if $0 == nil { viewModel.createdDraftTask = nil } }
        )) { ref in
            NavigationStack { TaskFormScreen(taskID: ref.id) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private struct DraftTaskRef: Identifiable { let id: String }

    // MARK: - Тело

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.document.blocks.count <= 1 && viewModel.document.isEffectivelyEmpty {
            TFLoading(.block)
            Spacer()
        } else {
            TFErrorBanner(viewModel.loadErrorMessage)
                .padding(.horizontal, TFSpacing.screenHorizontal)
            TFErrorBanner(viewModel.aiErrorMessage, variant: .block)
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.top, TFSpacing.xs)
            TFErrorBanner(viewModel.actionErrorMessage)
                .padding(.horizontal, TFSpacing.screenHorizontal)
            // «Идёт процесс»: долгие AI-операции (постановка, разбор, ассист)
            // держат модель десятки секунд, и без видимого сигнала это
            // выглядит как «нажал — тишина, пустота» (жалоба владельца
            // 20.09.2026). Спиннер с подписью и есть этот сигнал.
            if viewModel.aiBusy {
                HStack(spacing: TFSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(viewModel.aiLabel)
                        .tfText(.action)
                        .foregroundStyle(Color.tfText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, TFSpacing.md)
                .padding(.vertical, TFSpacing.sm)
                .background(Color.tfCard2)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.top, TFSpacing.xs)
                .transition(.opacity)
            }
            // Статус сохранения ниже — ОВЕРЛЕЕМ, не строкой стека. Строкой он
            // сначала резервировал полоску ~20pt всегда, потом (03.09.2026)
            // появлялся только при непустом тексте — и именно это добивало:
            // на каждое нажатие клавиши строка влезала в стек и обратно,
            // раскладка экрана дёргалась, внизу мигала чёрная полоса, а
            // тулбар «Liquid Glass» на перестройке дублировал свою кнопку
            // «…» (владелец 08.09.2026: «слева пилюлина с двумя
            // троеточиями… внизу полоска чёрная появляется» — проверено
            // кадром: без статуса кнопка одна, с ним две). Оверлей
            // размеров хоста не меняет, перестраивать нечего.
            editorBody
                .overlay(alignment: .bottom) { saveStatusBadge }
                .animation(.easeInOut(duration: 0.2), value: viewModel.statusLabel)
        }
    }

    /// Подтверждение сохранения. Ошибку не гасим по таймеру — она состояние,
    /// а не уведомление (гашение делает `NoteEditorViewModel`, здесь только
    /// вид). Не перехватывает тапы: под ней живой текст.
    @ViewBuilder
    private var saveStatusBadge: some View {
        if !viewModel.statusLabel.isEmpty {
            Text(viewModel.statusLabel)
                .tfText(.caption)
                .foregroundStyle(viewModel.saveState == .error ? Color.tfRed : Color.tfDim)
                .padding(.horizontal, TFSpacing.md)
                .padding(.vertical, TFSpacing.xs)
                .background(.ultraThinMaterial, in: Capsule())
                // Лента форматирования — `inputAccessoryView`, слой UIKit
                // ПОВЕРХ SwiftUI: в safe area он не входит, и плашка без
                // этой добавки наполовину прячется под ним (проверено
                // кадром 08.09.2026). Признак «лента на экране» — есть ли
                // сфокусированное поле, другого у SwiftUI тут нет.
                .padding(.bottom, (focus.blockID != nil ? MarkdownKeyboardAccessoryHost.height : 0) + TFSpacing.sm)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// Тело редактора — общий `BlockDocumentEditor` (тот же компонент стоит в
    /// описании задачи, см. `TaskFormScreen`): строки блоков, лента над
    /// клавиатурой, разбивка по Enter и слияние по Backspace живут там.
    /// Экрану заметки остаются скролл, отступы и сохранение.
    private var editorBody: some View {
        ScrollView {
            BlockDocumentEditor(
                blocks: $viewModel.document.blocks,
                focus: focus,
                placeholder: "Пишите здесь что угодно…",
                onEdit: { viewModel.documentDidChange() }
            )
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.vertical, TFSpacing.sm)
            .padding(.bottom, TFSpacing.xl * 2)
        }
        .scrollDismissesKeyboard(.interactively)
        // Тот же системный ScrollEdgeEffect (iOS 26), что уже выключали в
        // чате (`ChatVoiceComposer.swift`, 26.09.2026: «какая-то подложка/
        // повидла») и в карточке задачи (LOCK-254, 30.09.2026) — здесь он
        // был всё это время незамеченным: `BlockDocumentEditor` даёт свою
        // ленту над клавиатурой с самого начала (LOCK-140/141), а отключение
        // эффекта сюда никогда не доезжало.
        .hideComposerScrollEdgeEffect()
        // ScrollView, в отличие от List в карточке задачи (LOCK-254 правка г),
        // своего фона не имел вовсе — фон экрана на `content` (строка 40) не
        // дотягивался до зоны под клавиатурным аксессуаром, и там просвечивал
        // системный чёрный (владелец 30.09.2026, кадр «База знаний»: чёрная
        // полоса над лентой форматирования). Тот же фикс, что уже доказан на
        // List — сплошной фон прямо на самом скролле.
        .background(Color.tfBackground)
    }

    private var deleteTitleSuffix: String {
        let title = viewModel.document.derivedTitle
        return title.isEmpty ? "" : " «\(title)»"
    }

    private var combinedMenu: some View {
        Menu {
            Section("AI") {
                Button { Task { await runAssist(.continueThought) } } label: {
                    Label("Продолжить мысль", systemImage: "pencil.line")
                }
                Button { Task { await runAssist(.shorten) } } label: {
                    Label("Сократить текст", systemImage: "scissors")
                }
                Button { Task { await runAssist(.expand) } } label: {
                    Label("Развить в шаги", systemImage: "list.bullet.indent")
                }
                Button {
                    let selection = focus.controller?.selectedText()
                    Task { await viewModel.runExtractTasks(selectedText: selection) }
                } label: {
                    Label("Собрать задачи из текста", systemImage: "checklist")
                }
                Button {
                    let selection = focus.controller?.selectedText()
                    Task { await viewModel.collectDraft(selectedText: selection) }
                } label: {
                    Label("Собрать постановку", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
            .disabled(viewModel.aiBusy)

            Button { showMovePicker = true } label: {
                Label("Переместить в папку", systemImage: "folder")
            }
            Button { Task { await exportMarkdown() } } label: {
                Label("Выгрузить в Markdown", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Удалить заметку", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Ещё")
    }

    // MARK: - Меню AI / «Ещё» — действия

    /// Есть выделение — правим прямо в textView этого блока (замена на
    /// месте); нет — весь документ (см. `NoteEditorViewModel.runAssist`).
    private func runAssist(_ action: JournalAssistAction) async {
        let hasSelection = focus.controller?.hasSelection ?? false
        let selection = hasSelection ? focus.controller?.selectedText() : nil
        guard let result = await viewModel.runAssist(action, selectedText: selection),
              !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        if hasSelection, let id = focus.blockID, let ctrl = focus.controller {
            ctrl.insertPlainParagraph(result)
            viewModel.updateRuns(blockID: id, runs: ctrl.currentRuns())
        } else {
            viewModel.applyAssistResultToWholeDocument(result, action: action)
        }
    }

    private func exportMarkdown() async {
        guard let url = await viewModel.exportToMarkdownFile() else { return }
        // Показываем системный лист «Поделиться» НАПРЯМУЮ, а не через
        // SwiftUI `.sheet`. Вложенный в шторку `UIActivityViewController`
        // рисовался серой пустой панелью без действий (жалоба владельца
        // 20.09.2026) — он рассчитан на собственное модальное представление.
        presentShareSheet(url: url)
    }

    private func presentShareSheet(url: URL) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.keyWindow?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(
                x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0
            )
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }

    private func performDelete() async {
        if await viewModel.deleteNote() { dismiss() }
    }
}

// MARK: - Таблица

/// Таблица заметки. Ячейка — такой же `NoteBlockTextView`, как обычный блок
/// (свой контроллер из общего `controllerStore`, та же клавиатурная панель),
/// только Enter внутри неё не разбивает блок надвое, а ставит перенос:
/// «следующей ячейки» в плоской модели документа не существует. Правка
/// уезжает в документ через `BlockDocumentOps.updateRuns` — он сам
/// разбирает, блок пришёл или ячейка. Живёт здесь, а не в общем
/// `BlockDocumentEditor`: таблицы есть только в заметках.
///
/// Ширина колонки считается по её САМОМУ ДЛИННОМУ содержимому и зажимается
/// в `minColumn…maxColumn`: раньше все колонки были по 140pt, и колонка
/// порядкового номера с одной цифрой занимала столько же, сколько колонка
/// с абзацем текста (владелец 08.09.2026: «целая прям ячейка здоровенная
/// выделяется для одной циферки»). Тянуть колонки по доступной ширине,
/// как это делает `Grid`, нельзя: одна длинная колонка сплющит остальные в
/// нечитаемые полоски — поэтому таблица шире экрана прокручивается вбок.
struct NoteTableBlock: View {
    let rows: [NoteTableRow]
    let controllerStore: NoteBlockControllerStore
    let accessoryView: UIView?

    let onChange: (UUID, [RichRun]) -> Void
    let onFocus: (UUID, NoteBlockTextController) -> Void
    let onBlur: (UUID) -> Void
    let onMarksChange: (UUID, Set<InlineMark>) -> Void
    let onInsertRow: (UUID) -> Void
    let onInsertColumn: (UUID) -> Void
    let onDeleteRow: (UUID) -> Void
    let onDeleteColumn: (UUID) -> Void

    /// Кегль ячейки — общий с параграфом (`MarkdownText.baseFont`), чтобы
    /// текст в таблице не выглядел вторым сортом; шапка отличается только
    /// начертанием и подложкой.
    private static let cellFontSize: CGFloat = 15
    private static let paddingH = TFSpacing.sm
    private static let paddingV = TFSpacing.xs
    /// Нижняя граница — тап-зона: в колонку уже 44pt пальцем не попасть.
    private static let minColumn: CGFloat = 44
    /// Верхняя — чтобы одна многословная колонка не уезжала на три экрана.
    private static let maxColumn: CGFloat = 220
    private static let minRowHeight: CGFloat = TFHitTarget.min
    private static let handleRailSize: CGFloat = TFHitTarget.min

    /// Строка может вырасти из-за переноса текста. Левая рейка живёт вне
    /// горизонтального ScrollView, поэтому ей нужны фактические высоты строк,
    /// чтобы каждая хваталка оставалась напротив своей строки.
    @State private var rowHeights: [UUID: CGFloat] = [:]

    var body: some View {
        let widths = columnWidths
        HStack(alignment: .top, spacing: 0) {
            rowHandleRail

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    columnHandleRail(widths)
                    tableGrid(widths)
                }
            }
        }
        // Своих DragGesture на рейках нет: тап открывает системный Menu,
        // а движение пальца остаётся штатному ScrollView. Так хваталка не крадёт скролл.
        .onPreferenceChange(NoteTableRowHeightPreferenceKey.self) { heights in
            if rowHeights != heights { rowHeights = heights }
        }
    }

    private var rowHandleRail: some View {
        VStack(spacing: 0) {
            Image(systemName: "tablecells")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: Self.handleRailSize, height: Self.handleRailSize)
                .accessibilityHidden(true)

            ForEach(rows) { row in
                if let cellID = row.cells.first?.id {
                    rowMenu(cellID)
                        .frame(
                            width: Self.handleRailSize,
                            height: max(rowHeights[row.id] ?? Self.minRowHeight, Self.minRowHeight)
                        )
                }
            }
        }
    }

    private func columnHandleRail(_ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(widths.enumerated()), id: \.offset) { index, width in
                if let cellID = firstCell(inColumn: index) {
                    columnMenu(cellID)
                        .frame(width: width, height: Self.handleRailSize)
                } else {
                    Color.clear.frame(width: width, height: Self.handleRailSize)
                }
            }
        }
    }

    private func tableGrid(_ widths: [CGFloat]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(row.cells.enumerated()), id: \.element.id) { index, cell in
                        cellView(cell, width: index < widths.count ? widths[index] : Self.minColumn)
                    }
                }
                .frame(minHeight: Self.minRowHeight, alignment: .top)
                .background(row.cells.first?.isHeader == true ? Color.tfCard2 : Color.clear)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: NoteTableRowHeightPreferenceKey.self,
                            value: [row.id: proxy.size.height]
                        )
                    }
                }
                // Линия между строками; нижняя кромка последней строки
                // приходит из рамки всей таблицы.
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.tfStroke).frame(height: TFBorder.width)
                }
            }
        }
        // Вертикальные линии рисуются поверх ВСЕЙ таблицы, а не рамкой
        // каждой ячейки. Иначе высота линии = высоте своей ячейки, и
        // ради ровной сетки ячейки пришлось бы растягивать
        // `maxHeight: .infinity` — а жадная по высоте строка заставляет
        // VStack делить высоту между строками поровну, и текст с
        // переносом обрезается (ровно это и было видно на «Сохранить
        // результат и историю»).
        .overlay(alignment: .leading) { columnDividers(widths) }
        .overlay {
            RoundedRectangle(cornerRadius: TFRadius.sm)
                .strokeBorder(Color.tfStroke, lineWidth: TFBorder.width)
        }
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.sm))
        .padding(.horizontal, 1)
    }

    private func rowMenu(_ cellID: UUID) -> some View {
        Menu {
            Button {
                tapHaptic()
                onInsertRow(cellID)
            } label: {
                Label("Добавить строку ниже", systemImage: "plus")
            }
            Divider()
            Button(role: .destructive) {
                tapHaptic()
                onDeleteRow(cellID)
            } label: {
                Label("Удалить строку", systemImage: "trash")
            }
        } label: {
            Capsule()
                .fill(Color.tfDim)
                .frame(width: 4, height: 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Меню строки")
        .accessibilityHint("Добавить или удалить эту строку")
    }

    private func columnMenu(_ cellID: UUID) -> some View {
        Menu {
            Button {
                tapHaptic()
                onInsertColumn(cellID)
            } label: {
                Label("Добавить столбец справа", systemImage: "plus")
            }
            Divider()
            Button(role: .destructive) {
                tapHaptic()
                onDeleteColumn(cellID)
            } label: {
                Label("Удалить столбец", systemImage: "trash")
            }
        } label: {
            Capsule()
                .fill(Color.tfDim)
                .frame(width: 22, height: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Меню столбца")
        .accessibilityHint("Добавить или удалить этот столбец")
    }

    private func firstCell(inColumn column: Int) -> UUID? {
        rows.lazy.compactMap { row in
            guard column < row.cells.count else { return nil }
            return row.cells[column].id
        }.first
    }

    private func tapHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func columnDividers(_ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(widths.enumerated()), id: \.offset) { index, width in
                Color.clear
                    .frame(width: width)
                    .overlay(alignment: .trailing) {
                        if index < widths.count - 1 {
                            Rectangle().fill(Color.tfStroke).frame(width: TFBorder.width)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }

    private func cellView(_ cell: NoteTableCell, width: CGFloat) -> some View {
        NoteBlockTextView(
            blockID: cell.id,
            runs: cell.runs,
            blockKind: .paragraph,
            controller: controllerStore.controller(for: cell.id),
            accessoryView: accessoryView,
            baseFontOverride: UIFont.systemFont(ofSize: Self.cellFontSize, weight: cell.isHeader ? .semibold : .regular),
            literalNewline: true,
            onChange: onChange,
            onFocus: onFocus,
            onBlur: onBlur,
            onMarksChange: onMarksChange,
            // Enter до сюда не доходит (`literalNewline`), а Backspace в
            // начале ячейки не должен сливать её с соседней — у таблицы нет
            // «предыдущего блока», в который можно втечь.
            onSplit: { _, _ in },
            onBackspaceAtStart: { _ in }
        )
        .frame(width: width - Self.paddingH * 2, alignment: .topLeading)
        .padding(.horizontal, Self.paddingH)
        .padding(.vertical, Self.paddingV)
        .frame(minHeight: Self.minRowHeight, alignment: .topLeading)
    }

    /// Ширина каждой колонки = самая длинная строка её ячеек плюс поля.
    /// Меряем по тексту без марок: жирный шире обычного на доли пункта, а
    /// заводить ради этого полный `NSAttributedString` на каждый рендер
    /// таблицы дороже, чем добавить пункт запаса.
    private var columnWidths: [CGFloat] {
        let columnCount = rows.map(\.cells.count).max() ?? 0
        guard columnCount > 0 else { return [] }
        var widths = [CGFloat](repeating: Self.minColumn, count: columnCount)
        for row in rows {
            for (index, cell) in row.cells.enumerated() where index < columnCount {
                let font = UIFont.systemFont(ofSize: Self.cellFontSize, weight: cell.isHeader ? .semibold : .regular)
                let longestLine = cell.plainText
                    .components(separatedBy: "\n")
                    .reduce(CGFloat.zero) { max($0, ($1 as NSString).size(withAttributes: [.font: font]).width) }
                widths[index] = max(widths[index], ceil(longestLine) + Self.paddingH * 2 + 2)
            }
        }
        return widths.map { min($0, Self.maxColumn) }
    }
}

private struct NoteTableRowHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

/// Обёртка `UIActivityViewController` для «Выгрузить в Markdown» больше не
/// нужна: лист показывается напрямую из `presentShareSheet` (вложенный в
/// SwiftUI-шторку он рисовался серой пустой панелью).
