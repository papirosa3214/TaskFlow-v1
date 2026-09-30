import SwiftUI
import UIKit

/// Два режима задачи во всём приложении: компактная панель
/// `QuickAddTaskView` для создания и одна плоская системная шторка для
/// существующей задачи. Все поля в готовой задаче активны сразу.
struct TaskFormScreen: View {
    let taskID: String?

    private enum LinkedTaskNavigation: Identifiable, Hashable {
        case detail(String)

        var id: String {
            switch self {
            case .detail(let id): "detail-\(id)"
            }
        }
    }

    fileprivate enum DictationTarget: Equatable {
        case title, description, comment, subtask(String), newSubtask
    }

    @State private var viewModel: TaskFormViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(LabelStore.self) private var labelStore
    @Environment(SessionStore.self) private var session
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isDescriptionFocused: Bool
    @FocusState private var isCommentFocused: Bool
    @State private var dictation = DictationEngine.shared
    @State private var dictationTarget: DictationTarget = .title
    /// Фокус блока описания, живые метки форматирования и запрос ссылки —
    /// общее состояние блочного редактора (`BlockDocumentEditor`), такое же,
    /// как у заметки: лента над клавиатурой живёт вне дерева SwiftUI и
    /// обычный `@State` ей не виден.
    @State private var titleFocus = NoteEditorFocusState()
    @State private var descriptionFocus = NoteEditorFocusState()
    @State private var commentFocus = NoteEditorFocusState()
    @State private var pendingAction: AgentOwnerActionKind?
    @State private var actionComment = ""
    @State private var replyingSubtask: ApiSubtask?
    @State private var subtaskReplyText = ""
    @State private var toast: TaskToastMessage?
    @State private var isAttachmentPickerPresented = false
    /// Выбор документа из базы знаний (второй источник у «Прикрепить файл»).
    @State private var isKnowledgePickerPresented = false
    /// Вложение, которое ЗАМЕНЯЕМ (длинное нажатие → «Заменить…»): после
    /// загрузки нового старое удаляем.
    @State private var replaceAttachmentTarget: ApiAttachment?
    /// Открытый отчёт: показываем его документ-зеркало.
    @State private var openedReportNoteID: String?

    private enum AttachmentSource { case phone, knowledge }
    @State private var isDeleteConfirmationPresented = false
    @State private var linkedTaskNavigation: LinkedTaskNavigation?
    @State private var isExistingTaskPickerPresented = false
    @State private var linkedTaskQuickAddViewModel: TaskFormViewModel?
    @State private var expandedLinkedTaskViewModel: TaskFormViewModel?
    /// Тексты шагов, которые правят прямо сейчас (id шага → набранное).
    // LOCK-255: блоки вместо строки — тот же Markdown, что у названия и
    // описания задачи (владелец 30.09.2026: «вся карточка как описание»).
    @State private var subtaskTitleDrafts: [String: [NoteBlock]] = [:]
    /// Свой фокус на каждый шаг — `BlockDocumentEditor` не умеет делить
    /// один `NoteEditorFocusState` между независимыми документами.
    @State private var subtaskFocusStates: [String: NoteEditorFocusState] = [:]
    @State private var subtaskCommitTasks: [String: Task<Void, Never>] = [:]
    @FocusState private var focusedSubtaskID: String?
    // LOCK-255: тоже блоки — поле «Добавить подзадачу» больше не однострочный
    // TextField, Enter в нём теперь переносит строку (как везде в общем
    // редакторе), добавляет шаг отдельная кнопка рядом.
    @State private var newSubtaskBlocks: [NoteBlock] = [NoteBlock(kind: .paragraph)]
    @State private var newSubtaskFocus = NoteEditorFocusState()
    /// Долгое нажатие на строку → «Добавить подзадачу после» ставит сюда
    /// id той строки, вставка появляется сразу под ней (LOCK-250).
    @State private var insertAfterSubtaskID: String?
    @State private var insertSubtaskBlocks: [NoteBlock] = [NoteBlock(kind: .paragraph)]
    @State private var insertSubtaskFocus = NoteEditorFocusState()
    /// Свой фокус на каждый черновик шага в режиме создания задачи —
    /// `viewModel.subtaskDrafts`, до сохранения на сервере.
    @State private var subtaskDraftFocusStates: [UUID: NoteEditorFocusState] = [:]
    @State private var isDueEditorExpanded = false
    @State private var hasCollaborationPlan = false
    /// id черновика плана, ждущего утверждения владельцем — не nil включает
    /// пункт «Утвердить план совместной работы» в меню «Ещё» (LOCK-249).
    /// Заполняется `CollaborationPlanView.load()` через `@Binding`.
    @State private var pendingPlanApprovalId: String?
    /// Смена значения форсирует `CollaborationPlanView` пересоздаться
    /// (`.id(...)`) и заново загрузиться после утверждения плана — у неё
    /// свой `didStartLoad`, обычный `onAppear` второй раз не сработает.
    @State private var collaborationPlanReloadToken = 0
    @State private var isApprovingCollaborationPlan = false
    @State private var isSuggestingCollaborationPlan = false
    @State private var isProposingCollaborationPlan = false
    /// Какие подзаголовки карточки сейчас раскрыты. При открытии — ни
    /// одного (владелец 01.10.2026, LOCK-272: «чтобы карточка не пугала»):
    /// под свёрнутыми «Подзадачи»/«План»/«Связанные» сразу видно только то,
    /// что сейчас в работе. Раньше (LOCK-248) по умолчанию были раскрыты
    /// «Сведения» и «Лента активности». Без `AppStorage` — состояние живёт в
    /// текущей сессии экрана и сбрасывается при каждом открытии карточки.
    @State private var expandedSections: Set<TaskDetailSection> = []
    /// Итог карточки — секция «Итог» (LOCK-273). nil — не загружен или пуст.
    @State private var outcome: ApiTaskOutcome?
    /// Выведена ли карточка в Dynamic Island — чтобы в «Ещё» был пункт
    /// «Убрать», а не второй раз «Вывести».
    @State private var isInDynamicIsland = false
    @State private var isEditorReady = false
    @State private var pendingSaveTask: Task<Void, Never>?

    /// Показывает `QuickAddTaskView` как `.sheet` НАД этим экраном — временный
    /// мост, пока точка входа («+» → «Задача» в `RootShellView.swift`, App/,
    /// чужая папка) не переключена на прямой показ панели без пуша (диф —
    /// в отчёте оркестратору). Пока мост жив: перед панелью на мгновение
    /// виден пустой фон вместо экрана-источника — известный, не финальный вид.
    @State private var showQuickAdd: Bool
    /// «Развернуть» из панели — та же вью-модель (не копия: в
    /// `TaskAttachmentsController` уже могут лежать выбранные локальные
    /// файлы, копия их потеряла бы), эта же структура показывает `fullFormBody`.
    @State private var isExpanded: Bool

    /// `presetDueToday`/`startDictation` — контракт `INTEGRATION.md`,
    /// обновлён оркестратором по ходу этой задачи (`/task/new?due=today`,
    /// `/task/new?dictate=1` из `CreateMenu` веба): поле названия
    /// сфокусировано, кнопка микрофона показана. Само распознавание при
    /// тапе — `DictationEngine.shared` (просьба владельца 03.09.2026).
    init(taskID: String? = nil, presetDueToday: Bool = false, startDictation: Bool = false) {
        self.taskID = taskID
        self._viewModel = State(initialValue: TaskFormViewModel(taskID: taskID, presetDueToday: presetDueToday, startDictation: startDictation))
        self._showQuickAdd = State(initialValue: taskID == nil)
        self._isExpanded = State(initialValue: false)
    }

    /// «Развернуть» из `QuickAddTaskView` — тот же экран, СРАЗУ с готовой
    /// вью-моделью и в режиме полной формы (сохранение всё ещё «создание»:
    /// Вью-модель остаётся той же, поэтому введённые в панели данные
    /// не теряются.
    init(expandingFrom viewModel: TaskFormViewModel) {
        self.taskID = nil
        self._viewModel = State(initialValue: viewModel)
        self._showQuickAdd = State(initialValue: false)
        self._isExpanded = State(initialValue: true)
    }

    var body: some View {
        if viewModel.isEditing || isExpanded {
            fullFormBody
        } else {
            // Создание, панель ещё не показана/уже закрыта — фон-заглушка
            // моста (см. комментарий у `showQuickAdd`).
            Color.tfBackground
                .ignoresSafeArea()
                .toolbar(.hidden, for: .navigationBar)
                .fullScreenCover(isPresented: $showQuickAdd, onDismiss: {
                    // `isExpanded` к этому моменту уже true, если сюда пришли
                    // через «развернуть» (устанавливается синхронно ДО сброса
                    // showQuickAdd в onExpand ниже) — тогда экран не закрываем,
                    // а показываем `fullFormBody`. Иначе (сохранили или смахнули
                    // панель вниз) — обычное закрытие экрана создания.
                    if !isExpanded { dismiss() }
                }) {
                    QuickAddTaskView(
                        viewModel: viewModel,
                        onSaved: { showQuickAdd = false },
                        onExpand: {
                            isExpanded = true
                            showQuickAdd = false
                        }
                    )
                    // Владелец 07.09.2026: «как в Todoist — не всплывающее
                    // окно, а надстройка прямо над клавиатурой». `.sheet` с
                    // детентами тут не годится: с фокусом в поле система
                    // резервирует место под клавиатуру и перескакивает на
                    // больший детент — панель раздувалась почти на весь экран.
                    // Поэтому прозрачный `fullScreenCover`: панель сама сидит
                    // у нижней кромки и поднимается вместе с клавиатурой
                    // штатным keyboard avoidance, фон мутит `QuickAddTaskView`.
                    .presentationBackground(.clear)
                }
        }
    }

    private var fullFormBody: some View {
        formNavigationBody
            .task { await loadScreen() }
            .modifier(FocusDictationTargetModifier(
                isTitleFocused: isTitleFocused,
                isDescriptionFocused: isDescriptionFocused,
                isCommentFocused: isCommentFocused,
                dictationTarget: $dictationTarget,
                scheduleSave: scheduleSave
            ))
            .modifier(AutosaveFieldsModifier(viewModel: viewModel, scheduleSave: scheduleSave))
            .onDisappear(perform: handleDisappear)
    }

    private var formNavigationBody: some View {
        formPresentationBody
            .navigationDestination(item: $linkedTaskNavigation) { destination in
                switch destination {
                case .detail(let id):
                    TaskFormScreen(taskID: id)
                }
            }
            .sheet(isPresented: $isExistingTaskPickerPresented) {
                LinkedTaskPicker(
                    tasks: taskStore.tasks,
                    excludedIDs: linkedTaskExcludedIDs,
                    onSelect: { task in await viewModel.linkExistingTask(task) }
                )
            }
            .fullScreenCover(isPresented: linkedTaskQuickAddPresented, onDismiss: {
                Task { await viewModel.loadIfNeeded() }
            }) {
                if let linkedTaskQuickAddViewModel {
                    QuickAddTaskView(
                        viewModel: linkedTaskQuickAddViewModel,
                        onSaved: { self.linkedTaskQuickAddViewModel = nil },
                        onExpand: { expandLinkedTaskQuickAdd(linkedTaskQuickAddViewModel) }
                    )
                    .presentationBackground(.clear)
                }
            }
            // LOCK-253: та же шторка, что у обычной задачи (см. RootShellView.swift) —
            // развёрнутая форма создания дочерней задачи не должна отличаться
            // от открытия существующей.
            .sheet(isPresented: expandedLinkedTaskPresented, onDismiss: {
                Task { await viewModel.loadIfNeeded() }
            }) {
                if let expandedLinkedTaskViewModel {
                    NavigationStack {
                        TaskFormScreen(expandingFrom: expandedLinkedTaskViewModel)
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color.tfSheetBackground)
                }
            }
            .onChange(of: linkedTaskNavigation) { previous, current in
                if previous != nil, current == nil { Task { await viewModel.loadIfNeeded() } }
            }
    }

