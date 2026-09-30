import Foundation

/// Пользовательское представление без имён эмиттеров и технических команд.
struct ServiceTicketPresentation {
    let title: String
    let okCount: Int
    let errorCount: Int
    let warningCount: Int
    let preview: String

    init(summary: ServiceTicketSummary) {
        switch summary.source {
        case "autonomy-110": title = "Работа серверных механизмов"
        case "runaway-110": title = "Контроль процессов"
        case "kb-add": title = "База знаний"
        default: title = summary.title
        }
        let checks = summary.checks ?? []
        okCount = summary.okCount ?? checks.count { $0.status == "ok" }
        errorCount = summary.errorCount ?? (checks.isEmpty && summary.level == "error" ? 1 : checks.count { $0.status == "error" })
        warningCount = summary.warningCount ?? (checks.isEmpty && summary.level == "warning" ? 1 : checks.count { $0.status == "warning" })
        let problems = checks.filter { $0.status != "ok" }
        if !problems.isEmpty {
            preview = problems.prefix(2).map(\.name).joined(separator: " · ")
                + (problems.count > 2 ? " · ещё \(problems.count - 2)" : "")
        } else if !checks.isEmpty {
            preview = "Все проверки прошли в штатном режиме"
        } else {
            preview = "Состояние сервиса и результаты проверки"
        }
    }
}
