import SwiftUI
import UIKit

/// One native sheet, with an interactive horizontal transition inside it.
struct TaskFormScreen: View {
    @State private var model: TaskFormViewModel
    @State private var selectedCardID: String?
    @State private var models: [String: TaskFormViewModel] = [:]
    @State private var family: [ApiTask] = []
    @State private var incoming: TaskFormViewModel?
    @State private var pull: CGFloat = 0
    @State private var pullingCardID: String?
    @State private var expandedSectionsByCard: [String: Set<TaskDetailSection>] = [:]
    @State private var expandedSheet = false
    @State private var settling = false
    @State private var requestSwitch: ((String) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let expanding: Bool

    init(taskID: String? = nil, presetDueToday: Bool = false, startDictation: Bool = false) {
        _model = State(initialValue: TaskFormViewModel(taskID: taskID, presetDueToday: presetDueToday, startDictation: startDictation))
        _selectedCardID = State(initialValue: taskID)
        expanding = false
    }

    init(expandingFrom viewModel: TaskFormViewModel) {
        _model = State(initialValue: viewModel)
        _selectedCardID = State(initialValue: nil)
        expanding = true
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.tfBackground.ignoresSafeArea()
                TaskCardContent(model: model, expanding: expanding, family: family,
                    onFamilyLoaded: receiveFamily,
                    onFamilySelected: { finishSelection($0, width: geometry.size.width) },
                    onSwitchAvailable: { requestSwitch = $0 },
                    onSelectionFailed: resetPull,
                    initialExpandedSections: expandedSections(for: model),
                    onExpandedSectionsChanged: { storeExpandedSections($0, for: model) })
                    .id(selectedCardID ?? "new")
                    .blur(radius: reduceMotion ? 0 : 3.2 * pullProgress(width: geometry.size.width))
                    .opacity(reduceMotion ? 1 : 1 - 0.14 * latePullProgress(width: geometry.size.width))
                    .overlay {
                        if pull > 0 {
                            Color.tfCard2
                                .opacity((reduceMotion ? 0.06 : 0.16) * pullProgress(width: geometry.size.width))
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        if pull > 0 || settling {
                            Color.clear.contentShape(Rectangle()).onTapGesture {}.accessibilityHidden(true)
                        }
                    }
                if let incoming, pull > 0 {
                    TaskCardContent(model: incoming, expanding: false, family: [],
                        onFamilyLoaded: { _ in }, onFamilySelected: { _ in },
                        initialExpandedSections: expandedSections(for: incoming),
                        onExpandedSectionsChanged: { storeExpandedSections($0, for: incoming) },
                        preview: true)
                        .background(Color.tfBackground.ignoresSafeArea())
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14))
                        .shadow(color: Color.black.opacity(0.52), radius: 10, x: -7)
                        .shadow(color: Color.black.opacity(0.3), radius: 30, x: -18)
                        .overlay(alignment: .leading) {
                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.18), Color.black.opacity(0.46)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 58)
                            .offset(x: -58)
                            attachedPullHandle(height: geometry.size.height)
                        }
                        .offset(x: reduceMotion ? 0 : geometry.size.width - pull)
                        .opacity(reduceMotion ? min(1, pull / geometry.size.width) : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .clipped()
            .overlay(alignment: .trailing) {
                if expandedSheet && family.count > 1 {
                    TaskFamilyEdgeTabs(members: family, selectedID: selectedCardID,
                        height: geometry.size.height, width: geometry.size.width,
                        pull: $pull, pullingCardID: $pullingCardID, busy: settling,
                        prepare: prepare, select: select, cancel: resetPull)
                }
            }
            .overlay(alignment: .leading) {
                if expandedSheet, family.count > 1,
                   let active = family.first(where: { $0.id == selectedCardID }) {
                    let activeHeight = TaskFamilyEdgeTabs.slotHeight(
                        height: geometry.size.height,
                        count: max(1, family.count - 1)
                    )
                    Color.clear.frame(width: 32, height: activeHeight)
                        .overlay(alignment: .leading) {
                            UnevenRoundedRectangle(bottomTrailingRadius: TaskFamilyEdgeTabs.cornerRadius,
                                topTrailingRadius: TaskFamilyEdgeTabs.cornerRadius)
                                .fill(TaskFamilyEdgeTabs.fillColor)
                                .frame(width: TaskFamilyEdgeTabs.expandedWidth, height: activeHeight)
                                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 5)
                                .offset(x: -18)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Открытая карточка: \(active.title)")
                        .accessibilityIdentifier("task.family.active.\(active.id)")
                }
            }
            .background(TaskSheetExpansionProbe { expanded in
                if expandedSheet != expanded {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { expandedSheet = expanded }
                }
                if !expanded && !settling && pull > 0 { resetPull() }
            })
        }
        .background(Color.tfBackground.ignoresSafeArea())
    }

    private func receiveFamily(_ members: [ApiTask]) {
        family = members
        if let id = model.taskID { models[id] = model }
        for member in members where member.id != model.taskID && models[member.id] == nil {
            let candidate = TaskFormViewModel(taskID: member.id)
            candidate.isLoadingTask = true
            models[member.id] = candidate
            Task { await candidate.loadIfNeeded(); await candidate.loadRoles() }
        }
    }

    private func prepare(_ id: String) {
        guard id != selectedCardID, !settling else { return }
        if let cached = models[id] {
            incoming = cached
            if cached.loadedTask == nil && !cached.isLoadingTask {
                cached.isLoadingTask = true
                Task { await cached.loadIfNeeded(); await cached.loadRoles() }
            }
        }
        else {
            let candidate = TaskFormViewModel(taskID: id)
            candidate.isLoadingTask = true
            models[id] = candidate
            incoming = candidate
            Task { await candidate.loadIfNeeded(); await candidate.loadRoles() }
        }
    }

    private func select(_ id: String) {
        guard !settling, id != selectedCardID, let requestSwitch else { resetPull(); return }
        prepare(id)
        guard let candidate = models[id] else { resetPull(); return }
        settling = true
        Task {
            while candidate.isLoadingTask {
                try? await Task.sleep(for: .milliseconds(30))
                if Task.isCancelled { return }
            }
            guard candidate.loadedTask != nil else {
                model.saveErrorMessage = candidate.loadErrorMessage ?? "Не удалось открыть связанную карточку"
                resetPull()
                return
            }
            requestSwitch(id)
        }
    }

    private func finishSelection(_ id: String, width: CGFloat) {
        guard let candidate = models[id] else { resetPull(); return }
        Task {
            while candidate.isLoadingTask {
                try? await Task.sleep(for: .milliseconds(30))
                if Task.isCancelled { return }
            }
            guard candidate.loadedTask != nil else { resetPull(); return }
            incoming = candidate
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.38, bounce: 0.04), completionCriteria: .logicallyComplete) {
                pull = width
            } completion: {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    model = candidate
                    selectedCardID = id
                    incoming = nil
                    pull = 0
                    pullingCardID = nil
                    settling = false
                }
            }
        }
    }

    private func resetPull() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.3, bounce: 0.08), completionCriteria: .logicallyComplete) {
            pull = 0
            settling = false
        } completion: {
            pullingCardID = nil
        }
    }

    private func pullProgress(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(1, max(0, pull / width))
    }

    private func latePullProgress(width: CGFloat) -> CGFloat {
        max(0, (pullProgress(width: width) - 0.55) / 0.45)
    }

    private func expandedSections(for model: TaskFormViewModel) -> Set<TaskDetailSection> {
        guard let id = model.taskID else { return [] }
        return expandedSectionsByCard[id] ?? []
    }

    private func storeExpandedSections(_ sections: Set<TaskDetailSection>, for model: TaskFormViewModel) {
        guard let id = model.taskID else { return }
        expandedSectionsByCard[id] = sections
    }

    @ViewBuilder
    private func attachedPullHandle(height: CGFloat) -> some View {
        if let pullingCardID {
            let remaining = Array(family.enumerated()).filter { $0.element.id != selectedCardID }
            let slotHeight = TaskFamilyEdgeTabs.slotHeight(height: height, count: remaining.count)
            VStack(spacing: 8) {
                ForEach(remaining, id: \.element.id) { index, member in
                    if member.id == pullingCardID {
                        UnevenRoundedRectangle(topLeadingRadius: TaskFamilyEdgeTabs.cornerRadius,
                            bottomLeadingRadius: TaskFamilyEdgeTabs.cornerRadius)
                            .fill(TaskFamilyEdgeTabs.fillColor)
                            .frame(width: TaskFamilyEdgeTabs.expandedWidth, height: slotHeight)
                            .shadow(color: Color.black.opacity(0.3), radius: 8, x: -5)
                            .overlay {
                                if index == 0 {
                                    Image(systemName: "square.stack")
                                        .font(.caption)
                                        .foregroundStyle(Color.tfSub)
                                } else {
                                    Text("\(index)")
                                        .font(.caption)
                                        .foregroundStyle(Color.tfSub)
                                }
                            }
                    } else {
                        Color.clear.frame(width: TaskFamilyEdgeTabs.expandedWidth, height: slotHeight)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .offset(x: -18)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A transparent edge hit area; only a few points of each bookmark remain visible.
struct TaskFamilyEdgeTabs: View {
    static let restingWidth: CGFloat = 10
    static let expandedWidth: CGFloat = 26
    static let cornerRadius: CGFloat = 10
    static let fillColor = Color.tfCard2.opacity(0.48)

    let members: [ApiTask]
    let selectedID: String?
    private var remaining: [(offset: Int, element: ApiTask)] {
        Array(members.enumerated()).filter { $0.element.id != selectedID }
    }
    let height: CGFloat
    let width: CGFloat
    @Binding var pull: CGFloat
    @Binding var pullingCardID: String?
    let busy: Bool
    let prepare: (String) -> Void
    let select: (String) -> Void
    let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: String?
    @State private var captured: String?
    @State private var suppressTap = false

    static func slotHeight(height: CGFloat, count: Int) -> CGFloat {
        min(116, max(64, height * 0.65 / CGFloat(max(1, count)) - 8))
    }

    private var slotHeight: CGFloat { Self.slotHeight(height: height, count: remaining.count) }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(remaining, id: \.element.id) { index, member in
                Button {
                    guard !suppressTap else { return }
                    prepare(member.id)
                    select(member.id)
                } label: {
                    UnevenRoundedRectangle(topLeadingRadius: Self.cornerRadius,
                        bottomLeadingRadius: Self.cornerRadius)
                        .fill(Self.fillColor)
                        .frame(width: hovered == member.id ? Self.expandedWidth : Self.restingWidth,
                            height: slotHeight)
                        .shadow(color: Color.black.opacity(0.3), radius: 8, x: -5)
                        .overlay {
                            if hovered == member.id {
                                if index == 0 { Image(systemName: "square.stack").font(.caption).foregroundStyle(Color.tfSub) }
                                else { Text("\(index)").font(.caption).foregroundStyle(Color.tfSub) }
                            }
                        }
                        .frame(width: 32, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .opacity(pullingCardID == member.id ? 0 : 1)
                .offset(x: pullingCardID == nil || pullingCardID == member.id ? 0 : min(40, pull * 0.45))
                .buttonStyle(.plain)
                .accessibilityLabel(member.title)
                .accessibilityIdentifier("task.family.\(member.id)")
            }
        }
        .frame(width: 32)
        .contentShape(Rectangle())
        .disabled(busy)
        .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.05), value: hovered)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !busy, !remaining.isEmpty else { return }
                let distance = max(0, -value.translation.width)
                if abs(value.translation.width) + abs(value.translation.height) > 8 { suppressTap = true }
                if captured == nil {
                    let index = min(remaining.count - 1, max(0, Int(value.location.y / (slotHeight + 8))))
                    let id = remaining[index].element.id
                    if hovered != id { hovered = id; prepare(id) }
                    if distance > 18 {
                        captured = id
                        pullingCardID = id
                    }
                }
                if captured != nil { pull = min(width, distance) }
            }
            .onEnded { value in
                defer { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { suppressTap = false } }
                let target = captured
                hovered = nil
                captured = nil
                // A stationary touch belongs to the accessibility/tap button.
                if target == nil && abs(value.translation.width) < 4 && abs(value.translation.height) < 4 { return }
                if let target, pull > width * 0.28 || -value.predictedEndTranslation.width > width * 0.55 {
                    select(target)
                } else { cancel() }
            })
    }
}

/// Reads the actual system-sheet detent, independent of keyboard height.
private struct TaskSheetExpansionProbe: UIViewRepresentable {
    let update: (Bool) -> Void
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) { view.update = update; view.check() }
    final class ProbeView: UIView {
        var update: ((Bool) -> Void)?
        private var lastReported: Bool?
        private func report(_ expanded: Bool) {
            guard lastReported != expanded else { return }
            lastReported = expanded
            DispatchQueue.main.async { [weak self] in self?.update?(expanded) }
        }
        override func layoutSubviews() { super.layoutSubviews(); check() }
        override func didMoveToWindow() { super.didMoveToWindow(); check() }
        func check() {
            guard window != nil else { return }
            var responder: UIResponder? = self
            while let next = responder?.next {
                responder = next
                if let controller = next as? UIViewController {
                    var ancestor: UIViewController? = controller
                    while let current = ancestor {
                        if current.presentingViewController != nil,
                           let sheet = current.presentationController as? UISheetPresentationController,
                           sheet.containerView != nil {
                            let expanded = sheet.selectedDetentIdentifier == .large
                            report(expanded)
                            return
                        }
                        ancestor = current.parent
                    }
                    // A full-screen/pushed card has no partial detent.
                    report(true)
                    return
                }
            }
        }
    }
}

/// Invisible intent target prevents the text view from summoning the keyboard.
struct CardTextEditGate: ViewModifier {
    let enabled: Bool
    let identifier: String
    var text: String = ""
    let arm: () -> Void

    func body(content: Content) -> some View {
        content
            .environment(\.documentTextEditable, enabled)
            .accessibilityHidden(!enabled)
            .overlay {
                if !enabled {
                    Button(action: arm) { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(text.isEmpty ? "Показать редактирование" : text)
                        .accessibilityHint("Показать карандаш для редактирования")
                        .accessibilityIdentifier("task.arm.\(identifier)")
                }
            }
    }
}
