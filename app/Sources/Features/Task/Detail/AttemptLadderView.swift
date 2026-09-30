import SwiftUI

/// Индикатор текущей ступени модели из `attempt_ladder` серверного ответа.
/// Чистый SwiftUI без рамок, фонов и материалов: состояние передаётся цветом.
public struct AttemptLadderView: View {
    let ladder: ApiAttemptLadder
    let agentState: AgentState?

    public init(ladder: ApiAttemptLadder, agentState: AgentState? = nil) {
        self.ladder = ladder
        self.agentState = agentState
    }

    private var escalated: Bool {
        ladder.currentStep > 1 || agentState == .blocked
    }

    private var modelLabel: String {
        guard let model = ladder.currentModel, !model.isEmpty else {
            return "модель не указана"
        }
        return model.prefix(1).uppercased() + model.dropFirst()
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text("\(ladder.currentStep)/\(ladder.totalSteps)")
            Image(systemName: "arrow.right")
                .accessibilityHidden(true)
            Text(modelLabel)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(escalated ? Color.tfOrange : Color.tfSub)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = ["Попытка \(ladder.currentStep) из \(ladder.totalSteps)", modelLabel]
        if escalated { parts.append("эскалация") }
        return parts.joined(separator: ", ")
    }
}
