import SwiftUI

/// Модалка по тапу на строку-сноску "(не исправлено...)" — НЕ inline-кнопка.
/// Единственное действие — комментарий к задаче через `createComment`.
struct ServiceTicketResolutionSheet: View {
    let item: ServiceTicketResolutionItem
    let taskId: String
    let onSubmitted: () -> Void

    @State private var selectedOption: Int?
    @State private var customText: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    private let apiClient = APIClient()

    private var options: [String] {
        if case .needsDecision(let opts) = item.status { return opts }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            Text("Что делаем дальше?").tfText(.action).fontWeight(.semibold)
            Text(item.problem).tfText(.body).foregroundStyle(Color.tfSub)

            ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                Button {
                    selectedOption = idx
                    customText = option
                } label: {
                    HStack {
                        Image(systemName: selectedOption == idx ? "largecircle.fill.circle" : "circle")
                        Text(option).tfText(.body)
                    }
                }
                .buttonStyle(TFTapRowStyle())
            }

            Text("Свой вариант:").tfText(.meta).foregroundStyle(Color.tfDim)
            // Плоский SwiftUI `TextField` вместо `TFTextField`: полю нужен рост
            // на несколько строк (`axis: .vertical`) — при выборе готового
            // варианта или длинной причине из `unresolved` сюда попадает целое
            // предложение, а `TFTextField` (сверено чтением файла) всегда
            // однострочный и такого не умеет. `TFButton` ниже, наоборот,
            // подходит без потери поведения — используется он.
            TextField("Что делать?", text: $customText, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            TFErrorBanner(errorMessage, variant: .inline)

            TFButton(
                isSubmitting ? "Отправка…" : "Отправить",
                variant: .primary,
                isEnabled: !customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
            ) {
                Task { await submit() }
            }
        }
        .padding(TFSpacing.lg)
        .task {
            if customText.isEmpty {
                customText = options.first ?? {
                    if case .unresolved(let reason) = item.status { return reason }
                    return ""
                }()
            }
        }
    }

    private func submit() async {
        let text = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            _ = try await apiClient.createComment(taskId: taskId, text: text)
            onSubmitted()
        } catch {
            errorMessage = "Не удалось отправить комментарий"
        }
    }
}
