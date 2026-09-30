import SwiftUI

/// Фильтр списка заметок проекта по дате последнего изменения.
enum NotesDateFilter: String, CaseIterable, Identifiable {
    case day, week, month, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: "День"
        case .week: "Неделя"
        case .month: "Месяц"
        case .all: "Всё"
        }
    }
    /// Порог «отрезаем всё, что старше». Для `.all` — без отсечения.
    func cutoff(now: Date) -> Date? {
        switch self {
        case .day: now.addingTimeInterval(-24 * 60 * 60)
        case .week: now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .month: now.addingTimeInterval(-30 * 24 * 60 * 60)
        case .all: nil
        }
    }
}

// «Документация» — spec/SCREENS-2.md §8.1, дубль `src/components/ProjectNotes.tsx`
// (чужая папка `src/components/`, не Directory — своя копия, тот же приём
// дублирования, что у всего этого раздела). Источник данных — ОДИН запрос
// `directoryProjectDocs` (`DirectoryAPI.swift`, сервер уже разворачивает
// поддерево папок сам), плюс отдельно список ВСЕХ папок Дневника — он нужен
// только для пикера «Выбрать папку», которого одного запроса не даёт.
//
// Свой `APIClient()` — тот же безопасный приём, что весь остальной проект
// (второй экземпляр без состояния, см. `DirectoryAPI.swift`).
struct ProjectNotesSection: View {
    let project: ApiProject
    /// ProjectTasksScreen передаёт колбэк, который обновляет `notesFolderId`
    /// локально (свежий `ApiProject` из `patchProject`) — сама секция стор
    /// проектов не трогает, только сообщает наверх, что изменилось.
    let onProjectPatched: (ApiProject) -> Void

    @State private var docs: APIClient.DirectoryProjectDocs?
    @State private var allFolders: [ApiJournalFolder] = []
    @State private var isLoading = true
    @State private var busy = false
    @State private var pickerOpen = false
    @State private var detachConfirm = false
    @State private var pendingNoteID: String?
    @State private var errorMessage: String?
    @State private var dateFilter: NotesDateFilter = .all

    private let apiClient = APIClient()

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            HStack {
                Text("Документация")
                    .tfText(.title)
                    .foregroundStyle(Color.tfSub)
                Spacer()
                if docs?.folder != nil {
                    TFIconButton("plus", label: "Добавить документ") { Task { await addNote() } }
                }
            }

            if isLoading {
                TFLoading()
            } else if let folder = docs?.folder {
                folderSection(folder)
            } else {
                emptySection
            }

