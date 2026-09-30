import SwiftUI

// Пузырь сообщения — 1:1 `ChatBubble`/`AddressLine` из `src/screens/ChatScreen.tsx`.
// Числа не в spec/DESIGN-TOKENS.md (компонент туда не попал построчно) —
// сняты с живого веб-кода по правилу ARCHITECTURE.md п.3 «расходится спека
// с кодом — верить коду».

/// «→ тебе» / «→ {имя}» / «→ всем» над пузырём (SCREENS-2 §3, дословно).
private struct AddressLine: View {
    let message: ApiChatMessage
    let mine: Bool
    let toMe: Bool

    var body: some View {
        let target = toMe ? "тебе" : (message.toUserId != nil ? (message.toUserName ?? "—") : "всем")
        HStack(spacing: 4) {
            if !mine {
                Text(message.fromUserName ?? "—")
            }
            Text("→ \(target)")
                .foregroundStyle(toMe ? Color.tfRed : (mine ? Color.tfDim : Color.tfSub))
                .fontWeight(toMe ? .semibold : .regular)
        }
        .tfText(.meta) // 12px — ближайшая ступень шкалы к веб-тексту 12px
        .foregroundStyle(mine ? Color.tfDim : Color.tfSub)
        .padding(.horizontal, 4)
    }
}

/// Картинка-вложение — требует `Authorization` (`APIClient.downloadAttachment`,
/// см. комментарий в Core), поэтому `AsyncImage(url:)` сюда не годится:
/// грузим байты сами и держим готовый `UIImage`.
// Не private: ту же картинку показывает лента задачи (LOCK-119) — вложения
// комментария там не рисовались вовсе, а второй такой же загрузчик заводить
// незачем.
struct ChatAttachmentImage: View {
    let attachmentId: String
    let fileName: String
    @State private var uiImage: UIImage?
    @State private var failed = false
    private let api = APIClient()

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if failed {
                ChatFileChip(fileName: fileName)
            } else {
                Color.tfCard2
                    .frame(height: 140)
                    .overlay { ProgressView() }
            }
        }
        .frame(maxWidth: 220)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
        .task {
            guard uiImage == nil else { return }
            do {
                let data = try await api.downloadAttachment(id: attachmentId)
                uiImage = UIImage(data: data)
                if uiImage == nil { failed = true }
            } catch {
                failed = true
            }
        }
    }
}

/// Аватар автора сообщения — фото, если есть (`avatar_url` отдаётся
/// сервером БЕЗ авторизации, `AsyncImage(url:)` годится напрямую в отличие
/// от вложений), иначе инициалы через `TFAvatar`. Обёртка нужна ровно
/// потому, что `TFAvatar.image` — уже готовый `Image`, а не URL.
private struct ChatUserAvatar: View {
    let avatarUrlPath: String?
    let initials: String
    let tint: Color
    let userID: String?

    var body: some View {
        if let avatarUrlPath, let url = URL(string: APIClient.baseURL.absoluteString + avatarUrlPath) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    TFAvatar(size: .md, image: image, initials: initials, tint: tint, userID: userID)
                } else {
                    TFAvatar(size: .md, initials: initials, tint: tint, userID: userID)
                }
            }
        } else {
            TFAvatar(size: .md, initials: initials, tint: tint, userID: userID)
        }
    }
}

/// Файл-не-картинка — чип со скрепкой и именем (веб: `bg-card2 h-9 px-3`).
struct ChatFileChip: View {
    let fileName: String
    var body: some View {
        HStack(spacing: TFSpacing.sm) {
            Image(systemName: "paperclip")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            Text(fileName)
                .tfText(.meta)
                .foregroundStyle(Color.tfText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, TFSpacing.md)
        .frame(height: TFHitTarget.min)
        .frame(maxWidth: 220, alignment: .leading)
        .background(Color.tfCard2)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
    }
}

struct ChatBubble: View {
    /// Учётка Секретаря на сервере (`lib/ownerDraft.ts`, SECRETARY_ID).
    static let secretaryID = "u-secretary"

    let message: ApiChatMessage
    let mine: Bool
    let toMe: Bool

    @State private var pendingTaskID: String?

    /// Задачи из вложения: что предложила локальная модель и показывать ли шторку.
    @State private var extractedTasks: [ExtractedNoteTask] = []
    @State private var isShowingExtractedTasks = false
    @State private var extractErrorMessage: String?

    private struct TaskRef: Identifiable {
        let id: String
    }

