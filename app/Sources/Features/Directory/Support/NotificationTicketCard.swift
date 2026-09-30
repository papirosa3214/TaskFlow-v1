import SwiftUI

/// Карточка-тикет сводки стороннего сервиса в списке — компактная превью-
/// строка, визуально ОТДЕЛЬНАЯ от карточки-задачи. Тап открывает полный
/// разбор в `NotificationTicketDetailSheet` (нативное окно снизу на всю
/// высоту, `.tfBottomSheet`) — владелец 27.09.2026: «как в карточку задачи
/// должен проваливаться», не разворачивать текст инлайн в списке.
struct NotificationTicketCard: View {
    let summary: ServiceTicketSummary
    let detail: ServiceTicketDetail?
    let onOpenTask: (String) -> Void
    let onTapResolutionItem: (ServiceTicketResolutionItem) -> Void

    @State private var showDetail = false

    @AppStorage private var isRead: Bool

    init(summary: ServiceTicketSummary, detail: ServiceTicketDetail?,
         onOpenTask: @escaping (String) -> Void,
         onTapResolutionItem: @escaping (ServiceTicketResolutionItem) -> Void) {
        self.summary = summary
        self.detail = detail
        self.onOpenTask = onOpenTask
        self.onTapResolutionItem = onTapResolutionItem
        // Версия по ts: новая сводка снова непрочитанная. Перезапуск не
        // возвращает обводку уже открытым уведомлениям на этом устройстве.
        _isRead = AppStorage(wrappedValue: false,
            "taskflow.serviceNotification.read.\(summary.id).\(summary.revision ?? summary.ts)")
    }

    var body: some View {
        Button {
            showDetail = true
            isRead = true
        } label: {
            TFCard {
                VStack(alignment: .leading, spacing: TFSpacing.md) {
                    header
                    statusLine
                    Text(presentation.preview)
                        .tfText(.caption).foregroundStyle(Color.tfSub)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if let date = NotificationTicketStyle.parseTicketDate(summary.ts) {
                        Text(DirectoryDate.relative(date))
                            .tfText(.caption).foregroundStyle(Color.tfDim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if !isRead {
                    RoundedRectangle(cornerRadius: TFRadius.xl, style: .continuous)
                        .strokeBorder(Color.tfRed.opacity(0.45), lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(TFTapScaleStyle())
        .tfBottomSheet(isPresented: $showDetail, title: presentation.title) {
            NotificationTicketDetailSheet(
                summary: summary,
                detail: detail,
                onOpenTask: { taskId in
                    showDetail = false
                    onOpenTask(taskId)
                },
                onTapResolutionItem: { item in
                    showDetail = false
                    onTapResolutionItem(item)
                }
            )
        }
    }

    private var presentation: ServiceTicketPresentation { ServiceTicketPresentation(summary: summary) }

    private var header: some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            Circle().fill(Color.tfSub).frame(width: 8, height: 8).padding(.top, 7)
            Text(presentation.title)
                .tfText(.title).foregroundStyle(Color.tfText)
                .lineLimit(2).multilineTextAlignment(.leading)
            Spacer(minLength: TFSpacing.sm)
            Image(systemName: "chevron.right")
                .font(.system(size: 13)).foregroundStyle(Color.tfDim)
        }
    }

    private var statusLine: some View {
        ServiceTicketStatusCounts(summary: summary)
    }
}

struct ServiceTicketStatusCounts: View {
    let summary: ServiceTicketSummary
    private var presentation: ServiceTicketPresentation { ServiceTicketPresentation(summary: summary) }

    var body: some View {
        HStack(spacing: TFSpacing.lg) {
            countLabel(presentation.okCount, icon: "checkmark.circle", title: "Штатно", color: .tfGreen)
            countLabel(presentation.errorCount, icon: "xmark.circle", title: "Ошибок", color: .tfRed)
            countLabel(presentation.warningCount, icon: "exclamationmark.circle", title: "Предупреждений", color: .tfOrange)
        }
    }

    private func countLabel(_ count: Int, icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(count)")
        }
        .tfText(.row)
        .foregroundStyle(count > 0 ? color : Color.tfDim)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(count)")
    }

}

/// Общее между компактной карточкой и полным разбором — цвет уровня и
/// разбор даты `.110` (локальное время без зоны, не GMT ISO8601).
enum NotificationTicketStyle {
    static func parseTicketDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: raw)
    }

    static func levelColor(_ level: String) -> Color {
        switch level {
        case "error": return Color.tfRed
        case "warning": return Color.tfOrange
        default: return Color.tfBlue
        }
    }

    /// `AttributedString(markdown:)` с фолбэком на буквальный `Text` при
    /// ошибке парсинга — не `Text(LocalizedStringKey:)`: `.inlineOnlyPreservingWhitespace`
    /// рендерит `**bold**`/`*italic*` без риска сломанной разметки исказить
    /// текст, а провал парсинга просто показывает исходную строку как есть.
    static func markdownText(_ raw: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(raw)
    }
}
