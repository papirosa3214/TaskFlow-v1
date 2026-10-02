import SwiftUI

// Живой ход роли в чате (владелец 27.09.2026, LOCK-229): пока роль отвечает,
// окно чата показывает то же, что окно сессии Claude Code, — текст ответа
// растёт по словам, между кусками текста идут шаги (что читает, что
// выполняет, что ищет). После ответа ход остаётся в ленте таким же, каким
// шёл вживую (владелец 01.10.2026: свёрнутая строка «7 шагов · 42 с»
// выглядела так, будто всё удалили).
//
// 30.09.2026: текст идёт ровной скоростью и проявляется из пустоты,
// размышления — строкой «Думает…» с раскрываемым окошком вместо мелькающих
// фраз; тап по шагу или размышлению открывает шторку с подробностями.

/// Действие шага по имени инструмента с сервера. Сервер имя не
/// интерпретирует — подпись и значок целиком на клиенте. Существительные, а
/// не глаголы: одна и та же подпись годится и для идущего шага, и для
/// сделанного, и не зависит от рода роли.
enum RoleLiveStepKind {
    static func label(forTool tool: String) -> String {
        // Инструменты трекера (`taskflow_taskflow_agents` и т.п.): что именно
        // сделано, сервер пишет подписью — «кто на связи», «задачи проекта».
        if tool.hasPrefix("taskflow_") { return "Трекер" }
        switch tool {
        case "read": return "Чтение"
        case "edit", "write": return "Правка"
        case "bash": return "Команда"
        case "grep", "glob", "find": return "Поиск"
        case "ls": return "Папка"
        default: return "Действие"
        }
    }

    static func symbol(forTool tool: String) -> String {
        if tool.hasPrefix("taskflow_") { return "checklist" }
        switch tool {
        case "read": return "doc.text"
        case "edit", "write": return "pencil.line"
        case "bash": return "terminal"
        case "grep", "glob", "find": return "magnifyingglass"
        case "ls": return "folder"
        default: return "gearshape"
        }
    }
}

enum RoleLiveFormat {
    /// «1 шаг / 3 шага / 7 шагов».
    static func steps(_ count: Int) -> String {
        let mod100 = count % 100
        let word: String
        if mod100 >= 11 && mod100 <= 14 {
            word = "шагов"
        } else {
            switch count % 10 {
            case 1: word = "шаг"
            case 2, 3, 4: word = "шага"
            default: word = "шагов"
            }
        }
        return "\(count) \(word)"
    }

    /// «42 с», «3 мин 5 с», «12 мин».
    static func duration(seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s) с" }
        let minutes = s / 60
        let rest = s % 60
        return rest == 0 ? "\(minutes) мин" : "\(minutes) мин \(rest) с"
    }
}