    // Аватар раньше показывался только у чужих сообщений (веб 1:1) — просьба
    // владельца 03.09.2026: «надо, чтобы она была тоже с его стороны, моя —
    // с моей» — своя аватарка теперь тоже видна, справа у своих сообщений,
    // тем же компонентом (`message.fromUser*` у своего сообщения — это и
    // есть сам владелец). Сознательное расхождение с вебом, не гэп.
    var body: some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            if mine { Spacer(minLength: TFSpacing.sm) }

            if !mine {
                // Размер — веб 28px точечно; в шкале `TFAvatar.Size` ближайшее 30 (см. отчёт).
                ChatUserAvatar(
                    avatarUrlPath: message.fromUserAvatarUrl,
                    initials: message.fromUserInitials ?? "?",
                    tint: Color(hex: message.fromUserColor ?? TFHexDefault.unassigned),
                    userID: message.fromUserId
                )
            }

            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                AddressLine(message: message, mine: mine, toMe: toMe)

                if !message.text.isEmpty {
                    Text(message.text)
                        .tfText(.row) // 14px — веб text-[14px]
                        // Мои сообщения — БЕЗ красной заливки, только красная
                        // обводка; у остальных обводки нет вовсе (владелец
                        // 21.09.2026). Поэтому цвет текста единый.
                        .foregroundStyle(Color.tfText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(mine ? Color.clear : Color.tfCard)
                        .overlay {
                            if mine {
                                RoundedRectangle(cornerRadius: TFRadius.xl)
                                    .strokeBorder(Color.tfRed, lineWidth: TFBorder.width)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
                }

                ForEach(message.attachments ?? [], id: \.id) { attachment in
                    if let mime = attachment.mime, mime.hasPrefix("image/") {
                        ChatAttachmentImage(attachmentId: attachment.id, fileName: attachment.fileName)
                    } else {
                        // Долгое нажатие на файл — «Создать задачи»: сервер
                        // вытащит текст и отдаст его локальной модели, список
                        // подтвердим в общей шторке.
                        ChatFileChip(fileName: attachment.fileName)
                            .contextMenu {
                                if attachmentSupportsTaskExtraction(mime: attachment.mime) {
                                    Button {
                                        Task { await extractTasks(from: attachment.id) }
                                    } label: {
                                        Label("Создать задачи", systemImage: "wand.and.stars")
                                    }
                                }
                            }
                    }
                }

                if let taskId = message.taskId, message.fromUserId == Self.secretaryID {
                    // Ответ Секретаря о постановке — карточкой с шагами,
                    // дочерними и «Запустить / Удалить» (владелец 23.09.2026).
                    SecretaryDraftCard(taskID: taskId) { pendingTaskID = taskId }
                } else if let taskId = message.taskId, let taskTitle = message.taskTitle {
                    Button { pendingTaskID = taskId } label: {
                        Text(taskTitle)
                            .tfText(.meta)
                            .foregroundStyle(Color.tfSub)
                            .underline()
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                }

                Text(timestampText)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
            .frame(maxWidth: 300, alignment: mine ? .trailing : .leading) // ~78% экрана 420pt (веб max-w-[78%])

            if mine {
                ChatUserAvatar(
                    avatarUrlPath: message.fromUserAvatarUrl,
                    initials: message.fromUserInitials ?? "?",
                    tint: Color(hex: message.fromUserColor ?? TFHexDefault.unassigned),
                    userID: message.fromUserId
                )
            } else {
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal, TFSpacing.lg)
        .sheet(item: Binding(
            get: { pendingTaskID.map(TaskRef.init) },
            set: { pendingTaskID = $0?.id }
        )) { ref in
            NavigationStack { TaskFormScreen(taskID: ref.id) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingExtractedTasks) {
            TFBottomSheetContent(title: "Задачи из файла", onClose: { isShowingExtractedTasks = false }) {
                NoteExtractedTasksSheetContent(tasks: extractedTasks) {
                    isShowingExtractedTasks = false
                }
            }
            .presentationBackground(Color.tfSheetBackground)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Не получилось", isPresented: Binding(
            get: { extractErrorMessage != nil },
            set: { if !$0 { extractErrorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(extractErrorMessage ?? "")
        }
    }

    private func extractTasks(from attachmentId: String) async {
        do {
            let tasks = try await APIClient().extractTasksFromAttachment(id: attachmentId)
            guard !tasks.isEmpty else {
                extractErrorMessage = "В файле не нашлось конкретных задач"
                return
            }
            extractedTasks = tasks
            isShowingExtractedTasks = true
        } catch {
            extractErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Не удалось разобрать файл"
        }
    }

    private var timestampText: String {
        guard let date = message.createdAtDate else { return "" }
        return "\(RelativeTime.relative(from: date)) · \(RelativeTime.absoluteMoscow(from: date))"
    }
}
