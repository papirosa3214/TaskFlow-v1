import Foundation
import SwiftUI

// ═══════════ NotesScreen — единая «База знаний» ═══════════
//
// Была своя рисованная шапка (обходила то, что у `TFScreenHeader.large`
// нет leading-слота под стрелку «Назад») — просьба владельца 03.09.2026
// («шапка кривущая, нужны нативные кнопки») перевела её на `tfNativeHeader`
// + системный `Menu` вместо самодельного `.popover`, тем же приёмом, что
// уже стоит на Today/Settings/Upcoming/Agents. Системная стрелка «Назад»
// подставляется стеком навигации сама — свою больше не рисуем.
public struct NotesScreen: View {
    @State private var viewModel = NotesViewModel()
    @State private var knowledgeQuery = ""
    @State private var knowledgeChunks: [ApiKnowledgeChunk] = []
    @State private var isSearchingKnowledge = false
    @State private var knowledgeSearchError: String?

    /// Открыть сразу на этой папке (её и предков разворачиваем, к ней же
    /// скроллим) — просьба владельца 03.09.2026: шеврон «Документация» у
    /// проекта вёл на общий несвязанный корень Дневника, не на папку,
    /// показанную в превью карточки проекта. `nil` — обычный корень, как раньше.
    private let focusFolderID: Int?
    /// Сценарий центрального «+»: не просто открыть базу, а сразу завести
    /// документ и перейти в его редактор.
    private let startsNewNote: Bool
    @State private var hasStartedNewNote = false

    @State private var showRenameSheet = false
    @State private var renameText = ""
    @State private var showMovePicker = false
    @State private var showDeleteConfirm = false
    @State private var pendingNoteID: String?
    @State private var shareURLs: [URL] = []

    private let apiClient = APIClient()