    private var formPresentationBody: some View {
        // Урок 2026-09-25 (чёрные треугольники в углах системной клавиатуры,
        // iOS 26): фон нужен ОДНИМ слоем на самом верху этого тела, через
        // `ZStack` + `.ignoresSafeArea()` без ограничения edges — регион
        // `.keyboard` входит в `.all` по умолчанию. Фон на внутреннем
        // контейнере (было — `.background(...)` прямо на `VStack`) не
        // достаёт до угла клавиатуры: тот стоит НАД ней, а не под. Уже
        // применено так в `RoleChatRoomScreen`; здесь раньше фон был на
        // внутреннем VStack — тот же класс бага, что владелец описывал как
        // «чёрные уголки рядом с клавиатурой».
        ZStack {
            Color.tfBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if viewModel.isLoadingTask {
                    TFLoading(.block)
                    Spacer()
                } else if viewModel.notFound {
                    Spacer()
                    TFEmptyState(text: "Задача не найдена")
                    Spacer()
                } else {
                    // Одна форма на всё: развёрнутое создание выглядит и ведёт
                    // себя ровно как открытая задача. Владелец 11.09.2026 —
                    // «расширенную форму заменить на нашу стандартную обычную».
                    // Отдельной анкеты (`TFCollapsibleSection` + `TFFieldGroup`)
                    // больше нет.
                    nativeTaskDetail
                }
            }
        }
        // AUD-001: свой header (× слева, «Готово»/«Сохранение…» справа) был
        // ВТОРЫМ рядом с системным навбаром — тут не просто дубль текста,
        // а форма с семантикой отмены/сохранения, обычный «‹ Назад» её не
        // заменяет. Штатный путь — `navigationBarBackButtonHidden` + свой
        // toolbar вместо самодельной шапки.
        .tfNativeHeader("", displayMode: .inline)
        // Мягкая кромка прокрутки под шапкой (iOS 26+).
        //
        // По умолчанию система гасит уезжающий контент жёстко: на кадре
        // 16.09.2026 текст обрывался ровно по горизонтальной линии — строка
        // «Кегли-сироты…» срезана посередине, выше линии буквы притушены,
        // ниже целые. Владелец: «градация прям чёткая, есть линия, не мутная».
        //
        // `.soft` растягивает затухание, и текст уходит под шапку размыто,
        // без видимой границы. Это штатный путь Apple вместо самодельных
        // градиентных подложек (ср. TFHeaderBackdrop, который делает то же
        // руками там, где шапка не нативная).
        //
        // Цель сборки — iOS 18, поэтому под проверкой доступности: на
        // старых системах эффекта нет вовсе и кромка остаётся прежней.
        .modifier(TFSoftTopScrollEdge())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // LOCK-254: без `Spacer()` — с ним iOS 26 рисует дисмисс и
            // диктовку как два отдельных стеклянных «шарика» по разным
            // краям клавиатуры, а не одну пилюлю (владелец 30.09.2026,
            // после Lock 1: «как были два отдельных шарика, так и есть»).
            // Рядом друг с другом система объединяет их в одну капсулу —
            // тот же визуальный язык, что у Markdown-панели.
            ToolbarItemGroup(placement: .keyboard) {
                taskKeyboardDismissButton
                taskKeyboardDictationButton
            }
            if viewModel.agentState != nil || (viewModel.attemptLadder?.currentStep ?? 0) > 0 {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: TFSpacing.sm) {
                        if let state = viewModel.agentState {
                            Label(agentStateText(state), systemImage: agentStateIcon(state))
                                .tfText(.caption)
                                .foregroundStyle(agentStateColor(state))
                        }
                        if let ladder = viewModel.attemptLadder, ladder.currentStep > 0 {
                            AttemptLadderView(ladder: ladder, agentState: viewModel.agentState)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task {
                        // Отложенное сохранение перебиваем здесь, а не внутри
                        // `saveExistingEdits` — см. комментарий у метода.
                        pendingSaveTask?.cancel()
                        if viewModel.isEditing { await saveExistingEdits() }
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Закрыть")
            }
            if viewModel.isEditing {
                editingToolbarItems
            } else {
                if viewModel.showAiButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        aiStructureButton
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await submit() }
                    } label: {
                        Text(viewModel.isSaving ? "Сохранение…" : "Готово")
                            .fontWeight(.semibold)
                    }
                    .tint(Color.tfRed)
                    .disabled(!viewModel.isSaveEnabled)
                }
            }
        }
        .confirmationDialog("Удалить задачу?", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await deleteCurrentTask() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Задача будет удалена без возможности восстановления.")
        }
        .alert("Комментарий", isPresented: Binding(
            get: { pendingAction != nil },
            set: { if !$0 { pendingAction = nil } }
        ), presenting: pendingAction) { action in
            TextField(action.commentRequired ? "Комментарий (обязателен)" : "Комментарий (необязательно)", text: $actionComment)
            Button("Отправить") {
                // `Task` начинает выполняться после возврата из обработчика,
                // поэтому перед сбросом alert сохраняем снимок текста. Иначе
                // review → in_progress уходит без обязательного comment.
                let comment = TaskFormViewModel.ownerActionCommentForSubmission(actionComment)
                actionComment = ""
                pendingAction = nil
                Task { await viewModel.performOwnerAction(action, comment: comment, taskStore: taskStore) }
            }
            .disabled(action.commentRequired && actionComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Отмена", role: .cancel) {
                actionComment = ""
                pendingAction = nil
            }
        }
        .alert("Ответ агенту", isPresented: Binding(
            get: { replyingSubtask != nil },
            set: { if !$0 { replyingSubtask = nil } }
        ), presenting: replyingSubtask) { subtask in
            TextField("Комментарий", text: $subtaskReplyText)
            Button("Отправить") {
                Task { await viewModel.replyToSubtask(subtask, text: subtaskReplyText) }
                subtaskReplyText = ""
                replyingSubtask = nil
            }
            .disabled(subtaskReplyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Отмена", role: .cancel) {
                subtaskReplyText = ""
                replyingSubtask = nil
            }
        }
        .taskToast($toast)
        .fileImporter(
            isPresented: $isAttachmentPickerPresented,
            allowedContentTypes: [.item],
            onCompletion: handleAttachmentImport
        )
        .sheet(isPresented: $isKnowledgePickerPresented) {
            KnowledgePickerSheet { noteID, title in
                let old = replaceAttachmentTarget
                replaceAttachmentTarget = nil
                Task {
                    await attachKnowledgeNote(noteID: noteID, title: title)
                    if let old { await viewModel.attachments.removeUploaded(old) }
                }
            }
            .onDisappear { replaceAttachmentTarget = nil }
        }
        .sheet(isPresented: Binding(
            get: { openedReportNoteID != nil },
            set: { if !$0 { openedReportNoteID = nil } }
        )) {
            if let noteID = openedReportNoteID {
                NavigationStack { NoteEditorScreen(noteID: noteID) }
            }
        }
    }

    /// Длинное нажатие на вложение → «Заменить…»: запоминаем, что меняем, и
    /// открываем нужный источник. После успешной загрузки старое удаляется.
    private func replaceAttachment(from source: AttachmentSource, target: ApiAttachment) {
        replaceAttachmentTarget = target
        switch source {
        case .phone: isAttachmentPickerPresented = true
        case .knowledge: isKnowledgePickerPresented = true
        }
    }

    /// Единая карточка существующей задачи: это одновременно и просмотр,
    /// и форма. Никакого второго экрана за «Изменить» больше нет: название,
    /// описание и все свойства задачи активны прямо здесь.
    // 15.09.2026: список карточки развалился на секции-переменные.
    // Одним куском его тип вырастал настолько, что рантайм не мог
    // развернуть имя типа и падал переполнением стека на устройстве
    // (в симуляторе стек больше — там держалось). Вид и поведение
    // прежние, поделены только границы.
    @ViewBuilder private var headerSection: some View {
            Section {
                // Итог перечитывается, когда меняется состояние карточки
                // (например, проверяющий вынес вердикт) — LOCK-273.
                Color.clear
                    .frame(height: 0)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .task(id: outcomeReloadKey) { await loadOutcome() }
                VStack(spacing: 0) {
                    titleBlockTopDivider
                    // Владелец 30.09.2026: «вся карточка как описание» —
                    // тот же `BlockDocumentEditor`, что у описания и у
                    // заметки (13.09.2026), просто своим шрифтом/цветом.
                    // Инлайн-разметка (жирный/курсив/…) теперь доступна и
                    // в названии; заголовки/списки/код-блок технически
                    // тоже доступны через ту же ленту — отдельно не
                    // урезаны, раз просили «точно как описание, без
                    // ограничений».
                    BlockDocumentEditor(
                        blocks: $viewModel.titleBlocks,
                        focus: titleFocus,
                        placeholder: "Название задачи",
                        baseFontOverride: UIFontMetrics(forTextStyle: .headline)
                            .scaledFont(for: .systemFont(ofSize: 17, weight: .regular)),
                        textColor: UIColor(Color.tfText),
                        onEdit: { scheduleSave() }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowSeparator(.hidden)
                    titleBlockBottomDivider
                }
                .listRowSeparator(.hidden)
            }
            .listRowBackground(Color.tfBackground)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
    }

    /// Границы блока названия: одна физическая точка, чуть заметнее
    /// стандартного `Divider`, без добавления высоты или отступов строки.
    private var titleBlockDivider: some View {
        Color.tfDim
            .opacity(0.45)
            .frame(maxWidth: .infinity)
            .frame(height: 1 / UIScreen.main.scale)
    }

    private var titleBlockTopDivider: some View {
        titleBlockDivider.offset(y: -14)
    }

    private var titleBlockBottomDivider: some View {
        titleBlockDivider.offset(y: 15)
    }

    /// Чип «Сведения» — владелец 28.09.2026: срок/проект/приоритет/метки
    /// сжаты в один ряд ярлычков вместо четырёх полноширинных строк.
    @ViewBuilder
    private func detailChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .tfText(.action)
        .foregroundStyle(Color.tfSub)
        .padding(.horizontal, TFSpacing.sm)
        .padding(.vertical, 6)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
    }

    /// Содержимое секции «Сведения»: ряд чипов (срок/проект/приоритет/метки),
    /// редактор срока (`isDueEditorExpanded` — отдельный toggle по тапу на
    /// чип «Срок»), исполнитель и создатель. Контент отделён от обёртки —
    /// оборачивается `collapsibleSection` в `nativeTaskDetailBody`
    /// (LOCK-248).
    @ViewBuilder private var detailsContent: some View {
            FlowLayout(spacing: TFSpacing.sm) {
                Button {
                    isDueEditorExpanded.toggle()
                } label: {
                    detailChip(icon: "calendar", text: nativeDueText)
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Без проекта") { viewModel.projectId = nil }
                    ForEach(projectStore.projects) { project in
                        Button {
                            viewModel.projectId = project.id
                        } label: {
                            if viewModel.projectId == project.id {
                                Label(project.name, systemImage: "checkmark")
                            } else {
                                Text(project.name)
                            }
                        }
                    }
                } label: {
                    detailChip(icon: "folder", text: projectStore.projects.first { $0.id == viewModel.projectId }?.name ?? "Без проекта")
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(TaskPriority.allCases, id: \.rawValue) { priority in
                        Button {
                            viewModel.priority = priority
                        } label: {
                            if viewModel.priority == priority {
                                Label(priority.label, systemImage: "checkmark")
                            } else {
                                Text(priority.label)
                            }
                        }
                    }
                } label: {
                    detailChip(icon: "flag", text: viewModel.priority.label)
                }
                .buttonStyle(.plain)

                Menu {
                    if labelStore.labels.isEmpty {
                        Text("Нет доступных меток")
                    } else {
                        ForEach(labelStore.labels) { label in
                            Button {
                                let binding = labelBinding(label.id)
                                binding.wrappedValue.toggle()
                            } label: {
                                if viewModel.selectedLabelIds.contains(label.id) {
                                    Label(label.name, systemImage: "checkmark")
                                } else {
                                    Text(label.name)
                                }
                            }
                        }
                    }
                } label: {
                    detailChip(icon: "tag", text: nativeLabelsText)
                }
                .buttonStyle(.plain)
            }

            // Тап по чипу «Срок» открывает тот же компактный редактор
            // прямо под рядом чипов, не на весь экран.
            if isDueEditorExpanded {
                ExistingTaskDueEditor(
                    dueDate: $viewModel.dueDate,
                    startMinutes: $viewModel.startMinutes,
                    durationMin: $viewModel.durationMin,
                    runRepeat: $viewModel.runRepeat,
                    repeatUntil: $viewModel.repeatUntil
                )
            }

            // «Исполнитель» и «Создал» отсюда убраны (владелец 01.10.2026,
            // LOCK-272): создателя видно в ленте активности, исполнитель
            // выбирается в кнопке «Работа» и сразу запускается.
    }

    // 15.09.2026: тип экрана стирается здесь намеренно. Цепочка
    // body → fullFormBody → formNavigationBody → formPresentationBody →
    // List копила такой generic-тип, что рантайм не мог развернуть его
    // имя и падал переполнением стека прямо при открытии карточки на
    // устройстве. AnyView разрывает цепочку: дальше вглубь тип не растёт.
    private var nativeTaskDetail: AnyView { AnyView(nativeTaskDetailBody) }

    private var nativeTaskDetailBody: some View {
        List {
            aiStructureStatusSection

            if let message = viewModel.saveErrorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .listRowSeparator(.hidden)
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
            }

            headerSection

            collapsibleSection(.description, title: "Описание") {
                // Тот же редактор, что в заметке: те же строки блоков, та же
                // лента над клавиатурой, тот же Enter/Backspace. Владелец
                // 13.09.2026 — «один единый формат с заметками».
                BlockDocumentEditor(
                    blocks: $viewModel.taskDescriptionBlocks,
                    focus: descriptionFocus,
                    placeholder: "Описание",
                    baseFontOverride: UIFont.preferredFont(forTextStyle: .footnote),
                    textColor: UIColor(Color.tfSub),
                    onEdit: { scheduleSave() }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowSeparator(.hidden)
            }

            collapsibleSection(.details, title: "Сведения") { detailsContent }

            // Секция целиком скрыта, пока не подтверждено, что approved-план
            // есть — иначе на обычных карточках оставалась бы пустая строка.
            if let taskID = viewModel.taskID {
                if hasCollaborationPlan {
                    collapsibleSection(.collaborationPlan, title: "План совместной работы") {
                        CollaborationPlanView(taskId: taskID, subtasks: viewModel.subtasks, hasApprovedPlan: $hasCollaborationPlan, pendingApprovalPlanId: $pendingPlanApprovalId)
                            .id(collaborationPlanReloadToken)
                            .listRowSeparator(.hidden)
                    } preview: {
                        ForEach(runningSubtasks.filter { $0.collaborationPlanId != nil }) { subtask in
                            planNodeInWorkRow(subtask)
                        }
                    }
                } else {
                    CollaborationPlanView(taskId: taskID, subtasks: viewModel.subtasks, hasApprovedPlan: $hasCollaborationPlan, pendingApprovalPlanId: $pendingPlanApprovalId)
                        .id(collaborationPlanReloadToken)
                        .frame(width: 0, height: 0)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listSectionSeparator(.hidden)
                }
            }

            // Итог: вердикт, что сдала каждая роль, документы, код (LOCK-273).
            if let outcome, !outcome.isEmpty {
                collapsibleSection(.outcome, title: "Итог") {
                    TaskOutcomeContent(
                        outcome: outcome,
                        roleTitle: { key in viewModel.roles.first { $0.role == key }?.title ?? key },
                        onToast: { toast = TaskToastMessage($0) }
                    )
                }
            }

            collapsibleSection(.subtasks, title: "Подзадачи") {
                subtasksContent
            } preview: {
                ForEach(runningSubtasks) { subtask in
                    nativeSubtaskRow(subtask)
                }
            }

            // У несохранённой задачи связывать нечего — секция появляется
            // вместе с самой задачей. Исключение — создание дочерней:
            // родитель уже известен и должен быть виден до сохранения.
            collapsibleSection(.linkedTasks, title: "Связанные задачи") {
                linkedTasksContent
            } preview: {
                if let parent = viewModel.parentTask, Self.isInWork(parent) {
                    linkedTaskRow(parent, relation: "Родительская")
                }
                ForEach(viewModel.childTasks.filter(Self.isInWork)) { child in
                    linkedTaskRow(child, relation: "Дочерняя")
                }
            }

            // Лента идёт сразу после связанных задач — это завершающий блок
            // основного сценария карточки.
            collapsibleSection(.journal, title: "Лента активности") {
                    // Было — Enter отправлял комментарий (11.09.2026:
                    // «хочу написать комментарий, не работает»), и клавиша
                    // Return рисовалась синей «Отправить». Владелец
                    // 30.09.2026 переопределил это явно: «Интер не
                    // отправляет сообщения ни в одном месте приложения,
                    // Интер делает только новую строку» — тот же принцип,
                    // что уже в `ChatVoiceComposer.swift` (21.09.2026).
                    // Теперь Enter — обычный перенос строки, отправка —
                    // только явной кнопкой. Кнопке нужен `.borderless`,
                    // иначе `List` отдаёт ей тап по всей строке, включая поле.
                    // Владелец 30.09.2026: «вся карточка как описание» —
                    // тот же `BlockDocumentEditor`, что у названия и
                    // описания. `onSubmit`/Enter здесь нет вообще — Enter
                    // просто новый блок, отправка только кнопкой.
                    HStack(alignment: .bottom) {
                        BlockDocumentEditor(
                            blocks: $viewModel.commentBlocks,
                            focus: commentFocus,
                            placeholder: "Комментарий",
                            textColor: UIColor(Color.tfSub)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Отправить") { Task { await viewModel.sendComment() } }
                            .buttonStyle(.borderless)
                            .disabled(
                                !viewModel.isEditing
                                || viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                    }
                    ForEach(viewModel.journalEntries) { entry in
                        nativeJournalRow(entry)
                            .listRowSeparator(.hidden)
                    }
            }

            // Чаты, привязанные к задаче. Секция только ПЕРЕХОДИТ в переписку:
            // свой чат внутри карточки не заводится и не рисуется — для этого есть
            // отдельный экран (владелец 21.09.2026: «заводить прям чат прямо в
            // карточке не надо, надо чтобы просто переходил»). Появляется только
            // когда чат уже привязан — со стороны чата.
            if !viewModel.taskChats.isEmpty {
                collapsibleSection(.chatByTask, title: "Чат по задаче") {
                    chatByTaskContent
                }
            }

            if !viewModel.attachments.uploaded.isEmpty || !viewModel.attachments.pending.isEmpty {
                collapsibleSection(.attachments, title: "Вложения") {
                    ForEach(viewModel.attachments.uploaded) { attachment in
                        Label(attachment.fileName, systemImage: "paperclip")
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .contextMenu {
                                Button { replaceAttachment(from: .phone, target: attachment) } label: {
                                    Label("Заменить с iPhone", systemImage: "iphone")
                                }
                                Button { replaceAttachment(from: .knowledge, target: attachment) } label: {
                                    Label("Заменить из базы знаний", systemImage: "books.vertical")
                                }
                                Button(role: .destructive) {
                                    Task { await viewModel.attachments.removeUploaded(attachment) }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await viewModel.attachments.removeUploaded(attachment) }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                    ForEach(viewModel.attachments.pending) { attachment in
                        Label(attachment.fileName, systemImage: "paperclip")
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .swipeActions {
                                Button(role: .destructive) {
                                    viewModel.attachments.removePending(attachment)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            // Отчёты — «зеркало» документов из папки проекта: сам файл лежит
            // в документации, здесь название, автор и время; тап открывает
            // документ. Владелец 20.09.2026.
            if !viewModel.reports.isEmpty {
                collapsibleSection(.reports, title: "Отчёты") {
                    ForEach(viewModel.reports) { report in
                        Button {
                            if let noteID = report.noteID { openedReportNoteID = noteID }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(report.title, systemImage: "doc.text")
                                    .tfText(.action)
                                    .foregroundStyle(Color.tfText)
                                Text(reportSubtitle(report))
                                    .tfText(.caption)
                                    .foregroundStyle(Color.tfDim)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        }
        // Владелец 07.09.2026: «размести все элементы плоско, без лишних
        // подложек» — `Form` не всегда честно слушается `.listStyle(.plain)`
        // (осталась подложка-карточка под секциями даже после смены стиля),
        // `List` его уважает по-настоящему.
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        // Карточка получалась полосатой: промежутки и заголовки секций шли на
        // нашем фоне, а сами строки — на системном чёрном, и это било в глаза
        // (владелец 09.09.2026: «текст задачи, текст описания — чёрный, он
        // должен быть везде одинаковым»). Гасим и подложку списка, и подложку
        // строк, оставляя один фон на весь экран.
        .listRowBackground(Color.tfBackground)
        .scrollContentBackground(.hidden)
        .background(Color.tfBackground)
        .scrollDismissesKeyboard(.interactively)
        // Ушли из строки шага — сохранили её название. Тот же принцип, что
        // у названия задачи выше: отдельной кнопки «сохранить» нет.
        .onChange(of: focusedSubtaskID) { previous, current in
            if let current { dictationTarget = .subtask(current) }
            guard let previous,
                  let subtask = viewModel.subtasks.first(where: { $0.id == previous })
            else { return }
            commitSubtaskTitle(subtask)
        }
        // Системный List сохраняет свою структуру, но между подряд идущими
        // свёрнутыми заголовками оставляет примерно вдвое меньше воздуха.
        .listSectionSpacing(TFSpacing.sm)
        // LOCK-254/255: тот же системный ScrollEdgeEffect (iOS 26), что уже
        // выключали в чате (`ChatVoiceComposer.swift:315-325`, владелец
        // 26.09.2026: «какая-то подложка/повидла») — там, где список
        // упирается в клавиатуру/аксессуар. Раньше в карточке задачи его не
        // было видно, потому что ни одно поле не имело своего
        // `inputAccessoryView`; теперь у подзадач/названия/описания/
        // комментария он есть, и та же подложка стала видна здесь тоже
        // (владелец 30.09.2026, кадр с серой полосой над панелью подзадачи).
        .hideComposerScrollEdgeEffect()
        .refreshable { await viewModel.refresh() }
    }

    /// Контент секции «Связанные задачи» (LOCK-248). Обёртку `Section`
    /// формирует `collapsibleSection` в `nativeTaskDetailBody` — здесь только
    /// содержимое.
    @ViewBuilder private var linkedTasksContent: some View {
        if let parent = viewModel.parentTask {
            linkedTaskRow(parent, relation: "Родительская")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        Task { await viewModel.unlinkFromParent() }
                    } label: {
                        Label("Отвязать", systemImage: "link.badge.minus")
                    }
                }
        }

        ForEach(viewModel.childTasks) { child in
            linkedTaskRow(child, relation: "Дочерняя")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        Task { await viewModel.unlinkChildTask(child) }
                    } label: {
                        Label("Отвязать", systemImage: "link.badge.minus")
                    }
                }
        }

        if viewModel.parentTask == nil, viewModel.childTasks.isEmpty {
            if viewModel.isEditing {
                Button {
                    startLinkedTaskQuickAdd()
                } label: {
                    Text("Добавить связанную задачу")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                }
            } else {
                Button { isExistingTaskPickerPresented = true } label: {
                    Text("Выбрать родительскую задачу")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                }
            }
        }
    }

    /// Контент секции «Чат по задаче». Появляется только когда есть
    /// привязанные чаты — условие снаружи (LOCK-248). Контент отделён от
    /// обёртки.
    @ViewBuilder private var chatByTaskContent: some View {
        ForEach(viewModel.taskChats) { chat in
            NavigationLink(value: AppRoute.roleChat(id: chat.id)) {
                HStack(spacing: TFSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chat.displayTitle)
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(2)
                        if let members = chat.membersCount, members > 0 {
                            Text("Участников: \(members)")
                                .tfText(.meta)
                                .foregroundStyle(Color.tfDim)
                        }
                    }
                    Spacer(minLength: TFSpacing.sm)
                }
                .contentShape(Rectangle())
            }
        }
    }

    /// Шаги, над которыми сейчас работают, — видны и под свёрнутым
    /// заголовком (LOCK-272).
    private var runningSubtasks: [ApiSubtask] {
        viewModel.subtasks.filter { !$0.done && ($0.state == .running || $0.agentState == .inProgress) }
    }

    private static func isInWork(_ task: ApiTask) -> Bool {
        task.status != .completed && task.agentState == .inProgress
    }

    /// Узел плана в работе под свёрнутым «Планом совместной работы»: роль и
    /// что она делает.
    private func planNodeInWorkRow(_ subtask: ApiSubtask) -> some View {
        let role = viewModel.roles.first { "role_\($0.role)" == subtask.agentId }?.title ?? "Роль"
        return HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            Image(systemName: "play.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating)
            Text(role)
                .tfText(.action)
                .foregroundStyle(Color.tfText)
            Text(subtask.title)
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role) в работе: \(subtask.title)")
    }

    private func linkedTaskRow(_ task: ApiTask, relation: String) -> some View {
        let status = linkedTaskStatus(task)
        return Button {
            linkedTaskNavigation = .detail(task.id)
        } label: {
            HStack(spacing: TFSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(2)
                    Label("\(relation) · \(status.text)", systemImage: status.icon)
                        .tfText(.meta)
                        .foregroundStyle(status.color)
                }
                Spacer(minLength: TFSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .accessibilityHint("Открывает связанную задачу")
        .listRowSeparator(.hidden)
    }

    private func linkedTaskStatus(_ task: ApiTask) -> (icon: String, text: String, color: Color) {
        if task.status == .completed {
            return ("checkmark.circle.fill", "Выполнена", .green)
        }
        switch task.agentState {
        case .review:
            return ("eye.fill", "На ревью", .blue)
        case .blocked:
            return ("exclamationmark.triangle.fill", "Заблокирована", .orange)
        case .inProgress:
            return ("play.circle.fill", "В работе", .secondary)
        case .todo:
            return ("clock.arrow.circlepath", "В очереди", .secondary)
        case nil:
            return ("circle", "Открыта", .secondary)
        }
    }

    @ViewBuilder
    private var aiStructureStatusSection: some View {
        switch viewModel.aiStructureStatus {
        case .idle:
            EmptyView()
        case .processing:
            Section {
                HStack(spacing: TFSpacing.sm) {
                    ProgressView()
                    Text("AI структурирует задачу…")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("AI структурирует задачу")
            }
            .listRowBackground(Color.tfBackground)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        case .completed:
            Section {
                Label("Структура готова", systemImage: "checkmark.circle")
            }
            .listRowBackground(Color.tfBackground)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            .listRowBackground(Color.tfBackground)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        }
    }

    private var linkedTaskQuickAddPresented: Binding<Bool> {
        Binding(get: { linkedTaskQuickAddViewModel != nil }, set: { if !$0 { linkedTaskQuickAddViewModel = nil } })
    }

    private var expandedLinkedTaskPresented: Binding<Bool> {
        Binding(get: { expandedLinkedTaskViewModel != nil }, set: { if !$0 { expandedLinkedTaskViewModel = nil } })
    }

    private func startLinkedTaskQuickAdd() {
        guard let taskID else { return }
        linkedTaskQuickAddViewModel = TaskFormViewModel(taskID: nil, parentTaskID: taskID, parentTaskTitle: viewModel.title, presetProjectID: viewModel.projectId)
    }

    private func expandLinkedTaskQuickAdd(_ linkedViewModel: TaskFormViewModel) {
        linkedTaskQuickAddViewModel = nil
        DispatchQueue.main.async { expandedLinkedTaskViewModel = linkedViewModel }
    }

    private func taskSectionHeader(_ title: String) -> some View {
        Text(title)
            .tfText(.taskTitle)
            .fontWeight(.semibold)
            .foregroundStyle(Color.tfText)
            .textCase(nil)
            // Без `.underline()` (владелец 28.09.2026: «полоска другого цвета
            // под подзаголовком» — это она и была). Акцент держим
            // `fontWeight(.semibold)` + `tfText(.title)`; рамок и линий
            // карточка задачи не рисует.
    }

    /// Тапабельный заголовок секции-«аккордеона»: тот же `taskSectionHeader`,
    /// + справа шеврон (вверх/вниз) — единственный сигнал свёрнутости.
    /// Тап переключает членство в `expandedSections` с пружинистой
    /// анимацией; само содержимое секции оборачивается через
    /// `collapsibleSection` (LOCK-248).
    @ViewBuilder
    private func collapsibleHeader(_ section: TaskDetailSection, _ title: String) -> some View {
        let expanded = expandedSections.contains(section)
        Button {
            withAnimation(.easeInOut(duration: TFDuration.fast)) {
                if expanded { expandedSections.remove(section) }
                else { expandedSections.insert(section) }
            }
        } label: {
            HStack(spacing: TFSpacing.sm) {
                taskSectionHeader(title)
                Spacer(minLength: 0)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(expanded ? "Свернуть" : "Развернуть")
    }

    /// Обёртка секции списка под аккордеон: контент показывается только
    /// когда ключ в `expandedSections`. Когда свёрнута — секция пустая,
    /// остаётся только заголовок (LOCK-248).
    @ViewBuilder
    private func collapsibleSection<Content: View>(
        _ section: TaskDetailSection,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        collapsibleSection(section, title: title, content: content, preview: { EmptyView() })
    }

    /// То же, но свёрнутая секция показывает `preview` — то, что сейчас в
    /// работе (LOCK-272). Выполнилось — строка уходит обратно под шеврон.
    @ViewBuilder
    private func collapsibleSection<Content: View, Preview: View>(
        _ section: TaskDetailSection,
        title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        Section {
            if expandedSections.contains(section) {
                content()
            } else {
                preview()
            }
        } header: {
            collapsibleHeader(section, title)
        }
        .listRowBackground(Color.tfBackground)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
    }

    private var linkedTaskExcludedIDs: Set<String> {
        var ids = viewModel.ancestorTaskIDs
        ids.formUnion(viewModel.childTasks.map(\.id))
        if let taskID { ids.insert(taskID) }
        return ids
    }

    /// Шаг: строка, а под ней — то, что к ней относится.
    ///
    /// Владелец 09.09.2026: живая работа агента должна читаться на самом шаге,
    /// а не отдельной плашкой сверху. «Понаставят агента сразу пять в
    /// активностях — а так я реально вижу, по какой он работает». Поэтому:
    /// у идущего шага вместо пустого кружка крутится кольцо, тап по названию
    /// раскрывает под ним, что агент делает прямо сейчас; шаг закрыт — тот же
    /// тап показывает оставленный итог. Ничего не меняется в привычке: щёлкнул
    /// и смотришь, просто содержимое зависит от состояния шага.
    ///
    /// `DisclosureGroup` не используем — он рисует шеврон, а владелец их
    /// не хочет («функционал оставить, эффект тот же»). Раскрытие своё, по
    /// тапу на название; кружок остаётся отдельной кнопкой «сделано», иначе
    /// один жест значил бы две разные вещи.
    @ViewBuilder
    private func nativeSubtaskRow(_ subtask: ApiSubtask) -> some View {
        let isRunning = subtask.state == .running
        let hasDetails = subtask.result?.isEmpty == false
            || subtask.agentState == .blocked
            || subtask.agentState == .review
            || (isRunning && viewModel.activity.isActive)

        return VStack(alignment: .leading, spacing: TFSpacing.sm) {
            HStack(spacing: TFSpacing.md) {
                Button {
                    guard subtask.agentState != .review else { return }
                    Task { await viewModel.toggleSubtaskDone(subtask) }
                } label: {
                    subtaskMark(subtask, isRunning: isRunning)
                }
                .buttonStyle(.plain)
                .disabled(subtask.agentState == .review)
                // Отметка слева — иконка без текста, поэтому подпись задаём
                // явно и покрываем ОБЕ ветки `subtaskMark`: кольцо при running
                // и системную иконку во всех остальных состояниях.
                .accessibilityLabel(
                    isRunning
                        ? TFSubtaskState.running.label
                        : (subtask.done ? "Шаг выполнен" : "Отметить шаг выполненным")
                )
                .accessibilityHint(subtask.agentState == .review ? "" : "Переключает отметку шага")

                // Текст шага — обычное поле, как название и описание выше:
                // тап ставит курсор, правка уходит на сервер по вводу или
                // по уходу фокуса. Аккордеон с шевроном (раскрыть/свернуть
                // подробности) здесь больше не нужен — тап теперь означает
                // «правлю», а подробности показываются сами, когда есть.
                // Зачёркивания у сделанного шага нет: владелец 11.09.2026 —
                // «мне ж надо смотреть, как они называются». Что шаг закрыт,
                // видно по галочке слева.
                // Многострочное поле (длинные названия шагов видны целиком),
                // поэтому Return здесь переносит строку, а не сохраняет —
                // правка уходит на сервер, когда фокус покидает строку
                // (см. `.onChange(of: focusedSubtaskID)` у списка).
                BlockDocumentEditor(
                    blocks: subtaskTitleBinding(subtask),
                    focus: subtaskFocus(for: subtask),
                    placeholder: "Шаг",
                    textColor: UIColor(Color.tfSub),
                    onEdit: { scheduleSubtaskCommit(subtask) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if hasDetails {
                subtaskDetails(subtask, isRunning: isRunning)
                    .padding(.leading, 21 + TFSpacing.md)
            }
        }
        .listRowSeparator(.hidden)
        .contextMenu {
            Button {
                insertAfterSubtaskID = subtask.id
                insertSubtaskFocus.blockID = insertSubtaskBlocks.first?.id
            } label: {
                Label("Добавить подзадачу после", systemImage: "text.insert")
            }
        }
    }

    /// Пока строку правят, текст живёт здесь, а не в модели: поллинг задачи
    /// (раз в 30 с) перезаписывает `viewModel.subtasks` целиком и стёр бы
    /// набранное на полуслове.
    private func subtaskTitleBinding(_ subtask: ApiSubtask) -> Binding<[NoteBlock]> {
        Binding(
            get: {
                if let draft = subtaskTitleDrafts[subtask.id] { return draft }
                let parsed = MarkdownParser.parse(subtask.title)
                return parsed.isEmpty ? [NoteBlock(kind: .paragraph)] : parsed
            },
            set: { subtaskTitleDrafts[subtask.id] = $0 }
        )
    }

    /// Свой `NoteEditorFocusState` на шаг — заведён лениво и держится, пока
    /// жива карточка (шагов на экране немного, накладных расходов нет).
    private func subtaskFocus(for subtask: ApiSubtask) -> NoteEditorFocusState {
        if let existing = subtaskFocusStates[subtask.id] { return existing }
        let state = NoteEditorFocusState()
        subtaskFocusStates[subtask.id] = state
        return state
    }

    /// Раньше коммит шёл по уходу фокуса (`.onChange(of: focusedSubtaskID)`);
    /// у `BlockDocumentEditor` такого сигнала со всего списка нет — коммитим
    /// с тем же дебаунсом, что у названия/описания задачи (400 мс тишины).
    private func scheduleSubtaskCommit(_ subtask: ApiSubtask) {
        subtaskCommitTasks[subtask.id]?.cancel()
        subtaskCommitTasks[subtask.id] = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            commitSubtaskTitle(subtask)
        }
    }

    private func commitSubtaskTitle(_ subtask: ApiSubtask) {
        guard let draft = subtaskTitleDrafts[subtask.id] else { return }
        let trimmed = MarkdownEncoder.encode(draft).trimmingCharacters(in: .whitespacesAndNewlines)
        // Пустым названием шаг не затираем — это почти всегда промах, а не
        // намерение; строка возвращается к прежнему тексту.
        guard !trimmed.isEmpty, trimmed != subtask.title else { return }
        Task { await viewModel.renameSubtask(subtask, to: trimmed) }
    }

    /// Отметка слева: крутится, пока шаг идёт.
    @ViewBuilder
    private func subtaskMark(_ subtask: ApiSubtask, isRunning: Bool) -> some View {
        if isRunning {
            TFSubtaskStatusRing(.running)
        } else {
            Image(systemName: subtask.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(subtask.done ? Color.tfTeal : .secondary)
                .frame(width: 21, height: 21)
        }
    }

    /// Что показываем под раскрытым шагом: у идущего — чем агент занят, у
    /// закрытого или заблокированного — его итог и кнопки владельца.
    @ViewBuilder
    private func subtaskDetails(_ subtask: ApiSubtask, isRunning: Bool) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            if isRunning, viewModel.activity.isActive {
                if !viewModel.activity.actions.isEmpty {
                    activityChips(viewModel.activity.actions)
                }
                if let text = viewModel.activity.text {
                    Text(text)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                }
                ForEach(viewModel.activity.actions.suffix(5).reversed()) { action in
                    HStack(alignment: .top, spacing: TFSpacing.sm) {
                        Circle()
                            .fill(Color.tfDim)
                            .frame(width: 4, height: 4)
                            .padding(.top, 7)
                        Text(action.text ?? action.target)
                            .tfText(.meta)
                            .foregroundStyle(Color.tfSub)
                    }
                }
            }
            if let result = subtask.result, !result.isEmpty {
                // Итог шага — главное, ради чего эту карточку открывают:
                // виден целиком и всегда, без сворачивания и усечения
                // (владелец 11.09.2026).
                Text(result).tfText(.action).foregroundStyle(Color.tfSub)
            }
            if isOwner, subtask.agentState == .review {
                Button("Принять") { Task { await viewModel.acceptSubtask(subtask) } }
                Button("Вернуть на доработку") { replyingSubtask = subtask }
            } else if isOwner, subtask.agentState == .blocked {
                Button("Ответить") { replyingSubtask = subtask }
            }
        }
    }

    /// Ярлычки действий агента у идущего шага: СНАЧАЛА число всех действий,
    /// ПОСЛЕ — последние пять иконок (владелец 21.09.2026: «в самом начале
    /// делаем число, а эти пять меняются после»). Раньше было наоборот —
    /// уникальные виды иконок, потом счётчик; владелец это забраковал.
    /// Никакой истории: живая картинка на момент просмотра.
    @ViewBuilder
    private func activityChips(_ actions: [ApiTaskActivityAction]) -> some View {
        HStack(spacing: TFSpacing.xs) {
            Text("\(actions.count) \(pluralActions(actions.count))")
                .tfText(.micro)
                .foregroundStyle(Color.tfSub)
                .padding(.horizontal, TFSpacing.sm)
                .frame(height: 24)
                .background(Color.tfCard2)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            ForEach(Array(actions.suffix(5)), id: \.id) { action in
                Image(systemName: activityIcon(action.kind))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.tfDim)
                    .frame(width: 24, height: 24)
                    .background(Color.tfCard2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func activityIcon(_ kind: String) -> String {
        switch kind {
        case "read": "book"
        case "edit": "chevron.left.forwardslash.chevron.right"
        case "write": "doc.badge.plus"
        case "search": "magnifyingglass"
        case "run": "terminal"
        case "think": "brain"
        case "web": "globe"
        case "image": "photo"
        case "test": "checkmark.seal"
        case "build": "hammer"
        case "git": "arrow.triangle.branch"
        case "attach": "paperclip"
        default: "ellipsis"
        }
    }

    private func pluralActions(_ n: Int) -> String {
        let mod100 = n % 100
        if mod100 >= 11 && mod100 <= 14 { return "действий" }
        switch n % 10 {
        case 1: return "действие"
        case 2, 3, 4: return "действия"
        default: return "действий"
        }
    }

    /// Плоская строка ленты — без аватарок/цветных плашек `TaskJournalView`
    /// (та осталась только в мёртвом `TaskDetailScreen`), обычный `Text` в
    /// `Form`, текст события — тот же словарь §19.2 (`TaskJournalView.eventText`).
    @ViewBuilder
    private func nativeJournalRow(_ entry: TaskJournalEntry) -> some View {
        switch entry {
        case .comment(let comment):
            // Сообщение привязанного чата открывает саму переписку: лента
            // задачи показывает её, но продолжать разговор нужно в чате
            // (владелец 21.09.2026: «чтобы не комментарии писать в самой
            // задаче, а в чате переписываться»).
            if comment.isFromChat, let chatID = comment.chatID {
                NavigationLink(value: AppRoute.roleChat(id: chatID)) {
                    journalCommentBody(comment)
                }
            } else {
                journalCommentBody(comment)
            }
        case .event(let event):
            // Кто сделал — обязательно (владелец 22.09.2026: безличное
            // «выполнил шаг» не говорит, чья это работа). Нет автора —
            // действие системы. Имя и действие разделены точкой, чтобы не
            // согласовывать глагол с родом («Система взял»).
            HStack(alignment: .firstTextBaseline) {
                (Text(event.actorName?.isEmpty == false ? event.actorName! : "Система").fontWeight(.medium)
                    + Text(" · ")
                    + Text(TaskJournalView.eventText(event)))
                    .tfText(.action).foregroundStyle(Color.tfSub)
                Spacer()
                if let date = event.createdAtDate {
                    Text(TaskDateText.relativeTime(date)).tfText(.meta).foregroundStyle(Color.tfSub)
                }
            }
        }
    }

    /// Тело комментария ленты — общее для обычного комментария и для сообщения
    /// привязанного чата (у второго только добавляется пометка).
    @ViewBuilder
    private func journalCommentBody(_ comment: ApiComment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(comment.userName?.isEmpty == false ? comment.userName! : "Система")
                    .tfText(.body).fontWeight(.medium)
                if comment.isFromChat {
                    // Пометка нейтральная: синий акцент в приложении не используется.
                    TFPill("из чата", color: Color.tfSub)
                }
                Spacer()
                if let date = comment.createdAtDate {
                    Text(TaskDateText.relativeTime(date)).tfText(.meta).foregroundStyle(Color.tfSub)
                }
            }
            Text(comment.text).tfText(.action).foregroundStyle(Color.tfSub)
            // ВЛОЖЕНИЯ КОММЕНТАРИЯ. 11.09.2026: лента рисовала только
            // текст, и приложенные кадры в приложении не показывались
            // вовсе. Чинить сначала полез в `TaskJournalView.commentCard`
            // — а он живёт в мёртвом `TaskDetailScreen` и не исполняется;
            // рабочая лента здесь. Картинки грузит `ChatAttachmentImage`
            // (умеет ходить с авторизацией, обычный AsyncImage к этому
            // эндпоинту не годится), прочие файлы — строкой с именем.
            if let attachments = comment.attachments, !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(attachments) { attachment in
                        if attachment.mime?.hasPrefix("image/") == true {
                            ChatAttachmentImage(
                                attachmentId: attachment.id,
                                fileName: attachment.fileName
                            )
                        } else {
                            Label(attachment.fileName, systemImage: "paperclip")
                                .tfText(.meta)
                                .foregroundStyle(Color.tfSub)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var nativeDueText: String {
        guard let dueDate = viewModel.dueDate else { return "Не установлен" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TaskDateText.moscow
        let dayDifference = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: dueDate)
        ).day ?? 0
        let date = switch dayDifference {
        case 0: "Сегодня"
        case 1: "Завтра"
        default: TaskDateText.dueLabel(dueDate)
        }
        guard let minutes = viewModel.startMinutes else { return date }
        let start = String(format: "%02d:%02d", minutes / 60, minutes % 60)
        return "\(date) · \(TaskDateText.timeRange(start: start, durationMin: viewModel.durationMin))"
    }

    private func labelBinding(_ labelID: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.selectedLabelIds.contains(labelID) },
            set: { selected in
                if selected {
                    viewModel.selectedLabelIds.insert(labelID)
                } else {
                    viewModel.selectedLabelIds.remove(labelID)
                }
            }
        )
    }

    private var nativeLabelsText: String {
        let labels = labelStore.labels.filter { viewModel.selectedLabelIds.contains($0.id) }.map(\.name)
        return labels.isEmpty ? "Не выбраны" : labels.joined(separator: ", ")
    }

    /// Подпись исполнителя: имя владельца (карточка на человеке), имя
    /// выбранной роли либо «Автоматически» (LOCK-178).
    private var selectedRoleTitle: String {
        if let me = session.currentUser, viewModel.assigneeId == me.id {
            return me.name
        }
        guard let role = viewModel.ownerSelectedRole,
              let profile = viewModel.roles.first(where: { $0.role == role }) else {
            return "Автоматически"
        }
        return profile.title
    }

    private func agentStateText(_ state: AgentState) -> String {
        switch state {
        case .inProgress: "В работе"
        case .blocked: "Заблокирована"
        case .review: "На проверке"
        case .todo: "В очереди"
        }
    }

    /// Цвет подписи состояния в шапке. «На проверке»: серая — ждёт
    /// проверяющего, синяя — отправлена ему и он работает, зелёная — он
    /// вынес вердикт (владелец 22.09.2026). Считаем по ленте после
    /// последнего ухода в review: прошлые круги проверки не в счёт.
    private func agentStateColor(_ state: AgentState) -> Color {
        switch state {
        case .blocked:
            return .orange
        case .inProgress:
            return .tfSub
        case .review:
            let events = viewModel.journalEntries.compactMap { entry -> ApiTaskEvent? in
                if case .event(let event) = entry { return event }
                return nil
            }
            // `journalEntries` идут от новых к старым: всё, что новее
            // последнего ухода в review, лежит ДО него.
            let end = events.firstIndex { $0.kind == "state_changed" && $0.toValue == "review" }
                ?? events.endIndex
            let current = events[..<end]
            if current.contains(where: { $0.kind == "review_recorded" }) { return .tfGreen }
            if current.contains(where: {
                $0.kind == "reviewer_sent" || ($0.kind == "run_requested" && $0.field == "reviewer")
            }) {
                return .tfBlue
            }
            return .tfSub
        case .todo:
            return .tfSub
        }
    }

    private func agentStateIcon(_ state: AgentState) -> String {
        switch state {
        case .inProgress: "play.circle.fill"
        case .blocked: "exclamationmark.triangle.fill"
        case .review: "eye.fill"
        case .todo: "clock.arrow.circlepath"
        }
    }

    private var isOwner: Bool { session.currentUser?.role == .owner }

    /// Две кнопки справа (владелец 01.10.2026, LOCK-272: «команд пиздец
    /// сколько, половины не знаю»): «Работа» — всё, что двигает исполнение
    /// (исполнитель, запуск, приёмка, план, исследование), и «Ещё» —
    /// действия над самой карточкой. Отдельной кнопки «Изменить» и галочки
    /// сохранения нет: поля активны сразу и сохраняются автоматически.
    @ToolbarContentBuilder
    private var editingToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                workMenuItems
            } label: {
                Image(systemName: "person.2")
                    .foregroundStyle(Color.tfText)
            }
            .accessibilityLabel("Работа")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                moreMenuItems
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Color.tfText)
            }
            .accessibilityLabel("Ещё")
        }
    }

    /// «Работа»: кто исполняет и что с ним делать.
    @ViewBuilder
    private var workMenuItems: some View {
        // Исполнитель — роль (AgentProfile), не учётка (LOCK-178). Раньше —
        // строка в «Сведениях»; выбор роли теперь сразу её и запускает
        // (владелец 01.10.2026: «назначить исполнителя — тем самым и
        // запустить»). «Автоматически» — роли нет, диспетчер подберёт сам.
        Menu {
            Button("Автоматически — оркестратор выберет агента") {
                assignExecutor(role: nil)
            }
            // Себя — тем же именем, что и в остальных местах: карточка
            // на владельце. Назначенную на человека задачу агенты не
            // берут и работник расписания не трогает.
            if let me = session.currentUser {
                Button {
                    viewModel.assigneeId = me.id
                    viewModel.ownerSelectedRole = nil
                } label: {
                    if viewModel.assigneeId == me.id {
                        Label(me.name, systemImage: "checkmark")
                    } else {
                        Text(me.name)
                    }
                }
            }
            ForEach(viewModel.roles) { role in
                Button {
                    assignExecutor(role: role.role)
                } label: {
                    if viewModel.ownerSelectedRole == role.role {
                        Label(role.title, systemImage: "checkmark")
                    } else {
                        Text(role.title)
                    }
                }
            }
        } label: {
            Label("Исполнитель: \(selectedRoleTitle)", systemImage: "person.crop.circle")
        }

        if isOwner {
            // Один запуск вместо двух (владелец 01.10.2026: «Запустить» и
            // «Запустить исполнителя» путали): разрешить ролям взять
            // карточку и сразу поднять исполнителя.
            Button {
                Task { await launchExecutor() }
            } label: {
                Label("Запустить исполнителя", systemImage: "play.circle")
            }
            .disabled((viewModel.assigneeId ?? "").isEmpty && viewModel.ownerSelectedRole == nil)
            // Вернуть в черновик можно, пока за карточку никто не взялся.
            if viewModel.readyForPickup, viewModel.agentState == nil {
                Button {
                    Task { await viewModel.toggleReadyFlag(taskStore: taskStore) }
                } label: {
                    Label("Вернуть в черновик", systemImage: "pause")
                }
            }
        }

        if isOwner, let state = viewModel.agentState {
            ownerActionMenuItems(state)
        }
        if isOwner {
                    if viewModel.agentState == .review {
                        Button {
                            Task {
                                if await viewModel.runAgent(mode: "reviewer") {
                                    toast = TaskToastMessage("Верификатор поднят — проверит карточку")
                                }
                            }
                        } label: {
                            Label("Отправить на проверку верификатору", systemImage: "checkmark.seal")
                        }
                    }
            Divider()
                    // Утверждение черновика плана совместной работы —
                    // LOCK-249: сам граф ролей уже виден в карточке, здесь
                    // только запуск, рядом с остальными действиями над
                    // агентом/ролями. Пункт есть, только пока владелец
                    // видит непринятый черновик (`pendingPlanApprovalId`
                    // заполняет `CollaborationPlanView.load()`).
                    if let taskID {
                        if let planId = pendingPlanApprovalId {
                            Button {
                                Task { await approveCollaborationPlan(taskId: taskID, planId: planId) }
                            } label: {
                                Label("Утвердить план совместной работы", systemImage: "checkmark.circle")
                            }
                            .disabled(isApprovingCollaborationPlan)
                        }
                        // Явный выбор шаблона — LOCK-252: серверный автоподбор
                        // по ключевым словам карточки (при создании задачи)
                        // угадывает профиль не всегда надёжно (владелец
                        // 30.09.2026: получил «Исследование» вместо ожидаемой
                        // «Доставки»). Свой шаблон — свой предсказуемый набор
                        // ролей, без гадания по тексту. Пункт виден ВСЕГДА,
                        // а не только при отсутствии черновика: сервер сам
                        // гасит любой висящий черновик при новом /propose
                        // (`supersedePendingDrafts`), так что неудачный
                        // автоподбор перебивается этим же пунктом, без
                        // отдельного «отклонить черновик» — правка 30.09.2026,
                        // раньше пункт был спрятан за уже существующим
                        // черновиком и не открывался вовсе.
                        Menu {
                            ForEach(Self.collaborationPlanTemplates, id: \.profile) { template in
                                Button {
                                    Task { await proposeCollaborationPlan(taskId: taskID, profile: template.profile) }
                                } label: {
                                    Label(template.title, systemImage: template.icon)
                                }
                            }
                        } label: {
                            Label("Предложить план по шаблону", systemImage: "list.bullet.rectangle")
                        }
                        .disabled(isProposingCollaborationPlan)
                        // Умная параллелизация (30.09.2026): подобрать план
                        // ИЗ уже написанных открытых подзадач локальным
                        // классификатором, не из шаблона по словам карточки.
                        // Та же логика supersedePendingDrafts на сервере —
                        // виден всегда, не только при отсутствии черновика.
                        Button {
                            Task { await suggestCollaborationPlanFromSubtasks(taskId: taskID) }
                        } label: {
                            Label("Предложить план из подзадач", systemImage: "wand.and.stars")
                        }
                        .disabled(isSuggestingCollaborationPlan)
                    }
            Divider()
                    // Глубокое исследование (миграция 052 сервера
                    // New-Todoist). Тумблер-отметка и кнопка запуска
                    // серверного конвейера: он сам собирает источники,
                    // проверяет их и кладёт отчёт в секцию «Отчёты».
                    Button {
                        Task { await viewModel.toggleNeedsResearch(taskStore: taskStore) }
                    } label: {
                        Label(
                            viewModel.needsResearch
                                ? "Глубокое исследование: включено"
                                : "Нужно глубокое исследование",
                            systemImage: viewModel.needsResearch
                                ? "magnifyingglass.circle.fill"
                                : "magnifyingglass"
                        )
                    }
                    if viewModel.needsResearch {
                        Button {
                            Task {
                                if await viewModel.startResearch() {
                                    toast = TaskToastMessage("Исследование запущено — отчёт появится в карточке")
                                }
                            }
                        } label: {
                            Label("Запустить исследование", systemImage: "sparkles")
                        }
                    }
        }
    }

    /// «Ещё»: сама карточка — AI-разбор, повторы, закрепление, файлы,
    /// островок, шаблон, связи, удаление.
    @ViewBuilder
    private var moreMenuItems: some View {
        if viewModel.showAiButton {
            Button {
                Task { await viewModel.structureWithAI() }
            } label: {
                Label("Структурировать с AI", systemImage: "sparkles")
            }
            .disabled(viewModel.aiStructureStatus.isProcessing)
        }
        // Серия повтора завершилась на конце года — одним тапом
        // продлеваем на следующий (владелец 20.09.2026).
        if isOwner, viewModel.seriesEnded {
            Button {
                Task {
                    if await viewModel.extendRepeat() {
                        toast = TaskToastMessage("Серия продлена на следующий год")
                    }
                }
            } label: {
                Label("Продлить на год", systemImage: "calendar.badge.plus")
            }
        }
        if viewModel.showAiButton || (isOwner && viewModel.seriesEnded) {
            Divider()
        }

        // Закрепление переехало сюда из строки списка проекта
        // (владелец 11.09.2026): «закреплять я буду в самой карточке,
        // через три точки, а не рисовать скрепки в каждой строке».
        Button {
            Task { await viewModel.togglePinned(taskStore: taskStore) }
        } label: {
            Label(
                viewModel.pinned ? "Открепить задачу" : "Закрепить задачу",
                systemImage: viewModel.pinned ? "pin.slash" : "pin"
            )
        }
        Menu {
            Button { isAttachmentPickerPresented = true } label: {
                Label("С iPhone", systemImage: "iphone")
            }
            Button { isKnowledgePickerPresented = true } label: {
                Label("Из базы знаний", systemImage: "books.vertical")
            }
        } label: {
            Label("Прикрепить файл", systemImage: "paperclip")
        }
        // Островок: вывести и убрать тем же пунктом (владелец 01.10.2026:
        // «до сих пор висит задача, а я не знаю, как её убрать»).
        if isInDynamicIsland {
            Button { removeFromDynamicIsland() } label: {
                Label("Убрать из Dynamic Island", systemImage: "bolt.slash")
            }
        } else {
            Button { outputDynamicIsland() } label: {
                Label("Вывести в Dynamic Island", systemImage: "bolt.badge.a")
            }
        }
        Button { saveAsTemplate() } label: {
            Label("Сохранить как шаблон", systemImage: "doc.on.doc")
        }
        if taskID != nil {
            Button { isExistingTaskPickerPresented = true } label: {
                Label("Связать существующую задачу", systemImage: "link.badge.plus")
            }
        }

        Divider()

        Button("Удалить задачу", systemImage: "trash", role: .destructive) {
            isDeleteConfirmationPresented = true
        }
    }

    /// Назначить исполнителя и сразу запустить (владелец 01.10.2026).
    private func assignExecutor(role: String?) {
        viewModel.ownerSelectedRole = role
        viewModel.assigneeId = nil
        pendingSaveTask?.cancel()
        Task {
            guard await viewModel.save(taskStore: taskStore) else { return }
            if role != nil, isOwner {
                await launchExecutor()
            } else if isOwner, !viewModel.readyForPickup {
                // «Автоматически»: роль подберёт диспетчер — только
                // разрешаем ролям взять карточку.
                await viewModel.startTask(taskStore: taskStore)
            }
        }
    }

    /// Разрешить ролям взять карточку (если она ещё черновик) и поднять
    /// исполнителя, если он сам уже не взялся.
    private func launchExecutor() async {
        if !viewModel.readyForPickup {
            await viewModel.startTask(taskStore: taskStore)
        }
        guard viewModel.agentState != .inProgress else {
            toast = TaskToastMessage("Исполнитель уже работает")
            return
        }
        if await viewModel.runAgent(mode: "executor") {
            toast = TaskToastMessage("Исполнитель запущен")
        }
    }

    /// Перенесено буквально из `TaskDetailScreen.ownerActionMenuItems` —
    /// та же логика (§19.2 AgentOwnerActions), другой источник состояния.
    @ViewBuilder
    private func ownerActionMenuItems(_ state: AgentState) -> some View {
        switch state {
        case .review:
            Button { Task { await viewModel.performOwnerAction(.acceptReview, comment: nil, taskStore: taskStore) } } label: {
                Label("Принять и закрыть задачу", systemImage: "checkmark.circle")
            }
            Button { pendingAction = .returnToWorkFromReview } label: {
                Label("Вернуть на доработку", systemImage: "arrow.uturn.backward")
            }
        case .blocked:
            Button { pendingAction = .replyAndReturnFromBlocked } label: {
                Label("Ответить и вернуть в работу", systemImage: "arrowshape.turn.up.left")
            }
            Button { Task { await viewModel.performOwnerAction(.acceptAndClose, comment: nil, taskStore: taskStore) } } label: {
                Label("Принять и закрыть задачу", systemImage: "checkmark.circle")
            }
        case .inProgress:
            Button { Task { await viewModel.performOwnerAction(.returnToWorkFromInProgress, comment: nil, taskStore: taskStore) } } label: {
                Label("Вернуть на доработку", systemImage: "arrow.uturn.backward")
            }
            Button { Task { await viewModel.performOwnerAction(.acceptAndClose, comment: nil, taskStore: taskStore) } } label: {
                Label("Принять и закрыть задачу", systemImage: "checkmark.circle")
            }
        case .todo:
            // Ставит только планировщик, сам подхватит в ближайший обход —
            // владельцу тут доступно только закрыть задачу вручную, если
            // ждать не нужно.
            Button { Task { await viewModel.performOwnerAction(.acceptAndClose, comment: nil, taskStore: taskStore) } } label: {
                Label("Принять и закрыть задачу", systemImage: "checkmark.circle")
            }
        }
    }

    /// Утверждение черновика плана совместной работы — LOCK-249, кнопка в
    /// меню «Ещё». Сервер сам материализует slots и стартует корневые узлы
    /// графа; здесь только вызов и перезагрузка `CollaborationPlanView`.
    private func approveCollaborationPlan(taskId: String, planId: String) async {
        isApprovingCollaborationPlan = true
        do {
            _ = try await APIClient().approveCollaborationPlan(taskId: taskId, planId: planId)
            pendingPlanApprovalId = nil
            collaborationPlanReloadToken += 1
            toast = TaskToastMessage("План утверждён — роли начинают работу")
        } catch {
            toast = TaskToastMessage("Не удалось утвердить план")
        }
        isApprovingCollaborationPlan = false
    }

    /// Умная параллелизация (30.09.2026) — тот же паттерн, что у
    /// `approveCollaborationPlan`: вызов и перезагрузка `CollaborationPlanView`,
    /// которая сама заберёт свежий draft и заполнит `pendingPlanApprovalId`.
    /// Сервер может ответить «параллелить нечего» (меньше двух открытых
    /// подзадач или все совпали с текущим исполнителем) — это не ошибка,
    /// сообщаем причину тем же тостом, план при этом не создаётся.
    private func suggestCollaborationPlanFromSubtasks(taskId: String) async {
        isSuggestingCollaborationPlan = true
        do {
            let result = try await APIClient().suggestCollaborationPlanFromSubtasks(taskId: taskId)
            switch result {
            case .suggested:
                collaborationPlanReloadToken += 1
                toast = TaskToastMessage("План предложен — проверьте и утвердите")
            case .notSuggested(let reason):
                toast = TaskToastMessage(reason)
            }
        } catch {
            toast = TaskToastMessage("Не удалось предложить план")
        }
        isSuggestingCollaborationPlan = false
    }

    /// Шаблоны сервера, доступные для явного выбора (LOCK-252) — тот же
    /// набор строк `profile`, что в PROFILES на сервере (task-collaboration-plans.ts),
    /// без "manual" (внутренний тег умной параллелизации, не пользовательский
    /// выбор) и без "product_feature" (нужны отдельные булевы флаги — вне
    /// этой правки). Подписи называют роли конвейера, чтобы владелец видел,
    /// что получит, не запоминая, что стоит за словом «Доставка».
    private static let collaborationPlanTemplates: [(profile: String, title: String, icon: String)] = [
        ("single_executor", "Один исполнитель", "person.fill"),
        ("research", "Исследование: исследователь → аналитик", "magnifyingglass"),
        ("delivery", "Доставка: архитектор → исполнитель → QA → критик", "shippingbox"),
        ("full_cycle", "Полный цикл: все роли", "person.3.fill"),
    ]

    /// Явный выбор шаблона плана владельцем — LOCK-252, тот же паттерн
    /// перезагрузки, что у `approveCollaborationPlan`/
    /// `suggestCollaborationPlanFromSubtasks`. Сервер сам гасит любой
    /// висящий черновик перед созданием нового (`supersedePendingDrafts`),
    /// так что повторный вызов безопасен.
    private func proposeCollaborationPlan(taskId: String, profile: String) async {
        isProposingCollaborationPlan = true
        do {
            _ = try await APIClient().proposeCollaborationPlan(taskId: taskId, profile: profile)
            collaborationPlanReloadToken += 1
            toast = TaskToastMessage("План предложен — проверьте и утвердите")
        } catch {
            toast = TaskToastMessage("Не удалось предложить план")
        }
        isProposingCollaborationPlan = false
    }

    private var outcomeReloadKey: String {
        "\(viewModel.taskID ?? "")|\(viewModel.agentState.map { "\($0)" } ?? "-")|\(viewModel.subtasks.filter(\.done).count)"
    }

    private func loadOutcome() async {
        guard let taskID = viewModel.taskID else { outcome = nil; return }
        outcome = try? await APIClient().taskOutcome(taskId: taskID)
    }

    private func removeFromDynamicIsland() {
        guard #available(iOS 16.2, *), let taskID else { return }
        Task {
            await LiveActivityService.end(taskID: taskID, api: APIClient())
            isInDynamicIsland = false
            toast = TaskToastMessage("Задача убрана из Dynamic Island")
        }
    }

    private func refreshDynamicIslandState() {
        guard #available(iOS 16.2, *), let taskID else { isInDynamicIsland = false; return }
        isInDynamicIsland = LiveActivityService.isShown(taskID: taskID)
    }

    private func outputDynamicIsland() {
        // Тост здесь больше не «по спеке»: он сообщает то, что реально
        // произошло. Саму активность поднимает вьюмодель — у неё и задача,
        // и клиент API (10.09.2026, карточка cd831b02).
        guard #available(iOS 16.2, *) else {
            toast = TaskToastMessage("Островок доступен с iOS 16.2")
            return
        }
        Task {
            toast = TaskToastMessage(await viewModel.outputToDynamicIsland())
            refreshDynamicIslandState()
        }
    }

    private func saveAsTemplate() {
        // Перенесено из `TaskDetailScreen` буквально — на сервере нет
        // эндпоинта шаблонов, тост показывается по спеке.
        toast = TaskToastMessage("Задача сохранена в шаблоны")
    }

    private func deleteCurrentTask() async {
        guard let taskID, await taskStore.delete(taskId: taskID) else { return }
        dismiss()
    }

    // LOCK-254: размер иконок и тап-цели — те же, что в MarkdownKeyboardAccessoryBar
    // (`.font(size: 18)` + `TFHitTarget.min`), иначе системная капсула здесь
    // выходит заметно мельче капсулы Markdown-панели (владелец 30.09.2026:
    // «это, по-твоему, одинаковый размер пилюль?»).
    private var taskKeyboardDismissButton: some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 18))
                .frame(width: TFHitTarget.min, height: TFHitTarget.min)
        }
        .accessibilityLabel("Скрыть клавиатуру")
    }

    // LOCK-254: та же `VoiceBarsView` при записи, что и у Markdown-панели
    // (`MarkdownKeyboardAccessoryBar.micButton`) и у записи голосового в
    // чате — один визуальный язык на всё приложение.
    private var taskKeyboardDictationButton: some View {
        Button {
            Task { await toggleDictation() }
        } label: {
            switch dictation.recordingState {
            case .recording:
                VoiceBarsView(
                    level: dictation.currentLevel,
                    color: Color.tfRed.mix(with: .black, by: 0.55), peakColor: Color.tfRed,
                    barWidth: 3, spacing: 2, maxHeight: 20, isSmooth: true
                )
                .frame(width: TFHitTarget.min, height: TFHitTarget.min)
            case .transcribing:
                ProgressView()
                    .frame(width: TFHitTarget.min, height: TFHitTarget.min)
            default:
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .frame(width: TFHitTarget.min, height: TFHitTarget.min)
            }
        }
        .disabled(dictation.recordingState == .transcribing)
        .accessibilityLabel("Голосовой ввод")
    }

    private func toggleDictation() async {
        switch dictation.recordingState {
        case .idle, .failed:
            await dictation.startRecording()
        case .recording:
            guard let text = await dictation.stopRecordingAndTranscribe() else { return }
            switch dictationTarget {
            case .title:
                viewModel.title = appendedDictation(text, to: viewModel.title)
            case .description:
                viewModel.taskDescription = appendedDictation(text, to: viewModel.taskDescription)
            case .comment:
                viewModel.commentText = appendedDictation(text, to: viewModel.commentText)
            case .newSubtask:
                // Недостижимо — своя диктовка теперь у BlockDocumentEditor;
                // оставлено ради компиляции switch по DictationTarget.
                let existingText = MarkdownEncoder.encode(newSubtaskBlocks)
                newSubtaskBlocks = MarkdownParser.parse(appendedDictation(text, to: existingText))
            case .subtask(let id):
                // Практически недостижимо: у шага теперь своя диктовка через
                // BlockDocumentEditor/MarkdownKeyboardAccessoryBar, этот путь
                // остаётся только ради компиляции switch по DictationTarget.
                guard let subtask = viewModel.subtasks.first(where: { $0.id == id }) else { return }
                let existingText = MarkdownEncoder.encode(subtaskTitleDrafts[id] ?? [])
                let base = existingText.isEmpty ? subtask.title : existingText
                subtaskTitleDrafts[id] = MarkdownParser.parse(appendedDictation(text, to: base))
            }
        case .transcribing:
            break
        }
    }

    private func appendedDictation(_ text: String, to existing: String) -> String {
        guard !existing.isEmpty else { return text }
        return existing + (existing.hasSuffix(" ") ? "" : " ") + text
    }

    // MARK: - Тело

    private var aiStructureButton: some View {
        Button {
            Task { await viewModel.structureWithAI() }
        } label: {
            HStack(spacing: TFSpacing.sm) {
                if viewModel.aiStructureStatus.isProcessing {
                    ProgressView()
                    Text("Структурирую…").tfText(.body).fontWeight(.semibold)
                } else {
                    Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold))
                    Text("Структурировать с AI").tfText(.body).fontWeight(.semibold)
                }
            }
            // Была фиолетово-розовая заливка градиентом — просьба владельца
            // 03.09.2026: причесать под лаконичный стиль «Моделей и голосов»
            // (без цветных плашек), тот же нейтральный `tfCard2`, что у
            // «Сегодня»/«Завтра» в `DueDateFieldView`.
            .foregroundStyle(Color.tfText)
            .padding(.horizontal, TFSpacing.lg)
            .padding(.vertical, TFSpacing.sm)
            .background(Color.tfCard2)
            .clipShape(Capsule())
        }
        .buttonStyle(TFTapScaleStyle())
        .disabled(viewModel.aiStructureStatus.isProcessing)
        .accessibilityLabel(viewModel.aiStructureStatus.isProcessing ? "AI структурирует задачу" : "Структурировать задачу с AI")
    }

    /// Шаги — одинаково в создании и в готовой задаче. Владелец 11.09.2026:
    /// «просто тапаю и редактирую, как саму задачу, как описание» — никаких
    /// кнопок «изменить», плюсов, галочек и крестиков. Разница только в
    /// источнике: у новой задачи это черновики в памяти, у существующей —
    /// шаги с сервера. Контент отделён от обёртки — оборачивается
    /// `collapsibleSection` в `nativeTaskDetailBody` (LOCK-248).
    @ViewBuilder private var subtasksContent: some View {
            if viewModel.isEditing {
                ForEach(viewModel.subtasks) { subtask in
                    nativeSubtaskRow(subtask)
                    if insertAfterSubtaskID == subtask.id {
                        insertSubtaskRow(after: subtask.id)
                    }
                }
            } else {
                ForEach($viewModel.subtaskDrafts) { $draft in
                    BlockDocumentEditor(
                        blocks: blocksBinding($draft.title),
                        focus: subtaskDraftFocus(for: draft.id),
                        placeholder: "Шаг",
                        textColor: UIColor(Color.tfSub)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onDelete { viewModel.subtaskDrafts.remove(atOffsets: $0) }
            }
            newSubtaskRow
    }

    /// Строку `String` ↔ блоки — тот же приём, что у `title`/`taskDescription`
    /// в `TaskFormViewModel`, только здесь оборачивает уже существующий
    /// `Binding<String>` (черновик шага при создании задачи, ещё не на
    /// сервере — своего вычисляемого свойства в модели у него нет).
    private func blocksBinding(_ stringBinding: Binding<String>) -> Binding<[NoteBlock]> {
        Binding(
            get: {
                let parsed = MarkdownParser.parse(stringBinding.wrappedValue)
                return parsed.isEmpty ? [NoteBlock(kind: .paragraph)] : parsed
            },
            set: { stringBinding.wrappedValue = MarkdownEncoder.encode($0) }
        )
    }

    private func subtaskDraftFocus(for id: UUID) -> NoteEditorFocusState {
        if let existing = subtaskDraftFocusStates[id] { return existing }
        let state = NoteEditorFocusState()
        subtaskDraftFocusStates[id] = state
        return state
    }

    /// Последняя строка списка шагов. Владелец 11.09.2026: «нажимаю
    /// „Добавить подзадачу“ — какая-то форма пытается открыться и сразу
    /// умирает» — диалога нет. LOCK-255 («вся карточка как описание»):
    /// поле стало блочным Markdown-редактором, Enter в нём теперь просто
    /// перенос строки (как везде в общем редакторе), поэтому добавление —
    /// явной кнопкой справа, а не по Enter, как было раньше.
    private var newSubtaskRow: some View {
        HStack(alignment: .bottom, spacing: TFSpacing.sm) {
            BlockDocumentEditor(
                blocks: $newSubtaskBlocks,
                focus: newSubtaskFocus,
                placeholder: "Добавить подзадачу",
                textColor: UIColor(Color.tfDim)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isBlank(newSubtaskBlocks) {
                Button { addSubtaskInline() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Добавить подзадачу")
            }
        }
        .listRowSeparator(.hidden)
    }

    /// Инлайн-поле вставки после конкретной подзадачи — тот же паттерн, что
    /// `newSubtaskRow`, но не в конце списка, а сразу под указанной строкой.
    private func insertSubtaskRow(after subtaskID: String) -> some View {
        HStack(alignment: .bottom, spacing: TFSpacing.sm) {
            BlockDocumentEditor(
                blocks: $insertSubtaskBlocks,
                focus: insertSubtaskFocus,
                placeholder: "Добавить подзадачу",
                textColor: UIColor(Color.tfDim)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isBlank(insertSubtaskBlocks) {
                Button { addSubtaskInline(after: subtaskID) } label: {
                    Image(systemName: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Добавить подзадачу")
            }
        }
        .listRowSeparator(.hidden)
    }

    private func isBlank(_ blocks: [NoteBlock]) -> Bool {
        MarkdownEncoder.encode(blocks).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addSubtaskInline(after subtaskID: String) {
        let title = MarkdownEncoder.encode(insertSubtaskBlocks).trimmingCharacters(in: .whitespacesAndNewlines)
        insertSubtaskBlocks = [NoteBlock(kind: .paragraph)]
        insertAfterSubtaskID = nil
        guard !title.isEmpty else { return }
        Task { await viewModel.addSubtask(title, afterId: subtaskID) }
    }

    private func addSubtaskInline() {
        let title = MarkdownEncoder.encode(newSubtaskBlocks).trimmingCharacters(in: .whitespacesAndNewlines)
        newSubtaskBlocks = [NoteBlock(kind: .paragraph)]
        guard !title.isEmpty else { return }
        if viewModel.isEditing {
            Task { await viewModel.addSubtask(title) }
        } else {
            viewModel.subtaskDrafts.append(SubtaskDraft(title: title))
        }
        // Фокус после добавления возвращаем в ту же строку: список шагов
        // обычно пишут подряд, а не по одному с перезаходом.
        newSubtaskFocus.blockID = newSubtaskBlocks.first?.id
    }

    private func scheduleSave() {
        guard viewModel.isEditing, isEditorReady else { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await saveExistingEdits()
        }
    }

    /// ⚠️ Здесь НЕЛЬЗЯ трогать `pendingSaveTask`: этот метод вызывается в том
    /// числе изнутри самой `pendingSaveTask` (см. `scheduleSave`), и отмена
    /// отменяла задачу, внутри которой выполнялась. `URLSession` дальше
    /// создавался в уже отменённом контексте и бросал `URLError.cancelled` —
    /// владелец видел «Сеть недоступна: cancelled» на любой правке карточки
    /// (09.09.2026, ловилось на «Срок» → «Убрать дату и время»). Отменяет
    /// отложенное сохранение тот, кто его перебивает: `scheduleSave` и
    /// `handleDisappear`.
    private func saveExistingEdits() async {
        guard viewModel.isEditing, isEditorReady else { return }
        _ = await viewModel.save(taskStore: taskStore)
    }

    private func handleDisappear() {
        viewModel.stopPolling()
        pendingSaveTask?.cancel()
        guard viewModel.isEditing, isEditorReady else { return }
        // Карточку закрыли, не выходя из строки шага — правка не должна
        // пропасть вместе с экраном.
        for subtask in viewModel.subtasks where subtaskTitleDrafts[subtask.id] != nil {
            commitSubtaskTitle(subtask)
        }
        Task { await saveExistingEdits() }
    }

    private func reportSubtitle(_ report: TaskReport) -> String {
        var parts: [String] = []
        if let author = report.authorName, !author.isEmpty { parts.append(author) }
        if let date = report.createdAtDate { parts.append(TaskDateText.relativeTime(date)) }
        return parts.joined(separator: " · ")
    }

    private func handleAttachmentImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            replaceAttachmentTarget = nil
            return
        }
        let old = replaceAttachmentTarget
        replaceAttachmentTarget = nil
        Task {
            await viewModel.attachments.add(url: url)
            if let old { await viewModel.attachments.removeUploaded(old) }
        }
    }

    /// Приложить документ из базы знаний: забираем его markdown и кладём
    /// файлом .md к задаче — тем же путём, что и любой другой файл.
    private func attachKnowledgeNote(noteID: String, title: String) async {
        do {
            let note = try await APIClient().note(id: noteID, format: "markdown")
            let markdown = note.markdown ?? ""
            guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                viewModel.attachments.errorMessage = "Документ пуст"
                return
            }
            let base = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = String((base.isEmpty ? "Документ" : base).prefix(80)) + ".md"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try markdown.data(using: .utf8)?.write(to: url, options: .atomic)
            await viewModel.attachments.add(url: url)
        } catch {
            viewModel.attachments.errorMessage = "Не удалось приложить документ"
        }
    }

    private func loadScreen() async {
        await viewModel.loadIfNeeded()
        await viewModel.loadRoles()
        if taskStore.tasks.isEmpty { await taskStore.load() }
        if projectStore.projects.isEmpty { await projectStore.load() }
        if labelStore.labels.isEmpty { await labelStore.load() }
        if viewModel.startDictation { titleFocus.blockID = viewModel.titleBlocks.first?.id }
        await viewModel.loadActivity()
        await viewModel.loadReports()
        viewModel.startPolling()
        refreshDynamicIslandState()
        isEditorReady = true
    }

    private func submit() async {
        if await viewModel.save(taskStore: taskStore) {
            dismiss()
        }
    }
}

/// Сворачиваемые подзаголовки карточки (LOCK-248). Список не растёт
/// «по ходу жизни» — это перечень секций, которые владелец просил
/// видеть компактными по умолчанию. «Шапка» (имя + описание) и блок
/// плана совместной работы — не сворачиваются: первая несёт суть карточки,
/// второй показывается только когда он реально есть.
enum TaskDetailSection: Hashable {
    /// Блочный редактор описания задачи.
    case description
    /// Утверждённый план совместной работы.
    case collaborationPlan
    /// Итог: вердикт, что сдала каждая роль, документы, код (LOCK-273).
    case outcome
    /// Шаги задачи.
    case subtasks
    /// Родительские и дочерние задачи.
    case linkedTasks
    /// Привязанные к задаче чаты (отдельная секция внутри `linkedTasksSection`).
    case chatByTask
    /// Срок/проект/приоритет/метки + исполнитель/создатель.
    case details
    /// Вложения (`if attachments`). По умолчанию свёрнуты — обычно пусто.
    case attachments
    /// Отчёты (`if reports`). По умолчанию свёрнуты — обычно пусто.
    case reports
    /// Лента активности + поле ввода комментария.
    case journal
}

/// Раньше это была одна цепочка из 14 `.onChange` подряд прямо на `fullFormBody`
/// — Swift 6.6 typecheck таймаутит на такой длине ("unable to type-check this
/// expression in reasonable time"), Xcode 27 справлялся, 26.6 — нет. Разбито
/// на два модификатора без изменения поведения (см. TaskFormScreen 22.09.2026).
private struct FocusDictationTargetModifier: ViewModifier {
    let isTitleFocused: Bool
    let isDescriptionFocused: Bool
    let isCommentFocused: Bool
    @Binding var dictationTarget: TaskFormScreen.DictationTarget
    let scheduleSave: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: isTitleFocused) { wasFocused, isFocused in
                if isFocused { dictationTarget = .title }
                if wasFocused, !isFocused { scheduleSave() }
            }
            .onChange(of: isDescriptionFocused) { _, isFocused in
                if isFocused { dictationTarget = .description }
            }
            .onChange(of: isCommentFocused) { _, isFocused in
                if isFocused { dictationTarget = .comment }
            }
    }
}

private struct AutosaveFieldsModifier: ViewModifier {
    let viewModel: TaskFormViewModel
    let scheduleSave: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.title) { _, _ in scheduleSave() }
            .onChange(of: viewModel.taskDescription) { _, _ in scheduleSave() }
            .onChange(of: viewModel.dueDate) { _, _ in scheduleSave() }
            .onChange(of: viewModel.startMinutes) { _, _ in scheduleSave() }
            .onChange(of: viewModel.durationMin) { _, _ in scheduleSave() }
            .onChange(of: viewModel.runRepeat) { _, _ in scheduleSave() }
            .onChange(of: viewModel.repeatUntil) { _, _ in scheduleSave() }
            .modifier(AutosaveFieldsModifierTail(viewModel: viewModel, scheduleSave: scheduleSave))
    }
}

private struct AutosaveFieldsModifierTail: ViewModifier {
    let viewModel: TaskFormViewModel
    let scheduleSave: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.projectId) { _, _ in scheduleSave() }
            .onChange(of: viewModel.priority) { _, _ in scheduleSave() }
            .onChange(of: viewModel.selectedLabelIds) { _, _ in scheduleSave() }
            .onChange(of: viewModel.ownerSelectedRole) { _, _ in scheduleSave() }
            .onChange(of: viewModel.assigneeId) { _, _ in scheduleSave() }
    }
}

/// Тот же редактор срока, что в форме создания: быстрые даты,
/// календарь, системный барабан времени и длительность.
private struct ExistingTaskDueEditor: View {
    private enum Field: Hashable {
        case date, time, duration, repeatRule
    }

    @Binding var dueDate: Date?
    @Binding var startMinutes: Int?
    @Binding var durationMin: Int?
    @Binding var runRepeat: String
    @Binding var repeatUntil: Date?
    @State private var activeField: Field = .date

    private static let durationOptions: [(minutes: Int, label: String)] = [
        (15, "15м"), (30, "30м"), (45, "45м"), (60, "1ч"), (120, "2ч"), (180, "3ч"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            ZStack {
                switch activeField {
            case .date:
                DatePicker("", selection: dueDateBinding, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                .frame(width: 300, height: 180)
                .clipped()
                .padding(.top, TFSpacing.sm)
            case .time:
                DatePicker("", selection: startTimeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                .frame(width: 300, height: 180)
                .clipped()
                .padding(.top, TFSpacing.sm)
            case .duration:
                Picker("", selection: $durationMin) {
                    Text("Без длительности").tag(Int?.none)
                    ForEach(Self.durationOptions, id: \.minutes) { option in
                        Text(option.label).tag(Optional(option.minutes))
                    }
                }
                .labelsHidden()
                .pickerStyle(.wheel)
                .frame(width: 300, height: 180)
                .clipped()
                .padding(.top, TFSpacing.sm)
            case .repeatRule:
                Picker("", selection: $runRepeat) {
                    Text("Не повторять").tag("none")
                    Text("Ежедневно").tag("daily")
                    Text("По будням").tag("weekdays")
                    Text("Еженедельно").tag("weekly")
                    Text("Ежемесячно").tag("monthly")
                }
                .labelsHidden()
                .pickerStyle(.wheel)
                .frame(width: 300, height: 180)
                .clipped()
                .padding(.top, TFSpacing.sm)
                }

                HStack {
                    pickerArrow(icon: "chevron.left", label: "Предыдущее поле срока") {
                        stepField(by: -1)
                    }
                    Spacer(minLength: 0)
                    pickerArrow(icon: "chevron.right", label: "Следующее поле срока") {
                        stepField(by: 1)
                    }
                }
                .padding(.top, TFSpacing.sm)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height),
                              abs(value.translation.width) >= 36 else { return }
                        stepField(by: value.translation.width < 0 ? 1 : -1)
                    }
            )
        }
        .padding(.vertical, TFSpacing.xs)
        .tint(Color.tfSub)
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .onAppear { prepareField(activeField) }
        .onChange(of: dueDate == nil) { _, isNil in
            if isNil {
                startMinutes = nil
                durationMin = nil
            }
        }
    }

    private func pickerArrow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.regular))
                .foregroundStyle(Color.tfDim.opacity(0.35))
                .frame(width: 44, height: 180)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func stepField(by step: Int) {
        let fields: [Field] = [.date, .time, .duration, .repeatRule]
        guard let index = fields.firstIndex(of: activeField) else { return }
        activeField = fields[(index + step + fields.count) % fields.count]
        prepareField(activeField)
    }

    private func prepareField(_ field: Field) {
        if dueDate == nil {
            dueDate = moscowStartOfDay(offsetDays: 0)
        }
        if field == .time, startMinutes == nil {
            startMinutes = 9 * 60
        }
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { dueDate ?? moscowStartOfDay(offsetDays: 0) },
            set: { dueDate = $0 }
        )
    }

    private var startTimeBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = startMinutes ?? 9 * 60
                return Calendar.current.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                startMinutes = (components.hour ?? 9) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func moscowStartOfDay(offsetDays: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TaskDateText.moscow
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offsetDays, to: today) ?? today
    }
}

