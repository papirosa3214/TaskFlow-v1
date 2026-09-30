import SwiftUI
import UniformTypeIdentifiers

/// Содержимое секции «Итог» карточки (владелец 01.10.2026): что решили и
/// что сдали — одним местом. Вердикт проверяющего и итог каждой роли
/// открываются шторкой целиком; документы — заметки проекта, открываются
/// как заметка, в меню — «В базу знаний» и «Сохранить на телефон».
/// Строки — прямо в `Section` списка карточки (оборачивает
/// `collapsibleSection` в `TaskFormScreen`), без своих фонов.
struct TaskOutcomeContent: View {
    let outcome: ApiTaskOutcome
    /// Название роли по ключу (`analyst` → «Аналитик») — из ролей карточки.
    let roleTitle: (String) -> String
    let onToast: (String) -> Void

    private let api = APIClient()

    var body: some View {
        if let verdict = outcome.verdict {
            OutcomeTextRow(sheetTitle: "Вердикт проверяющего", markdown: verdict.findings) {
                HStack(spacing: TFSpacing.sm) {
                    Image(systemName: verdict.isApproved ? "checkmark.seal.fill" : "exclamationmark.bubble.fill")
                        .foregroundStyle(verdict.isApproved ? Color.tfGreen : Color.tfOrange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Проверяющий: \(verdict.title)")
                            .tfText(.action)
                            .foregroundStyle(Color.tfText)
                        if let date = verdict.createdDate {
                            Text(RelativeTime.relative(from: date))
                                .tfText(.meta)
                                .foregroundStyle(Color.tfDim)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }

        ForEach(outcome.nodes) { node in
            OutcomeTextRow(sheetTitle: nodeTitle(node), markdown: node.result ?? "Роль ничего не написала.") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(nodeTitle(node))
                        .tfText(.action)
                        .foregroundStyle(Color.tfText)
                    if let result = node.result, !result.isEmpty {
                        Text(result)
                            .tfText(.meta)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        ForEach(outcome.documents) { document in
            HStack(spacing: TFSpacing.sm) {
                NavigationLink(value: AppRoute.noteEditor(noteID: document.id)) {
                    Label(document.title, systemImage: document.isOutcome ? "flag.checkered" : "doc.text")
                        .tfText(.action)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(2)
                }
                Menu {
                    Button {
                        Task { await pushToKnowledge(document) }
                    } label: {
                        Label("В базу знаний", systemImage: "books.vertical")
                    }
                    ShareLink(
                        item: NoteMarkdownExport(id: document.id, title: document.title),
                        preview: SharePreview(document.title)
                    ) {
                        Label("Сохранить на телефон", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.tfSub)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Действия с документом")
            }
        }

        if let branch = outcome.branch {
            VStack(alignment: .leading, spacing: 2) {
                Label("Код: ветка \(branch.name)", systemImage: "arrow.triangle.branch")
                    .tfText(.action)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(branch.commit) — \(branch.subject)")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(2)
            }
        }
    }

    private func nodeTitle(_ node: ApiTaskOutcome.Node) -> String {
        guard let role = node.role else { return node.title }
        return "\(roleTitle(role)) — \(node.title)"
    }

    private func pushToKnowledge(_ document: ApiTaskOutcome.Document) async {
        do {
            try await api.pushNoteToKnowledge(noteId: document.id)
            onToast("«\(document.title)» — в базе знаний")
        } catch {
            onToast("Не удалось отправить в базу знаний")
        }
    }
}

/// Строка, тап по которой открывает полный текст шторкой. Шторка своя у
/// каждой строки: один `.sheet` на весь набор строк в `List` не сработал бы.
private struct OutcomeTextRow<Label: View>: View {
    let sheetTitle: String
    let markdown: String
    @ViewBuilder let label: () -> Label
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            OutcomeTextSheet(title: sheetTitle, markdown: markdown)
        }
    }
}

/// Полный текст вердикта или итога роли — системная шторка на пол-экрана.
private struct OutcomeTextSheet: View {
    let title: String
    let markdown: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                RoleReplyMarkdown(text: markdown)
                    .textSelection(.enabled)
                    .padding(.horizontal, TFSpacing.screenHorizontal)
                    .padding(.vertical, TFSpacing.md)
            }
            .tfNativeHeader(title, displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Документ файлом `.md` для «Поделиться»: текст берётся с сервера в момент
/// выбора — сохранить в «Файлы», отправить себе, открыть в другом
/// приложении.
struct NoteMarkdownExport: Transferable {
    let id: String
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: UTType(filenameExtension: "md") ?? .plainText) { item in
            let note = try await APIClient().note(id: item.id, format: "markdown")
            let name = item.title
                .components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(name.isEmpty ? "Документ" : String(name.prefix(120)))
                .appendingPathExtension("md")
            try (note.markdown ?? "").write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
