import SwiftUI

/// `/settings/voice-models` — spec/SCREENS-2.md §16 + `src/screens/VoiceModelsScreen.tsx`
/// (спека не даёт словарь статусов дословно нигде, кроме текста — цвета и
/// раскладку строк беру из веб-кода, ARCHITECTURE.md п.3).
///
/// Шапка — штатная iOS-навигация, общая с остальными экранами настроек.
///
/// ⚠️ Веб-версия при `!localAIModelsSupported()` (браузер, не нативное
/// приложение) заменяет экран целиком на короткую заглушку — здесь это
/// состояние НЕДОСТИЖИМО: это и есть то самое нативное приложение на iPhone,
/// заглушка не рендерится никогда, ветка сознательно не портирована.
///
/// ⚠️ Секция «На телефоне», 03.09.2026: «Распознавание речи» подключена —
/// не `WhisperKit`/`argmaxinc`, как на вебе, а NVIDIA Parakeet TDT v3 через
/// `FluidAudio` (SPM, `project.yml`) — владелец сам назвал модель («маленькая,
/// все хвалят, мультиязычная») и явно попросил не городить пикер из
/// нескольких движков. Реальный статус (не заглушка): строка тянет
/// `DictationEngine.shared.modelState`, тап при «скачать» реально качает и
/// греет модель. Логика записи/распознавания и приёмник UI — там же
/// (`Sources/Core/Speech/DictationEngine.swift`), не в этом файле.
///
/// «Расшифровка действий» — другой по природе движок (локальная LLM,
/// объясняющая, чем занят агент, не спич-ту-текст) — пока НЕ подключена,
/// честный гэп остаётся: строка так и показывает «не скачана».
struct VoiceModelsScreen: View {
    @State private var serverStatus: AIStatusResponse?
    @State private var isLoadingServerStatus = true

    @State private var isLogEnabled = DictationLog.isEnabled()
    @State private var logEntries = DictationLog.readEntries()
    @State private var pendingArchiveCount = DictationArchiveQueue.pendingCount()
    @State private var dictation = DictationEngine.shared
    /// Подтверждение удаления весов модели — необратимое действие, спрашиваем.
    @State private var showDeleteConfirm = false

    /// Локальные (Ollama) модели сервера — для меню замены; память берётся
    /// из `size`/`size_vram`, которые сервер подмешивает из `/api/ps`.
    @State private var serverModels: [AILocalModel] = []
    /// Выбранная серверная модель приложения. Пусто — серверная по умолчанию.
    @State private var selectedServerModel: String = AIServerModelSetting.selected ?? ""
    /// Какая строка развёрнута (аккордеон). Тап по строке разворачивает её
    /// НА МЕСТЕ — описание модели для локальной, промпт для серверной
    /// (владелец 20.09.2026: «тапнул — расширилась, и в расширенной карточке
    /// описание; промпт так же, а не отдельными всплывающими окнами»).
    /// Одновременно развёрнута одна строка. Шевронов не рисуем.
    @State private var expandedRow: ExpandedRow?

    private enum ExpandedRow: String {
        case speech
        case extractTasks
        case journalAssist
        case actionExplain
        case taskIntake
    }

    @State private var promptsStore = AIPromptsStore.shared
    /// Дебаунс-отправка промптов на сервер: при каждом нажатии клавиши
    /// отменяем предыдущую задачу и через 0.6с шлём актуальное значение.
    @State private var extractSaveTask: Task<Void, Never>?
    @State private var journalSaveTask: Task<Void, Never>?
    @State private var activitySaveTask: Task<Void, Never>?
    @State private var taskIntakeSaveTask: Task<Void, Never>?
    @State private var extractSaveState: PromptSaveState = .saved
    @State private var journalSaveState: PromptSaveState = .saved
    @State private var activitySaveState: PromptSaveState = .saved
    @State private var taskIntakeSaveState: PromptSaveState = .saved

