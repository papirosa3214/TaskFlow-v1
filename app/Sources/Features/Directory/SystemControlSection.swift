import SwiftUI
import Observation
import os

// Настройки → Сервер: один переключатель автоматики «Система».
// ВКЛ — автоматические допуск, назначение и запуск; ВЫКЛ — ручной запуск.
// «Авторевьюер» управляет маршрутом проверки, «Расписание» — индикатор.
// Состояние хранится на сервере; непрочитанное значение не показываем как ВЫКЛ.

@MainActor
@Observable
final class SystemControlViewModel {
    private let api: APIClient
    private let log = Logger(subsystem: "TaskFlow", category: "system-control")

    /// Состояние обеих ручек читается ОТДЕЛЬНО и может быть неизвестным.
    /// Это не педантизм: показать выключённый тумблер там, где мы просто не
    /// дозвонились до сервера, — соврать владельцу. Он решит, что систему
    /// кто-то остановил, и полезет включать уже включённое.
    private(set) var isSystemOn = false
    private(set) var isSystemStateKnown = false
    private(set) var isTogglingSystem = false

    /// Когда система в следующий раз обойдёт доску. Приходит с сервера и
    /// нужен только для подписи: сама работа от него не зависит.
    private(set) var nextScanAt: Date?

    /// Планировщик расписания (taskflow-scheduler) — независимая лампа.
    private(set) var scheduler: SchedulerRunState?

    /// «Сначала проверка Reviewer» — общий маршрут новых карточек
    /// (раньше это был флаг на каждой карточке).
    private(set) var reviewerFirstDefault = true
    private(set) var isReviewerDefaultKnown = false
    private(set) var isSavingReviewerDefault = false

