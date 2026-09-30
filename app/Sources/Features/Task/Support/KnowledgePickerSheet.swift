import SwiftUI

/// Выбор документа из БАЗЫ ЗНАНИЙ, чтобы приложить его к задаче.
///
/// Владелец 20.09.2026: «Прикрепить файл» кидал сразу в Файлы iPhone, а надо
/// выбор источника. База знаний — это корень: в ней и папки проектов, и
/// документы вне проектов, поэтому дробить на «проектные» и «базу» не нужно —
/// один список с деревом папок.
///
/// Экран только ВЫБИРАЕТ: отдаёт `onPick(noteID, title)`, а вложение делает
/// вызывающий (заметка конвертируется в markdown и уходит файлом к задаче).
struct KnowledgePickerSheet: View {
    let onPick: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    private let api = APIClient()

    @State private var folders: [ApiJournalFolder] = []
    @State private var notes: [NoteListItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var query = ""

    private struct DocSection: Identifiable {
        let id: String
        let title: String
        let notes: [NoteListItem]
    }

    var body: some View {
        TFBottomSheetContent(title: "База знаний", onClose: { dismiss() }) {
            Group {
                if isLoading {
                    TFLoading(.block)
                } else if let errorMessage {
                    Text(errorMessage)
                        .tfText(.action)
                        .foregroundStyle(Color.tfRed)
                        .padding(TFSpacing.lg)
                } else if sections.isEmpty {
                    Text("Ничего не найдено")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                        .padding(TFSpacing.lg)
                } else {
                    list
                }
            }
        }
        .presentationBackground(Color.tfSheetBackground)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    private var list: some View {
        List {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.notes) { note in
                        Button {
                            onPick(note.id, note.title)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title.isEmpty ? "Без названия" : note.title)
                                    .tfText(.body)
                                    .foregroundStyle(Color.tfText)
                                if !note.preview.isEmpty {
                                    Text(note.preview)
                                        .tfText(.caption)
                                        .foregroundStyle(Color.tfDim)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .listRowBackground(Color.tfSheetBackground)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.tfSheetBackground)
        .searchable(text: $query, prompt: "Поиск по документам")
    }

    /// Папки деревом (как в «Заметках»), под каждой — её документы; документы
    /// без папки — отдельным разделом. С поиском пустые разделы уходят.
    private var sections: [DocSection] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        func matches(_ note: NoteListItem) -> Bool {
            guard !q.isEmpty else { return true }
            return note.title.lowercased().contains(q) || note.preview.lowercased().contains(q)
        }

        var out: [DocSection] = []
        var visited = Set<Int>()
        func walk(parentID: Int?, depth: Int) {
            for folder in folders where folder.parentId == parentID {
                guard visited.insert(folder.id).inserted else { continue }
                let items = notes.filter { $0.folderId == folder.id && matches($0) }
                if !items.isEmpty {
                    let pad = String(repeating: "  ", count: depth)
                    out.append(DocSection(id: "f\(folder.id)", title: pad + folder.name, notes: items))
                }
                walk(parentID: folder.id, depth: depth + 1)
            }
        }
        walk(parentID: nil, depth: 0)

        let rootNotes = notes.filter { $0.folderId == nil && matches($0) }
        if !rootNotes.isEmpty {
            out.append(DocSection(id: "root", title: "Без папки", notes: rootNotes))
        }
        return out
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let foldersTask = api.journalFolders()
            async let notesTask = api.notesList()
            folders = try await foldersTask
            notes = try await notesTask
        } catch {
            errorMessage = "Не удалось загрузить базу знаний"
        }
    }
}
