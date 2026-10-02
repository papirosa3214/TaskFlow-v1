import Foundation

// Память ролей (02.10.2026) — контракт `server/src/routes/memory.ts`.

private struct MemoriesEnvelope: Decodable { let memories: [ApiMemory] }
private struct MemoryEnvelope: Decodable { let memory: ApiMemory }
private struct MemoryDetailEnvelope: Decodable { let memory: ApiMemory; let chunks: [ApiMemoryChunk] }

public extension APIClient {
    func memories(scope: String? = nil, roleKey: String? = nil, query: String? = nil) async throws -> [ApiMemory] {
        var items: [URLQueryItem] = []
        if let scope { items.append(URLQueryItem(name: "scope", value: scope)) }
        if let roleKey { items.append(URLQueryItem(name: "role_key", value: roleKey)) }
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        let envelope: MemoriesEnvelope = try await request(.get, "/memories", query: items)
        return envelope.memories
    }

    func memory(id: String) async throws -> (ApiMemory, [ApiMemoryChunk]) {
        let envelope: MemoryDetailEnvelope = try await request(.get, "/memories/\(id)")
        return (envelope.memory, envelope.chunks)
    }

    @discardableResult
    func createMemory(text: String, kind: String, scope: String, roleKey: String?, title: String?, pinned: Bool) async throws -> ApiMemory {
        var body: [String: JSONValue] = [
            "text": .string(text), "kind": .string(kind), "scope": .string(scope), "pinned": .bool(pinned),
        ]
        if let roleKey { body["role_key"] = .string(roleKey) }
        if let title, !title.isEmpty { body["title"] = .string(title) }
        let envelope: MemoryEnvelope = try await request(.post, "/memories", body: body)
        return envelope.memory
    }

    /// Правка: передаются только изменённые поля.
    @discardableResult
    func updateMemory(id: String, fields: [String: JSONValue]) async throws -> ApiMemory {
        let envelope: MemoryEnvelope = try await request(.patch, "/memories/\(id)", body: fields)
        return envelope.memory
    }

    func deleteMemory(id: String) async throws {
        struct Ok: Decodable { let ok: Bool }
        let _: Ok = try await request(.delete, "/memories/\(id)")
    }

    /// Файл в память: текст извлекает сервер (txt, md, pdf, doc и прочий текст).
    @discardableResult
    func uploadMemoryFile(fileName: String, data: Data, mime: String, scope: String, roleKey: String?) async throws -> ApiMemory {
        var query = [URLQueryItem(name: "name", value: fileName), URLQueryItem(name: "scope", value: scope)]
        if let roleKey { query.append(URLQueryItem(name: "role_key", value: roleKey)) }
        let envelope: MemoryEnvelope = try await uploadRaw(path: "/memories/files", query: query, data: data, mime: mime)
        return envelope.memory
    }
}