/// Системная шторка выбора уже существующей корневой задачи. Показываем
/// только задачи без `parent_id`: это не даёт случайно выдернуть ребёнка из
/// другой ветки и отсекает основной источник циклических связей.
private struct LinkedTaskPicker: View {
    let tasks: [ApiTask]
    let excludedIDs: Set<String>
    let onSelect: (ApiTask) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var linkingID: String?
    @State private var errorMessage: String?

    private var candidates: [ApiTask] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks
            .filter { $0.parentId == nil && !excludedIDs.contains($0.id) }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
            .sorted {
                if $0.status != $1.status { return $0.status == .active }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "Нет доступных задач",
                        systemImage: "link",
                        description: Text("Создайте новую связанную задачу или измените строку поиска.")
                    )
                } else {
                    ForEach(candidates) { task in
                        Button {
                            guard linkingID == nil else { return }
                            linkingID = task.id
                            Task {
                                if await onSelect(task) {
                                    dismiss()
                                } else {
                                    linkingID = nil
                                    errorMessage = "Не удалось связать задачу"
                                }
                            }
                        } label: {
                            HStack(spacing: TFSpacing.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(task.status == .completed ? "Выполнена" : "Открыта")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: TFSpacing.sm)
                                if linkingID == task.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "link.badge.plus")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .disabled(linkingID != nil)
                        .accessibilityHint("Добавляет задачу как дочернюю")
                    }
                }
            }
            .navigationTitle("Связать задачу")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Поиск задач")
            .alert("Ошибка", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

/// Мягкая верхняя кромка прокрутки (iOS 26+).
///
/// Вынесено отдельным модификатором, потому что `.scrollEdgeEffectStyle`
/// доступен с iOS 26, а цель сборки — iOS 18: `if #available` внутри цепочки
/// модификаторов дал бы две разные ветки типа и не собрался бы.
///
/// На системах старше 26 модификатор ничего не делает — кромка остаётся
/// системной по умолчанию (жёсткой), экран при этом полностью рабочий.
struct TFSoftTopScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}
