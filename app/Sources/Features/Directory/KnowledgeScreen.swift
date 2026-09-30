import SwiftUI

/// Совместимый маршрут «Базы знаний». Сама витрина не дублирует документы:
/// единый экран с деревом, редактором и смысловым поиском — `NotesScreen`.
struct KnowledgeScreen: View {
    var body: some View {
        NotesScreen()
    }
}
