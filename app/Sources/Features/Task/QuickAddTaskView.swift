import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Быстрое создание задачи. На iOS 26 вся компактная форма находится в
/// штатном `safeAreaBar(edge: .bottom)`: система сама размещает её над
/// клавиатурой. Поверхность — системный `glassEffect`, а кнопка основного
/// действия — `glassProminent`; ручных материалов, рамок и теней нет.
/// На iOS 18–25 сохранён прежний оверлей как совместимый fallback.
struct QuickAddTaskView: View {
    @Bindable var viewModel: TaskFormViewModel
    var onSaved: () -> Void
    var onExpand: () -> Void

    @Environment(TaskStore.self) private var taskStore
    @Environment(SessionStore.self) private var session
    @Environment(ProjectStore.self) private var projectStore
    @Environment(LabelStore.self) private var labelStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isDescriptionFocused: Bool
    @State private var isAttachmentImporterPresented = false
    @State private var isDescriptionExpanded = false
    @State private var isSubtasksExpanded = false
    @State private var newSubtaskTitle = ""
    @FocusState private var isSubtaskFocused: Bool
    @State private var isDueDatePopoverPresented = false
    @State private var isAttachmentsPopoverPresented = false

    // 15.09.2026: тип экрана стирается на границе — та же защита, что
    // спасла карточку задачи. Форма растёт секциями, и без разрыва
    // цепочки рантайм рано или поздно упрётся в стек при развороте типа.
    var body: some View { AnyView(bodyContent) }

    @ViewBuilder private var bodyContent: some View {
        Group {
            if #available(iOS 26.0, *) {
                systemQuickAdd
            } else {
                legacyQuickAdd
            }
        }
        .alert("Не удалось сохранить задачу", isPresented: Binding(
            get: { viewModel.saveErrorMessage != nil },
            set: { if !$0 { viewModel.saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.saveErrorMessage = nil }
        } message: {
            Text(viewModel.saveErrorMessage ?? "")
        }
        .task {
            await viewModel.loadRoles()
            isTitleFocused = true
        }
    }

    /// iOS 26: `safeAreaBar` — системный контейнер для произвольной панели у
    /// края safe area. Когда появляется клавиатура, её верхняя граница
    /// становится нижней safe area, поэтому вся форма движется вместе с ней.
    /// В отличие от `.toolbar(placement: .keyboard)`, здесь помещается не
    /// только ряд команд, а целая форма переменной высоты.
    @available(iOS 26.0, *)
    private var systemQuickAdd: some View {
        ZStack {
            // Прозрачный cover обязан оставить исходный экран видимым. Цвет
            // нужен лишь в зоне, которую открывают скругления клавиатуры;
            // отдельный UIKit-view рисует там полосу высотой 28 pt.
            KeyboardCornerBackdrop()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isDueDatePopoverPresented, !isAttachmentsPopoverPresented else { return }
                    closePanel()
                }
                .safeAreaBar(edge: .bottom) {
                    card(systemAppearance: true)
                        .glassEffect(.regular, in: .rect(cornerRadius: 26))
                        .tint(Color.primary)
                        .padding(.horizontal, TFSpacing.md)
                        .padding(.bottom, TFSpacing.sm)
                }
        }
    }

    /// Совместимость для минимальной версии приложения (iOS 18).
    private var legacyQuickAdd: some View {
        ZStack(alignment: .bottom) {
            // Замутнённый фон — владелец 07.09.2026: «остальное чуть-чуть
            // замутнить, чтобы окошко было более чётким». Тап по фону
            // закрывает панель, как смахивание у шторки.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.1))
                .ignoresSafeArea()
                .onTapGesture {
                    // Пока открыт поповер срока/вложений, тап по фону гасит
                    // только его: закрывать всю панель из-под открытой
                    // презентации — верный способ поймать залипшую анимацию.
                    guard !isDueDatePopoverPresented, !isAttachmentsPopoverPresented else { return }
                    closePanel()
                }

            card(systemAppearance: false)
                // Слои: замутнённый фон → карточка (`tfCard`) → капсула
                // инструментов, вдавленная в карточку (темнее + внутренняя
                // тень, см. `toolsCapsule`).
                .background(Color.tfCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                // Тонкая светлая кромка по краю карточки — владелец
                // 07.09.2026: без неё плашка растворяется в замутнённом фоне.
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
                .padding(.horizontal, TFSpacing.md)
                .padding(.bottom, TFSpacing.sm)
        }
    }

    /// Тёплый белый свет «ленты» в жёлобе инструментов — владелец
    /// 07.09.2026: «не красный свет, а обычный тёплый». Тем же цветом
    /// подсвечен низ иконок, чтобы источник читался одним.
    private static let warmGlow = Color(red: 1.0, green: 0.84, blue: 0.6)

    private func card(systemAppearance: Bool) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TextField("Новая задача", text: $viewModel.title, axis: .vertical)
                .tfText(.input)
                .foregroundStyle(Color.tfText)
                .lineLimit(1...4)
                .focused($isTitleFocused)

            if isDescriptionExpanded || !viewModel.taskDescription.isEmpty {
                TextField("Описание", text: $viewModel.taskDescription, axis: .vertical)
                    .tfText(.input)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1...3)
                    .focused($isDescriptionFocused)
            }

