import SwiftUI

/// Содержимое нижней шторки раскрытого дня — открывается и в НЕДЕЛЬНОМ, и в
/// МЕСЯЧНОМ виде. Заголовок и системные toolbar-иконки задаёт
/// `UpcomingScreen.daySheet`.
struct UpcomingDaySheetContent: View {
    let date: String
    let tasks: [ApiTask]
    let onTaskTap: (String) -> Void

    var body: some View {
        // Своя прокрутка обязательна: без неё жест целиком доставался шторке,
        // и вместо листания она просто ехала наверх (владелец 10.09.2026).
        // Половинное состояние отдаёт жест этому `ScrollView`
        // (`presentationContentInteraction(.scrolls)` в `UpcomingScreen`).
        ScrollView {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if tasks.isEmpty {
                Text("На этот день ничего не запланировано")
                    .tfText(.action)
                    .foregroundStyle(Color.tfDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(tasks, id: \.id) { task in
                        TFTaskRow(UpcomingTaskRow.model(for: task)) {
                            onTaskTap(task.id)
                        }
                    }
                }
                .padding(.bottom, TFSpacing.lg)
            }
        }
    }
}