    var body: some View {
        // Урок 2026-09-25 (чёрные треугольники в углах системной клавиатуры,
        // iOS 26): фон одним слоем на самом верху тела экрана, `ZStack` +
        // `.ignoresSafeArea()` без ограничения edges.
        ZStack {
            Color.tfBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: TFSpacing.lg) {
                        onDeviceSection
                        onServerSection
                        dictationLogSection
                    }
                    .padding(.horizontal, TFSpacing.screenHorizontal)
                    .padding(.top, TFSpacing.sm)
                    .padding(.bottom, TFSpacing.xl * 2)
                }
            }
        }
        .tfNativeHeader("Модели и голоса")
        .task {
            dictation.refreshModelState()
            await loadServerStatus()
            await promptsStore.refresh()
        }
        .confirmationDialog(
            "Удалить \(dictation.selectedModel.displayName)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) { dictation.deleteModel() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Веса модели исчезнут с телефона. При следующей диктовке её придётся скачать заново.")
        }
        .onDisappear {
            extractSaveTask?.cancel()
            journalSaveTask?.cancel()
            activitySaveTask?.cancel()
            taskIntakeSaveTask?.cancel()
            // Последний flush, если пользователь ушёл со страницы на полуслове.
            // @MainActor — `save*` помечены, иначе Swift 6 ругается на
            // пересечение акторов.
            Task { @MainActor in await promptsStore.saveExtractTasksPrompt() }
            Task { @MainActor in await promptsStore.saveJournalAssistPrompt() }
            Task { @MainActor in await promptsStore.saveActivityPrompt() }
            Task { @MainActor in await promptsStore.saveTaskIntakePrompt() }
        }
    }

    private func loadServerStatus() async {
        isLoadingServerStatus = true
        defer { isLoadingServerStatus = false }
        serverStatus = try? await APIClient().aiStatus()
        // Список моделей и их память — тем же заходом; недоступен сервер —
        // просто не показываем варианты замены.
        serverModels = (try? await APIClient().aiLocalModels()) ?? []
    }

    // MARK: - На телефоне

    private var onDeviceSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            SettingsCapsLabel("На телефоне")
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    Button {
                        toggleExpanded(.speech)
                    } label: {
                        VoiceModelRow(
                            icon: dictation.isEnabled ? "mic" : "mic.slash",
                            title: "Распознавание речи",
                            subtitle: speechSubtitle,
                            value: speechValue
                        )
                    }
                    .buttonStyle(TFTapRowStyle())
                    // Всё управление моделью — в долгом нажатии, отдельного
                    // тумблера нет (владелец 20.09.2026: «тумблер не нужен
                    // отдельный, добавь выключить в меню»). Меню нужно и когда
                    // модель готова, поэтому строка не выключается `.disabled`.
                    .contextMenu {
                        Button {
                            Task { await dictation.checkModel() }
                        } label: {
                            Label("Проверить и обновить", systemImage: "arrow.down.circle")
                        }
                        Menu {
                            ForEach(DictationEngine.ModelChoice.allCases) { choice in
                                Button {
                                    Task { await dictation.selectModel(choice) }
                                } label: {
                                    if choice == dictation.selectedModel {
                                        Label(choice.displayName, systemImage: "checkmark")
                                    } else {
                                        Text("\(choice.displayName) — \(choice.note)")
                                    }
                                }
                            }
                        } label: {
                            Label("Заменить модель", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            dictation.setEnabled(!dictation.isEnabled)
                        } label: {
                            Label(
                                dictation.isEnabled ? "Выключить диктовку" : "Включить диктовку",
                                systemImage: dictation.isEnabled ? "mic.slash" : "mic"
                            )
                        }
                        // Разрушительное — всегда последним, ниже «выключить».
                        if dictation.modelState == .ready {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Удалить модель", systemImage: "trash")
                            }
                        }
                    }

                    if expandedRow == .speech {
                        speechDescription
                    }
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
        }
    }

    /// Описание модели в развёрнутой строке: что это, где работает и как
    /// управлять. Заменяет прежний отдельный абзац под карточкой.
    private var speechDescription: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Parakeet TDT v3 (NVIDIA) — \(dictation.selectedModel.note).")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            Text("Движок работает полностью на телефоне, без сервера: диктовка задач, заметок и комментариев идёт офлайн и не отправляет аудио в сеть. Понимает русский и ещё два десятка языков.")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            Text("Веса качаются один раз и живут на устройстве. Долгое нажатие на строку — скачать или обновить, заменить модель, удалить её или выключить диктовку.")
                .tfText(.action)
                .foregroundStyle(Color.tfDim)
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.bottom, TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleExpanded(_ row: ExpandedRow) {
        withAnimation(.easeInOut(duration: TFDuration.fast)) {
            expandedRow = expandedRow == row ? nil : row
        }
    }

    /// Один образец подписи на весь раздел ИИ: «Модель · что делает».
    /// Модель называем всегда, даже пока не скачана — владелец видит, что
    /// именно стоит на телефоне. Короткий отклик на действие («Модель
    /// актуальна», «Модель удалена») временно подменяет подпись.
    private var speechSubtitle: String {
        if let feedback = dictation.feedback { return feedback }
        if case .failed(let message) = dictation.modelState { return message }
        return "\(dictation.selectedModel.displayName) · диктовка задач и заметок"
    }
    private var speechValue: String {
        switch dictation.modelState {
        case .unknown: "…"
        case .notDownloaded: "скачать"
        case .downloading(let progress): "\(Int((progress * 100).rounded()))%"
        // Единое слово с серверными строками: там «работает», и локальная
        // модель не должна выбиваться («готова») — просьба владельца.
        case .ready: "работает"
        case .failed: "ошибка"
        }
    }

    // MARK: - Промпт модели (разворот в карточке)

    /// Промпт конкретной серверной способности — разворачивается ПРЯМО в
    /// карточке под строкой (владелец 20.09.2026: «промпт так же, а не
    /// отдельными всплывающими окнами»). Отдельного раздела «Свои промпты» нет.
    @ViewBuilder
    private func promptExpansion(_ row: ExpandedRow) -> some View {
        @Bindable var store = promptsStore
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            switch row {
            case .extractTasks:
                promptEditor(
                    title: "Системный промпт для задач",
                    subtitle: "Что серверная модель учитывает при разборе диктовки в задачи",
                    placeholder: promptPlaceholder(AIPromptsStore.scopeExtractTasks),
                    text: $store.extractTasksPrompt,
                    saveState: extractSaveState,
                    onCommit: { scheduleSave(scope: .extractTasks) },
                    onReset: { resetPrompt(scope: .extractTasks) }
                )
            case .journalAssist:
                promptEditor(
                    title: "Системный промпт для журнала",
                    subtitle: "Что серверная модель учитывает при «продолжить / сократить / развить» в Дневнике",
                    placeholder: promptPlaceholder(AIPromptsStore.scopeJournalAssist),
                    text: $store.journalAssistPrompt,
                    saveState: journalSaveState,
                    onCommit: { scheduleSave(scope: .journalAssist) },
                    onReset: { resetPrompt(scope: .journalAssist) }
                )
            case .actionExplain:
                promptEditor(
                    title: "Системный промпт для расшифровки действий",
                    subtitle: "Что серверная модель учитывает, объясняя, чем занят агент",
                    placeholder: promptPlaceholder(AIPromptsStore.scopeActivity),
                    text: $store.activityPrompt,
                    saveState: activitySaveState,
                    onCommit: { scheduleSave(scope: .actionExplain) },
                    onReset: { resetPrompt(scope: .actionExplain) }
                )
            case .taskIntake:
                promptEditor(
                    title: "Как собирать постановку",
                    subtitle: "Правила разбора текста в родителя с дочерними карточками: стиль названия, глубина разбиения, когда одна карточка, а когда дерево",
                    placeholder: promptPlaceholder(AIPromptsStore.scopeTaskIntake),
                    text: $store.taskIntakePrompt,
                    saveState: taskIntakeSaveState,
                    onCommit: { scheduleSave(scope: .taskIntake) },
                    onReset: { resetPrompt(scope: .taskIntake) }
                )
            default:
                EmptyView()
            }
            Text("Сервер сам подмешивает ваш промпт при вызове модели. Меняется только для вашего аккаунта, на других устройствах и в вебе появится автоматически.")
                .tfText(.caption)
                .foregroundStyle(Color.tfDim)
        }
        .padding(.bottom, TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Placeholder для поля промпта: показываем ШТАТНЫЙ серверный промпт —
    /// ровно он применяется, пока поле пустое. Он полупрозрачный и исчезает
    /// при вводе первой буквы (так устроен редактор). Сервер не отдал дефолты —
    /// обычная короткая подсказка.
    private func promptPlaceholder(_ scope: String) -> String {
        promptsStore.defaultPrompt(for: scope)
            ?? "Оставьте пустым — сервер возьмёт свой промпт по умолчанию"
    }

    @ViewBuilder
    private func promptEditor(
        title: String,
        subtitle: String,
        placeholder: String,
        text: Binding<String>,
        saveState: PromptSaveState,
        onCommit: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).tfText(.body).foregroundStyle(Color.tfText)
                Text(subtitle).tfText(.action).foregroundStyle(Color.tfSub)
            }
            // `TextEditor` с моноширинным шрифтом: промпт — код, а не
            // художественный текст, и моноширинный лучше читается при
            // редактировании многострочных инструкций.
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
                    .tfMonospaced(16, relativeTo: .callout)
                    .foregroundStyle(Color.tfText)
                    .frame(minHeight: 96, maxHeight: 160)
                    .padding(.horizontal, TFSpacing.xs)
                    .padding(.vertical, TFSpacing.xs)
                    .onChange(of: text.wrappedValue) { _, _ in onCommit() }
            }
            .background(Color.tfCard2)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: TFRadius.md)
                    .strokeBorder(Color.tfStroke, lineWidth: TFBorder.width)
            )
            HStack(spacing: TFSpacing.sm) {
                saveStatusLabel(saveState)
                Spacer()
                if !text.wrappedValue.isEmpty {
                    Button("Сбросить", action: onReset)
                        .buttonStyle(TFTapFadeStyle())
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.tfCoral)
                }
            }
        }
        .padding(TFSpacing.md)
    }

    @ViewBuilder
    private func saveStatusLabel(_ state: PromptSaveState) -> some View {
        switch state {
        case .saved:
            Label("Сохранено", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .tfText(.caption)
                .foregroundStyle(Color.tfGreen)
        case .saving:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Сохраняю…").tfText(.caption).foregroundStyle(Color.tfDim)
            }
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .tfText(.caption)
                .foregroundStyle(Color.tfRed)
                .lineLimit(2)
        }
    }

    private enum PromptScope { case extractTasks, journalAssist, actionExplain, taskIntake }

    private enum PromptSaveState: Equatable {
        case saved
        case saving
        case error(String)
    }

    /// Дебаунс 0.6с — последняя правка выигрывает; на каждом нажатии клавиши
    /// предыдущая отправка отменяется. На onDisappear делается явный flush
    /// без дебаунса, чтобы уход со страницы не терял правку.
    private func scheduleSave(scope: PromptScope) {
        switch scope {
        case .extractTasks:
            extractSaveTask?.cancel()
            extractSaveState = .saving
            extractSaveTask = Task {
                try? await Task.sleep(for: .milliseconds(600))
                if Task.isCancelled { return }
                await promptsStore.saveExtractTasksPrompt()
                if Task.isCancelled { return }
                await MainActor.run {
                    extractSaveState = saveStateFromStore(scope: .extractTasks)
                }
            }
        case .journalAssist:
            journalSaveTask?.cancel()
            journalSaveState = .saving
            journalSaveTask = Task {
                try? await Task.sleep(for: .milliseconds(600))
                if Task.isCancelled { return }
                await promptsStore.saveJournalAssistPrompt()
                if Task.isCancelled { return }
                await MainActor.run {
                    journalSaveState = saveStateFromStore(scope: .journalAssist)
                }
            }
        case .actionExplain:
            activitySaveTask?.cancel()
            activitySaveState = .saving
            activitySaveTask = Task {
                try? await Task.sleep(for: .milliseconds(600))
                if Task.isCancelled { return }
                await promptsStore.saveActivityPrompt()
                if Task.isCancelled { return }
                await MainActor.run {
                    activitySaveState = saveStateFromStore(scope: .actionExplain)
                }
            }
        case .taskIntake:
            taskIntakeSaveTask?.cancel()
            taskIntakeSaveState = .saving
            taskIntakeSaveTask = Task {
                try? await Task.sleep(for: .milliseconds(600))
                if Task.isCancelled { return }
                await promptsStore.saveTaskIntakePrompt()
                if Task.isCancelled { return }
                await MainActor.run {
                    taskIntakeSaveState = saveStateFromStore(scope: .taskIntake)
                }
            }
        }
    }

    private func resetPrompt(scope: PromptScope) {
        switch scope {
        case .extractTasks: promptsStore.extractTasksPrompt = ""
        case .journalAssist: promptsStore.journalAssistPrompt = ""
        case .actionExplain: promptsStore.activityPrompt = ""
        case .taskIntake: promptsStore.taskIntakePrompt = ""
        }
        scheduleSave(scope: scope)
    }

    private func saveStateFromStore(scope: PromptScope) -> PromptSaveState {
        if let err = promptsStore.lastSaveError { return .error(err) }
        return .saved
    }

    // MARK: - На сервере

    private var onServerSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            SettingsCapsLabel("На сервере")
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    // Тап — развернуть промпт этой способности прямо в карточке,
                    // долгое нажатие — выбор серверной модели.
                    Button { toggleExpanded(.extractTasks) } label: {
                        VoiceModelRow(
                            icon: "cpu", title: "Мозг для задач",
                            subtitle: brainSubtitle,
                            value: brainValue
                        )
                    }
                    .buttonStyle(TFTapRowStyle())
                    .contextMenu { serverModelMenu }
                    if expandedRow == .extractTasks {
                        promptExpansion(.extractTasks)
                    }

                    TFDivider(inset: rowDividerInset).padding(.trailing, rowDividerInset)
                    Button { toggleExpanded(.journalAssist) } label: {
                        VoiceModelRow(
                            icon: "cloud", title: "Разбор диктовки",
                            subtitle: serverModelSubtitle,
                            value: serverModelValue
                        )
                    }
                    .buttonStyle(TFTapRowStyle())
                    .contextMenu { serverModelMenu }
                    if expandedRow == .journalAssist {
                        promptExpansion(.journalAssist)
                    }

                    // «Расшифровка действий» живёт НА СЕРВЕРЕ: пока карточка
                    // открыта, сервер сам зовёт локальную модель и кладёт
                    // готовую фразу в активность (activity.ts, observer).
                    // На телефоне модели для этого нет — отдельного движка
                    // не заводим (решение владельца 20.09.2026).
                    TFDivider(inset: rowDividerInset).padding(.trailing, rowDividerInset)
                    Button { toggleExpanded(.actionExplain) } label: {
                        VoiceModelRow(
                            icon: "sparkles", title: "Расшифровка действий",
                            subtitle: "\(effectiveServerModelName) · чем занят агент",
                            value: serverModelValue
                        )
                    }
                    .buttonStyle(TFTapRowStyle())
                    if expandedRow == .actionExplain {
                        promptExpansion(.actionExplain)
                    }

                    // Слой владельца «как собирать постановку» (scope
                    // task_intake): им руководствуется машинная постановка,
                    // когда из текста собирается родитель + дочерние карточки.
                    TFDivider(inset: rowDividerInset).padding(.trailing, rowDividerInset)
                    Button { toggleExpanded(.taskIntake) } label: {
                        VoiceModelRow(
                            icon: "square.stack.3d.up",
                            title: "Постановка задач",
                            subtitle: "\(effectiveServerModelName) · текст в дерево карточек",
                            value: serverModelValue
                        )
                    }
                    .buttonStyle(TFTapRowStyle())
                    if expandedRow == .taskIntake {
                        promptExpansion(.taskIntake)
                    }
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
        }
    }

    /// Меню серверной модели: только проверка и замена — удаления на сервере
    /// нет (решение владельца 20.09.2026: «удалять ничего не надо, чисто
    /// замена»). В списке видно размер и распределение GPU/CPU.
    @ViewBuilder
    private var serverModelMenu: some View {
        Button {
            Task { await loadServerStatus() }
        } label: {
            Label("Проверить", systemImage: "arrow.clockwise")
        }
        Menu {
            if serverModels.isEmpty {
                Text("Не удалось получить список моделей")
            } else {
                ForEach(serverModels) { model in
                    Button {
                        selectServerModel(model.name)
                    } label: {
                        if model.name == effectiveServerModel {
                            Label(serverModelLabel(model), systemImage: "checkmark")
                        } else {
                            Text(serverModelLabel(model))
                        }
                    }
                }
            }
        } label: {
            Label("Заменить модель", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    /// «Qwen 3.6 · 27B · 9.2 ГБ · 100% на GPU» — размер и где реально лежат
    /// веса. Для незагруженной — только размер и «не загружена».
    private func serverModelLabel(_ model: AILocalModel) -> String {
        var parts = [VoiceModelsScreen.humanServerModelName(model.name)]
        if let size = model.size { parts.append(Self.modelBytes(size)) }
        if model.loaded == true {
            if let size = model.size, size > 0, let vram = model.sizeVram {
                if vram <= 0 {
                    parts.append("на CPU")
                } else {
                    let pct = Int((Double(vram) / Double(size) * 100).rounded())
                    parts.append(pct >= 99 ? "на GPU" : "\(pct)% на GPU")
                }
            } else {
                parts.append("загружена")
            }
        } else {
            parts.append("не загружена")
        }
        return parts.joined(separator: " · ")
    }

    private static func modelBytes(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f ГБ", gb) }
        return String(format: "%.0f МБ", Double(bytes) / 1_048_576)
    }

    /// Какая модель показывается в подписи: выбранная вручную, иначе — та,
    /// что отдаёт сервер (его значение по умолчанию).
    private var effectiveServerModel: String {
        if !selectedServerModel.isEmpty { return selectedServerModel }
        return serverStatus?.model ?? ""
    }

    private var effectiveServerModelName: String {
        let raw = effectiveServerModel
        return raw.isEmpty ? "Серверная модель" : VoiceModelsScreen.humanServerModelName(raw)
    }

    private func selectServerModel(_ name: String) {
        selectedServerModel = name
        AIServerModelSetting.set(name)
        Task { await loadServerStatus() }
    }

    private var brainSubtitle: String {
        "\(effectiveServerModelName) · разбивка задач на шаги"
    }
    private var brainValue: String {
        isLoadingServerStatus ? "…" : (serverStatus?.online == true ? "работает" : "нет связи")
    }

    /// Тот же образец, что у «Мозга для задач»: в заголовке функция, в
    /// подписи — «Модель · что делает». Раньше здесь модель стояла заголовком
    /// и строка выбивалась из соседней (замечание владельца 20.09.2026:
    /// «Делай по одному образцу»).
    private var serverModelSubtitle: String {
        "\(effectiveServerModelName) · диктовка, сводки и Дневник"
    }
    private var serverModelValue: String {
        guard !isLoadingServerStatus else { return "…" }
        guard let serverStatus, serverStatus.online else { return "нет связи" }
        // Про «не найдена» говорим только про модель по умолчанию: выбранную
        // вручную мы взяли из списка установленных, она по определению есть.
        if selectedServerModel.isEmpty, serverStatus.installed == false { return "не найдена" }
        return "работает"
    }

    /// Порт `serverModelName` (`src/lib/aiStatus.ts`) — «qwen3.6-27b-iq4-16k:latest» → «Qwen 3.6 · 27B».
    /// Не `private` — тем же приёмом сокращает модель `ServerStatusSection`
    /// (просьба владельца 03.09.2026: «просто Qwen 27B и всё, я и так пойму,
    /// какая это модель» — сырое `qwen3.6-27b-iq4-16k` не влезало в строку).
    static func humanServerModelName(_ raw: String) -> String {
        guard !raw.isEmpty else { return "Неизвестная модель" }
        let base = raw.split(separator: ":").first.map(String.init) ?? raw
        let lowerBase = base.lowercased()
        let family: String
        if lowerBase.contains("qwen") { family = "Qwen" }
        else if lowerBase.contains("llama") { family = "Llama" }
        else if lowerBase.contains("deepseek") { family = "DeepSeek" }
        else if lowerBase.contains("hermes") { family = "Hermes" }
        else { family = base.split(whereSeparator: { "-_.".contains($0) }).first.map(String.init) ?? base }

        var parts = [family]
        if let versionRange = base.range(of: #"\d+\.\d+"#, options: .regularExpression) {
            parts.append(String(base[versionRange]))
        }
        let name = parts.joined(separator: " ")

        if let sizeRange = base.range(of: #"\d+[bB]\b"#, options: .regularExpression) {
            let sizeDigits = base[sizeRange].dropLast() // отрезать "b"
            return "\(name) · \(sizeDigits)B"
        }
        return name
    }

    // MARK: - Диагностика диктовки (DictationLogSection)

    private var dictationLogSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            SettingsCapsLabel("Диагностика диктовки")

            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    VoiceModelRow(
                        icon: "icloud.and.arrow.up",
                        title: "Архив аудио на сервере",
                        subtitle: pendingArchiveCount == 0 ? "Всё выгружено" : "Ждут отправки: \(pendingArchiveCount). Уйдут, когда .110 будет доступен",
                        value: nil
                    )
                    TFDivider(inset: rowDividerInset).padding(.trailing, rowDividerInset)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Записывать, что распознала модель").tfText(.body).foregroundStyle(Color.tfText)
                            Text("Видно текст от модели и текст после исправлений").tfText(.action).foregroundStyle(Color.tfSub)
                        }
                        Spacer()
                        Button(isLogEnabled ? "Включено" : "Выключено") {
                            isLogEnabled.toggle()
                            DictationLog.setEnabled(isLogEnabled)
                        }
                        .buttonStyle(TFTapScaleStyle())
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isLogEnabled ? Color.tfGreen : Color.tfBlue)
                        .padding(.horizontal, TFSpacing.sm)
                        .padding(.vertical, TFSpacing.xs)
                        .background((isLogEnabled ? Color.tfGreen : Color.tfBlue).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
                    }
                    .padding(TFSpacing.md)
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)

            if isLogEnabled && logEntries.isEmpty {
                Text("Пока пусто — продиктуй что-нибудь, и запись появится здесь.")
                    .tfText(.action).foregroundStyle(Color.tfSub)
                    .padding(.horizontal, TFSpacing.screenHorizontal + TFSpacing.xs)
            }

            if !logEntries.isEmpty {
                TFCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(logEntries.enumerated()), id: \.element.at) { index, entry in
                            dictationLogRow(entry)
                            if index != logEntries.count - 1 { TFDivider() }
                        }
                    }
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)

                Button("Очистить журнал") {
                    DictationLog.clear()
                    logEntries = []
                }
                .buttonStyle(TFTapFadeStyle())
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.tfCoral)
                .padding(.horizontal, TFSpacing.screenHorizontal + TFSpacing.xs)
            }
        }
    }

    private func dictationLogRow(_ entry: DictationLogEntry) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text("\(Self.entryTimeFormatter.string(from: DateFormats.iso8601(entry.at) ?? Date())) · \(entry.engine)\(entry.raw == entry.normalized ? " · исправлений не потребовалось" : " · исправлено нами")")
                .tfText(.micro).foregroundStyle(Color.tfDim)
            Text("от модели: \(entry.raw.isEmpty ? "—" : entry.raw)")
                .tfText(.action).foregroundStyle(Color.tfSub)
            if entry.raw != entry.normalized {
                Text("после правок: \(entry.normalized)")
                    .tfText(.action).foregroundStyle(Color.tfText)
            }
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let entryTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Europe/Moscow")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var rowDividerInset: CGFloat { TFSpacing.lg + 32 + TFSpacing.md }
}