    /// Показывается только на собственное действие владельца. Неудачное
    /// чтение состояния его не касается — он ничего не трогал, и ругаться
    /// на него за молчащий сервер незачем.
    var errorMessage: String?

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func load() async {
        // `try?` здесь был бы проглоченной ошибкой: в логе пусто, на экране
        // «выключено», и разбираться потом не с чем.
        do {
            let state = try await api.fetchSystemRunState()
            isSystemOn = state.active
            nextScanAt = state.nextScanAt
            scheduler = state.scheduler
            isSystemStateKnown = true
        } catch {
            log.error("не удалось прочитать состояние системы: \(error.localizedDescription, privacy: .public)")
        }
        do {
            let settings = try await api.fetchTaskIntakeSettings()
            reviewerFirstDefault = settings.reviewerFirstDefault
            isReviewerDefaultKnown = true
        } catch {
            log.error("не удалось прочитать настройку авторевьюера: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setSystemOn(_ on: Bool) async {
        guard isSystemStateKnown, on != isSystemOn, !isTogglingSystem else { return }
        let confirmed = isSystemOn
        isSystemOn = on
        isTogglingSystem = true
        errorMessage = nil
        defer { isTogglingSystem = false }
        do {
            let state = try await api.setSystemRunning(on)
            isSystemOn = state.active
            nextScanAt = state.nextScanAt
        } catch {
            // Откат ровно к подтверждённому значению: оптимистичный показ
            // допустим только тогда, когда отказ его честно отменяет.
            isSystemOn = confirmed
            errorMessage = on ? "Не удалось включить систему" : "Не удалось выключить систему"
            log.error("переключение системы отклонено: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setReviewerDefault(_ on: Bool) async {
        guard isReviewerDefaultKnown, on != reviewerFirstDefault, !isSavingReviewerDefault else { return }
        let confirmed = reviewerFirstDefault
        reviewerFirstDefault = on
        isSavingReviewerDefault = true
        errorMessage = nil
        defer { isSavingReviewerDefault = false }
        do {
            reviewerFirstDefault = try await api.updateReviewerFirstDefault(on).reviewerFirstDefault
        } catch {
            reviewerFirstDefault = confirmed
            errorMessage = "Не удалось изменить проверку ревьюера"
            log.error("смена проверки ревьюера отклонена: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct SystemControlSection: View {
    @State private var viewModel = SystemControlViewModel()

    // Время обхода показывается МОМЕНТОМ («обход в 14:26»), а не тикающим
    // отсчётом — и вот почему.
    //
    // Сначала здесь стоял Timer.publish(every: 1) + @State now. Это работало,
    // но подпись строки — обычный String, поэтому каждую секунду
    // пересобиралась вся карточка целиком: обе строки и оба тумблера.
    // Платить перерисовкой всего экрана за бегущие секунды не стоит.
    //
    // Живой отсчёт в SwiftUI делается либо Text(date, style: .timer), либо
    // TimelineView(.periodic) — тогда перерисовывается только сам Text. Но
    // TFListRow принимает subtitle строкой, и вставить туда View нельзя без
    // правки самого компонента, а он вне этой карточки работ (LOCK-170).
    //
    // Момент времени решает задачу владельца ровно так же: видно, когда
    // система в следующий раз посмотрит доску. Перерисовка при этом одна —
    // когда пришло новое состояние с сервера.

    // Строки собраны ровно теми же кирпичами, что и «Пользовательские
    // настройки» (`SettingsScreen.toggleRow`): `TFListRow` с plain-иконкой
    // 40×40, `titleStyle: .action`, `verticalPadding: TFSpacing.xs` и
    // `TFToggle` в `trailing`. Голый системный `Toggle` с меткой, который
    // стоял здесь сначала, был полноразмерным и синим — в приложении
    // тумблеры уменьшены до 0.82 и красные (`TFToggle`), поэтому строка
    // выбивалась и высотой, и цветом из всех соседних.
    var body: some View {
        TFCard(padding: 0) {
            VStack(spacing: 0) {
                TFListRow(
                    icon: "power", iconStyle: .plain,
                    title: "Система",
                    subtitle: systemSubtitle,
                    trailing: AnyView(TFToggle(isOn: systemBinding)
                        .disabled(!viewModel.isSystemStateKnown || viewModel.isTogglingSystem)),
                    titleStyle: .action,
                    verticalPadding: TFSpacing.xs
                )
                TFDivider(inset: rowDividerInset)
                TFListRow(
                    icon: "checkmark.seal", iconStyle: .plain,
                    title: "Авторевьюер",
                    trailing: AnyView(TFToggle(isOn: reviewerDefaultBinding)
                        .disabled(!viewModel.isReviewerDefaultKnown || viewModel.isSavingReviewerDefault)),
                    titleStyle: .action,
                    verticalPadding: TFSpacing.xs
                )
                // Расписание — отдельная лампа: воркер живёт независимо от
                // будильника и делает запуск по времени и отложенные повторы.
                // Лампа и её подпись собраны ТЕМ ЖЕ видом, что у «Pi Runtime»
                // ниже (кружок 7pt слева от значения), чтобы в одной секции не
                // было двух разных способов показать состояние.
                TFDivider(inset: rowDividerInset)
                TFListRow(
                    icon: "clock.arrow.circlepath", iconStyle: .plain,
                    title: "Расписание",
                    trailing: AnyView(schedulerAccessory),
                    titleStyle: .action,
                    verticalPadding: TFSpacing.xs
                )
                if viewModel.errorMessage != nil {
                    TFErrorBanner(viewModel.errorMessage)
                        .padding(.horizontal, TFSpacing.lg)
                        .padding(.bottom, TFSpacing.sm)
                }
            }
        }
        .task { await viewModel.load() }
        // Ждём РОВНО до момента обхода и перечитываем состояние один раз.
        // Не опрос по таймеру: до срока делать нечего, а следующий момент
        // всё равно знает только сервер.
        //
        // `.task(id:)` сам снимает ожидание при уходе с экрана и запускает
        // заново, когда сервер сообщил новый срок. Если приложение свернули и
        // вернули уже после срока, задержка получится отрицательной — тогда
        // перечитываем сразу.
        .task(id: viewModel.nextScanAt) {
            guard viewModel.isSystemOn, let next = viewModel.nextScanAt else { return }
            let delay = next.timeIntervalSinceNow + 1
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            await viewModel.load()
        }
    }

    private var rowDividerInset: CGFloat { TFSpacing.lg + 40 + TFSpacing.md }

    // Заголовок строки ПОСТОЯННЫЙ («Система»,
    // «Авторевьюер», «Расписание»), состояние живёт в тумблере/лампе:
    // меняющийся заголовок читался бы двояко — это текущее положение или то,
    // что случится по нажатию.
    //
    // Подписи короткие намеренно: `TFListRow` режет subtitle в одну строку
    // (`lineLimit(1)`), длинная фраза оборвалась бы многоточием.

    /// Пока состояние не прочитано — говорим об этом прямо. Показать
    /// «Остановлена» там, где мы просто не дозвонились до сервера, — соврать
    /// владельцу: он решит, что систему кто-то выключил, и полезет включать.
    /// А когда система точно выключена, молчим: об этом и так говорит
    /// тумблер (просьба владельца 20.09.2026 — убрать слово «Остановлена»).
    /// В подписи остаётся только то, что тумблер показать не может, — момент
    /// ближайшего обхода.
    private var systemSubtitle: String? {
        guard viewModel.isSystemStateKnown else { return "Нет связи с сервером" }
        guard viewModel.isSystemOn else { return nil }
        return nextScanText
    }

    /// «обход в 14:26» — момент ближайшего обхода доски.
    ///
    /// `nil` — сервер не сообщил срок (старая версия или система стоит): тогда
    /// подпись пуста, без выдуманного времени.
    private var nextScanText: String? {
        guard let next = viewModel.nextScanAt else { return nil }
        // Срок уже прошёл, а состояние ещё не перечитано — значит обход
        // прямо сейчас. Показывать прошедшее время было бы враньём.
        if next.timeIntervalSinceNow <= 0 { return "идёт обход" }
        return "обход в \(Self.scanTimeFormatter.string(from: next))"
    }

    /// Только часы и минуты, в часовом поясе устройства: секунды в подписи
    /// не нужны, а формат берётся из настроек телефона, а не зашивается.
    private static let scanTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private var systemBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isSystemOn },
            set: { on in Task { await viewModel.setSystemOn(on) } }
        )
    }

    private var reviewerDefaultBinding: Binding<Bool> {
        Binding(
            get: { viewModel.reviewerFirstDefault },
            set: { on in Task { await viewModel.setReviewerDefault(on) } }
        )
    }

    /// Лампа расписания — ровно тот же вид, что у «Pi Runtime»:
    /// `Circle` 7pt слева от значения. Работает воркер или нет, показывает
    /// цвет (зелёный — жив и обходил доску недавно, красный — молчит дольше
    /// 15 минут, серый — выключен); словами это не дублируем, справа остаётся
    /// только время последнего обхода (просьба владельца 20.09.2026: «либо
    /// лампочку убирай, либо надпись убирай, а вот последний обход имеет
    /// смысл показывать»).
    @ViewBuilder
    private var schedulerAccessory: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(schedulerLampColor)
                .frame(width: 7, height: 7)
            Text(schedulerLastRunText)
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var schedulerLastRunText: String {
        guard let last = viewModel.scheduler?.lastRunAt else { return "обходов ещё не было" }
        return "Последний обход \(Self.scanTimeFormatter.string(from: last))"
    }

    private var schedulerLampColor: Color {
        guard let s = viewModel.scheduler, s.active, let last = s.lastRunAt else {
            return viewModel.scheduler?.active == true ? Color.tfGreen : Color.tfDim
        }
        return Date().timeIntervalSince(last) > 15 * 60 ? Color.tfRed : Color.tfGreen
    }
}
