import SwiftUI
import UIKit

// Свайп строки — spec/SCREENS-2.md §0.6 (`useRowSwipe`), числа сверены живьём
// с `src/lib/useRowSwipe.ts`: ширина панели действия 88pt, направление
// фиксируется после 8px смещения и только если горизонталь весомее
// вертикали в 1.3 раза (иначе это прокрутка списка), строка остаётся
// открытой при смещении >36px ИЛИ броске быстрее 280px/с — симметрично в
// обе стороны (в отличие от строки задачи §3.3, где открытие/закрытие имеют
// РАЗНЫЕ пороги — тот случай уже занят `TodayTaskRow.swift`, чужой файл).
//
// Используется строкой проекта (`ProjectsScreen`) — свайп влево «Изменить»
// (`#007AFF`), вправо «Удалить» (`#FF3B30`).
struct DirectorySwipeRow<Content: View>: View {
    let onEdit: () -> Void
    let onDelete: () -> Void
    /// Скругление строки и панели действий под ней. По умолчанию `lg` — как у
    /// строки-ряда (метки); «Проекты» с 08.09.2026 показывают карточку
    /// (`ProjectCard`, радиус `xl`), и клип обязан совпадать с ней, иначе
    /// углы карточки срезаются меньшим радиусом.
    var cornerRadius: CGFloat = TFRadius.lg
    @ViewBuilder let content: () -> Content

    // Ширина была 88pt против 84pt в списках задач — свайп справочников
    // раскрывался чуть шире соседних экранов. Числа сведены в `TFRowSwipe`.
    private let actionWidth: CGFloat = TFRowActionWidth
    private let openPx = TFRowSwipe.openThreshold
    private let openVelocity = TFRowSwipe.openVelocity
    /// Своё имя в общем реестре раскрытых строк (`TFSwipeRowRegistry`).
    @State private var rowID = UUID()

    @State private var settledOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0

    private var offsetX: CGFloat { clamp(settledOffset + dragOffset) }

    /// Ширина открытой панели действия с заходом ПОД карточку.
    ///
    /// 16.09.2026, владелец: «карточки с закруглениями, а свайп ровные
    /// 90 угловые, захватывает фон». Карточка скруглена со всех сторон, панель
    /// обрезается по внешней границе строки — и на стыке, под скруглением
    /// карточки, открывался тёмный серп фона.
    ///
    /// Панель делается шире ровно на радиус и, поскольку прижата к своему краю
    /// строки, этим излишком заезжает под карточку. Под скруглением оказывается
    /// её цвет, стык становится сплошным. Снаружи обрезка по
    /// `RoundedRectangle(cornerRadius:)` сохраняется, поэтому внешние углы
    /// остаются скруглёнными как у карточки.
    ///
    /// Закрытая панель имеет нулевую ширину: излишек добавляется только когда
    /// она реально раскрывается, иначе полоска цвета торчала бы в покое.
    private func panelWidth(forOpening isOpening: Bool, shift: CGFloat) -> CGFloat {
        guard isOpening, shift > 0 else { return 0 }
        return shift + cornerRadius
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Button(action: { close(); onDelete() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.white)
                }
                .frame(width: panelWidth(forOpening: offsetX > 0, shift: offsetX))
                .frame(maxHeight: .infinity)
                .background(Color.tfSwipeDelete)
                .opacity(offsetX > 0 ? 1 : 0)
                Spacer(minLength: 0)
                Button(action: { close(); onEdit() }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.white)
                }
                .frame(width: panelWidth(forOpening: offsetX < 0, shift: -offsetX))
                .frame(maxHeight: .infinity)
                .background(Color.tfSwipeEdit)
                .opacity(offsetX < 0 ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            content()
                .offset(x: offsetX)
                .gesture(
                    HorizontalPan(
                        onBegin: { UIImpactFeedbackGenerator(style: .soft).impactOccurred() },
                        onChange: { dx in dragOffset = dx },
                        onEnd: { dx, velocity in settle(dx: dx, velocity: velocity) }
                    )
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        // Раскрыта всегда одна строка: как только реестр называет другую
        // (или прокрутка гасит всё), эта закрывается сама.
        .onChange(of: TFSwipeRowRegistry.shared.openRowID) { _, openID in
            if openID != rowID, settledOffset != 0 { close() }
        }
    }

    private func close() {
        withAnimation(TFRowSwipe.settleAnimation()) {
            settledOffset = 0
            dragOffset = 0
        }
        TFSwipeRowRegistry.shared.didClose(rowID)
    }

    private func settle(dx: CGFloat, velocity: CGFloat) {
        let finalOffset = clamp(settledOffset + dx)
        // 16.09.2026: `velocity` здесь нужен только для условия открыть/закрыть
        // ниже. Анимация доведения от скорости пальца НЕ зависит — пружина
        // фиксированная, см. шапку `TFRowSwipe.settleAnimation` в
        // `HorizontalPan.swift`. Как в нативных Mail/Notes: свайпнул — плашка
        // доезжает со своей скоростью, рука быстрая или медленная — без разницы.
        withAnimation(TFRowSwipe.settleAnimation()) {
            if settledOffset == 0 {
                if finalOffset < -openPx || velocity < -openVelocity {
                    settledOffset = -actionWidth
                } else if finalOffset > openPx || velocity > openVelocity {
                    settledOffset = actionWidth
                } else {
                    settledOffset = 0
                }
            } else if settledOffset < 0 {
                settledOffset = (dx > openPx || velocity > openVelocity) ? 0 : -actionWidth
            } else {
                settledOffset = (dx < -openPx || velocity < -openVelocity) ? 0 : actionWidth
            }
            dragOffset = 0
        }
        if settledOffset == 0 {
            TFSwipeRowRegistry.shared.didClose(rowID)
        } else {
            TFSwipeRowRegistry.shared.didOpen(rowID)
        }
    }

    private func clamp(_ raw: CGFloat) -> CGFloat {
        if raw > actionWidth {
            let over = raw - actionWidth
            return actionWidth + (over * 30) / (30 + over)
        } else if raw < -actionWidth {
            let over = -raw - actionWidth
            return -actionWidth - (over * 30) / (30 + over)
        }
        return raw
    }
}
