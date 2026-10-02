import Charts
import SwiftUI

/// Нативный виджет в ответе роли — блок ```widget с JSON (владелец
/// 01.10.2026: «на вопрос какая погода агент скидывает виджет в чат»).
/// Формат задаёт промпт чата (`chat.wrapper` на сервере); данные погоды
/// роль берёт готовыми из `taskflow_weather`.
///
/// Разбор нестрогий: число может прийти строкой и наоборот, незнакомое поле
/// пропускается. Непонятный тип или битый JSON — не пустое место, а карточка
/// с исходным текстом.
struct ChatWidgetView: View {
    let json: String

    var body: some View {
        if let data = WidgetData.parse(json) {
            switch data.string("type") ?? "" {
            case "weather": WeatherWidget(data: data)
            case "metrics": MetricsWidget(data: data)
            case "progress": ProgressWidget(data: data)
            case "checklist": ChecklistWidget(data: data)
            case "card": CardWidget(data: data)
            case "chart": ChartWidget(data: data)
            default: UnknownWidget(raw: json)
            }
        } else {
            UnknownWidget(raw: json)
        }
    }
}

// MARK: - Данные

/// Обёртка над JSON-объектом с мягкими геттерами.
struct WidgetData {
    let raw: [String: Any]

    static func parse(_ json: String) -> WidgetData? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return WidgetData(raw: object)
    }

    func string(_ key: String) -> String? {
        switch raw[key] {
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case let n as NSNumber:
            return Self.format(n.doubleValue)
        default:
            return nil
        }
    }

    func number(_ key: String) -> Double? {
        switch raw[key] {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.-").inverted))
        default: return nil
        }
    }

    func bool(_ key: String) -> Bool? {
        switch raw[key] {
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["true", "да", "1", "yes"].contains(s.lowercased())
        default: return nil
        }
    }

    func array(_ key: String) -> [WidgetData] {
        (raw[key] as? [[String: Any]] ?? []).map(WidgetData.init)
    }

    func object(_ key: String) -> WidgetData? {
        (raw[key] as? [String: Any]).map(WidgetData.init)
    }

    static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

// MARK: - Общая подложка

private struct WidgetCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            if let title {
                Text(title).font(.headline).foregroundStyle(Color.tfText)
            }
            content
        }
        .padding(TFSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: TFRadius.xl).strokeBorder(Color.tfStroke, lineWidth: TFBorder.width))
    }
}

// MARK: - Погода

private struct WeatherWidget: View {
    let data: WidgetData

    private var isDay: Bool { data.bool("is_day") ?? true }
    private var icon: String { data.string("icon") ?? "cloudy" }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.string("location") ?? "Погода")
                        .font(.headline)
                    Text(temperature(data.number("temperature")))
                        .font(.system(size: 56, weight: .thin))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: TFSpacing.xs) {
                    Image(systemName: WeatherSymbol.name(icon, isDay: isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 40))
                    if let condition = data.string("condition") {
                        Text(condition).font(.subheadline.weight(.medium))
                    }
                    if let high = data.number("high"), let low = data.number("low") {
                        Text("Макс. \(temperature(high)) · мин. \(temperature(low))")
                            .font(.caption)
                    }
                }
            }
            details
            let forecast = data.array("forecast")
            if !forecast.isEmpty {
                Divider().overlay(.white.opacity(0.35))
                HStack {
                    ForEach(Array(forecast.prefix(5).enumerated()), id: \.offset) { _, day in
                        VStack(spacing: TFSpacing.xs) {
                            Text(day.string("day") ?? "").font(.caption.weight(.semibold))
                            Image(systemName: WeatherSymbol.name(day.string("icon") ?? "cloudy", isDay: true))
                                .symbolRenderingMode(.multicolor)
                                .font(.title3)
                                .frame(height: 26)
                            Text(temperature(day.number("high"))).font(.caption.weight(.semibold))
                            Text(temperature(day.number("low"))).font(.caption).opacity(0.75)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(TFSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: WeatherSymbol.gradient(icon, isDay: isDay),
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: TFRadius.sheet)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var details: some View {
        let items: [(String, String)] = [
            data.number("feels_like").map { ("thermometer.medium", "Ощущается \(temperature($0))") },
            data.number("humidity").map { ("humidity", "\(WidgetData.format($0))%") },
            data.string("wind").map { ("wind", $0) },
        ].compactMap { $0 }
        if !items.isEmpty {
            HStack(spacing: TFSpacing.lg) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Label(item.1, systemImage: item.0).font(.caption)
                }
            }
            .opacity(0.9)
        }
    }

    private func temperature(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))°"
    }
}

enum WeatherSymbol {
    static func name(_ icon: String, isDay: Bool) -> String {
        switch icon.lowercased() {
        case "clear", "sunny": return isDay ? "sun.max.fill" : "moon.stars.fill"
        case "partly_cloudy", "partly": return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case "fog": return "cloud.fog.fill"
        case "drizzle": return "cloud.drizzle.fill"
        case "rain": return "cloud.rain.fill"
        case "snow": return "cloud.snow.fill"
        case "storm", "thunder": return "cloud.bolt.rain.fill"
        case "wind": return "wind"
        default: return "cloud.fill"
        }
    }

    static func gradient(_ icon: String, isDay: Bool) -> [Color] {
        if !isDay { return [Color(hex: "#1B2735"), Color(hex: "#3A4B6B")] }
        switch icon.lowercased() {
        case "clear", "sunny": return [Color(hex: "#3D8BD9"), Color(hex: "#7EC2F0")]
        case "partly_cloudy", "partly": return [Color(hex: "#4E86B8"), Color(hex: "#93B8D6")]
        case "rain", "drizzle", "storm": return [Color(hex: "#3F5163"), Color(hex: "#6F8194")]
        case "snow": return [Color(hex: "#7F9AB6"), Color(hex: "#B9C9DA")]
        case "fog": return [Color(hex: "#737D87"), Color(hex: "#A3ACB4")]
        default: return [Color(hex: "#5E6E7E"), Color(hex: "#8E9BA8")]
        }
    }
}

