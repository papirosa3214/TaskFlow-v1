import Foundation

/// Проекты и метки — spec/API.md §5.4.
public extension APIClient {

    func projects() async throws -> [ApiProject] {
        try await request(.get, "/projects")
    }

    /// `withDocs=true` создаёт и линкует папку заметок (`journal_folders`).
    func createProject(
        name: String,
        color: String? = nil,
        withDocs: Bool = false,
        knowledgeDatasetId: String? = nil
    ) async throws -> ApiProject {
        var body: [String: JSONValue] = ["name": .string(name)]
        if let color { body["color"] = .string(color) }
        if withDocs { body["with_docs"] = .bool(true) }
        // Пусто — проект едет в общий датасет TaskFlow, как было до появления
        // выбора (08.09.2026).
        if let knowledgeDatasetId, !knowledgeDatasetId.isEmpty {
            body["knowledge_dataset_id"] = .string(knowledgeDatasetId)
        }
        return try await request(.post, "/projects", body: body)
    }

    func patchProject(id: String, fields: [String: JSONValue]) async throws -> ApiProject {
        try await request(.patch, "/projects/\(id)", body: fields)
    }

    /// Владелец; оркестратору 403 (spec §5.4).
    func deleteProject(id: String) async throws {
        let _: APIOkResponse = try await request(.delete, "/projects/\(id)")
    }

    func labels() async throws -> [ApiLabel] {
        try await request(.get, "/labels")
    }

    func createLabel(name: String, color: String? = nil) async throws -> ApiLabel {
        var body: [String: JSONValue] = ["name": .string(name)]
        if let color { body["color"] = .string(color) }
        return try await request(.post, "/labels", body: body)
    }

    func patchLabel(id: String, fields: [String: JSONValue]) async throws -> ApiLabel {
        try await request(.patch, "/labels/\(id)", body: fields)
    }

    func deleteLabel(id: String) async throws {
        let _: APIOkResponse = try await request(.delete, "/labels/\(id)")
    }
}