/// Строка шага: значок, действие, подпись (путь, команда, запрос).
struct RoleLiveStepRow: View {
    let step: RoleChatLiveStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            icon
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16)
            Text(RoleLiveStepKind.label(forTool: step.tool))
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
            if let detail = step.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.tfDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var icon: some View {
        switch step.status {
        case .running:
            Image(systemName: RoleLiveStepKind.symbol(forTool: step.tool))
                .foregroundStyle(Color.tfSub)
                .symbolEffect(.pulse, options: .repeating)
        case .done:
            Image(systemName: RoleLiveStepKind.symbol(forTool: step.tool))
                .foregroundStyle(Color.tfDim)
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.tfOrange)
        }
    }

    private var accessibilityText: String {
        let status: String
        switch step.status {
        case .running: status = "идёт"
        case .done: status = "готово"
        case .error: status = "ошибка"
        }
        return [RoleLiveStepKind.label(forTool: step.tool), step.detail, status]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// Элементы хода по порядку: шаги строками, текст абзацами, размышления
/// свёрнутой строкой. В истории промежуточный текст («сейчас проверю…»)
/// приглушён — главный ответ в пузыре ниже. Тап по шагу или законченному
/// размышлению — шторка с подробностями (владелец 30.09.2026).
struct RoleLiveItemsList: View {
    let items: [RoleChatLiveItem]
    var textColor: Color = .tfText
    /// Проявление текста из пустоты — только у идущего хода.
    var fade: RoleTextFade?
    @State private var detail: RoleLiveDetail?

    var body: some View {
        let after = fade == nil ? [] : Self.charactersAfter(items)
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            // Индекс, а не текст: текст растёт каждые 150 мс, и id по нему
            // пересоздавал бы строку на каждом кадре.
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                switch item {
                case .text(let text):
                    RoleReplyMarkdown(text: text, color: textColor, fade: fade?.shifted(by: after[index]))
                case .step(let step):
                    Button { detail = .step(step) } label: {
                        RoleLiveStepRow(step: step)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Показать подробности")
                case .thinking(let thinking):
                    if thinking.isRunning {
                        RoleThinkingLiveRow(thinking: thinking)
                    } else {
                        Button { detail = .thinking(thinking) } label: {
                            RoleThinkingDoneRow(thinking: thinking)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Показать размышления")
                    }
                }
            }
        }
        .sheet(item: $detail) { detail in
            RoleLiveDetailSheet(detail: detail)
        }
    }

    /// Сколько символов текста идёт после каждого элемента — чтобы хвост
    /// проявлялся по всему ходу, а не у каждого абзаца отдельно.
    static func charactersAfter(_ items: [RoleChatLiveItem]) -> [Int] {
        var result = Array(repeating: 0, count: items.count)
        var sum = 0
        for index in items.indices.reversed() {
            result[index] = sum
            if case .text(let text) = items[index] { sum += text.count }
        }
        return result
    }
}

/// Идущий ход: шаги и растущий текст прямо по фону ленты, без карточки —
/// как ответ роли в 1:1-чате (LOCK-230); внизу — сколько уже идёт.
struct RoleLiveTurnBubble: View {
    let turn: RoleChatLiveTurn
    let showsName: Bool
    var isComplete = false
    var onPlaybackComplete: () -> Void = {}
    @State private var completionReported = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var driver = RoleLivePacerDriver()
    @State private var visibleItems: [RoleChatLiveItem] = []
    @State private var fade = RoleTextFade()

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            if showsName {
                Text(turn.name)
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
            }
            if !visibleItems.isEmpty {
                RoleLiveItemsList(items: visibleItems, fade: reduceMotion ? nil : fade)
            }
            // Сервер до 30.09.2026 шлёт только признак «думает» без текста.
            if turn.thinking != nil && turn.runningThinking == nil {
                RoleThinkingLiveRow(thinking: nil)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(footer(now: context.date))
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { ingest(turn.items) }
        .onChange(of: turn.items) { _, items in ingest(items) }
        .task(id: isComplete) {
            // Часы очереди: ~60 раз в секунду, но экран перерисовывается
            // только когда показалось новое слово.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { break }
                if driver.tick() { publish() }
                let animating = driver.isAnimating(now: .now)
                if animating != fade.isAnimating { fade.isAnimating = animating }
                if isComplete && !driver.pacer.hasPendingText && (reduceMotion || !animating) && !completionReported {
                    completionReported = true
                    onPlaybackComplete()
                }
            }
        }
    }

    private func ingest(_ items: [RoleChatLiveItem]) {
        driver.pacer.ingest(items)
        publish()
    }

    private func publish() {
        let items = driver.pacer.visibleItems
        if items != visibleItems { visibleItems = items }
        fade = RoleTextFade(
            rate: driver.pacer.rate,
            lastRevealAt: driver.pacer.lastRevealAt,
            isAnimating: driver.isAnimating(now: .now)
        )
    }

    private func footer(now: Date) -> String {
        let steps = turn.items.filter(\.isStep).count
        var parts = [isComplete ? "Ответ получен" : "Работает"]
        if let start = turn.startDate {
            parts.append(RoleLiveFormat.duration(seconds: Int(now.timeIntervalSince(start))))
        }
        if steps > 0 { parts.append(RoleLiveFormat.steps(steps)) }
        return parts.joined(separator: " · ")
    }
}

/// Держатель очереди вне наблюдения SwiftUI: такты часов меняют скорость и
/// бюджет, но перерисовку вызывают только новые слова.
@MainActor
final class RoleLivePacerDriver {
    var pacer = RoleLiveTextPacer()
    private var lastTick: ContinuousClock.Instant?

