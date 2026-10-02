import SwiftUI

// Строка списка: название → одна строка описания → показатели.
// Приоритет — флаг в нижнем ряду; план — person.2; дочерние — ветвление.
// Решение владельца 01.10.2026. Чекбокса завершения здесь нет.
public struct TFTaskRowModel {
    public var projectName: String?
    public var projectColor: Color?
    public var assigneeInitials: String?
    public var assigneeColor: Color?
    public var assigneeID: String?
    public var title: String
    public var isDone: Bool
    public var description: String?
    public var agentStatus: String?
    public var agentStatusColor: Color?
    public var subtasksDone: Int?
    public var subtasksTotal: Int?
    /// Есть дочерние задачи (владелец 28.09.2026: нужен отдельный ярлык от
    /// подзадач — разные режимы структуры карточки).
    public var childrenCount: Int?
    /// Есть УТВЕРЖДЁННЫЙ collaboration plan — сигналит, что у карточки
    /// (или нескольких) есть особая структура совместной работы.
    public var hasCollaborationPlan: Bool
    public var priority: TaskPriority?
    public var isOverdue: Bool
    public var dueText: String?
    public var labels: [(title: String, color: Color)]

    public init(
        projectName: String? = nil,
        projectColor: Color? = nil,
        assigneeInitials: String? = nil,
        assigneeColor: Color? = nil,
        assigneeID: String? = nil,
        title: String,
        isDone: Bool = false,
        description: String? = nil,
        agentStatus: String? = nil,
        agentStatusColor: Color? = nil,
        subtasksDone: Int? = nil,
        subtasksTotal: Int? = nil,
        childrenCount: Int? = nil,
        hasCollaborationPlan: Bool = false,
        priority: TaskPriority? = nil,
        isOverdue: Bool = false,
        dueText: String? = nil,
        labels: [(title: String, color: Color)] = []
    ) {
        self.projectName = projectName
        self.projectColor = projectColor
        self.assigneeInitials = assigneeInitials
        self.assigneeColor = assigneeColor
        self.assigneeID = assigneeID
        self.title = title
        self.isDone = isDone
        self.description = description
        self.agentStatus = agentStatus
        self.agentStatusColor = agentStatusColor
        self.subtasksDone = subtasksDone
        self.subtasksTotal = subtasksTotal
        self.childrenCount = childrenCount
        self.hasCollaborationPlan = hasCollaborationPlan
        self.priority = priority
        self.isOverdue = isOverdue
        self.dueText = dueText
        self.labels = labels
    }
}

public struct TFTaskRow: View {
    let model: TFTaskRowModel
    let action: () -> Void

    public init(_ model: TFTaskRowModel, action: @escaping () -> Void) {
        self.model = model
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            TFTaskRowContent(title: model.title, description: model.description, isDone: model.isDone) {
                if let initials = model.assigneeInitials {
                    TFAvatar(size: .taskList, initials: initials, tint: model.assigneeColor ?? Color(hex: TFHexDefault.unassigned), userID: model.assigneeID)
                }
            } metadata: {
                TFTaskStructureIndicators(priority: model.priority, subtasksDone: model.subtasksDone, subtasksTotal: model.subtasksTotal, childrenCount: model.childrenCount ?? 0, hasCollaborationPlan: model.hasCollaborationPlan)
                if model.isOverdue {
                    TFOverduePill()
                } else if let due = model.dueText {
                    TFDuePill(due)
                }
                if let status = model.agentStatus {
                    Text(status).foregroundStyle(model.agentStatusColor ?? Color.tfTeal).layoutPriority(-1)
                }
                if let project = model.projectName {
                    Text("#\(project)").foregroundStyle(model.projectColor ?? .tfSub).layoutPriority(-1)
                }
                ForEach(model.labels, id: \.title) { label in
                    TFLabelPill(label.title, color: label.color).layoutPriority(-1)
                }
            }
        }
        .buttonStyle(TFTapRowStyle())
    }
}

/// Общая геометрия всех списочных строк; действия и свайпы остаются у экранов.
struct TFTaskRowContent<Avatar: View, Metadata: View>: View {
    let title: String
    let description: String?
    let isDone: Bool
    let horizontalPadding: CGFloat
    let avatar: Avatar
    let metadata: Metadata

    init(title: String, description: String?, isDone: Bool, horizontalPadding: CGFloat = TFSpacing.lg, @ViewBuilder avatar: () -> Avatar, @ViewBuilder metadata: () -> Metadata) {
        self.title = title
        self.description = description
        self.isDone = isDone
        self.horizontalPadding = horizontalPadding
        self.avatar = avatar()
        self.metadata = metadata()
    }

    var body: some View {
        HStack(alignment: .center, spacing: TFSpacing.md) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .tfText(.body)
                    .foregroundStyle(isDone ? Color.tfSub : Color.tfText)
                    .strikethrough(isDone)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let description, !description.isEmpty {
                    Text(description.components(separatedBy: .newlines).joined(separator: " "))
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                }
                HStack(spacing: TFSpacing.xs) {
                    metadata
                }
                .tfText(.caption)
                .foregroundStyle(Color.tfSub)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 8)
        .padding(.bottom, 9)
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Три типа структуры — в отдельных однотонных прямоугольных плашках.
struct TFTaskStructureIndicators: View {
    let priority: TaskPriority?
    let subtasksDone: Int?
    let subtasksTotal: Int?
    let childrenCount: Int
    let hasCollaborationPlan: Bool

    var body: some View {
        Group {
            if let priority {
                Image(systemName: "flag.fill")
                    .foregroundStyle(priority.color)
                    .accessibilityLabel("Приоритет: \(priority.label)")
            }
            if let done = subtasksDone, let total = subtasksTotal {
                badge {
                    HStack(spacing: 3) {
                        Image(systemName: "checklist")
                        Text("\(done)/\(total)")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Подзадачи: \(done) из \(total)")
            }
            if hasCollaborationPlan {
                badge {
                    Image(systemName: "person.2")
                }
                .accessibilityLabel("План совместной работы")
            }
            if childrenCount > 0 {
                badge {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                        Text("\(childrenCount)")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Дочерние задачи: \(childrenCount)")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }

    private func badge<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, TFSpacing.sm)
            .padding(.vertical, 2)
            .background(Color.tfCard)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
    }
}

#Preview("Строка задачи") {
    VStack(spacing: 0) {
        TFTaskRow(TFTaskRowModel(
            projectName: "AI Control Center",
            projectColor: .tfPink,
            assigneeInitials: "МК",
            title: "Собрать дизайн-систему",
            description: "Токены, компоненты, таббар и меню создания — первая волна нативной сборки.",
            subtasksDone: 2,
            subtasksTotal: 5,
            priority: .urgent,
            isOverdue: true,
            labels: [("UX/UI", .tfPurple)]
        )) {}
        TFDivider(inset: TFSpacing.lg, dimmed: true) // stroke/50 — спека §4 «Строка задачи»
        TFTaskRow(TFTaskRowModel(
            title: "Готовая задача",
            isDone: true,
            dueText: "Завтра · 2 дн."
        )) {}
    }
    .background(Color.tfBackground)
}