// MARK: - Строка раздела ИИ
//
// Статусы-точки убраны 20.09.2026 (владелец): статус пишется словом, точек нет.

/// Одна строка раздела ИИ — иконка/заголовок/подпись/значение
/// (`ModelRow` в вебе — здесь намеренно с префиксом `Voice`, модуль один на
/// весь таргет, `ModelRow` слишком общее имя для отдельного экрана).
///
/// С 20.09.2026 не `private`: это ЭТАЛОННЫЙ вид строки приложения (владелец:
/// «Модели и голоса — эталон»), и им же собирается профиль роли
/// (`AgentProfileScreen`), чтобы агентские экраны не выдумывали свой вид.
///
/// Точки-статусы убраны (владелец 20.09.2026): статус пишется СЛОВОМ
/// («работает», «не работает»), а не цветной точкой.
struct VoiceModelRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let value: String?

    var body: some View {
        HStack(spacing: TFSpacing.md) {
            Image(systemName: icon).font(.system(size: TFIconSize.sm)).foregroundStyle(Color.tfDim).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                // Длинные заголовки («Расшифровка действий») слегка
                // ужимаются, а не обрезаются многоточием.
                Text(title).tfText(.body).foregroundStyle(Color.tfText)
                    .lineLimit(1).minimumScaleFactor(0.8)
                // Подпись «Модель · что делает» — до двух строк: в одну она
                // физически не влезает и рвалась многоточием посреди слова.
                Text(subtitle).tfText(.action).foregroundStyle(Color.tfSub)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let value {
                Text(value).tfText(.action).foregroundStyle(Color.tfDim).lineLimit(1)
            }
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.md)
    }
}