            if isSubtasksExpanded || !viewModel.subtaskDrafts.isEmpty {
                subtaskDraftRows
            }

            HStack(spacing: TFSpacing.xs) {
                toolsScroll(systemAppearance: systemAppearance)

                if viewModel.isSaveEnabled {
                    primaryActionButton(systemAppearance: systemAppearance)
                }
            }
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.sm)
    }

    /// Иконки листаются в пределах панели, но UIKit-подложка снимает
    /// горизонтальную «резинку». В legacy-виде сохраняем старое капсульное
    /// отсечение; системному iOS 26 бару форму задаёт сама стеклянная панель.
    @ViewBuilder
    private func toolsScroll(systemAppearance: Bool) -> some View {
        if systemAppearance {
            ScrollView(.horizontal, showsIndicators: false) {
                toolsCapsule(slot: TFHitTarget.min, systemAppearance: true)
                    .background(ScrollBounceDisabler())
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                toolsCapsule(slot: TFHitTarget.min, systemAppearance: false)
                    .background(ScrollBounceDisabler())
            }
            .clipShape(Capsule())
        }
    }

    /// Собственной диктовки здесь нет: владелец использует системный микрофон
    /// клавиатуры, а дальнейшая обработка полученного текста одинакова. Кнопка
    /// отправки появляется только для непустого названия; её вид полностью
    /// системный и компактный на iOS 26.
    @ViewBuilder
    private func primaryActionButton(systemAppearance: Bool) -> some View {
        if #available(iOS 26.0, *), systemAppearance {
            Button(action: save) {
                Image(systemName: "arrow.up")
                    .font(.system(size: TFIconSize.xs, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Добавить задачу")
        } else {
            Button(action: save) {
                Image(systemName: "arrow.up")
                    .font(.system(size: TFIconSize.xs, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    // Кнопка — наоборот выпуклая: блик сверху, затемнение снизу,
                    // светлая кромка по верхней дуге и падающая тень под кругом.
                    .background {
                        Circle()
                            .fill(Color.tfRed)
                            .overlay {
                                // Только блик сверху, без затемнения снизу: чёрный
                                // градиент уводил низ кнопки в бордовый, и она
                                // переставала совпадать по цвету с подсветкой жёлоба
                                // (владелец 07.09.2026: «красный должен соответствовать»).
                                Circle().fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.22), Color.clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                            }
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
                                    .mask(
                                        Circle().fill(
                                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center)
                                        )
                                    )
                            }
                            .shadow(color: .black.opacity(0.5), radius: 7, y: 4)
                            .shadow(color: Color.tfRed.opacity(0.45), radius: 10, y: 2)
                    }
                    .frame(width: TFHitTarget.min, height: TFHitTarget.min)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Добавить задачу")
        }
    }

    /// Подзадачи прямо в панели — владелец 07.09.2026: «а где я подзадачу тут
    /// могу шлёпать?». Ради них полную форму открывать больше не нужно.
    private var subtaskDraftRows: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            ForEach(viewModel.subtaskDrafts) { draft in
                HStack(spacing: TFSpacing.sm) {
                    Image(systemName: "circle")
                        .font(.system(size: TFIconSize.xs))
                        .foregroundStyle(Color.tfDim)
                    Text(draft.title)
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                    Spacer(minLength: 0)
                    Button {
                        viewModel.subtaskDrafts.removeAll { $0.id == draft.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: TFIconSize.xs))
                            .foregroundStyle(Color.tfDim)
                            .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Удалить подзадачу \(draft.title)")
                }
            }

            HStack(spacing: TFSpacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: TFIconSize.xs))
                    .foregroundStyle(Color.tfDim)
                TextField("Подзадача", text: $newSubtaskTitle)
                    .tfText(.input)
                    .foregroundStyle(Color.tfText)
                    .focused($isSubtaskFocused)
                    .submitLabel(.next)
                    .onSubmit(addSubtaskDraft)
            }
        }
    }

    /// Овальная панель инструментов — один ряд, всё, что раньше было
    /// отдельными строками (срок/проект/приоритет/метки/вложения/исполнитель)
    /// плюс «развернуть», теперь иконки внутри одной капсулы, как у Todoist.
    private func toolsCapsule(slot: CGFloat, systemAppearance: Bool) -> some View {
        HStack(spacing: 0) {
            // Владелец 07.09.2026: «было бы логично, что если я ещё раз тапнул
            // на описание, я бы мог его убрать» — тумблер, а не кнопка в одну
            // сторону. Заполненное поле тапом не теряется: сворачиваем только
            // пустое.
            Button {
                withAnimation(.easeInOut(duration: TFDuration.fast)) {
                    if isDescriptionExpanded, viewModel.taskDescription.isEmpty {
                        isDescriptionExpanded = false
                        isDescriptionFocused = false
                    } else {
                        isDescriptionExpanded = true
                        isDescriptionFocused = true
                    }
                }
            } label: {
                quickIcon(slot: slot, "text.alignleft", isSet: isDescriptionExpanded || !viewModel.taskDescription.isEmpty, systemAppearance: systemAppearance)
            }
            .accessibilityLabel("Описание")

            Button {
                withAnimation(.easeInOut(duration: TFDuration.fast)) {
                    if isSubtasksExpanded, viewModel.subtaskDrafts.isEmpty, newSubtaskTitle.isEmpty {
                        isSubtasksExpanded = false
                        isSubtaskFocused = false
                    } else {
                        isSubtasksExpanded = true
                        isSubtaskFocused = true
                    }
                }
            } label: {
                quickIcon(slot: slot, "checklist", isSet: isSubtasksExpanded || !viewModel.subtaskDrafts.isEmpty, systemAppearance: systemAppearance)
            }
            .accessibilityLabel("Подзадачи")
            .accessibilityValue(viewModel.subtaskDrafts.isEmpty ? "Нет" : "\(viewModel.subtaskDrafts.count)")

            Button { isDueDatePopoverPresented = true } label: {
                quickIcon(slot: slot, "calendar", isSet: viewModel.dueDate != nil, systemAppearance: systemAppearance)
            }
            .accessibilityLabel("Срок")
            .accessibilityValue(dueDateText)
            .popover(isPresented: $isDueDatePopoverPresented) {
                dueDatePicker
                    .padding(TFSpacing.lg)
                    .frame(width: 300)
                    .presentationCompactAdaptation(.popover)
                    // Прозрачный фон внешней презентации (см. `RootShellView`)
                    // протекает во вложенные — без явного материала поповер
                    // открывался пустым стеклом.
                    .presentationBackground(.regularMaterial)
            }

            Menu {
                Button("Не выбран") { viewModel.projectId = nil }
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
                quickIcon(slot: slot, "folder", isSet: viewModel.projectId != nil, systemAppearance: systemAppearance)
            }
            .accessibilityLabel("Проект")
            .accessibilityValue(projectName)

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
                quickIcon(slot: slot, "flag", isSet: viewModel.priority != .low, systemAppearance: systemAppearance)
            }
            .accessibilityLabel("Приоритет")
            .accessibilityValue(viewModel.priority.label)

            Menu {
                ForEach(labelStore.labels) { label in
                    Toggle(label.name, isOn: Binding(
                        get: { viewModel.selectedLabelIds.contains(label.id) },
                        set: { selected in
                            if selected { viewModel.selectedLabelIds.insert(label.id) }
                            else { viewModel.selectedLabelIds.remove(label.id) }
                        }
                    ))
                }
            } label: {
                quickIcon(slot: slot, "tag", isSet: !viewModel.selectedLabelIds.isEmpty, systemAppearance: systemAppearance)
            }
            .accessibilityLabel("Метки")
            .accessibilityValue(labelsText)

            // Исполнитель — роль (LOCK-178), как в полной карточке.
            Menu {
                Button("Автоматически") {
                    viewModel.ownerSelectedRole = nil
                    viewModel.assigneeId = nil
                }
                // Себя — как в полной карточке (владелец 27.09.2026: при
                // создании себя было не выбрать): карточку на владельце
                // агенты не берут.
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
                        viewModel.ownerSelectedRole = role.role
                        viewModel.assigneeId = nil
                    } label: {
                        if viewModel.ownerSelectedRole == role.role {
                            Label(role.title, systemImage: "checkmark")
                        } else {
                            Text(role.title)
                        }
                    }
                }
            } label: {
                quickIcon(slot: slot, "person", isSet: viewModel.ownerSelectedRole != nil || viewModel.assigneeId != nil, systemAppearance: systemAppearance)
            }
            .accessibilityLabel("Исполнитель")
            .accessibilityValue(assigneeName)

            Button { isAttachmentsPopoverPresented = true } label: {
                quickIcon(slot: slot, "paperclip", isSet: !viewModel.attachments.uploaded.isEmpty || !viewModel.attachments.pending.isEmpty, systemAppearance: systemAppearance)
            }
            .accessibilityLabel("Вложения")
            .accessibilityValue(attachmentsText)
            .popover(isPresented: $isAttachmentsPopoverPresented) {
                attachmentsPicker
                    .padding(TFSpacing.lg)
                    .frame(width: 300)
                    .presentationCompactAdaptation(.popover)
                    // Прозрачный фон внешней презентации (см. `RootShellView`)
                    // протекает во вложенные — без явного материала поповер
                    // открывался пустым стеклом.
                    .presentationBackground(.regularMaterial)
            }

            Button(action: onExpand) {
                quickIcon(slot: slot, "arrow.up.left.and.arrow.down.right", isSet: false, systemAppearance: systemAppearance)
            }
            .accessibilityLabel("Открыть полную форму")
        }
        // То же короткое физическое сжатие, что у кнопок Markdown-панели над
        // клавиатурой. Внешность ряда не меняется: это только реакция на палец.
        .buttonStyle(TFTapScaleStyle())
        .padding(.horizontal, systemAppearance ? 0 : TFSpacing.xs)
        // Владелец 07.09.2026: «сделай, как будто она впечаталась туда, в
        // глубину» — капсула темнее карточки плюс внутренняя тень сверху и
        // светлая кромка снизу, чтобы ряд читался вдавленным, а не выпуклым.
        .background {
            if !systemAppearance {
                Capsule()
                    .fill(Color.tfBackground)
                    .overlay {
                        Capsule()
                            .stroke(Color.black.opacity(0.55), lineWidth: 3)
                            .blur(radius: 2.5)
                            .offset(y: 1.5)
                            .mask(Capsule().fill(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)))
                    }
                    // Владелец 07.09.2026: «как будто в жёлобе под потолком
                    // светодиодная лента» — не прямой свет, а отражённый: мягкий
                    // разлив акцентного цвета по дну и подсвеченная нижняя дуга.
                    .overlay {
                        Capsule().fill(
                            LinearGradient(
                                colors: [.clear, Self.warmGlow.opacity(0.14)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )
                    }
                    .overlay {
                        Capsule()
                            .stroke(Self.warmGlow.opacity(0.45), lineWidth: 2.5)
                            .blur(radius: 3)
                            .offset(y: -2)
                            .mask(Capsule().fill(LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)))
                    }
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    }
            }
        }
    }

    /// Иконка инструмента: глиф по шкале Dynamic Type, тап-цель — штатные
    /// 44pt (HIG), выбранное значение подсвечено акцентом, а не только
    /// формой — цветом смысл не передаём в одиночку, у кнопок есть
    /// `accessibilityValue`.
    @ViewBuilder
    private func quickIcon(slot: CGFloat, _ systemImage: String, isSet: Bool, systemAppearance: Bool) -> some View {
        if systemAppearance {
            Image(systemName: systemImage)
                .symbolVariant(isSet ? .fill : .none)
                .font(.system(size: TFIconSize.sm))
                // Заполненная форма сама по себе почти не читается на стекле:
                // выбранный инструмент должен явно оставаться красным, как
                // активные переключатели форматирования в Markdown-панели.
                .foregroundStyle(isSet ? Color.tfRed : Color.tfSub)
                .frame(width: slot, height: slot)
        } else {
            Image(systemName: systemImage)
                // Владелец 07.09.2026: «катастрофически маленькие». 44pt — это
                // тап-цель, а не глиф: цель осталась 48pt, сам символ вырос с
                // 17pt (.body) до 22pt (.title2).
                .font(.title2)
                // Объём по одному источнику света с жёлобом: лента светит снизу,
                // поэтому низ глифа теплее и светлее, верх уходит в тень. Тени
                // направлены туда же — тёплый отсвет вниз, тёмная кромка вверх.
                .foregroundStyle(
                    LinearGradient(
                        colors: isSet
                            ? [Color.tfRed.opacity(0.7), Color.tfRed]
                            : [Color.tfSub.opacity(0.55), Color.tfText.opacity(0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.9), radius: 1, y: -1)
                .shadow(color: Self.warmGlow.opacity(0.5), radius: 2, y: 1.5)
                .frame(width: slot, height: slot)
        }
    }

    private var projectName: String {
        projectStore.projects.first { $0.id == viewModel.projectId }?.name ?? "Не выбран"
    }

    private var assigneeName: String {
        if let me = session.currentUser, viewModel.assigneeId == me.id {
            return me.name
        }
        guard let role = viewModel.ownerSelectedRole,
              let profile = viewModel.roles.first(where: { $0.role == role }) else {
            return "Автоматически"
        }
        return profile.title
    }

    private var dueDateText: String {
        guard let dueDate = viewModel.dueDate else { return "Не установлен" }
        let date = TaskDateText.dueLabel(dueDate)
        guard let minutes = viewModel.startMinutes else { return date }
        return "\(date), \(String(format: "%02d:%02d", minutes / 60, minutes % 60))"
    }

    private var labelsText: String {
        switch viewModel.selectedLabelIds.count {
        case 0: "Не выбраны"
        case 1: labelStore.labels.first { viewModel.selectedLabelIds.contains($0.id) }?.name ?? "1 метка"
        default: "\(viewModel.selectedLabelIds.count) метки"
        }
    }

    private var attachmentsText: String {
        let count = viewModel.attachments.uploaded.count + viewModel.attachments.pending.count
        return count == 0 ? "Нет" : "\(count)"
    }

    /// Владелец 09.09.2026: «если я сюда залез, значит я хочу устанавливать —
    /// зачем эти переключатели». Переключатели «Установить срок» и «Указать
    /// время» убраны: открыл выбор срока — сразу выбираешь. Дата
    /// проставляется на сегодня при открытии, время — на 9:00, и то и другое
    /// сразу правится. Отказаться от срока по-прежнему можно, но явной
    /// кнопкой внизу, а не тумблером сверху.
    private var dueDatePicker: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            DatePicker("Дата", selection: dueDateSelection, displayedComponents: .date)
            DatePicker("Время", selection: startTimeSelection, displayedComponents: .hourAndMinute)
            Picker("Продолжительность", selection: $viewModel.durationMin) {
                Text("Не указана").tag(Int?.none)
                Text("15 минут").tag(Optional(15))
                Text("30 минут").tag(Optional(30))
                Text("45 минут").tag(Optional(45))
                Text("1 час").tag(Optional(60))
                Text("2 часа").tag(Optional(120))
                Text("3 часа").tag(Optional(180))
            }

            if viewModel.dueDate != nil {
                Divider()
                Button(role: .destructive) {
                    viewModel.dueDate = nil
                    viewModel.startMinutes = nil
                    viewModel.durationMin = nil
                    isDueDatePopoverPresented = false
                } label: {
                    Text("Убрать срок").frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        // Открыли — значит выбираем: проставляем сегодня и 9:00, чтобы
        // пикеры были живыми, а не пустыми.
        .onAppear {
            if viewModel.dueDate == nil {
                viewModel.dueDate = Calendar.current.startOfDay(for: Date())
            }
            if viewModel.startMinutes == nil { viewModel.startMinutes = 9 * 60 }
        }
    }

    private var attachmentsPicker: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            Button { isAttachmentImporterPresented = true } label: {
                Label("Выбрать файл", systemImage: "paperclip")
            }
            .disabled(viewModel.attachments.isUploading)

            ForEach(viewModel.attachments.pending) { attachment in
                attachmentRow(attachment.fileName) { viewModel.attachments.removePending(attachment) }
            }
            ForEach(viewModel.attachments.uploaded) { attachment in
                attachmentRow(attachment.fileName) { Task { await viewModel.attachments.removeUploaded(attachment) } }
            }
        }
        .fileImporter(isPresented: $isAttachmentImporterPresented, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                Task { await viewModel.attachments.add(url: url) }
            }
        }
    }

    private func attachmentRow(_ name: String, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(name).lineLimit(1)
            Spacer()
            Button(role: .destructive, action: remove) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Удалить \(name)")
        }
    }

    private var hasDueDate: Binding<Bool> {
        Binding(
            get: { viewModel.dueDate != nil },
            set: { enabled in
                if enabled { viewModel.dueDate = Calendar.current.startOfDay(for: Date()) }
                else {
                    viewModel.dueDate = nil
                    viewModel.startMinutes = nil
                    viewModel.durationMin = nil
                }
            }
        )
    }

    private var dueDateSelection: Binding<Date> {
        Binding(get: { viewModel.dueDate ?? Date() }, set: { viewModel.dueDate = $0 })
    }

    private var hasStartTime: Binding<Bool> {
        Binding(
            get: { viewModel.startMinutes != nil },
            set: { enabled in
                viewModel.startMinutes = enabled ? (viewModel.startMinutes ?? 9 * 60) : nil
                if !enabled { viewModel.durationMin = nil }
            }
        )
    }

    private var startTimeSelection: Binding<Date> {
        Binding(
            get: {
                let minutes = viewModel.startMinutes ?? 9 * 60
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                viewModel.startMinutes = (components.hour ?? 9) * 60 + (components.minute ?? 0)
            }
        )
    }

    /// Закрытие панели: сначала снимаем фокус, потом закрываем. Иначе
    /// клавиатура опускается одновременно с анимацией закрытия — на устройстве
    /// это давало подвисания (владелец 07.09.2026: «пару раз тыкаю — застряла»).
    private func closePanel() {
        isTitleFocused = false
        isDescriptionFocused = false
        isSubtaskFocused = false
        dismiss()
    }

    /// Добавляет набранный пункт и оставляет фокус в поле — пункты вводятся
    /// подряд, как в списке напоминаний.
    private func addSubtaskDraft() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.subtaskDrafts.append(SubtaskDraft(title: trimmed))
        newSubtaskTitle = ""
        isSubtaskFocused = true
    }

    private func save() {
        guard viewModel.isSaveEnabled else { return }
        // Недописанный пункт при отправке не теряем — он такая же подзадача,
        // просто владелец не успел нажать Enter.
        addSubtaskDraft()
        isTitleFocused = false
        isDescriptionFocused = false
        isSubtaskFocused = false
        Task {
            if await viewModel.save(taskStore: taskStore) {
                onSaved()
            }
        }
    }
}