    private var trimmedKnowledgeQuery: String {
        knowledgeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isKnowledgeSearchActive: Bool { !trimmedKnowledgeQuery.isEmpty }

    public init(focusFolderID: Int? = nil, startsNewNote: Bool = false) {
        self.focusFolderID = focusFolderID
        self.startsNewNote = startsNewNote
    }

    public var body: some View {
        ZStack {
            Color.tfBackground.ignoresSafeArea()

            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    TFErrorBanner(viewModel.foldersErrorMessage)
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                    TFErrorBanner(viewModel.notesErrorMessage)
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                    TFErrorBanner(viewModel.actionErrorMessage)
                        .padding(.horizontal, TFSpacing.screenHorizontal)

                    if isKnowledgeSearchActive {
                        knowledgeSearchContent
                    } else {
                        if viewModel.isCreatingFolder {
                            createFolderRow
                        }

                        if viewModel.isLoading && !viewModel.hasAnyContent {
                            TFLoading(.block)
                                .frame(maxWidth: .infinity)
                        } else if !viewModel.hasAnyContent && !viewModel.isCreatingFolder {
                            TFEmptyState(
                                icon: "book",
                                text: "Документов пока нет\nДокументы складываются в папки — перетаскиванием или сразу при создании.",
                                actionTitle: "Создать документ"
                            ) { Task { await createNoteAndNavigate() } }
                            .padding(.top, TFSpacing.xl)
                        } else {
                            ForEach(viewModel.rows) { row in
                                rowView(row)
                            }
                        }
                    }
                }
                .padding(.vertical, TFSpacing.sm)
            }
            .task {
                await viewModel.load()
                if startsNewNote && !hasStartedNewNote {
                    hasStartedNewNote = true
                    await createNoteAndNavigate()
                }
                guard let focusFolderID else { return }
                expandAncestors(of: focusFolderID)
                // Короткая пауза — дать LazyVStack отрисовать развёрнутые
                // строки, прежде чем скроллить к ним (иначе scrollTo не
                // находит ещё не выложенный id).
                try? await Task.sleep(nanoseconds: 150_000_000)
                withAnimation { proxy.scrollTo("f:\(focusFolderID)", anchor: .top) }
            }
            }
        }
        .tfNativeHeader("База знаний", displayMode: .inline)
        .searchable(
            text: $knowledgeQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Поиск по базе знаний"
        )
        .toolbar {
            if viewModel.isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { viewModel.exitSelecting() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    selectionMenu
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    kebabMenu
                }
            }
        }
        // Редактор берём из общей фабрики маршрутов: пока экран не написан,
        // она отдаёт заглушку, и список заметок от этого не ломается.
        .navigationDestination(item: $pendingNoteID) { id in
            routeDestination(.noteEditor(noteID: id))
        }
        .refreshable {
            await viewModel.loadFolders()
            await viewModel.loadNotes()
        }
        // Поиск использует тот же индекс документов, но результат всегда
        // открывает исходную заметку. Дебаунс бережёт серверный retrieval.
        .task(id: trimmedKnowledgeQuery) {
            guard trimmedKnowledgeQuery.count >= 2 else {
                knowledgeChunks = []
                isSearchingKnowledge = false
                knowledgeSearchError = nil
                return
            }
            isSearchingKnowledge = true
            knowledgeSearchError = nil
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                knowledgeChunks = try await apiClient.knowledgeSearch(query: trimmedKnowledgeQuery)
            } catch is CancellationError {
                return
            } catch {
                knowledgeSearchError = (error as? APIError)?.errorDescription ?? "Не удалось выполнить поиск"
                knowledgeChunks = []
            }
            isSearchingKnowledge = false
        }
        .sheet(isPresented: $showMovePicker) {
            FolderPickerSheet(folders: viewModel.folders, title: "Переместить в папку") { folderID in
                Task { await viewModel.moveSelectedNotes(toFolderID: folderID) }
            }
        }
        .alert("Переименовать папку", isPresented: $showRenameSheet) {
            TextField("Название", text: $renameText)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") { Task { await viewModel.renameSelectedFolder(to: renameText); viewModel.exitSelecting() } }
        }
        .alert("Удалить отмеченное?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) { Task { await viewModel.deleteSelected() } }
        } message: {
            Text(viewModel.deleteConfirmDescription)
        }
    }

    // MARK: - Меню «…» (нативные, см. комментарий в начале файла)

    private var kebabMenu: some View {
        Menu {
            Button { Task { await createNoteAndNavigate() } } label: {
                Label("Создать документ", systemImage: "doc.text")
            }
            Button { viewModel.isCreatingFolder = true } label: {
                Label("Создать папку", systemImage: "folder")
            }
            Button { viewModel.enterSelecting() } label: {
                Label("Выбрать элементы", systemImage: "checklist")
            }
            Button {
                Task {
                    shareURLs = await viewModel.exportAllToMarkdownFiles()
                    if !shareURLs.isEmpty { presentShareSheet(urls: shareURLs) }
                }
            } label: {
                Label("Выгрузить всё в Markdown", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button { viewModel.noteDateOrder = alternateDateOrder } label: {
                Label(alternateDateOrder.title, systemImage: alternateDateOrder.systemImage)
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Ещё")
        .accessibilityLabel("Действия")
    }

    private var alternateDateOrder: NotesDateOrder {
        switch viewModel.noteDateOrder {
        case .newestFirst: .oldestFirst
        case .oldestFirst: .newestFirst
        }
    }

    private var selectionMenu: some View {
        Menu {
            Button {
                renameText = ""
                showRenameSheet = true
            } label: {
                Label("Переименовать", systemImage: "pencil")
            }
            .disabled(!viewModel.canRenameSelection)

            Button { showMovePicker = true } label: {
                Label("Переместить в папку", systemImage: "folder")
            }
            .disabled(viewModel.selectedNoteIDs.isEmpty)

            Button {
                Task {
                    var urls: [URL] = []
                    for id in viewModel.selectedNoteIDs {
                        if let note = viewModel.notes.first(where: { $0.id == id }),
                           let url = await viewModel.exportNoteToMarkdownFile(noteID: id, title: note.title) {
                            urls.append(url)
                        }
                    }
                    shareURLs = urls
                    if !shareURLs.isEmpty { presentShareSheet(urls: shareURLs) }
                }
            } label: {
                Label("Выгрузить в Markdown", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Удалить", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Ещё")
        .disabled(!viewModel.hasSelection)
        .accessibilityLabel("Действия с выбранным")
    }

    // MARK: - Инлайн-форма «Создать папку»

    private var createFolderRow: some View {
        HStack(spacing: TFSpacing.sm) {
            TFTextField("Название папки", text: $viewModel.newFolderName)
            Button(viewModel.isSavingFolder ? "Создаём…" : "Создать") {
                Task { await viewModel.submitCreateFolder() }
            }
            .tfText(.body)
            .foregroundStyle(Color.tfRed)
            .disabled(viewModel.isSavingFolder || viewModel.newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Отмена") { viewModel.isCreatingFolder = false; viewModel.newFolderName = "" }
                .tfText(.body)
                .foregroundStyle(Color.tfSub)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.vertical, TFSpacing.sm)
    }

    // MARK: - Строка дерева

    @ViewBuilder
    private func rowView(_ row: NotesTreeRow) -> some View {
        switch row.kind {
        case .folder(let folder, let noteCount, let latestNote):
            folderRow(row, folder: folder, noteCount: noteCount, latestNote: latestNote)
        case .note(let note):
            noteRow(row, note: note)
        }
    }

    private func folderRow(
        _ row: NotesTreeRow,
        folder: ApiJournalFolder,
        noteCount: Int,
        latestNote: NoteListItem?
    ) -> some View {
        Button {
            if viewModel.isSelecting { viewModel.toggleSelected(row) }
            else { viewModel.toggleExpanded(folder.id) }
        } label: {
            HStack(spacing: TFSpacing.sm) {
                indentGuides(row)
                if viewModel.isSelecting {
                    TFCheckbox(isChecked: viewModel.isSelected(row))
                }
                Image(systemName: viewModel.expandedFolderIDs.contains(folder.id) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.tfDim)
                    .frame(width: 16)
                Image(systemName: "folder")
                    .foregroundStyle(Color.tfSub)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(1)
                    if let latestNote {
                        Text(latestNote.title.isEmpty ? "Документ без названия" : latestNote.title)
                            .tfText(.caption)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(1)
                        Text("Обновлено \(updatedDateText(for: latestNote))")
                            .tfText(.caption)
                            .foregroundStyle(Color.tfDim)
                    } else {
                        Text("Документов пока нет")
                            .tfText(.caption)
                            .foregroundStyle(Color.tfDim)
                    }
                }
                Spacer()
                Text("\(noteCount)")
                    .tfText(.action)
                    .foregroundStyle(Color.tfDim)
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(TFTapRowStyle())
        // Чекбокс внутри строки — индикатор (создаётся без `action` и сам
        // скрыт от VoiceOver), поэтому состояние отметки объявляет кнопка
        // строки: без этого пользователь не слышит, выбрана папка или нет.
        .accessibilityAddTraits(viewModel.isSelecting && viewModel.isSelected(row) ? .isSelected : [])
    }

    private func noteRow(_ row: NotesTreeRow, note: NoteListItem) -> some View {
        Group {
            if viewModel.isSelecting {
                Button { viewModel.toggleSelected(row) } label: { noteRowContent(row, note: note) }
                    .buttonStyle(TFTapRowStyle())
                    // См. комментарий в `folderRow`: состояние отметки несёт
                    // кнопка строки, а не скрытый от VoiceOver чекбокс.
                    .accessibilityAddTraits(viewModel.isSelected(row) ? .isSelected : [])
            } else {
                NavigationLink(value: AppRoute.noteEditor(noteID: note.id)) {
                    noteRowContent(row, note: note)
                }
                .buttonStyle(TFTapRowStyle())
            }
        }
    }

    private func noteRowContent(_ row: NotesTreeRow, note: NoteListItem) -> some View {
        HStack(spacing: TFSpacing.sm) {
            indentGuides(row)
            if viewModel.isSelecting {
                TFCheckbox(isChecked: viewModel.isSelected(row))
            }
            Image(systemName: "doc.text")
                .foregroundStyle(Color.tfDim)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Без названия" : note.title)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                if !note.preview.isEmpty {
                    Text(note.preview)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                }
                Text("Обновлено \(updatedDateText(for: note))")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    /// Направляющие линии вложенности — 18px на уровень (spec «INDENT»).
    /// Упрощение против «уголков» файлового менеджера: рисуем сплошную
    /// вертикальную чёрточку на каждом уровне-предке, у которого после
    /// текущей строки ещё есть соседи (иначе — пусто, как и должно быть
    /// у последнего элемента ветки).
    private func indentGuides(_ row: NotesTreeRow) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<row.depth, id: \.self) { level in
                Rectangle()
                    .fill(level < row.ancestorContinues.count && row.ancestorContinues[level] ? Color.tfStroke : Color.clear)
                    .frame(width: 1)
                    .frame(width: 18)
            }
        }
    }

    private func createNoteAndNavigate() async {
        if let id = await viewModel.createNote() {
            pendingNoteID = id
        }
    }

    private func updatedDateText(for note: NoteListItem) -> String {
        let date = NotesDateOrder.date(of: note)
        guard date != .distantPast else { return "дата неизвестна" }
        return Self.updatedDateFormatter.string(from: date)
    }

    private static let updatedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter
    }()

    // MARK: - Смысловой поиск в той же базе

    @ViewBuilder
    private var knowledgeSearchContent: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            if trimmedKnowledgeQuery.count < 2 {
                TFEmptyState(
                    icon: "magnifyingglass",
                    text: "Введите минимум два символа для поиска по содержимому документов"
                )
            } else if isSearchingKnowledge && knowledgeChunks.isEmpty {
                TFLoading(.block)
            } else if knowledgeChunks.isEmpty && knowledgeSearchError == nil {
                TFEmptyState(
                    icon: "magnifyingglass",
                    text: "Ничего похожего — в базе знаний про это пока не писали"
                )
            } else {
                ForEach(knowledgeChunks) { chunk in
                    knowledgeChunkCard(chunk)
                }
            }

            TFErrorBanner(knowledgeSearchError, variant: .block)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.top, TFSpacing.sm)
    }

    private func knowledgeChunkCard(_ chunk: ApiKnowledgeChunk) -> some View {
        Button {
            if let id = chunk.docId { pendingNoteID = id }
        } label: {
            TFCard {
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    HStack(spacing: TFSpacing.sm) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(chunk.title?.isEmpty == false ? chunk.title! : "Документ")
                                .tfText(.caption)
                                .foregroundStyle(Color.tfText)
                                .lineLimit(1)
                            if let project = chunk.project, !project.isEmpty {
                                Text(project)
                                    .tfText(.caption)
                                    .foregroundStyle(Color.tfSub)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if let score = chunk.score {
                            Text(String(format: "%.0f%%", score * 100))
                                .tfText(.caption)
                                .foregroundStyle(Color.tfDim)
                                .monospacedDigit()
                        }
                    }
                    Text(Self.cleanedKnowledgeSnippet(chunk.text))
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(6)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(TFTapRowStyle())
        .disabled(chunk.docId == nil)
    }

    private static func cleanedKnowledgeSnippet(_ text: String) -> String {
        var body = text
        if body.hasPrefix("---") {
            let parts = body.components(separatedBy: "\n---")
            if parts.count > 1 {
                body = parts.dropFirst().joined(separator: "\n---")
            }
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Разворачивает саму папку и всех её предков по цепочке `parentId` —
    /// иначе целевая папка (и её заметки) остаётся свёрнутой глубоко в
    /// дереве, а `scrollTo` в `.task` выше не находит невыложенную строку.
    private func expandAncestors(of folderID: Int) {
        var current: Int? = folderID
        while let id = current {
            viewModel.expandedFolderIDs.insert(id)
            current = viewModel.folders.first { $0.id == id }?.parentId
        }
    }
}

/// Системный лист «Поделиться» показываем НАПРЯМУЮ, а не через SwiftUI
/// `.sheet`: вложенный в шторку `UIActivityViewController` рисовался серой
/// пустой панелью без действий (жалоба владельца 20.09.2026) — он рассчитан
/// на собственное модальное представление.
private func presentShareSheet(urls: [URL]) {
    guard let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive }),
        let root = scene.keyWindow?.rootViewController
    else { return }
    var top = root
    while let presented = top.presentedViewController { top = presented }
    let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
    if let popover = controller.popoverPresentationController {
        popover.sourceView = top.view
        popover.sourceRect = CGRect(
            x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0
        )
        popover.permittedArrowDirections = []
    }
    top.present(controller, animated: true)
}
