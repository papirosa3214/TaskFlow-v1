import Foundation

/// База знаний — смысловой поиск по документации всех проектов.
///
/// За ручками `/api/knowledge/*` стоит RAGFlow на .110 (датасет «TaskFlow —
/// документация»), но приложение об этом не знает и знать не должно: ключ
/// RAGFlow живёт на сервере, сюда ходим обычным токеном TaskFlow. Документы
/// в индекс складывает `~/kb/taskflow_docs_ragflow_sync.py` раз в сутки.
///
/// Поиск отвечает КУСКАМИ текста — так устроен retrieval. У каждого куска
/// есть `docId` — идентификатор настоящей заметки в TaskFlow, по нему
/// открывается оригинал (`AppRoute.noteEditor`), а не копия из индекса.
public struct ApiKnowledgeChunk: Decodable, Identifiable, Sendable, Hashable {
    /// Своего идентификатора у куска нет — собираем из документа и текста,
    /// чтобы `ForEach` не путал соседние фрагменты одного документа.
    public var id: String { (docId ?? documentName) + "#" + String(text.prefix(24)) }
    public let text: String
    public let score: Double?
    public let documentName: String
    /// Название заметки и проект — сервер подмешивает их из TaskFlow: в самом
    /// индексе документ зовётся `taskflow-<uuid>.md`.
    public let title: String?
    public let project: String?
    public let docId: String?

    enum CodingKeys: String, CodingKey {
        case text, score, title, project
        case documentName = "document_name"
        case docId = "doc_id"
    }
}

public struct ApiKnowledgeDocument: Decodable, Identifiable, Sendable, Hashable {
    public var id: String { ragflowId }
    public let name: String
    public let title: String?
    public let project: String?
    /// Заметки в TaskFlow больше нет, а в индексе она осталась — документация
    /// закрытого проекта. Открывается только из индекса.
    public let archived: Bool
    public let docId: String?
    public let ragflowId: String
    public let chunkCount: Int?
    public let size: Int?
    public let updatedAt: String?
    /// `false` — документ ещё индексируется и в поиске пока не участвует.
    public let indexed: Bool

    enum CodingKeys: String, CodingKey {
        case name, size, title, project, archived
        case docId = "doc_id"
        case ragflowId = "ragflow_id"
        case chunkCount = "chunk_count"
        case updatedAt = "updated_at"
        case indexed
    }
}

/// Датасет RAGFlow — «полка», на которую ложится документация проекта.
/// Разделение нужно, чтобы специфический проект не подмешивал свои документы
/// туда, где ищут рабочее (владелец 08.09.2026).
public struct ApiKnowledgeDataset: Decodable, Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let documentCount: Int?
    /// Датасет, куда попадают проекты без собственного выбора.
    public let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case documentCount = "document_count"
        case isDefault = "is_default"
    }
}

public extension APIClient {

    func knowledgeDatasets() async throws -> [ApiKnowledgeDataset] {
        struct Response: Decodable { let datasets: [ApiKnowledgeDataset] }
        let response: Response = try await request(.get, "/knowledge/datasets")
        return response.datasets
    }

    func createKnowledgeDataset(name: String) async throws -> ApiKnowledgeDataset {
        struct Response: Decodable { let id: String; let name: String }
        let response: Response = try await request(
            .post, "/knowledge/datasets", body: ["name": JSONValue.string(name)]
        )
        return ApiKnowledgeDataset(
            id: response.id, name: response.name, documentCount: 0, isDefault: false
        )
    }

    func knowledgeSearch(query: String, topK: Int = 8) async throws -> [ApiKnowledgeChunk] {
        struct Response: Decodable { let results: [ApiKnowledgeChunk] }
        let response: Response = try await request(
            .get, "/knowledge/search",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "top_k", value: String(topK)),
            ]
        )
        return response.results
    }

    /// Что вообще лежит в базе знаний — включая документы проектов, которых
    /// в TaskFlow уже нет: удаление проекта индекс не трогает, и это и есть
    /// архив.
    func knowledgeDocuments(page: Int = 1, pageSize: Int = 50) async throws -> [ApiKnowledgeDocument] {
        struct Response: Decodable { let documents: [ApiKnowledgeDocument] }
        let response: Response = try await request(
            .get, "/knowledge/documents",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page_size", value: String(pageSize)),
            ]
        )
        return response.documents
    }
}
