import SwiftUI

/// Лист создания / правки роли в экране «Команда» — LOCK-205.
///
/// Правила (зеркальные с сервером, `server/src/routes/roles.ts:289-323` и
/// `343-381`):
/// - Ключ — латиница в нижнем регистре, цифры и `_`, 2-32 знака, начинается
///   с буквы. Сервер отвечает 422 на любое другое.
/// - Название — непустая строка после `trim`. Сервер тоже валирует.
/// - `summary` и `prompt` опциональны; пустой `prompt` сбрасывает инструкцию
///   на файл `scripts/role-prompts/<роль>.md`.
///
/// Кнопка «Сбросить» у инструкции отправляет `PromptChange.reset` — клиент
/// не должен сам стирать поле «вслепую», иначе пользователь не отличит
/// «правка инструкции» от «вернуть прежнюю».
struct RoleEditorSheet: View {
    enum Mode: Identifiable {
        case create
        case edit(RoleProfile)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let profile): return "edit-\(profile.role)"
            }
        }

        var isEdit: Bool {
            if case .edit = self { return true }
            return false
        }

        var profile: RoleProfile? {
            if case .edit(let profile) = self { return profile }
            return nil
        }
    }

    @Bindable var viewModel: AgentsViewModel
    let mode: Mode

    @Environment(\.dismiss) private var dismiss

    @State private var key: String = ""
    @State private var title: String = ""
    @State private var summary: String = ""
    @State private var prompt: String = ""
    @State private var promptBaseline: String = ""
    @State private var promptConflict = false
    @State private var isSaving = false
    @State private var isTogglingEnabled = false
    @State private var errorText: String?
    @State private var showsRuntimeContext = false

    init(mode: Mode, viewModel: AgentsViewModel) {
        self.mode = mode
        self.viewModel = viewModel
        if case .edit(let profile) = mode {
            // В режиме правки заполняем поля начальными значениями. После
            // этого они живут в `@State`, и любая правка идёт через них.
            _title = State(initialValue: profile.title)
            _summary = State(initialValue: profile.summary ?? "")
            _prompt = State(initialValue: profile.prompt)
            _promptBaseline = State(initialValue: profile.prompt)
        }
    }

    var body: some View {
        // Урок 2026-09-25 (чёрные треугольники в углах системной клавиатуры,
        // iOS 26): фон одним слоем на самом верху тела экрана, `ZStack` +
        // `.ignoresSafeArea()` без ограничения edges.
        ZStack {
            Color.tfBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: TFSpacing.lg) {
                fields
                if let errorText {
                    Text(errorText)
                        .tfText(.meta)
                        .foregroundStyle(Color.tfRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if promptConflict, let profile = mode.profile {
                    Button("Принять новую версию, оставить мою правку") {
                        Task {
                            if let fresh = try? await APIClient().role(id: profile.role) {
                                promptBaseline = fresh.prompt
                                promptConflict = false
                                errorText = nil
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Spacer(minLength: 0)
                actions
            }
            .padding(.horizontal, TFSpacing.lg)
            .padding(.vertical, TFSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .sheet(isPresented: $showsRuntimeContext, onDismiss: {
            if let profile = mode.profile {
                Task {
                    if let fresh = try? await APIClient().role(id: profile.role) {
                        if prompt == promptBaseline {
                            prompt = fresh.prompt
                            promptBaseline = fresh.prompt
                            promptConflict = false
                        } else if fresh.prompt != promptBaseline {
                            promptConflict = true
                            errorText = "Инструкция роли изменилась. Ваша правка сохранена в поле; сравните её с текущей версией на сервере."
                        }
                    }
                }
            }
        }) {
            if let profile = mode.profile {
                RoleRuntimeContextSheet(role: profile)
            }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            if !mode.isEdit {
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text("Ключ")
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                    TFTextField("латиница, цифры, _", text: $key, icon: "number")
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: key) { _, _ in errorText = nil }
                    if let keyError {
                        Text(keyError)
                            .tfText(.caption)
                            .foregroundStyle(Color.tfRed)
                    }
                }
            }
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Text("Название")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                TFTextField("например, Исследователь", text: $title, icon: "textformat")
                    .onChange(of: title) { _, _ in errorText = nil }
            }
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Text("Чем занимается")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                TFTextField("коротко, одна строка", text: $summary, icon: "text.alignleft")
            }
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Text("Инструкция")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                Text("Системный промпт роли. Пусто — сервер читает файл scripts/role-prompts.")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
                multiline(text: $prompt, placeholder: "Системный промпт…")
                if !prompt.isEmpty {
                    Button("Сбросить на файл", action: { prompt = "" })
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.tfCoral)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: TFSpacing.sm) {
            if mode.isEdit, let profile = mode.profile {
                Button("Как запускается роль") {
                    showsRuntimeContext = true
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Открывает постоянные правила и источники запуска \(profile.title)")
            }
            TFButton(saveButtonTitle, icon: "checkmark", variant: .primary,
                     isEnabled: canSave && !isSaving && !isTogglingEnabled) {
                Task { await save() }
            }
            if mode.isEdit, let profile = mode.profile {
                TFButton(
                    profile.isEnabled ? "Отключить роль" : "Включить роль",
                    icon: profile.isEnabled ? "archivebox" : "tray.and.arrow.up",
                    variant: .outline,
                    isEnabled: !isSaving && !isTogglingEnabled
                ) {
                    Task { await toggleEnabled(profile: profile) }
                }
            }
        }
    }

    private var saveButtonTitle: String {
        mode.isEdit ? "Сохранить" : "Создать"
    }

    /// Кнопка «Сохранить» доступна, если:
    /// - создаём и ключ + название валидны, непустые;
    /// - правим и хотя бы одно из трёх полей реально изменилось.
    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if !mode.isEdit {
            return keyError == nil && !key.isEmpty
        }
        return keyChanged || titleChanged || summaryChanged || promptChanged
    }

    private var keyChanged: Bool {
        // Ключ в режиме правки не меняется, поле скрыто — для API это всегда
        // `false`. Оставлено на случай, если сервер когда-нибудь разрешит
        // переименование ключа.
        false
    }

    private var titleChanged: Bool {
        guard let profile = mode.profile else { return false }
        return title.trimmingCharacters(in: .whitespaces) != profile.title
    }

    private var summaryChanged: Bool {
        guard let profile = mode.profile else { return false }
        let original = profile.summary ?? ""
        return summary != original
    }

    private var promptChanged: Bool {
        return prompt != promptBaseline
    }

    private var keyError: String? {
        // Серверная регулярка: `^[a-z][a-z0-9_]{1,31}$`. На клиенте
        // проверяем только когда пользователь что-то ввёл — пустое поле
        // не должно ругаться, чтобы не моргало красным при первом открытии.
        guard !key.isEmpty else { return nil }
        if key.count < 2 || key.count > 32 { return "Ключ должен быть от 2 до 32 знаков" }
        // Только ASCII (LOCK-207): `isLetter`/`isNumber` пропускали кириллицу
        // и нелатинские цифры, которые сервер всё равно отвергает.
        let latin: ClosedRange<Character> = "a"..."z"
        let digits: ClosedRange<Character> = "0"..."9"
        guard let first = key.first else { return nil }
        if !latin.contains(first) { return "Ключ начинается со строчной латинской буквы" }
        if !key.allSatisfy({ latin.contains($0) || digits.contains($0) || $0 == "_" }) {
            return "Только строчная латиница, цифры и _"
        }
        // Служебные учётки: сервер не даёт роли такой ключ (New-Todoist
        // `server/src/routes/roles.ts`, `RESERVED_ROLE_KEYS`).
        if Self.reservedKeys.contains(key) { return "Этот ключ занят системой — выберите другой" }
        return nil
    }

    private static let reservedKeys: Set<String> = ["owner", "agent", "viewer", "orchestrator", "service"]

    // MARK: - Действия

    private func save() async {
        if promptConflict { return }
        if promptChanged, let profile = mode.profile {
            do {
                let fresh = try await APIClient().role(id: profile.role)
                if fresh.prompt != promptBaseline {
                    promptConflict = true
                    errorText = "Инструкция роли изменилась. Ваша правка сохранена в поле; сравните её с текущей версией на сервере."
                    return
                }
            } catch {
                errorText = error.localizedDescription
                return
            }
        }
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        let trimmedKey = key.trimmingCharacters(in: .whitespaces)
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespaces)
        let trimmedPrompt = prompt
        let success: Bool
        switch mode {
        case .create:
            success = await viewModel.createRole(
                key: trimmedKey,
                title: trimmedTitle,
                summary: trimmedSummary.isEmpty ? nil : trimmedSummary,
                prompt: trimmedPrompt.isEmpty ? nil : trimmedPrompt
            )
        case .edit(let profile):
            // Поля, которые не менялись, в PATCH не отправляем — сервер
            // требует, чтобы хотя бы одно было, и меняем только реально
            // тронутое (см. `APIClient.patchRole(...prompt: .keep)`).
            let promptChange: APIClient.PromptChange = promptChanged
                ? (trimmedPrompt.isEmpty ? .reset : .set(trimmedPrompt))
                : .keep
            success = await viewModel.patchRole(
                role: profile.role,
                title: titleChanged ? trimmedTitle : nil,
                summary: summaryChanged ? trimmedSummary : nil,
                prompt: promptChange
            )
        }
        if success {
            dismiss()
        } else if let message = viewModel.listErrorMessage {
            errorText = message
        } else {
            errorText = "Не удалось сохранить роль"
        }
    }

    private func toggleEnabled(profile: RoleProfile) async {
        isTogglingEnabled = true
        errorText = nil
        defer { isTogglingEnabled = false }
        let success = await viewModel.setRoleEnabled(role: profile.role, enabled: !profile.isEnabled)
        if success {
            dismiss()
        } else if let message = viewModel.listErrorMessage {
            errorText = message
        } else {
            errorText = "Не удалось изменить роль"
        }
    }

    // MARK: - Многострочное поле

    /// Многострочное поле без отдельного дизайн-компонента: на листе
    /// промпт — это одна-две строки, и оборачивать его в
    /// `VoiceModelsScreen.promptEditor` ради пары абзацев избыточно. Шрифт
    /// моноширинный, как у промптов в «Настройках»: код, а не текст.
    @ViewBuilder
    private func multiline(text: Binding<String>, placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .tfText(.input)
                    .foregroundStyle(Color.tfDim)
                    .padding(.horizontal, TFSpacing.sm)
                    .padding(.vertical, TFSpacing.sm)
                    .allowsHitTesting(false)
            }
            TextEditor(text: text)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .foregroundStyle(Color.tfText)
                .frame(minHeight: 96, maxHeight: 200)
                .padding(.horizontal, TFSpacing.xs)
                .padding(.vertical, TFSpacing.xs)
                .onChange(of: text.wrappedValue) { _, _ in errorText = nil }
        }
        .background(Color.tfCard2)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: TFRadius.md)
                .strokeBorder(Color.tfStroke, lineWidth: 0.5)
        )
    }
}