            TFErrorBanner(errorMessage, variant: .block)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.top, TFSpacing.xl)
        .task { await load() }
        .navigationDestination(item: $pendingNoteID) { id in routeDestination(.noteEditor(noteID: id)) }
        .confirmationDialog("Открепить папку?", isPresented: $detachConfirm, titleVisibility: .visible) {
            Button("Открепить", role: .destructive) { Task { await detach() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Сама папка и документы внутри останутся на месте — в Базе знаний. Здесь просто пропадёт эта секция.")
        }
        .confirmationDialog("Выбрать папку", isPresented: $pickerOpen, titleVisibility: .visible) {
            ForEach(allFolders) { folder in
                Button(folder.name) { Task { await attach(folder.id) } }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: - Папка привязана

    private func folderSection(_ folder: APIClient.DirectoryProjectDocs.FolderRef) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            NavigationLink(value: AppRoute.noteFolder(folderID: folder.id)) {
                HStack(spacing: TFSpacing.sm) {
                    Image(systemName: "folder")
                        .tfText(.title)
                        .foregroundStyle(Color.tfSub)
                    Text(folder.name)
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(1)
                    Spacer()
                    Text("\(filteredNotes.count)")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfDim)
                    Image(systemName: "chevron.right")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                }
                .frame(minHeight: 42)
            }
            .buttonStyle(TFTapRowStyle())

            // Фильтр по дате правки — день / неделя / месяц / всё.
            // Локальный, не дёргает сервер: список заметок уже загружен,
            // `updated_at` есть в каждой записи. На самом деле это и не могло
            // бы быть серверным — папка одна, заметок мало, фильтр тут же.
            if !(docs?.notes ?? []).isEmpty {
                Picker("Обновлены", selection: $dateFilter) {
                    ForEach(NotesDateFilter.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.leading, TFSpacing.lg)
                .padding(.top, TFSpacing.xs)
            }

            if filteredNotes.isEmpty {
                Text(filteredNotesHint)
                    .tfText(.action)
                    .foregroundStyle(Color.tfDim)
                    .padding(.leading, TFSpacing.lg)
            }

            ForEach(filteredNotes) { note in
                Button { pendingNoteID = note.id } label: {
                    HStack(alignment: .top, spacing: TFSpacing.sm) {
                        Image(systemName: "doc.text")
                            .tfText(.input)
                            .foregroundStyle(Color.tfDim)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title.isEmpty ? "Без названия" : note.title)
                                .tfText(.body)
                                .foregroundStyle(Color.tfText)
                                .lineLimit(1)
                            Text(updatedLabel(for: note))
                                .tfText(.meta)
                                .foregroundStyle(Color.tfSub)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.leading, TFSpacing.lg)
                    .frame(minHeight: 42)
                }
                .buttonStyle(TFTapRowStyle())
            }

            Button("Открепить папку") { detachConfirm = true }
                .buttonStyle(TFTapRowStyle())
                .tfText(.action)
                .foregroundStyle(Color.tfDim)
                .padding(.top, TFSpacing.xs)
        }
    }

    /// Заметки, отфильтрованные по выбранному `dateFilter`. Если фильтр
    /// режет всё — список пустой; для `Picker`'а показываем подсказку.
    private var filteredNotes: [APIClient.DirectoryProjectDocs.NoteRef] {
        let all = docs?.notes ?? []
        guard let cutoff = dateFilter.cutoff(now: Date()) else { return all }
        return all.filter { note in
            guard let updated = note.updatedAt.flatMap(DateFormats.sqliteUTC) else {
                return false
            }
            return updated >= cutoff
        }
    }

    /// Текст-подсказка под пустым списком после фильтра.
    private var filteredNotesHint: String {
        switch dateFilter {
        case .day: return "За последние сутки ничего не правилось"
        case .week: return "За последнюю неделю ничего не правилось"
        case .month: return "За последний месяц ничего не правилось"
        case .all: return "В папке пока нет заметок"
        }
    }

    /// Подпись под названием: «обновлено 11.09.2026» или «никогда» —
    /// короткая, в одну строку, не вытесняет название.
    private func updatedLabel(for note: APIClient.DirectoryProjectDocs.NoteRef) -> String {
        guard let updated = note.updatedAt.flatMap(DateFormats.sqliteUTC) else {
            return "никогда"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return "обновлено " + f.string(from: updated)
    }

    // MARK: - Папка не привязана

    private var emptySection: some View {
        TFCard {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                Text("Прикрепите папку документов — вся документация по проекту будет здесь же, рядом с задачами. Папка живёт в Базе знаний, так что документы можно перетаскивать и открывать оттуда.")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                HStack(spacing: TFSpacing.sm) {
                    Button {
                        Task { await createAndAttach() }
                    } label: {
                        HStack(spacing: TFSpacing.sm) {
                            Image(systemName: "folder.badge.plus").font(.system(size: 16))
                            Text(busy ? "Создаём…" : "Создать «\(project.name)»")
                        }
                        .tfText(.action)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tfText)
                        .padding(.horizontal, TFSpacing.lg)
                        .frame(height: TFHitTarget.min)
                        .background(Color.tfCard2)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                    }
                    .buttonStyle(TFTapScaleStyle())
                    .disabled(busy)

                    if !allFolders.isEmpty {
                        Button {
                            pickerOpen = true
                        } label: {
                            HStack(spacing: TFSpacing.sm) {
                                Image(systemName: "folder").font(.system(size: 16))
                                Text("Выбрать папку")
                            }
                            .tfText(.action)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.tfText)
                            .padding(.horizontal, TFSpacing.lg)
                            .frame(height: TFHitTarget.min)
                            .background(Color.tfCard2)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                        }
                        .buttonStyle(TFTapScaleStyle())
                    }
                }
            }
        }
    }

    // MARK: - Действия

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let docsResult = apiClient.directoryProjectDocs(projectId: project.id)
        async let foldersResult = apiClient.journalFolders()
        do {
            docs = try await docsResult
            allFolders = (try? await foldersResult) ?? []
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось загрузить документацию"
        }
    }

    private func createAndAttach() async {
        busy = true
        defer { busy = false }
        do {
            let folder = try await apiClient.createJournalFolder(name: project.name)
            let updated = try await apiClient.patchProject(id: project.id, fields: ["notes_folder_id": .number(Double(folder.id))])
            onProjectPatched(updated)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось создать папку"
        }
    }

    private func attach(_ folderId: Int) async {
        do {
            let updated = try await apiClient.patchProject(id: project.id, fields: ["notes_folder_id": .number(Double(folderId))])
            onProjectPatched(updated)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось привязать папку"
        }
    }

    private func detach() async {
        do {
            let updated = try await apiClient.patchProject(id: project.id, fields: ["notes_folder_id": JSONValue.null])
            onProjectPatched(updated)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось открепить папку"
        }
    }

    private func addNote() async {
        guard let folderId = docs?.folder?.id else { return }
        do {
            let note = try await apiClient.createNote(folderId: folderId, content: .string(""))
            await load()
            pendingNoteID = note.id
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось создать заметку"
        }
    }
}
