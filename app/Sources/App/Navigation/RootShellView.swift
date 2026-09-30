import SwiftUI

/// Корневая оболочка после входа: 3 вкладки (Обзор/Планирование/Чат).
/// + центральная кнопка создания, поверх — свой `NavigationStack` (своя
/// история) на каждую вкладку — spec/SCREENS-1.md §1.1, §2.1.
/// `/inbox` не входит в состав — маршрут убран из веба (INTEGRATION.md).
///
/// Панель и меню создания — готовые компоненты `DesignSystem`
/// (`TFTabBar`/`TFCreateMenu`, `Sources/DesignSystem/Navigation/TFTabBar.swift`,
/// появились 31.08.2026 уже по ходу этой задачи) — здесь только их подключение:
/// состояние вкладки/меню, переходы, бейдж «Сегодня». Само оформление панели
/// этот файл не трогает (правило `ARCHITECTURE.md`: DesignSystem — только читать).
/// Черновик быстрой задачи: `.sheet(item:)` требует `Identifiable`, а
/// `TaskFormViewModel` — общий класс формы и своего `id` не имеет.
private struct QuickAddDraft: Identifiable {
    let id = UUID()
    let viewModel: TaskFormViewModel
}

struct RootShellView: View {
    enum Tab: Int, CaseIterable, Hashable {
        /// «Проекты» вынесены отдельной вкладкой 08.09.2026 (владелец: «помимо
        /// обзора сделать ещё отдельную кнопочку проекты»). Раньше туда вёл
        /// только ряд внутри «Обзора». Порядок пунктов — 2 слева, 2 справа от
        /// круглой кнопки создания, `TFTabBar` делит их пополам сам.
        case overview, projects, upcoming, chat

        var route: AppRoute {
            switch self {
            case .overview: .overview
            case .projects: .projects
            case .upcoming: .upcoming
            case .chat: .chat
            }
        }

        var label: String {
            switch self {
            case .overview: "Обзор"
            case .projects: "Проекты"
            case .upcoming: "Планирование"
            case .chat: "Чат"
            }
        }

        /// Имена локальных SVG-ассетов. Все нарисованы на одном 24×24 поле со
        /// stroke 1.75, поэтому их видимый размер не пляшет между вкладками.
        /// У «Сегодня» число накладывает `TFTodayDateIcon`.
        var icon: String {
            switch self {
            case .overview: "TabIconHome"
            case .projects: "TabIconProjects"
            case .upcoming: "TabIconPlanning"
            case .chat: "TabIconChat"
            }
        }
    }

    @Environment(TaskStore.self) private var taskStore

