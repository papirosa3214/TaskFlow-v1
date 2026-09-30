import SwiftUI

// Массовый перенос просроченных — spec §3.8 `RescheduleSheet`. Открывается
// с колонки «Просрочено» на доске «Сегодня».
struct RescheduleSheetContent: View {
    let taskIds: [String]
    let taskStore: TaskStore
    let onClose: () -> Void

    @State private var displayedMonth = Date()
    /// 9:00 по умолчанию — как в редакторе срока внутри карточки.
    @State private var pickedTime = Calendar.current.date(
        bySettingHour: 9, minute: 0, second: 0, of: Date()
    ) ?? Date()
    @State private var isRescheduling = false
    @State private var done = 0
    @State private var errorMessage: String?

    var body: some View {
        // Своей шапки здесь нет: заголовок «Срок» рисует системный навбар
        // шторки (`tfBottomSheet`, 09.09.2026). Кнопок подтверждения и
        // закрытия тоже нет — выбор применяется сразу, а закрывается шторка
        // смахиванием, как везде в приложении.
        VStack(spacing: TFSpacing.lg) {
            if isRescheduling {
                Text("Переносим \(done) из \(taskIds.count)…")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
            }
            TFErrorBanner(errorMessage, variant: .block)

            // Тот же набор и тот же порядок, что в редакторе срока внутри
            // карточки: «Сегодня»/«Завтра» в ряд, ниже дата и время
            // (09.09.2026 — «эти вещи должны быть одинаковыми, согласованными
            // со всем приложением»). «На выходных» и «Следующая неделя»
            // убраны: в карточке их нет, а два набора быстрых дат в одном
            // приложении расходились бы.
            HStack(spacing: TFSpacing.sm) {
                quickButton("Сегодня") { apply(date: TodayDate.todayString()) }
                quickButton("Завтра") { apply(date: TodayDate.addDays(TodayDate.todayString(), 1)) }
            }

            DatePicker("Дата", selection: customDateBinding, displayedComponents: .date)
            DatePicker("Время", selection: customTimeBinding, displayedComponents: .hourAndMinute)

            Button {
                apply(date: nil)
            } label: {
                Text("Убрать срок")
                    .tfText(.body)
                    .foregroundStyle(Color.tfCoral)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TFTapFadeStyle())
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.bottom, TFSpacing.xl)
        .disabled(isRescheduling)
    }

    /// Выбор в пикере сразу переносит задачу — отдельной кнопки
    /// «применить» здесь нет и у быстрых кнопок тоже.
    private var customDateBinding: Binding<Date> {
        Binding(
            get: { displayedMonth },
            set: { picked in
                displayedMonth = picked
                let f = DateFormatter()
                f.calendar = Calendar(identifier: .gregorian)
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone(identifier: "Europe/Moscow")
                f.dateFormat = "yyyy-MM-dd"
                apply(date: f.string(from: picked))
            }
        )
    }

    /// Время переноса. Задача может быть без времени — тогда 9:00, как в
    /// редакторе срока внутри карточки.
    private var customTimeBinding: Binding<Date> {
        Binding(
            get: { pickedTime },
            set: { pickedTime = $0 }
        )
    }

    /// Один в один кнопка из редактора срока в карточке задачи.
    private func quickButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .tfText(.body)
                .fontWeight(.medium)
                .foregroundStyle(Color.tfText)
                .frame(maxWidth: .infinity)
                .frame(height: TFHitTarget.min)
                .background(Color.tfCard2)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
        }
        .buttonStyle(TFTapScaleStyle())
    }




    private func apply(date: String?) {
        Task { await runReschedule(date: date) }
    }


    private func runReschedule(date: String?) async {
        isRescheduling = true
        done = 0
        errorMessage = nil
        var failed = 0
        let comps = Calendar.current.dateComponents([.hour, .minute], from: pickedTime)
        let timeString = String(format: "%02d:%02d", comps.hour ?? 9, comps.minute ?? 0)
        await withTaskGroup(of: Bool.self) { group in
            for id in taskIds {
                group.addTask {
                    // `ApiTask` — все поля `let` (см. Core/Models/Task.swift), точечно
                    // мутировать `inout` нечем; полагаемся на ответ сервера, который
                    // `patch()` сам подставит в стор после await — без мгновенного
                    // оптимистичного обновления строки, но корректно.
                    // Вместе с датой переносим и время: пикер времени иначе
                    // был бы декоративным — покрутил, а на сервер ушла одна
                    // дата. Сняли срок — время тоже снимаем, сервер не
                    // принимает время без даты.
                    var fields: [String: JSONValue] = [
                        "due_date": date.map { JSONValue.string($0) } ?? .null
                    ]
                    fields["start_time"] = date == nil ? .null : .string(timeString)
                    return await taskStore.patch(taskId: id, fields: fields) { _ in }
                }
            }
            for await ok in group {
                if ok { done += 1 } else { failed += 1 }
            }
        }
        isRescheduling = false
        if failed > 0 {
            errorMessage = "Не удалось перенести \(failed) из \(taskIds.count) задач. Остальные уже перенесены — попробуйте ещё раз."
        } else {
            onClose()
        }
    }
}
