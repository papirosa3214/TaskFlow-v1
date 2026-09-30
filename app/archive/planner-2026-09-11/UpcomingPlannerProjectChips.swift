import SwiftUI

// Раньше здесь была самодельная шторка фильтров (spec/SCREENS-1.md §3.9
// `TaskFilterSheet`/`TaskFilterButton`, `UpcomingFilterSheetContent`) —
// заменена нативным `Menu` в `UpcomingScreen.filterMenu` (просьба владельца
// 03.09.2026: «Планирование» должно быть стеклянным, как «Сегодня», а не
// карточкой на весь экран, см. LOCK-049/050 в AGENT-WORK-SCOPES.md).
//
// `UpcomingPlannerProjectChips` ниже больше не рендерится — тот же приём,
// что у `Today/PlannerProjectChips.swift` (компонент оставлен на случай
// возврата, но выбор проектов теперь только в подменю «Показывать в разделе»
// внутри `filterMenu`: у `Menu` нет способа открыть себя программно на
// нужном пункте, ради которого раньше существовала кнопка «+» здесь).

/// Полоска чипов проектов под шапкой — spec §3.10 `PlannerProjectChips`.
struct UpcomingPlannerProjectChips: View {
    let projects: [ApiProject]
    let visibleProjectIds: Set<String>
    let onAdd: () -> Void

    var body: some View {
        let visible = projects.filter { visibleProjectIds.contains($0.id) }
        // Полоска целиком (включая неснимаемый чип «Входящие») показана, только
        // если список видимых проектов не пуст — спека §3.10.
        if !visible.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TFSpacing.sm) {
                    Text("Входящие")
                        .tfText(.meta)
                        .foregroundStyle(Color.tfText)
                        .padding(.horizontal, TFSpacing.md).padding(.vertical, TFSpacing.xs)
                        .background(Color.tfCard2)
                        .overlay(Capsule().strokeBorder(Color.tfStroke, lineWidth: TFBorder.width))
                        .clipShape(Capsule())

                    ForEach(visible) { p in
                        Text(p.name)
                            .tfText(.meta)
                            .foregroundStyle(Color(hex: p.color ?? TFHexDefault.unassigned))
                            .lineLimit(1)
                            .padding(.horizontal, TFSpacing.md).padding(.vertical, TFSpacing.xs)
                            .background(Color(hex: p.color ?? TFHexDefault.unassigned).opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Button(action: onAdd) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 12))
                            Text("проект")
                        }
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                        .padding(.horizontal, TFSpacing.md).padding(.vertical, TFSpacing.xs)
                        .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: TFBorder.width, dash: [4])).foregroundStyle(Color.tfStroke))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, TFSpacing.screenHorizontal).padding(.vertical, TFSpacing.sm)
            }
            .background(Color.tfBackground)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.tfStroke).frame(height: TFBorder.width) }
        }
    }
}