/// Снимает «резинку» с горизонтального скролла инструментов. SwiftUI своего
/// API для этого не даёт: `scrollBounceBehavior(.basedOnSize)` гасит отскок
/// только когда содержимое помещается целиком, а у нас оно шире экрана —
/// именно на это качание владелец 07.09.2026 и жаловался («жёлоб шатало»).
/// Пустая UIKit-вьюха кладётся фоном внутрь скролла и снимает `bounces` у
/// ближайшего `UIScrollView` вверх по иерархии.
private struct ScrollBounceDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            var candidate: UIView? = uiView.superview
            while let current = candidate {
                if let scrollView = current as? UIScrollView {
                    scrollView.bounces = false
                    scrollView.alwaysBounceHorizontal = false
                    return
                }
                candidate = current.superview
            }
        }
    }
}

/// Прозрачный `fullScreenCover` короткого создания должен показывать экран,
/// из которого он был открыт. Но верхние скругления системной клавиатуры
/// открывают крошечные участки окна этого cover. Рисуем цвет фона только под
/// этой кромкой: клавиатура закрывает всю полосу, кроме собственных уголков.
private struct KeyboardCornerBackdrop: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardCornerBackdropView {
        KeyboardCornerBackdropView()
    }

    func updateUIView(_ uiView: KeyboardCornerBackdropView, context: Context) {}
}

private final class KeyboardCornerBackdropView: UIView {
    private let cornerStrip = UIView()
    private var keyboardFrameInScreen: CGRect?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        cornerStrip.backgroundColor = UIColor(Color.tfBackground)
        addSubview(cornerStrip)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameDidChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCornerStrip()
    }

    @objc private func keyboardFrameDidChange(_ notification: Notification) {
        keyboardFrameInScreen = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        updateCornerStrip()
    }

    private func updateCornerStrip() {
        guard let keyboardFrameInScreen, let window else {
            cornerStrip.isHidden = true
            return
        }

        let keyboardFrameInWindow = window.convert(keyboardFrameInScreen, from: nil)
        let keyboardFrame = convert(keyboardFrameInWindow, from: window)
        let y = min(max(keyboardFrame.minY, bounds.minY), bounds.maxY)
        let height = min(28, bounds.maxY - y)

        cornerStrip.frame = CGRect(x: bounds.minX, y: y, width: bounds.width, height: max(0, height))
        cornerStrip.isHidden = height <= 0
    }
}