// MARK: - Метрики

private struct MetricsWidget: View {
    let data: WidgetData

    var body: some View {
        WidgetCard(title: data.string("title")) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: TFSpacing.md),
                                GridItem(.flexible(), spacing: TFSpacing.md)],
                      alignment: .leading, spacing: TFSpacing.md) {
                ForEach(Array(data.array("items").enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        Text(item.string("label") ?? "")
                            .font(.caption)
                            .foregroundStyle(Color.tfSub)
                        Text(item.string("value") ?? "—")
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.tfText)
                        if let delta = item.string("delta") {
                            let trend = item.string("trend") ?? ""
                            Label(delta, systemImage: trend == "up" ? "arrow.up.right"
                                  : trend == "down" ? "arrow.down.right" : "arrow.right")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(trend == "up" ? Color.tfGreen
                                                 : trend == "down" ? Color.tfRed : Color.tfSub)
                        }
                    }
                    .padding(TFSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.tfCard2, in: RoundedRectangle(cornerRadius: TFRadius.lg))
                }
            }
        }
    }
}

// MARK: - Прогресс

private struct ProgressWidget: View {
    let data: WidgetData

    var body: some View {
        WidgetCard(title: data.string("title")) {
            ForEach(Array(data.array("items").enumerated()), id: \.offset) { _, item in
                let raw = item.number("value") ?? 0
                let fraction = min(1, max(0, raw > 1 ? raw / 100 : raw))
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    HStack {
                        Text(item.string("label") ?? "").foregroundStyle(Color.tfText)
                        Spacer()
                        Text("\(Int((fraction * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(Color.tfSub)
                    }
                    .font(.subheadline)
                    ProgressView(value: fraction)
                        .tint(fraction >= 1 ? Color.tfGreen : Color.tfBlue)
                    if let note = item.string("note") {
                        Text(note).font(.caption).foregroundStyle(Color.tfSub)
                    }
                }
            }
        }
    }
}

// MARK: - Чек-лист

/// Отметки ставятся прямо в чате — локально, для себя: сервер про них не
/// знает (виджет — часть ответа роли, а не задача трекера).
private struct ChecklistWidget: View {
    let data: WidgetData
    @State private var toggled: Set<Int> = []

    var body: some View {
        WidgetCard(title: data.string("title")) {
            ForEach(Array(data.array("items").enumerated()), id: \.offset) { index, item in
                let done = (item.bool("done") ?? false) != toggled.contains(index)
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        if toggled.contains(index) { toggled.remove(index) } else { toggled.insert(index) }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(done ? Color.tfGreen : Color.tfDim)
                        Text(item.string("text") ?? "")
                            .strikethrough(done)
                            .foregroundStyle(done ? Color.tfSub : Color.tfText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: toggled)
            }
        }
    }
}

// MARK: - Карточка

private struct CardWidget: View {
    let data: WidgetData
    @Environment(\.openURL) private var openURL

    var body: some View {
        WidgetCard(title: nil) {
            VStack(alignment: .leading, spacing: 2) {
                if let title = data.string("title") {
                    Text(title).font(.headline).foregroundStyle(Color.tfText)
                }
                if let subtitle = data.string("subtitle") {
                    Text(subtitle).font(.subheadline).foregroundStyle(Color.tfSub)
                }
            }
            if let bodyText = data.string("body") {
                RoleReplyMarkdown(text: bodyText)
            }
            let rows = data.array("rows")
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.string("label") ?? "").foregroundStyle(Color.tfSub)
                            Spacer(minLength: TFSpacing.md)
                            Text(row.string("value") ?? "—")
                                .foregroundStyle(Color.tfText)
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.subheadline)
                        .padding(.vertical, TFSpacing.sm)
                        if index < rows.count - 1 { Divider() }
                    }
                }
            }
            if let link = data.object("link"), let raw = link.string("url"), let url = URL(string: raw) {
                Button {
                    openURL(url)
                } label: {
                    Label(link.string("title") ?? "Открыть", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.tfRed)
            }
        }
    }
}

// MARK: - График

private struct ChartWidget: View {
    let data: WidgetData

    private struct Point: Identifiable {
        let id: Int
        let x: String
        let y: Double
    }

    private var points: [Point] {
        data.array("points").enumerated().compactMap { index, item in
            guard let y = item.number("y") else { return nil }
            return Point(id: index, x: item.string("x") ?? "\(index + 1)", y: y)
        }
    }

    var body: some View {
        WidgetCard(title: data.string("title")) {
            let isLine = data.string("kind") == "line"
            Chart(points) { point in
                if isLine {
                    LineMark(x: .value("x", point.x), y: .value("y", point.y))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.tfRed)
                    PointMark(x: .value("x", point.x), y: .value("y", point.y))
                        .foregroundStyle(Color.tfRed)
                } else {
                    BarMark(x: .value("x", point.x), y: .value("y", point.y))
                        .foregroundStyle(Color.tfRed.gradient)
                        .cornerRadius(4)
                }
            }
            .chartYAxisLabel(data.string("unit") ?? "")
            .frame(height: 180)
        }
    }
}

// MARK: - Не разобрали

private struct UnknownWidget: View {
    let raw: String

    var body: some View {
        WidgetCard(title: nil) {
            Label("Виджет не разобран", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(Color.tfSub)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(raw)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.tfSub)
            }
        }
    }
}
