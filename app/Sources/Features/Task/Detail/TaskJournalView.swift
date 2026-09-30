import SwiftUI
import UniformTypeIdentifiers

// `TaskJournal` — spec/SCREENS-2.md §19.2 (тот же случай, что у SubtaskFeed:
// компонент карточки задачи, прямо адресованный этому экрану). Лента
// объединяет комментарии и системные события, новые СВЕРХУ.
//
// Упрощения относительно полной спеки (осознанно, см. отчёт):
// - «живая строка чем занят агент» (тикает раз в 2с) — статичный текст,
//   без опроса `activity.ts` (§5.14, отдельный крупный роут, не читан);
// - `ResumeSessionButton` — не сделан («служебная функциональность, для
//   нативного приложения актуальность уточнить отдельно», сама спека
//   разрешает пропустить);
// - формы владельца (ReturnToWorkSheet) — текстовое поле + отправка, без
//   микрофона/файла (диктовки в этой волне нигде нет, `NATIVE-PARTS.md` §0).
enum TaskJournalEntry: Identifiable {
    case comment(ApiComment)
    case event(ApiTaskEvent)

    var id: String {
        switch self {
        case .comment(let c): "c-\(c.id)"
        case .event(let e): "e-\(e.id)"
        }
    }

    var date: Date? {
        switch self {
        case .comment(let c): c.createdAtDate
        case .event(let e): e.createdAtDate
        }
    }

    /// Сортировка «новые сверху» — spec §19.2.
    static func merged(comments: [ApiComment], events: [ApiTaskEvent]) -> [TaskJournalEntry] {
        (comments.map(TaskJournalEntry.comment) + events.map(TaskJournalEntry.event))
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

enum AgentOwnerActionKind {
    case acceptReview
    case returnToWorkFromReview
    case replyAndReturnFromBlocked
    case acceptAndClose
    case returnToWorkFromInProgress

    /// spec §7 `commentRequiredFor()` — переходы В blocked/review и
    /// review→in_progress требуют комментарий. Здесь релевантны два случая.
    var commentRequired: Bool {
        switch self {
        case .returnToWorkFromReview, .replyAndReturnFromBlocked: true
        default: false
        }
    }
}

// 11.09.2026: сам экран-лента отсюда удалён (LOCK-120). Он рисовался только
// в `TaskDetailScreen`, а тот был двухстрочной заглушкой — код не
// исполнялся, и починка ленты, внесённая в него, ничего не меняла в
// приложении. Рабочая лента живёт в `TaskFormScreen.nativeJournalRow`.
// Здесь осталось то, что этой рабочей лентой и используется: разбор записей
// (`TaskJournalEntry`), виды владельческих действий и словарь формулировок
// событий.
enum TaskJournalView {
    /// Человеческие подписи событий ленты.
    ///
    /// 14.09.2026: словарь был составлен под названия событий из
    /// спецификации, а сервер шлёт другие — «created» против «task_created»,
    /// «subtask_completed» против «subtask_done» и так далее. Совпадала
    /// горстка, всё остальное падало в запасной вариант и выводилось
    /// сырьём: владелец видел в ленте «subtask_done», «task_created»,
    /// «state_changed» — технические строки в русскоязычном приложении.
    ///
    /// Названия ниже сверены с тем, что реально лежит в базе событий, а
    /// формулировки — с лентой в вебе, чтобы одно действие называлось
    /// одинаково в обоих местах. Запасной вариант больше не показывает
    /// `kind`: неизвестное событие подписывается по-русски.
    static func eventText(_ event: ApiTaskEvent) -> String {
        let value = event.toValue ?? ""
        let previous = event.fromValue ?? ""

        switch event.kind {
        // Жизненный цикл задачи
        case "task_created": return "создал задачу"
        case "claimed": return "взял задачу в работу"
        case "unclaimed": return "снял задачу с исполнителя"
        case "lease_expired": return "задача снята: исполнитель замолчал"
        case "task_dispatched":
            return value.isEmpty ? "отдал задачу в работу" : "отдал задачу в работу: \(value)"
        case "role_choice":
            return value.isEmpty ? "выбрал исполнителя" : value
        case "ready_flag_changed":
            return value == "1" ? "отметил задачу готовой к работе" : "снял отметку готовности"
        case "state_changed":
            switch value {
            case "in_progress": return "взялся за задачу"
            case "review": return "сдал задачу на проверку"
            case "blocked": return "заблокировал задачу — нужно ваше решение"
            case "completed": return "принял задачу"
            case "active": return "вернул задачу в работу"
            default: return "изменил состояние задачи"
            }
        case "review_recorded": return "записал итог проверки"
        // Отправка на проверку и ручные запуски (22.09.2026): раньше они не
        // оставляли в ленте следа вовсе.
        case "reviewer_sent":
            return value.isEmpty ? "отправлено на проверку" : "отправлено на проверку: \(value)"
        case "run_requested":
            if event.field == "reviewer" {
                return value.isEmpty ? "отправил на проверку" : "отправил на проверку: \(value)"
            }
            return value.isEmpty ? "запустил исполнителя" : "запустил исполнителя: \(value)"
        case "result_version_created": return "приложил результат на проверку"

        // Поля карточки
        case "field_changed":
            return fieldChangeText(field: event.field, previous: previous, value: value)
        case "description_changed": return "изменил описание"
        case "labels_changed": return "изменил метки"

        // Шаги
        case "subtasks_seeded":
            return value.isEmpty ? "добавил шаги" : "добавил шаги: \(value)"
        case "subtask_added": return "добавил шаг: \(value)"
        case "subtask_started": return "взялся за шаг: \(value)"
        case "subtask_done": return "выполнил шаг: \(value)"
        case "subtask_undone": return "снял отметку с шага: \(value)"
        case "subtask_renamed": return "переименовал шаг: \(previous) → \(value)"
        case "subtask_removed": return "удалил шаг: \(previous)"
        case "subtask_review": return "сдал шаг на проверку: \(value)"
        case "subtask_returned": return "вернул шаг на доработку: \(value)"
        case "subtask_blocked": return "застрял на шаге: \(value)"
        case "subtask_released": return "отпустил шаг: \(value)"

        default: return "обновил задачу"
        }
    }

    /// Правка одного поля карточки. Имена полей технические и на экран
    /// попадать не должны — каждому нужна своя человеческая формулировка.
    private static func fieldChangeText(field: String?, previous: String, value: String) -> String {
        switch field {
        case "assignee_id": return value.isEmpty ? "снял исполнителя" : "сменил исполнителя"
        case "owner_selected_role": return value.isEmpty ? "убрал выбор исполнителя" : value
        case "priority": return "сменил приоритет"
        case "due_date": return value.isEmpty ? "убрал срок" : "поставил срок: \(value)"
        case "start_time": return value.isEmpty ? "убрал время начала" : "поставил время: \(value)"
        case "duration_min": return "изменил длительность"
        case "project_id": return value.isEmpty ? "убрал задачу из проекта" : "перенёс задачу в другой проект"
        case "title": return "переименовал задачу"
        case "status": return value == "completed" ? "закрыл задачу" : "вернул задачу в работу"
        case "parent_id": return value.isEmpty ? "открепил задачу от родителя" : "прикрепил задачу к родителю"
        default: return "изменил карточку"
        }
    }
}

extension AgentOwnerActionKind: Identifiable {
    var id: Self { self }
}
