import SwiftUI

// Карточка проекта — владелец 08.09.2026: «список обычный такой голимый, а
// хочется, чтобы прям карточка была, с адекватной информацией: как давно
// висит, сколько задач выполнено, сколько вообще было поставлено».
//
// Общие числа приходят готовыми из `GET /api/projects` (`task_count`,
// `completed_count`, `overdue_count`, `last_activity_at`, `docs_count`).
// Разбиение активных задач на review/blocked/остальные берётся из уже
// загруженного общего `TaskStore`: отдельного запроса на каждый проект нет,
// а realtime-изменение задачи сразу перерисовывает соответствующую карточку.
//
// Оформление — по эталону «Модели и голоса» (владелец 03.09.2026 просил
// причёсывать экраны под него): без цветных плашек и заливок. Цвет проекта
// живёт ровно в одной точке у названия; полоса прогресса и весь текст —
// нейтральные. Первая версия красила ещё и полосу, и список из полутора
// десятков проектов превращался в радугу (владелец 08.09.2026: «всё
// приложение минималистичное, а тут как клоуна нарядил»).
struct ProjectCard: View {
    let project: ApiProject
    let tasks: [ApiTask]

    init(project: ApiProject, tasks: [ApiTask] = []) {
        self.project = project
        self.tasks = tasks
    }

    private var accent: Color { Color(hex: project.color ?? TFHexDefault.unassigned) }
    private var status: ProjectTaskStatusSummary {
        ProjectTaskStatusSummary(project: project, tasks: tasks)
    }
    private var total: Int { status.total }
    private var completed: Int { status.completed }
    private var overdue: Int { project.overdueCount ?? 0 }
    private var docs: Int { project.docsCount ?? 0 }

    var body: some View {
        TFCard {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                header
                if total > 0 {
                    progress
                }
                statusLine
                if hasMetadata {
                    metrics
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        // Выравнивание по верху: у имени в две строки точка, центрированная
        // по всему блоку, съезжала на межстрочный интервал. Отступ 6pt ставит
        // её по центру ПЕРВОЙ строки (17pt title).
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
            // Две строки, а не одна: в карточке место есть, а имена вроде
            // «Аудит фактической схемы мультиагентов TaskFlow» на одной
            // строке обрезаются до неразличимости (проверено кадром 08.09.2026).
            Text(project.name)
                .tfText(.title)
                .foregroundStyle(Color.tfText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: TFSpacing.sm)
            if project.pinned {
                Image(systemName: "pin.fill")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
                    .padding(.top, 3)
                    .accessibilityLabel("Закреплён")
            }
        }
    }

    /// Полоса «сделано из всего». Доля считается от ВСЕХ задач проекта
    /// (активные + выполненные), а не от активных: вопрос владельца — «сколько
    /// вообще было поставлено и сколько из этого закрыто».
    ///
    /// Полоса НЕЙТРАЛЬНАЯ, не цвета проекта: владелец 08.09.2026, увидев
    /// список из полутора десятков разноцветных полос, — «всё приложение
    /// минималистичное, а тут как клоуна нарядил». Цвет проекта остаётся
    /// только точкой у названия, как метка, а не как заливка.
    private var progress: some View {
        Capsule()
            .fill(Color.tfStroke)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.tfSub)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .accessibilityLabel("Выполнено \(completed) из \(total)")
    }

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    /// Главная сводка — без фонов и слов: системная иконка и число одним
    /// цветом. Порядок постоянный, поэтому карточки легко сравнивать глазами;
    /// полные названия остаются доступны VoiceOver.
    private var statusLine: some View {
        HStack(spacing: TFSpacing.lg) {
            statusMetric("tray.full", value: status.total, color: .tfText, label: "Всего задач")
            statusMetric("checkmark.circle.fill", value: status.completed, color: .tfGreen, label: "Выполнено")
            statusMetric("eye.fill", value: status.review, color: .tfBlue, label: "На ревью")
            statusMetric("exclamationmark.triangle.fill", value: status.blocked, color: .tfOrange, label: "Заблокировано")
            statusMetric("play.circle.fill", value: status.inWork, color: .tfDim, label: "В работе")
            Spacer(minLength: 0)
        }
    }

