import SwiftUI

// LOCK-183: строка «Команды» — плоская, как сотрудник в списке, а не
// тяжёлая карточка с конфигурацией. Всё техническое (Pi, provider, OAuth,
// credentials, размер контекста) в списке не показывается вовсе; конфиг
// живёт на отдельном экране профиля (`AgentProfileScreen`).

/// Цвет роли — визуальная метка. Неизвестные роли получают приглушённый.
func roleAccentColor(_ role: String) -> Color {
    switch role {
    case "owner": .tfRed
    case "architect": .tfPurple
    case "orchestrator", "builder": .tfBlue
    case "qa": .tfGreen
    case "researcher", "analyst": .tfTeal
    case "designer": .tfCoral
    default: .tfDim
    }
}

/// Человеческая подпись роли. Сервер её не отдаёт — это клиентская
/// презентационная карта (осознанное расхождение, см. docs/AGENTPROFILE-MIGRATION.md).
func roleSubtitle(_ role: String) -> String {
    switch role {
    case "architect": "Архитектура и системный дизайн"
    case "builder": "Разработка"
    case "qa": "Проверка качества"
    case "researcher": "Исследование"
    case "analyst": "Аналитика"
    case "critic_verifier": "Критика и проверка"
    case "designer": "Дизайн интерфейсов"
    default: role
    }
}

/// Подпись статуса роли для интерфейса. «Готова» с сервера здесь читается
/// как «Свободен»: экран про сотрудника, а не про служебный статус.
func roleStatusLabel(_ status: RoleRuntimeStatus) -> String {
    switch status {
    case .ready: "Свободен"
    case .working: "Работает"
    case .blocked: "Заблокирован"
    case .unavailable: "Недоступен"
    case .unknown: "—"
    }
}

func roleStatusColor(_ status: RoleRuntimeStatus) -> Color {
    switch status {
    case .ready: .tfGreen
    case .working: .tfTeal
    case .blocked: .tfOrange
    case .unavailable: .tfDim
    case .unknown: .tfDim
    }
}

struct RoleAvatarView: View {
    let initials: String
    let tint: Color
    let size: CGFloat
    /// Роль из `RoleProfile.role` — если для неё есть присланный владельцем
    /// аватар в `Resources/Assets.xcassets`, рисуем его. Неизвестные роли
    /// (owner, orchestrator) идут на прежний цветной круг с инициалами —
    /// ассета под них нет, рисовать заглушку из чужих рук неуместно.
    var role: String? = nil

    var body: some View {
        Group {
            if let asset = RoleAvatarAsset.imageName(for: role) {
                Image(asset)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle()
                    .fill(tint)
                    .overlay {
                        Text(initials)
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// «18 мин» — сколько роль держит текущую задачу. Считаем от `agentStartedAt`,
/// иначе молчим: выдуманную длительность показывать нельзя.
func roleWorkedDuration(_ task: ApiTask) -> String? {
    guard let started = DateFormats.sqliteUTC(task.agentStartedAt) else { return nil }
    let minutes = max(0, Int(Date().timeIntervalSince(started) / 60))
    if minutes < 60 { return "\(minutes) мин" }
    let hours = minutes / 60
    if hours < 24 {
        let rest = minutes % 60
        return rest == 0 ? "\(hours) ч" : "\(hours) ч \(rest) мин"
    }
    return "\(hours / 24) д"
}

struct AgentRow: View {
    let profile: RoleProfile
    /// Текущая задача роли из `TaskStore` — для длительности и названия.
    /// `nil` — либо роль свободна, либо задача ещё не подхвачена стором.
    let currentTask: ApiTask?

    var body: some View {
        HStack(alignment: .top, spacing: TFSpacing.md) {
            RoleAvatarView(initials: initials, tint: roleAccentColor(profile.role), size: 36, role: profile.role)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.title)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)

                if let title = currentTask?.title ?? profile.currentTask?.title {
                    Text(title)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                    Text(workLine)
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                } else if let summary = profile.summary, !summary.isEmpty {
                    // «Чем занимается» — серверный (LOCK-205). Ручной
                    // `roleSubtitle(_:)` остался в файле ради прежних мест
                    // (`AgentProfileScreen`), здесь показываем то, что
                    // прислал сервер.
                    Text(summary)
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: TFSpacing.sm)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(roleStatusColor(profile.status))
                        .frame(width: 7, height: 7)
                    Text(roleStatusLabel(profile.status))
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                        .fixedSize()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.tfDim)
            }
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.md)
        .contentShape(Rectangle())
    }

    private var initials: String {
        let parts = profile.title.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private var workLine: String {
        let model = profile.model.flatMap { $0.isEmpty ? nil : $0 } ?? "модель не задана"
        if let task = currentTask, let duration = roleWorkedDuration(task) {
            return "\(model) · \(duration)"
        }
        return model
    }
}
