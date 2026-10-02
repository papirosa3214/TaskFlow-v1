import Foundation

/// Запись памяти ролей — `server/src/lib/memory.ts` (02.10.2026). Короткий
/// факт, урок, предпочтение владельца или загруженный файл.
public struct ApiMemory: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// team — общая, role — одной роли, project — по проекту.
    public let scope: String
    public let roleKey: String?
    public let projectId: String?
    /// fact | lesson | preference | file
    public let kind: String
    public let title: String?
    public let text: String
    /// owner — записал владелец, role — роль сама.
    public let sourceKind: String
    public let createdBy: String?
    public let pinned: Int
    public let useCount: Int?
    public let lastUsedAt: String?
    public let createdAt: String?
    public let updatedAt: String?
    /// Число кусков у файла (только у `GET /memories/:id`).
    public let chunks: Int?

    public var isPinned: Bool { pinned != 0 }
    public var isFile: Bool { kind == "file" }
    public var isFromRole: Bool { sourceKind == "role" }

    enum CodingKeys: String, CodingKey {
        case id, scope, kind, title, text, pinned, chunks
        case roleKey = "role_key"
        case projectId = "project_id"
        case sourceKind = "source_kind"
        case createdBy = "created_by"
        case useCount = "use_count"
        case lastUsedAt = "last_used_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct ApiMemoryChunk: Codable, Sendable, Hashable {
    public let idx: Int
    public let text: String
}