    /// Такт; true — видимый текст вырос.
    func tick() -> Bool {
        let now = ContinuousClock.now
        defer { lastTick = now }
        guard let lastTick, pacer.hasPendingText else { return false }
        let elapsed = now - lastTick
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let before = pacer.lastRevealAt
        pacer.advance(elapsed: min(seconds, 0.1))
        return pacer.lastRevealAt != before
    }

    func isAnimating(now: Date) -> Bool {
        pacer.hasPendingText || now.timeIntervalSince(pacer.lastRevealAt) < RoleTextFade.duration + 0.1
    }
}

/// Роль думает (30.09.2026): «Думает…» с бегущим бликом, без мелькающих
/// фраз. Если сервер прислал текст размышления — стрелка раскрывает окошко,
/// где мысли идут прокруткой.
struct RoleThinkingLiveRow: View {
    /// nil — сервер прислал только признак «думает».
    let thinking: RoleChatThinking?
    @State private var isExpanded = false

    private var hasText: Bool {
        !(thinking?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Button {
                withAnimation(.snappy(duration: 0.28)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                    Image(systemName: "brain")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.tfSub)
                        .symbolEffect(.pulse, options: .repeating)
                        .frame(width: 16)
                    RoleShimmerText(text: "Думает…")
                    if hasText {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.tfDim)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasText)
            .accessibilityLabel("Думает")
            .accessibilityHint(hasText ? (isExpanded ? "Скрыть размышления" : "Показать размышления") : "")

            if isExpanded, let thinking, hasText {
                RoleThinkingWindow(text: thinking.text)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// «Думает…» с бликом, пробегающим по буквам — как индикатор в Claude.
struct RoleShimmerText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let label = Text(text).tfText(.meta)
        if reduceMotion {
            label.foregroundStyle(Color.tfSub)
        } else {
            TimelineView(.animation) { context in
                let period = 1.8
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period
                // Блик идёт от -0.3 до 1.3, чтобы входить и выходить за край.
                let center = -0.3 + phase * 1.6
                label
                    .foregroundStyle(Color.tfSub)
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: center - 0.25),
                                .init(color: Color.tfText, location: center),
                                .init(color: .clear, location: center + 0.25),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .mask(label)
                    }
            }
        }
    }
}

/// Окошко с идущими мыслями: невысокое, прокручивается само вниз, новый
/// текст проявляется так же плавно, как ответ. Уже накопленное при
/// раскрытии показывается сразу.
struct RoleThinkingWindow: View {
    let text: String
    @State private var driver = RoleLivePacerDriver()
    @State private var visible = ""
    @State private var fade = RoleTextFade()
    @State private var contentHeight: CGFloat = 0

    private static let maxHeight: CGFloat = 132

    var body: some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.tfStroke)
                .frame(width: 2)
            ScrollView {
                Text(visible)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .roleReveal(fade)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .frame(height: min(max(contentHeight, 1), Self.maxHeight))
            .mask {
                // Верх окошка растворяется, когда мыслей больше, чем влезает.
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: contentHeight > Self.maxHeight ? 24 : 0)
                    Color.black
                }
            }
        }
        .padding(.leading, 7)
        .onAppear {
            driver.pacer.ingest([.text(text)])
            driver.pacer.flush()
            publish()
        }
        .onChange(of: text) { _, text in
            driver.pacer.ingest([.text(text)])
            publish()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                if driver.tick() { publish() }
                let animating = driver.isAnimating(now: .now)
                if animating != fade.isAnimating { fade.isAnimating = animating }
            }
        }
    }

    private func publish() {
        if case .text(let shown)? = driver.pacer.visibleItems.first {
            if shown != visible { visible = shown }
        }
        fade = RoleTextFade(
            rate: driver.pacer.rate,
            lastRevealAt: driver.pacer.lastRevealAt,
            isAnimating: driver.isAnimating(now: .now)
        )
    }
}

/// Законченное размышление строкой: «Размышления · 12 с», тап — шторка.
struct RoleThinkingDoneRow: View {
    let thinking: RoleChatThinking

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            Image(systemName: "brain")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.tfDim)
                .frame(width: 16)
            Text("Размышления")
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
            if let seconds = thinking.durationSeconds {
                Text(RoleLiveFormat.duration(seconds: seconds))
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.tfDim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let seconds = thinking.durationSeconds else { return "Размышления" }
        return "Размышления, \(RoleLiveFormat.duration(seconds: seconds))"
    }
}

