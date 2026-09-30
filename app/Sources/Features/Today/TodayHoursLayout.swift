import Foundation
import SwiftUI

// Геометрия и раскладка сетки «часы» — порт `DayHours.tsx` (spec §3.5).
// Числа — замер, не круглые величины (см. комментарий в живом коде):
enum TodayHoursMetrics {
    static let hourH: CGFloat = 124 / 3          // высота часа
    static let gutterW: CGFloat = 161 / 3        // левая колонка с подписями
    static let snapMin: Int = 15                 // шаг привязки перетаскивания
    static let minH: CGFloat = 24                // минимальная высота плашки
    static let rightInset: CGFloat = 6
    static let colGap: CGFloat = 3
    /// Видимый диапазон суток — владелец 07.09.2026: «в 6 утра всё равно
    /// никто не встаёт, в час ночи никто не встаёт», убрать портянку из
    /// пустых ночных часов. Раньше сетка шла 0...24 плюс 5 декоративных
    /// строк-хвоста; теперь только реальные рабочие часы 6:00...22:00.
    static let startHour = 6
    static let endHour = 22
    static let hoursCount = endHour - startHour
    /// Задержка удержания перед стартом перетаскивания — владелец 07.09.2026:
    /// голое касание не должно сразу утаскивать плашку.
    static let dragHoldSeconds: Double = 0.25
}

/// «14:30» → 14.5.
func hoursFromTime(_ raw: String?) -> Double? {
    guard let (h, m) = DateFormats.localTimeComponents(raw) else { return nil }
    return Double(h) + Double(m) / 60
}

/// Смещение от верха сетки (0 = `startHour`) → «ЧЧ:ММ», округлённое до
/// SNAP_MIN, зажатое видимым диапазоном `startHour...endHour`.
func timeFromOffset(_ y: CGFloat) -> String {
    let raw = (y / TodayHoursMetrics.hourH) * 60
    let snap = CGFloat(TodayHoursMetrics.snapMin)
    let snapped = (raw / snap).rounded() * snap
    let startMin = CGFloat(TodayHoursMetrics.startHour * 60)
    let endMin = CGFloat(TodayHoursMetrics.endHour * 60)
    let clamped = min(max(snapped + startMin, startMin), endMin - snap)
    let h = Int(clamped) / 60
    let m = Int(clamped) % 60
    return String(format: "%02d:%02d", h, m)
}

func hourLabel(_ h: Int) -> String { String(format: "%02d:00", h) }

struct TodayPlacedBlock: Identifiable {
    var id: String { task.id }
    let task: ApiTask
    let top: CGFloat
    let height: CGFloat
    let colIndex: Int
    let columns: Int
    let durKnown: Bool
}

/// Раскладывает задачи одного дня по вертикали и, при коллизиях по
/// времени, по колонкам side-by-side (кластеры пересекающихся задач,
/// внутри — жадная раскладка). Порт `layoutDay()` (DayHours.tsx).
func layoutHoursDay(_ tasks: [ApiTask]) -> [TodayPlacedBlock] {
    struct Item { let task: ApiTask; let start: Double; let end: Double; let durKnown: Bool }
    let items = tasks
        .compactMap { t -> Item? in
            guard let start = hoursFromTime(t.startTime) else { return nil }
            let durKnown = t.durationMin != nil
            let dur = t.durationMin ?? 30
            return Item(task: t, start: start, end: start + Double(dur) / 60, durKnown: durKnown)
        }
        .sorted { $0.start != $1.start ? $0.start < $1.start : $0.end < $1.end }

    var placed: [TodayPlacedBlock] = []
    var cluster: [Item] = []
    var clusterEnd = -Double.infinity

    func flush() {
        guard !cluster.isEmpty else { return }
        var colEnds: [Double] = []
        var colOf: [Int] = []
        for item in cluster {
            if let existing = colEnds.firstIndex(where: { $0 <= item.start }) {
                colEnds[existing] = item.end
                colOf.append(existing)
            } else {
                colOf.append(colEnds.count)
                colEnds.append(item.end)
            }
        }
        let cols = colEnds.count
        let startHour = Double(TodayHoursMetrics.startHour)
        for (i, item) in cluster.enumerated() {
            // Задачи ДО `startHour` (глубокая ночь) прижимаются к верху
            // сетки вместо ухода в отрицательные координаты — сама задача
            // никуда не девается, просто видимый диапазон начинается не с
            // полуночи (владелец 07.09.2026).
            let hoursFromTop: Double = item.start - startHour
            let top: CGFloat = max(0, CGFloat(hoursFromTop) * TodayHoursMetrics.hourH + 1)
            let durHours: Double = item.end - item.start
            let height: CGFloat = max(TodayHoursMetrics.minH, CGFloat(durHours) * TodayHoursMetrics.hourH - 3)
            placed.append(TodayPlacedBlock(
                task: item.task,
                top: top,
                height: height,
                colIndex: colOf[i],
                columns: cols,
                durKnown: item.durKnown
            ))
        }
        cluster = []
    }

    for item in items {
        if !cluster.isEmpty && item.start >= clusterEnd {
            flush()
            clusterEnd = -Double.infinity
        }
        cluster.append(item)
        clusterEnd = max(clusterEnd, item.end)
    }
    flush()
    return placed
}

/// Текст на цветной плашке — тёмный (WCAG-аудит 19.08.2026, spec §3.5/живой код).
let todayChipInk = Color.tfHourChipInk
