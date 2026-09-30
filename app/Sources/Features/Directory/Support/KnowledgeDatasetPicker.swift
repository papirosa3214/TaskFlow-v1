import SwiftUI

// Выбор «полки» базы знаний для проекта — владелец 08.09.2026: «мало ли будет
// специфический бизнесовый проект, мне бы не хотелось замешивать документацию
// не туда, куда надо».
//
// Пусто (`nil`) — общий датасет TaskFlow, поведение по умолчанию. Отдельный
// датасет заводится прямо отсюда: обычно он нужен ровно в тот момент, когда
// заводится сам проект, и уходить за этим в веб-интерфейс RAGFlow незачем.
struct KnowledgeDatasetPicker: View {
    /// `nil` — общий датасет.
    @Binding var selection: String?
    /// Показывать ли предупреждение о переиндексации (для существующего
    /// проекта с документами). У нового проекта переносить нечего.
    var reindexWarning: String?

    @State private var datasets: [ApiKnowledgeDataset] = []
    @State private var isLoading = true
    @State private var isCreating = false
    @State private var newName = ""
    @State private var showNewField = false
    @State private var errorMessage: String?

    private let apiClient = APIClient()

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("База знаний")
                .tfText(.caption)
                .foregroundStyle(Color.tfSub)

            if isLoading {
                TFLoading(.inline)
            } else {
                Menu {
                    Button {
                        selection = nil
                    } label: {
                        Label("Общая база TaskFlow", systemImage: selection == nil ? "checkmark" : "")
                    }
                    ForEach(datasets.filter { !$0.isDefault }) { dataset in
                        Button {
                            selection = dataset.id
                        } label: {
                            Label(
                                dataset.name + (dataset.documentCount.map { " · \($0)" } ?? ""),
                                systemImage: selection == dataset.id ? "checkmark" : ""
                            )
                        }
                    }
                    Divider()
                    Button {
                        showNewField = true
                    } label: {
                        Label("Новая база…", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: TFSpacing.sm) {
                        Image(systemName: "books.vertical")
                            .tfText(.action)
                            .foregroundStyle(Color.tfDim)
                        Text(selectedName)
                            .tfText(.body)
                            .foregroundStyle(Color.tfText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .tfText(.caption)
                            .foregroundStyle(Color.tfDim)
                    }
                    .padding(.horizontal, TFSpacing.sm + 4)
                    .padding(.vertical, TFSpacing.sm + 2)
                    .background(Color.tfCard2)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                }
            }

            if showNewField {
                HStack(spacing: TFSpacing.sm) {
                    TextField("Название новой базы", text: $newName)
                        .tfText(.input)
                        .foregroundStyle(Color.tfText)
                        .padding(.horizontal, TFSpacing.sm + 4)
                        .padding(.vertical, TFSpacing.sm)
                        .background(Color.tfCard2)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                    Button(isCreating ? "…" : "Создать") {
                        Task { await createDataset() }
                    }
                    .tfText(.row)
                    .foregroundStyle(Color.tfRed)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }

            // Предупреждение показывается ДО нажатия, а не после: смена
            // датасета у проекта с документами — это переиндексация на
            // процессоре, и владелец просил видеть цену заранее.
            if let reindexWarning {
                Text(reindexWarning)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfYellow)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TFErrorBanner(errorMessage, variant: .inline)
        }
        .task {
            do {
                datasets = try await apiClient.knowledgeDatasets()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось получить список баз"
            }
            isLoading = false
        }
    }

    private var selectedName: String {
        guard let selection else { return "Общая база TaskFlow" }
        return datasets.first { $0.id == selection }?.name ?? "Своя база"
    }

    private func createDataset() async {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let created = try await apiClient.createKnowledgeDataset(name: trimmed)
            datasets.append(created)
            selection = created.id
            newName = ""
            showNewField = false
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось создать базу"
        }
    }
}