/// Что открыто в шторке: размышление или шаг.
enum RoleLiveDetail: Identifiable {
    case thinking(RoleChatThinking)
    case step(RoleChatLiveStep)

    var id: String {
        switch self {
        case .thinking(let thinking): return "thinking-\(thinking.id)"
        case .step(let step): return "step-\(step.id)"
        }
    }
}

/// Системная шторка на пол-экрана, тянется до полного: всё о выбранном
/// размышлении или шаге.
struct RoleLiveDetailSheet: View {
    let detail: RoleLiveDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.md) {
                    if let meta, !meta.isEmpty {
                        Text(meta)
                            .tfText(.caption)
                            .foregroundStyle(Color.tfDim)
                    }
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private var title: String {
        switch detail {
        case .thinking: return "Размышления"
        case .step(let step): return RoleLiveStepKind.label(forTool: step.tool)
        }
    }

    private var meta: String? {
        switch detail {
        case .thinking(let thinking):
            return thinking.durationSeconds.map { RoleLiveFormat.duration(seconds: $0) }
        case .step(let step):
            let status: String
            switch step.status {
            case .running: status = "Идёт"
            case .done: status = "Готово"
            case .error: status = "Ошибка"
            }
            return ([status, step.durationSeconds.map { RoleLiveFormat.duration(seconds: $0) }, step.tool] as [String?])
                .compactMap { $0 }
                .joined(separator: " · ")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch detail {
        case .thinking(let thinking):
            RoleReplyMarkdown(text: thinking.text, color: .tfText)
                .textSelection(.enabled)
        case .step(let step):
            if let detail = step.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Color.tfText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Подробностей у шага нет.")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
            }
        }
    }
}

// MARK: - Проявление текста

/// Как проявляется хвост идущего текста (владелец 30.09.2026): новые буквы
/// выходят из прозрачности и лёгкого размытия. Возраст буквы считается от
/// её расстояния до конца текста при текущей скорости очереди.
struct RoleTextFade: Equatable {
    var rate: Double = RoleLiveTextPacer.minRate
    var lastRevealAt: Date = .distantPast
    var isAnimating = false
    /// Сколько символов текста идёт после этого куска.
    var offset = 0

    static let duration: TimeInterval = 0.25

    func shifted(by characters: Int) -> RoleTextFade {
        var copy = self
        copy.offset += characters
        return copy
    }

    /// 0 — буква только появилась, 1 — проявилась полностью.
    func opacity(distance: Int, now: Date) -> Double {
        let age = Double(distance + offset) / max(rate, 1) + now.timeIntervalSince(lastRevealAt)
        let t = min(1, max(0, age / Self.duration))
        return t * t * (3 - 2 * t)
    }
}

struct RoleRevealRenderer: TextRenderer {
    var fade: RoleTextFade
    var now: Date

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var total = 0
        for line in layout { for run in line { total += run.count } }
        var index = 0
        for line in layout {
            var lineCount = 0
            for run in line { lineCount += run.count }
            // Строка целиком проявилась — рисуем одним вызовом.
            if fade.opacity(distance: total - index - lineCount, now: now) >= 1 {
                ctx.draw(line)
                index += lineCount
                continue
            }
            for run in line {
                for glyph in run {
                    let opacity = fade.opacity(distance: total - index - 1, now: now)
                    index += 1
                    guard opacity > 0.01 else { continue }
                    var copy = ctx
                    copy.opacity = opacity
                    copy.draw(glyph)
                }
            }
        }
    }
}

extension View {
    /// Проявление хвоста текста; nil — текст рисуется как обычно.
    @ViewBuilder
    func roleReveal(_ fade: RoleTextFade?) -> some View {
        if let fade {
            TimelineView(.animation(minimumInterval: nil, paused: !fade.isAnimating)) { context in
                self.textRenderer(RoleRevealRenderer(
                    fade: fade,
                    now: fade.isAnimating ? context.date : .distantFuture
                ))
            }
        } else {
            self
        }
    }
}