    // spec/SCREENS-1.md §1.1: стартовый экран — «Обзор» (было «Сегодня» —
    // расходилось со спекой и заодно ломало бейдж «Сегодня» ниже: initial-
    // срабатывание onChange помечало бы его просмотренным при каждом запуске).
    @State private var selectedTab: Tab = .overview
    @State private var isCreateMenuOpen = false
    /// Панель быстрого создания задачи: своя вью-модель живёт здесь, чтобы
    /// пережить переход «развернуть» в полную форму без потери введённого.
    ///
    /// Подаётся `.sheet(item:)`, а НЕ `.sheet(isPresented:)` с `if let` внутри:
    /// при втором варианте содержимое замыкания строится в той же транзакции,
    /// где вью-модель ещё `nil`, и шторка открывается пустой во весь экран
    /// (детент из пустого содержимого тоже не применяется). Проверено кадром
    /// симулятора 31.08.2026 — даже отладочный `Text` внутри `if let` не рисовался.
    @State private var quickAddDraft: QuickAddDraft?
    /// «Развернуть» из панели — полная форма с ТОЙ ЖЕ вью-моделью. Через
    /// `fullScreenCover`, а не пуш маршрута `/task/new`: маршрут строит экран
    /// заново и заводит СВОЮ вью-модель, то есть введённое в панели название,
    /// срок и выбранные файлы пропадали бы (проверено по коду `TaskFormScreen`
    /// 01.09.2026 — у него для этого есть `init(expandingFrom:)`).
    @State private var expandedDraft: QuickAddDraft?
    /// Куда переходим ПОСЛЕ закрытия панели: открыть полную форму в той же
    /// транзакции, где закрывается шторка, iOS не даёт — второе окно просто
    /// не появляется. Поэтому «развернуть» лишь запоминает вью-модель, а
    /// показ идёт из `onDismiss` (тем же приёмом сделан переход внутри
    /// `TaskFormScreen`).
    @State private var pendingExpand: TaskFormViewModel?
    @State private var paths: [Tab: NavigationPath] = [:]
    /// Зеркало `taskflow_today_badge_seen_date` из веба (spec §2.1) —
    /// `UserDefaults` вместо `localStorage`, тот же принцип: бейдж гаснет
    /// после первого захода на «Сегодня» в текущий календарный день и не
    /// появляется заново до полуночи, даже если список задач изменился.
    @AppStorage("taskflow_today_badge_seen_date") private var todayBadgeSeenDate: String = ""
    #if DEBUG
    /// Debug-роут `tasksheet:<id>` открывает ту же единую карточку, что и приложение.
    @State private var debugTaskSheetID: String?
    #endif

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .overview: navigationStack(for: .overview)
                case .projects: navigationStack(for: .projects)
                case .upcoming: navigationStack(for: .upcoming)
                case .chat: navigationStack(for: .chat)
                }
            }
            #if DEBUG
            // Отдельный узел (не тот, что несёт `.sheet(item: $quickAddDraft)`
            // ниже) — два `.sheet` на одном модификаторе в SwiftUI ненадёжны.
            // Копия шторки из `TodayScreen.swift` буквально (detents/индикатор/
            // радиус/фон) — единственный debug-роут, который реально
            // воспроизводит нативную шторку, а не пуш.
            .sheet(isPresented: Binding(
                get: { debugTaskSheetID != nil },
                set: { if !$0 { debugTaskSheetID = nil } }
            )) {
                if let id = debugTaskSheetID {
                    NavigationStack {
                        TaskFormScreen(taskID: id)
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color.tfSheetBackground)
                }
            }
            #endif
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Отступ под TFTabBar — теперь в самой `routeDestination` (см.
            // RouteDestinationView.swift): `.safeAreaInset`, повешенный
            // ЗДЕСЬ, снаружи `NavigationStack`, до запушенных экранов не
            // доходил вообще (`.navigationDestination` строит их отдельным
            // вызовом `routeDestination`, вне зоны действия этого модификатора
            // — проверено кадром симулятора 03.09.2026, баг было видно
            // «живьём»). Инсет только на корневых вкладках без единого пуша
            // был бы бесполезен: почти весь список экранов в приложении —
            // как раз запушенные.

            if isCreateMenuOpen {
                // Подложка ловит тап мимо и закрывает меню БЕЗ затемнения
                // фона (spec §2.1) — почти нулевая непрозрачность вместо
                // clear, иначе `onTapGesture` не ловит касания.
                Color.black.opacity(0.0001)
                    .ignoresSafeArea()
                    .onTapGesture { isCreateMenuOpen = false }
            }

            // Панель прячется на чате (её место занимает панель ввода,
            // владелец 01.09.2026) И на любом пуше текущей вкладки — см.
            // `shouldHideTabBar`. Раньше пряталась через `.opacity(0)` —
            // владелец 03.09.2026, увидев результат: «подложку-то ты
            // оставил какую-то, надо убрать вообще все слои, внизу ставить
            // только фон» — `.opacity` не убирает саму панель из дерева, её
            // фон-подложка (градиент под safe area, см. `TFTabBar.swift`)
            // технически всё ещё рендерится, просто прозрачной. Настоящее
            // «пусто внизу» — панель вообще не строится, когда скрыта.
            if !shouldHideTabBar {
                VStack(spacing: 0) {
                    if isCreateMenuOpen {
                        TFCreateMenu(items: createMenuItems)
                            .padding(.bottom, TFCreateMenuMetrics.gapAboveTabBar)
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                    }
                    TFTabBar(
                        items: tabItems,
                        selectedIndex: selectedIndexBinding,
                        isCreateMenuOpen: isCreateMenuOpen,
                        onSelect: { index in
                            guard let tab = Tab(rawValue: index) else { return }
                            // Повторный тап по УЖЕ активной вкладке возвращает в её
                            // корень — как в родных приложениях. Без этого из
                            // «Проектов» нельзя было вернуться в «Обзор» тапом по
                            // самой вкладке: она уже выбрана, ничего не менялось.
                            if tab == selectedTab {
                                paths[tab] = NavigationPath()
                            } else {
                                selectedTab = tab
                            }
                        },
                        onCreateTap: { isCreateMenuOpen.toggle() }
                    )
                }
                .transition(.opacity)
            }
        }
        .environment(\.chatBackAction, {
            isCreateMenuOpen = false
            paths[.chat] = NavigationPath()
            selectedTab = .overview
        })
        .animation(.easeOut(duration: TFAnimation.createMenu), value: isCreateMenuOpen)
        // Владелец 07.09.2026: панель быстрого создания — надстройка над
        // клавиатурой с замутнённым фоном, а не выезжающая шторка. Отсюда
        // прозрачный `fullScreenCover` вместо `.sheet`: `.sheet` с фокусом в
        // поле резервирует место под клавиатуру и раздувается почти на весь
        // экран, а свой оверлей (фон + карточка у нижней кромки) живёт внутри
        // `QuickAddTaskView`.
        .fullScreenCover(item: $quickAddDraft, onDismiss: {
            if let viewModel = pendingExpand {
                pendingExpand = nil
                expandedDraft = QuickAddDraft(viewModel: viewModel)
            }
        }) { draft in
            QuickAddTaskView(
                viewModel: draft.viewModel,
                onSaved: { quickAddDraft = nil },
                onExpand: {
                    // Развернуть — тот же незаконченный черновик, только
                    // полной формой: вью-модель передаётся как есть,
                    // введённое не теряется.
                    pendingExpand = draft.viewModel
                    quickAddDraft = nil
                }
            )
            .presentationBackground(.clear)
        }
        // LOCK-253: развёрнутая форма должна открываться и вести себя ровно
        // как обычная задача — та же системная шторка (detents/хендл/
        // скругление/фон), что у `.sheet` в TodayScreen.swift при открытии
        // существующей карточки, а не `fullScreenCover`. Тот же
        // `presentationBackground(Color.tfSheetBackground)` заодно чинит
        // чёрный фон в скруглённых углах системной клавиатуры (iOS 26) —
        // fullScreenCover такого фона не задавал вовсе, отсюда были видны
        // чёрные уголки на новой карточке, которых нет на обычной.
        .sheet(item: $expandedDraft) { draft in
            NavigationStack {
                TaskFormScreen(expandingFrom: draft.viewModel)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.tfSheetBackground)
        }
        #if DEBUG
        // Отладочный автопереход: снять экран в симуляторе иначе нечем —
        // тапать по нему из командной строки нельзя, а показывать владельцу
        // нужно конкретный экран, а не только стартовый. Задаётся переменной
        // окружения при запуске, в релиз не попадает.
        .task {
            guard let raw = ProcessInfo.processInfo.environment["TASKFLOW_DEBUG_ROUTE"],
                  raw.isEmpty == false else { return }
            // Небольшая пауза: сторы должны успеть загрузиться, иначе экран
            // откроется пустым и кадр окажется бесполезным.
            try? await Task.sleep(for: .seconds(2))
            let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
            switch parts[0] {
            case "create":
                isCreateMenuOpen = true
            case "quickadd":
                quickAddDraft = QuickAddDraft(viewModel: TaskFormViewModel(taskID: nil))
            case "expand":
                expandedDraft = QuickAddDraft(viewModel: TaskFormViewModel(taskID: nil))
            case "task" where parts.count == 2:
                paths[selectedTab, default: NavigationPath()].append(AppRoute.taskDetail(taskID: parts[1]))
            case "tasksheet" where parts.count == 2:
                debugTaskSheetID = parts[1]
            case "notifications": paths[selectedTab, default: NavigationPath()].append(AppRoute.notifications)
            case "projects": paths[selectedTab, default: NavigationPath()].append(AppRoute.projects)
            case "settings": paths[selectedTab, default: NavigationPath()].append(AppRoute.settings)
            case "notes": paths[selectedTab, default: NavigationPath()].append(AppRoute.notes)
            case "noteeditor" where parts.count == 2:
                paths[selectedTab, default: NavigationPath()].append(AppRoute.noteEditor(noteID: parts[1]))
            case "today": selectedTab = .upcoming
            case "upcoming": selectedTab = .upcoming
            case "chat": selectedTab = .chat
            case "agents": paths[selectedTab, default: NavigationPath()].append(AppRoute.agents)
            default: break
            }
        }
        #endif
    }

    private var tabItems: [TFTabItem] {
        Tab.allCases.map { tab in
            TFTabItem(icon: tab.icon, accessibilityLabel: tab.label, badgeCount: tab == .upcoming ? todayBadgeCount : nil, showsTodayDate: tab == .upcoming)
        }
    }

    private var selectedIndexBinding: Binding<Int?> {
        Binding(
            get: { selectedTab.rawValue },
            set: { newValue in
                if let newValue, let tab = Tab(rawValue: newValue) {
                    selectedTab = tab
                }
            }
        )
    }

    /// Центральный «+» — один вход в создание трёх сущностей. Каждый пункт
    /// открывает форму сразу, а не соответствующий раздел приложения.
    private var createMenuItems: [TFCreateMenuItem] {
        [
            TFCreateMenuItem(icon: "checkmark", title: "Задача") {
                // Задача заводится компактной панелью над клавиатурой, а не
                // полноэкранным бланком: владелец так и просил — нажал «плюс»,
                // написал название, сохранил. Полная форма остаётся за кнопкой
                // «развернуть» внутри самой панели.
                isCreateMenuOpen = false
                quickAddDraft = QuickAddDraft(viewModel: TaskFormViewModel(taskID: nil))
            },
            TFCreateMenuItem(icon: "book", title: "Заметка") {
                openCreateMenuTarget(.noteCreate)
            },
            TFCreateMenuItem(icon: "tray", title: "Проект") {
                openCreateMenuTarget(.projectCreate)
            },
        ]
    }

    /// Активные задачи со сроком «сегодня» — то же условие, что у веба
    /// (`due_date === todayStr() && status === "active"`, spec §2.1).
    private var todayBadgeCount: Int {
        guard todayBadgeSeenDate != DateFormats.todayString() else { return 0 }
        return taskStore.tasks.count { $0.status == .active && $0.isDueToday }
    }

    /// Свой (не системный) `TFTabBar` не умеет родное `hidesBottomBarWhenPushed`
    /// сам по себе — он отдельный узел `ZStack`, поверх ЛЮБОГО экрана текущей
    /// вкладки, включая запушенные. Раньше это было незаметно (пуши без
    /// клавиатуры), но на экране с клавиатурой (редактор заметки) стало
    /// видно прямо: чужой нижний бар «едет» вместе с клавиатурой — владелец
    /// 03.09.2026: «поднимается меню... оно не типовое, какая-то странная
    /// отсебятина». Прячем панель, как только на вкладке есть хоть один
    /// пуш — то же правило, что раньше было только у чата.
    private var shouldHideTabBar: Bool {
        // Панель вкладок прячем только когда внутри вкладки есть пуш (открыт
        // конкретный чат). На КОРНЕ вкладки «Чат» (список чатов) панель нужна
        // — иначе с неё некуда вернуться (владелец 21.09.2026).
        !(paths[selectedTab]?.isEmpty ?? true)
    }

    private func navigationStack(for tab: Tab) -> some View {
        NavigationStack(path: pathBinding(for: tab)) {
            routeDestination(tab.route, reservesTabBarSpace: true)
                .navigationDestination(for: AppRoute.self) { routeDestination($0, reservesTabBarSpace: false) }
        }
    }

    private func pathBinding(for tab: Tab) -> Binding<NavigationPath> {
        Binding(
            get: { paths[tab] ?? NavigationPath() },
            set: { paths[tab] = $0 }
        )
    }

    private func openCreateMenuTarget(_ route: AppRoute) {
        isCreateMenuOpen = false
        paths[selectedTab, default: NavigationPath()].append(route)
    }
}
