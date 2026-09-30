import SwiftUI

/// Чат координации — `/chat` (SCREENS-2 §3). Никакого стриминга токенов
/// нет (спека прямо это оговаривает) — сообщения приходят целиком, живой
/// сигнал только один: `TypingLine`.
struct ChatScreen: View {
    @Environment(SessionStore.self) private var session
    /// Стрелка «назад» в шапке: на чате нижняя панель вкладок скрыта, и это
    /// единственный выход. Действие кладёт `RootShellView` — чат корневая
    /// вкладка, `dismiss()` тут закрывать нечего.
    @Environment(\.chatBackAction) private var chatBack
    @State private var viewModel = ChatViewModel()
    @State private var isClearConfirmOpen = false
    /// Пушем экран открывает системная кнопка «назад» — тогда своя не нужна.
    var hidesOwnBackButton = false

    var body: some View {
        VStack(spacing: 0) {
            TFErrorBanner(viewModel.historyErrorMessage.map { _ in "Не удалось загрузить чат" })
                .padding(.horizontal, TFSpacing.lg)
                .padding(.top, TFSpacing.sm)

            messageList
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .chatComposerBar {
            ChatComposer(viewModel: viewModel)
        }
        // Была своя ZStack-шапка (`TFScreenHeader`) поверх ещё и системного
        // `.navigationTitle(.large)` без `.toolbar(.hidden)` — та же двойная
        // шапка, что чинили весь день на остальных экранах (просьба
        // владельца 03.09.2026: «нативные кнопки везде одним элементом» —
        // этот экран пропустили при прошлой зачистке). `chatBack` не `nil?`
        // — он ставится безусловно в `RootShellView` на всё время жизни
        // вкладки «Чат» (см. её же комментарий), так что кнопка «назад» в
        // toolbar тут не опциональна.
        //
        // Переключатель канала (был отдельной плашкой под шапкой) и кнопка
        // статистики (была пустой заглушкой — «ChatStatsSheet вне охвата»)
        // слиты в одно меню «…» — просьба владельца 03.09.2026: «минималистично,
        // не надо прям всё выпячивать, мне нужно — я кликну». Статистика
        // внутри при этом настоящая (`GET /chat/stats`, модель и запрос уже
        // были готовы — не хватало только этого экрана).
        .tfNativeHeader(viewModel.headerTitle, displayMode: .inline)
        .toolbar {
            // Своя стрелка «назад» нужна только когда экран КОРЕНЬ вкладки:
            // тогда системной кнопки нет и выйти больше нечем. Пушем из
            // списка чатов («Секретарь») системная кнопка есть, и рядом с ней
            // эта рисовала вторую стрелку (владелец 21.09.2026, LOCK-195).
            if !hidesOwnBackButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button { chatBack?() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Назад")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if viewModel.bothChannelsVisible {
                        Section("Канал") {
                            Button {
                                viewModel.switchChannel(to: .owner)
                            } label: {
                                if viewModel.activeChannel == .owner { Label(viewModel.counterpartFirstName, systemImage: "checkmark") }
                                else { Text(viewModel.counterpartFirstName) }
                            }
                        }
                    }
                    Button {
                        viewModel.openStats()
                    } label: {
                        Label("Статистика", systemImage: "chart.bar")
                    }
                    // Очистка чата — только владелец (владелец 21.09.2026:
                    // «должна быть возможность очищать этот чат»).
                    if session.currentUser?.role == .owner {
                        Button(role: .destructive) {
                            isClearConfirmOpen = true
                        } label: {
                            Label("Очистить чат", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Ещё")
            }
        }
        .background(Color.tfBackground)
        .alert("Очистить чат?", isPresented: $isClearConfirmOpen) {
            Button("Очистить", role: .destructive) {
                Task { await viewModel.clearChat() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все сообщения этого канала будут удалены. Отменить будет нельзя.")
        }
        .accessibilityIdentifier("chat.screen")
        .task {
            viewModel.configure(currentUser: session.currentUser)
            // Fire-and-forget: экран показывается сразу, данные подтягиваются в фоне.
            // Это и было главной причиной 27 с открытия чата — `start()` ждал
            // `reloadAll()` (участники + история + typing snapshot + markChatRead),
            // экран не отрисовывался пока все запросы не завершатся.
            Task { await viewModel.start() }
        }
        .onDisappear {
            viewModel.stop()
        }
        .tfBottomSheet(isPresented: $viewModel.isStatsSheetOpen, title: "Статистика чата") {
            ChatStatsSheetContent(
                stats: viewModel.stats,
                isLoading: viewModel.isLoadingStats,
                errorMessage: viewModel.statsErrorMessage
            )
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: TFSpacing.md) {
                    if viewModel.isLoadingHistory {
                        TFLoading(.block)
                    } else if viewModel.messages.isEmpty {
                        Text(viewModel.emptyStateText)
                            .tfText(.action)
                            .foregroundStyle(Color.tfDim)
                            .padding(.horizontal, TFSpacing.xl)
                            .padding(.top, TFSpacing.md)
                    }

                    ForEach(viewModel.messages) { message in
                        ChatBubble(
                            message: message,
                            mine: message.fromUserId == viewModel.currentUserId,
                            toMe: viewModel.currentUserId != nil
                                && message.toUserId == viewModel.currentUserId
                                && message.fromUserId != viewModel.currentUserId
                        )
                        .id(message.id)
                    }

                    TypingLine(typists: viewModel.visibleTypists)
                        .id("typing-line")
                }
                .padding(.top, TFSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .hideComposerScrollEdgeEffect()
            .onChange(of: viewModel.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.visibleTypists) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("typing-line", anchor: .bottom)
        }
    }
}

/// Содержимое шторки «Статистика» (`GET /chat/stats`, spec §3.9) — просьба
/// владельца 03.09.2026: «кого больше озадачивают» и т.п., подключил кнопку
/// в шапке к уже готовому эндпоинту (не была подключена никем раньше).
private struct ChatStatsSheetContent: View {
    let stats: ApiChatStats?
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.lg) {
            if isLoading && stats == nil {
                TFLoading(.block)
            } else if let errorMessage {
                TFErrorBanner(errorMessage, variant: .block)
            } else if let stats {
                Text("Всего сообщений: \(stats.total)")
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)

                if !stats.to.isEmpty { entryGroup(title: "Кому пишут больше всего", entries: stats.to) }
                if !stats.from.isEmpty { entryGroup(title: "От кого больше всего", entries: stats.from) }
                if !stats.pairs.isEmpty { pairGroup(stats.pairs) }
            }
        }
        .padding(.bottom, TFSpacing.xl)
    }

    private func entryGroup(title: String, entries: [ApiChatStatsEntry]) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader(title)
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        HStack {
                            Text(entry.name).tfText(.body).foregroundStyle(Color.tfText)
                            Spacer()
                            Text("\(entry.count)").tfText(.body).foregroundStyle(Color.tfSub)
                        }
                        .padding(.horizontal, TFSpacing.lg)
                        .padding(.vertical, TFSpacing.md)
                        if index < entries.count - 1 { TFDivider(inset: TFSpacing.lg) }
                    }
                }
            }
        }
    }

    private func pairGroup(_ pairs: [ApiChatStatsPair]) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Кто кому пишет")
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                        HStack {
                            Text("\(pair.from) → \(pair.to)").tfText(.body).foregroundStyle(Color.tfText).lineLimit(1)
                            Spacer()
                            Text("\(pair.count)").tfText(.body).foregroundStyle(Color.tfSub)
                        }
                        .padding(.horizontal, TFSpacing.lg)
                        .padding(.vertical, TFSpacing.md)
                        if index < pairs.count - 1 { TFDivider(inset: TFSpacing.lg) }
                    }
                }
            }
        }
    }
}