    private func statusMetric(_ icon: String, value: Int, color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .accessibilityHidden(true)
            Text("\(value)")
                .monospacedDigit()
        }
        .tfText(.caption)
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
    }

    /// Вторичная строка: просрочка, документы, последнее движение. Пункты
    /// без содержания не печатаются — нули здесь только создают шум.
    private var metrics: some View {
        HStack(spacing: TFSpacing.xs) {
            if overdue > 0 {
                metric("\(overdue) просрочено", color: .tfRed)
            }
            if docs > 0 {
                if overdue > 0 { separator }
                metric("\(docs) \(ProjectCard.docWord(docs))", color: .tfSub)
            }
            if let idle = idleText {
                if overdue > 0 || docs > 0 { separator }
                metric(idle, color: .tfDim)
            }
            Spacer(minLength: 0)
        }
    }

    private var hasMetadata: Bool {
        overdue > 0 || docs > 0 || idleText != nil
    }

    // Строка ролей («Разработчик · 5   Дизайнер · 2…») убрана 27.09.2026 по
    // просьбе владельца: ролей в проекте больше, чем влезает в строку, видны
    // две — остальные не узнать, информация бесполезная.

    private var separator: some View {
        Text("·")
            .tfText(.caption)
            .foregroundStyle(Color.tfDim)
    }

    private func metric(_ text: String, color: Color) -> some View {
        Text(text)
            .tfText(.caption)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    /// «5 дн. назад» — по последнему движению задач, а не по дате создания
    /// проекта: карточка отвечает на «сколько он уже висит», и проект,
    /// заведённый год назад, но живой вчера, висящим не считается.
    ///
    /// Пусто у проекта совсем без задач: «никогда» рядом с пустым проектом
    /// выглядит упрёком, хотя сказать там просто нечего.
    private var idleText: String? {
        guard let date = DateFormats.sqliteUTC(project.lastActivityAt) else { return nil }
        return RelativeTime.relative(from: date)
    }

    /// «1 документ / 2 документа / 5 документов» — тот же приём, что
    /// `DirectoryPluralize.taskWord`, только слово другое.
    static func docWord(_ n: Int) -> String {
        let mod100 = n % 100
        if mod100 >= 11 && mod100 <= 14 { return "документов" }
        switch n % 10 {
        case 1: return "документ"
        case 2...4: return "документа"
        default: return "документов"
        }
    }
}

/// Статусы в сервере двухуровневые: `status` отвечает только за active /
/// completed, а `agent_state` уточняет активную задачу. Поэтому «в работе» —
/// активные задачи за вычетом review и blocked; сюда входят и реально
/// запущенные (`in_progress`), и ещё не взятые в работу задачи.
struct ProjectTaskStatusSummary {
    let total: Int
    let completed: Int
    let review: Int
    let blocked: Int
    let inWork: Int

    init(project: ApiProject, tasks: [ApiTask]) {
        let scoped = tasks.filter { $0.projectId == project.id }
        let activeParentIDs = Set(tasks.lazy.filter { $0.status == .active }.compactMap(\.parentId))
        let completedWithOpenWork = scoped.count { task in
            guard task.status == .completed else { return false }
            return task.subtasks.contains { !$0.done } || activeParentIDs.contains(task.id)
        }
        let active = (project.taskCount ?? scoped.count { $0.status == .active }) + completedWithOpenWork
        completed = max(
            0,
            (project.completedCount ?? scoped.count { $0.status == .completed }) - completedWithOpenWork
        )
        review = scoped.count { $0.status == .active && $0.agentState == .review }
        blocked = scoped.count { $0.status == .active && $0.agentState == .blocked }
        inWork = max(0, active - review - blocked)
        total = active + completed
    }
}

#Preview("Карточки проектов") {
    ScrollView {
        VStack(spacing: TFSpacing.sm) {
            ProjectCard(project: ApiProject(
                id: "1", name: "TaskFlow — NewTodoist", color: "#e44332", ownerId: nil,
                createdAt: "2026-06-01 10:00:00", position: 0, pinned: true,
                notesFolderId: 3, taskCount: 5, completedCount: 59, overdueCount: 1,
                lastActivityAt: "2026-09-07 13:47:10", docsCount: 4
            ))
            ProjectCard(project: ApiProject(
                id: "2", name: "Домашний сервер", color: "#4A9FD8", ownerId: nil,
                createdAt: "2026-05-01 10:00:00", position: 1, pinned: false,
                notesFolderId: nil, taskCount: 2, completedCount: 42, overdueCount: 0,
                lastActivityAt: "2026-09-03 09:14:27", docsCount: 0
            ))
            ProjectCard(project: ApiProject(
                id: "3", name: "Пустой проект", color: nil, ownerId: nil,
                createdAt: "2026-09-08 10:00:00", position: 2, pinned: false,
                notesFolderId: nil, taskCount: 0, completedCount: 0, overdueCount: 0,
                lastActivityAt: nil, docsCount: 0
            ))
        }
        .padding(TFSpacing.screenHorizontal)
    }
    .background(Color.tfBackground)
}
