import SwiftUI
import UniformTypeIdentifiers

/// Память команды (владелец 02.10.2026): «пусть сами пишут, а я вижу и
/// редактирую; и чтобы файлы можно было закидывать».
///
/// Список всего, что знают роли: общая память, память каждой роли, файлы.
/// Записи, которые роль сделала сама, помечены. Тап — правка, свайп —
/// закрепить или удалить. «+» — записать самому или загрузить файл.
/// Закреплённое приходит ролям в каждое задание.
struct MemoryScreen: View {
    private enum Filter: Hashable {
        case all
        case team
        case role(String)
        case files
    }

    @State private var memories: [ApiMemory] = []
    @State private var roles: [PlanRoleOption] = []
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editing: MemoryEditorTarget?
    @State private var isFileImporterPresented = false
    @State private var isUploading = false

    private let api = APIClient()

    private var visible: [ApiMemory] {
        memories.filter { memory in
            switch filter {
            case .all: true
            case .team: memory.scope == "team" && !memory.isFile
            case .role(let key): memory.scope == "role" && memory.roleKey == key
            case .files: memory.isFile
            }
        }
    }

    var body: some View {
        List {
            Section {
                filterBar
                    .listRowInsets(EdgeInsets(top: TFSpacing.xs, leading: 0, bottom: TFSpacing.xs, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            if isUploading {
                Section { ProgressView("Загружаю файл в память…") }
            }
            if visible.isEmpty && !isLoading {
                ContentUnavailableView(
                    "Пока пусто",
                    systemImage: "brain",
                    description: Text("Роли запоминают сами по ходу работы. Можно записать самому или загрузить файл — «+» вверху.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(visible) { memory in
                Button { editing = .existing(memory) } label: { row(memory) }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await delete(memory) } } label: {
                            Label("Забыть", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button { Task { await togglePin(memory) } } label: {
                            Label(memory.isPinned ? "Открепить" : "Закрепить", systemImage: memory.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(Color.tfOrange)
                    }
                    .accessibilityIdentifier("memory-row-\(memory.id)")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.tfBackground)
        .tfNativeHeader("Память команды")
        .searchable(text: $search, prompt: "Поиск по памяти")
        .onSubmit(of: .search) { Task { await load() } }
        .onChange(of: search) { _, value in
            if value.isEmpty { Task { await load() } }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editing = .new } label: { Label("Записать", systemImage: "square.and.pencil") }
                    Button { isFileImporterPresented = true } label: { Label("Загрузить файл", systemImage: "doc.badge.plus") }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Добавить в память")
                .accessibilityIdentifier("memory-add")
            }
        }
        .fileImporter(isPresented: $isFileImporterPresented,
                      allowedContentTypes: [.plainText, .text, .pdf, .data, .item]) { result in
            Task { await importFile(result) }
        }
        .sheet(item: $editing) { target in
            MemoryEditorSheet(target: target, roles: roles, api: api) {
                Task { await load() }
            }
            .presentationDetents([.medium, .large])
        }
        .refreshable { await load() }
        .task {
            await loadRoles()
            await load()
        }
        .alert("Память", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Фильтр

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TFSpacing.sm) {
                chip("Всё", .all)
                chip("Общая", .team)
                chip("Файлы", .files)
                ForEach(roles) { role in
                    chip(role.title, .role(role.key))
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
        }
    }

    private func chip(_ title: String, _ value: Filter) -> some View {
        Button { filter = value } label: {
            Text(title)
                .font(.subheadline.weight(filter == value ? .semibold : .regular))
                .padding(.horizontal, TFSpacing.md)
                .padding(.vertical, TFSpacing.xs)
                .background(filter == value ? Color.tfRed.opacity(0.15) : Color.tfCard, in: Capsule())
                .foregroundStyle(filter == value ? Color.tfRed : Color.tfText)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Строка

    private func row(_ memory: ApiMemory) -> some View {
        HStack(alignment: .top, spacing: TFSpacing.md) {
            Image(systemName: Self.icon(memory.kind))
                .foregroundStyle(memory.isFile ? Color.tfBlue : Color.tfSub)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                if let title = memory.title, !title.isEmpty {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.tfText).lineLimit(1)
                }
                Text(memory.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(memory.isFile ? 2 : 3)
                Text(caption(memory))
                    .font(.caption)
                    .foregroundStyle(Color.tfSub)
            }
            Spacer(minLength: 0)
            if memory.isPinned {
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(Color.tfOrange)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func caption(_ memory: ApiMemory) -> String {
        var parts: [String] = []
        switch memory.scope {
        case "team": parts.append("общая")
        case "role": parts.append(roleTitle(memory.roleKey))
        default: parts.append("проект")
        }
        parts.append(Self.kindTitle(memory.kind))
        if memory.isFromRole {
            let author = memory.createdBy.map { $0.hasPrefix("role_") ? roleTitle(String($0.dropFirst(5))) : $0 } ?? "роль"
            parts.append("записал(а) \(author)")
        }
        if let used = memory.useCount, used > 0 { parts.append("вспоминали \(used)×") }
        return parts.joined(separator: " · ")
    }

    private func roleTitle(_ key: String?) -> String {
        guard let key else { return "роль" }
        return roles.first { $0.key == key }?.title ?? key
    }

    static func icon(_ kind: String) -> String {
        switch kind {
        case "lesson": "lightbulb"
        case "preference": "heart"
        case "file": "doc.text"
        default: "info.circle"
        }
    }

    static func kindTitle(_ kind: String) -> String {
        switch kind {
        case "lesson": "урок"
        case "preference": "предпочтение"
        case "file": "файл"
        default: "факт"
        }
    }

    // MARK: - Загрузка и действия

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do { memories = try await api.memories(query: search.trimmingCharacters(in: .whitespaces)) }
        catch is CancellationError {}
        catch { errorMessage = error.localizedDescription }
    }

    private func loadRoles() async {
        if let list = try? await api.roles() {
            roles = list.map { PlanRoleOption(key: $0.role, title: $0.title) }
        }
    }

    private func delete(_ memory: ApiMemory) async {
        do {
            try await api.deleteMemory(id: memory.id)
            withAnimation { memories.removeAll { $0.id == memory.id } }
        } catch { errorMessage = error.localizedDescription }
    }

    private func togglePin(_ memory: ApiMemory) async {
        do {
            try await api.updateMemory(id: memory.id, fields: ["pinned": .bool(!memory.isPinned)])
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Файл — в общую память; в память конкретной роли его можно
    /// перенести потом, в карточке записи.
    private func importFile(_ result: Result<URL, Error>) async {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        isUploading = true
        defer { isUploading = false }
        do {
            let data = try Data(contentsOf: url)
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            var roleKey: String?
            if case .role(let key) = filter { roleKey = key }
            try await api.uploadMemoryFile(fileName: url.lastPathComponent, data: data, mime: mime,
                                           scope: roleKey == nil ? "team" : "role", roleKey: roleKey)
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
}

// MARK: - Карточка записи

enum MemoryEditorTarget: Identifiable {
    case new
    case existing(ApiMemory)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let memory): memory.id
        }
    }
}

/// Новая запись или правка: текст, вид, чья память, закрепление. У файла
/// текст не правится — видно, на какие куски он разрезан.
struct MemoryEditorSheet: View {
    let target: MemoryEditorTarget
    let roles: [PlanRoleOption]
    let api: APIClient
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var kind = "fact"
    @State private var scope = "team"
    @State private var roleKey = ""
    @State private var pinned = false
    @State private var chunks: [ApiMemoryChunk] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isDeleteConfirmOpen = false

    private var existing: ApiMemory? {
        if case .existing(let memory) = target { return memory }
        return nil
    }

    private var isFile: Bool { existing?.isFile ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Заголовок (необязательно)", text: $title)
                    if isFile {
                        Text("Файл: текст разрезан на \(chunks.count) кусков, роли находят нужный по смыслу.")
                            .font(.footnote)
                            .foregroundStyle(Color.tfSub)
                    } else {
                        TextField("Что помнить", text: $text, axis: .vertical)
                            .lineLimit(3...12)
                            .accessibilityIdentifier("memory-text")
                        Picker("Вид", selection: $kind) {
                            Text("Факт").tag("fact")
                            Text("Урок").tag("lesson")
                            Text("Предпочтение").tag("preference")
                        }
                    }
                }
                Section {
                    Picker("Чья память", selection: $scope) {
                        Text("Общая — всем ролям").tag("team")
                        Text("Одной роли").tag("role")
                    }
                    if scope == "role" {
                        Picker("Роль", selection: $roleKey) {
                            ForEach(roles) { role in Text(role.title).tag(role.key) }
                        }
                    }
                    Toggle("Закрепить — всегда в задании", isOn: $pinned)
                } footer: {
                    Text("Закреплённое роль получает в каждом задании. Остальное — когда оно близко к теме.")
                }
                if isFile && !chunks.isEmpty {
                    Section("Содержимое") {
                        ForEach(chunks, id: \.idx) { chunk in
                            Text(chunk.text).font(.footnote).foregroundStyle(Color.tfSub).lineLimit(6)
                        }
                    }
                }
                if let memory = existing {
                    Section {
                        if memory.isFromRole {
                            Text("Записала роль сама. Поправьте, если неточно, — правка владельца для ролей важнее.")
                                .font(.footnote)
                                .foregroundStyle(Color.tfSub)
                        }
                        Button("Забыть", role: .destructive) { isDeleteConfirmOpen = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Запомнить" : (isFile ? "Файл в памяти" : "Запись памяти"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .disabled(isSaving || (!isFile && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                  || (scope == "role" && roleKey.isEmpty))
                        .accessibilityIdentifier("memory-save")
                }
            }
            .confirmationDialog("Забыть эту запись?", isPresented: $isDeleteConfirmOpen, titleVisibility: .visible) {
                Button("Забыть", role: .destructive) { Task { await remove() } }
            }
            .alert("Не сохранилось", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Понятно", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task { await fill() }
        }
    }

    private func fill() async {
        guard let memory = existing else {
            roleKey = roles.first?.key ?? ""
            return
        }
        title = memory.title ?? ""
        text = memory.text
        kind = memory.isFile ? "fact" : memory.kind
        scope = memory.scope == "role" ? "role" : "team"
        roleKey = memory.roleKey ?? roles.first?.key ?? ""
        pinned = memory.isPinned
        if memory.isFile, let detail = try? await api.memory(id: memory.id) {
            chunks = detail.1
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let memory = existing {
                var fields: [String: JSONValue] = [
                    "title": .string(cleanTitle),
                    "pinned": .bool(pinned),
                    "scope": .string(scope),
                ]
                if scope == "role" { fields["role_key"] = .string(roleKey) }
                if !memory.isFile {
                    fields["text"] = .string(cleanText)
                    fields["kind"] = .string(kind)
                }
                try await api.updateMemory(id: memory.id, fields: fields)
            } else {
                try await api.createMemory(text: cleanText, kind: kind, scope: scope,
                                           roleKey: scope == "role" ? roleKey : nil,
                                           title: cleanTitle, pinned: pinned)
            }
            onChange()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func remove() async {
        guard let memory = existing else { return }
        do {
            try await api.deleteMemory(id: memory.id)
            onChange()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
