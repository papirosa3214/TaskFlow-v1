import SwiftUI
import SDWebImage
import SDWebImageWebPCoder

/// Точка входа. Собирает единственные экземпляры клиента/сессии/сторов на
/// время жизни приложения и раздаёт их через `.environment(...)` — экраны
/// (свои и заглушки) читают их через `@Environment(Type.self)`.
@main
struct TaskFlowApp: App {
    @State private var apiClient: APIClient
    @State private var session: SessionStore
    @State private var realtimeClient = RealtimeClient()
    @State private var taskStore: TaskStore
    @State private var projectStore: ProjectStore
    @State private var labelStore: LabelStore
    @State private var notificationStore: NotificationStore

    init() {
        // Анимированные аватарки агентов (просьба владельца 03.09.2026:
        // «раньше были анимированными») — голый WebP-декодер в SDWebImage
        // из коробки не идёт, регистрируется явно один раз на старте,
        // раньше первого обращения к `AnimatedImage` (см. `AgentRow.swift`).
        SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared)

        // Один `APIClient` на всё приложение — сторы делят его между собой,
        // токен он читает сам из Keychain на каждый запрос (см. APIClient.swift).
        let client = APIClient()
        _apiClient = State(initialValue: client)
        _session = State(initialValue: SessionStore(apiClient: client))
        _taskStore = State(initialValue: TaskStore(apiClient: client))
        _projectStore = State(initialValue: ProjectStore(apiClient: client))
        _labelStore = State(initialValue: LabelStore(apiClient: client))
        _notificationStore = State(initialValue: NotificationStore(apiClient: client))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.environment["TASKFLOW_CHAT_COMPOSER_PREVIEW"] == "1" {
                    AgentChatComposerPreview()
                } else {
                    RootView()
                }
                #else
                RootView()
                #endif
            }
                // 15.09.2026: мягкая верхняя кромка прокрутки на всех
                // экранах. После обновления iOS система перестала
                // выбирать её сама, и под шапкой появилась резкая
                // граница везде, кроме двух экранов, где вызов стоял
                // руками. Модификатор действует на вложенные прокрутки,
                // поэтому ставится один раз здесь.
                .tfSoftTopScrollEdge()
                .environment(session)
                .environment(taskStore)
                .environment(projectStore)
                .environment(labelStore)
                .environment(notificationStore)
                .environment(realtimeClient)
                .preferredColorScheme(.dark) // project.yml сейчас держит UIUserInterfaceStyle: Dark
                // 14.09.2026, Dynamic Type. Верхняя граница системного размера
                // текста — `xxxLarge`.
                //
                // Шкала кеглей теперь масштабируется (см. `Typography.swift`),
                // и на `xxxLarge` проверено кадром симулятора: отступы, строки
                // настроек, кнопки «Изменить» — всё на месте, ничего не режется.
                // Это примерно 200% от базового кегля, то есть требование
                // WCAG 1.4.4 (Resize Text) закрыто.
                //
                // ПОЧЕМУ ЕСТЬ ГРАНИЦА. Выше начинаются accessibility-размеры
                // (до ~3×), и там ломается не текст, а РАСКЛАДКА: строки
                // собраны горизонтально (иконка │ заголовок │ значение │ шеврон)
                // и рассчитаны на фиксированную ширину. На `accessibility1`
                // уже режется «Искусственный интелл…» и «Интеграции (Google, A…»,
                // на максимуме «Изменить» уезжает в две строки, а заголовки
                // секций теряют отступ. Ограничение здесь — осознанный размен:
                // лучше полный текст на 200%, чем обрезанный на 300%.
                //
                // КАК СНЯТЬ. Убрать эту строку и переверстать строки под
                // крупный кегль: разрешить перенос значения под заголовок
                // (`ViewThatFits` или `dynamicTypeSize`-ветка с VStack вместо
                // HStack). Тогда accessibility-размеры станут безопасны.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }
}

/// Корневая развилка: пока идёт проверка сохранённого токена — заставка;
/// дальше либо `LoginView` (spec §2.1: беспарольный LAN-вход нативу не
/// подходит, только email/пароль), либо `RootShellView` (таббар + маршруты).
///
/// Явный `@MainActor` на всём типе (не только на `body`, как того минимально
/// требует `View`) — `startSessionServices()` ниже трогает `@MainActor`-
/// изолированные сторы напрямую из замыкания `.onChange`, без него компилятор
/// не гарантирует изоляцию для произвольного метода типа.
@MainActor
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(LabelStore.self) private var labelStore
    @Environment(NotificationStore.self) private var notificationStore
    @Environment(RealtimeClient.self) private var realtimeClient

    var body: some View {
        ZStack {
            // Фон заходит под системную клавиатуру; содержимое сохраняет
            // штатное изменение safe area и не перекрывается клавиатурой.
            Color.tfBackground.ignoresSafeArea()

            Group {
                if session.isBootstrapping {
                    launchScreen
                } else if session.isAuthenticated {
                    RootShellView()
                } else {
                    LoginView()
                }
            }
        }
        .task {
            await session.bootstrap()
        }
        .onChange(of: session.isAuthenticated, initial: true) { _, isAuthenticated in
            if isAuthenticated {
                startSessionServices()
            } else {
                realtimeClient.disconnect()
            }
        }
    }

    private var launchScreen: some View {
        ZStack {
            Color.tfBackground.ignoresSafeArea()
            TFLoading(.block)
        }
    }

    /// Вызывается ровно один раз на каждый переход «стал авторизован» —
    /// подключает реалтайм-канал и грузит списки задач/проектов/меток/
    /// уведомлений параллельно.
    private func startSessionServices() {
        realtimeClient.onEvent = { event in
            taskStore.apply(event)
            notificationStore.apply(event)
        }
        realtimeClient.onReconnected = {
            // spec §4.2: сервер не хранит очередь пропущенных событий — на
            // переподключение обновляем весь кэш, который мог протухнуть за
            // время разрыва, а не только задачи.
            Task {
                async let tasksRefreshed: () = taskStore.refreshAfterReconnect()
                async let notificationsRefreshed: () = notificationStore.load()
                _ = await (tasksRefreshed, notificationsRefreshed)
            }
        }
        realtimeClient.connect()

        Task {
            async let tasksLoaded: () = taskStore.load()
            async let projectsLoaded: () = projectStore.load()
            async let labelsLoaded: () = labelStore.load()
            async let notificationsLoaded: () = notificationStore.load()
            _ = await (tasksLoaded, projectsLoaded, labelsLoaded, notificationsLoaded)
        }
    }
}
