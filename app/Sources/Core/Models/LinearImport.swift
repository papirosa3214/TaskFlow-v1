import Foundation

struct LinearWorkspace: Decodable, Sendable { let id: String; let name: String }
struct LinearSourceState: Decodable, Sendable { let name: String; let type: String }
struct LinearSourcePerson: Decodable, Sendable { let id: String; let name: String }
struct LinearParentReference: Decodable, Sendable { let id: String }
struct LinearSourceIssue: Decodable, Identifiable, Sendable {
    let id: String
    let identifier: String
    let title: String
    let description: String?
    let url: String
    let priority: Int
    let dueDate: String?
    let parent: LinearParentReference?
    let state: LinearSourceState
    let assignee: LinearSourcePerson?
    let project: LinearSourcePerson?
}
struct LinearIssuePage: Decodable, Sendable {
    let workspace: LinearWorkspace
    let issues: [LinearSourceIssue]
    let cursor: String?
}
struct LinearPreviewItem: Decodable, Identifiable, Sendable {
    let id: String
    let identifier: String
    let title: String
    let description: String?
    let url: String
    let parentID: String?
    let taskID: String?
    let action: String
    let reason: String
    let comments: Int
    let history: Int
    let labels: Int
    let attachments: Int
    let documents: Int?
    let conflicts: [String]
    let sourceState: String
    let sourceAssignee: String?
    enum CodingKeys: String, CodingKey {
        case id, identifier, title, description, url, action, reason, comments, history, labels, attachments, documents, conflicts
        case parentID = "parent_id", taskID = "task_id", sourceState = "source_state", sourceAssignee = "source_assignee"
    }
}
struct LinearPreviewRow: Identifiable { let item: LinearPreviewItem; let depth: Int; var id: String { item.id } }
struct LinearImportPreview: Decodable, Sendable {
    let previewID: String
    let workspace: LinearWorkspace
    let fetchedAt: String
    let expiresAt: String
    let projectID: String?
    let items: [LinearPreviewItem]
    let warnings: [String]
    let createCount: Int
    let updateCount: Int
    enum CodingKeys: String, CodingKey {
        case workspace, items, warnings
        case previewID = "preview_id", fetchedAt = "fetched_at", expiresAt = "expires_at", projectID = "project_id", createCount = "create_count", updateCount = "update_count"
    }
    var rows: [LinearPreviewRow] {
        var rows: [LinearPreviewRow] = [], visited = Set<String>()
        let ids = Set(items.map(\.id))
        func append(_ item: LinearPreviewItem, depth: Int) {
            guard visited.insert(item.id).inserted else { return }
            rows.append(LinearPreviewRow(item: item, depth: depth))
            for child in items.filter({ $0.parentID == item.id }) { append(child, depth: depth + 1) }
        }
        for item in items where item.parentID == nil || !ids.contains(item.parentID!) { append(item, depth: 0) }
        for item in items where !visited.contains(item.id) { append(item, depth: 0) }
        return rows
    }
}
struct LinearImportedTask: Decodable, Identifiable, Sendable {
    let sourceID: String; let taskID: String; let title: String
    var id: String { taskID }
    enum CodingKeys: String, CodingKey { case title; case sourceID = "source_id", taskID = "task_id" }
}
struct LinearImportConflict: Decodable, Sendable {
    let sourceID: String; let fields: [String]
    enum CodingKeys: String, CodingKey { case fields; case sourceID = "source_id" }
}
struct LinearImportResult: Decodable, Sendable {
    let created: Int; let updated: Int; let conflicts: [LinearImportConflict]; let taskIDs: [LinearImportedTask]
    enum CodingKeys: String, CodingKey { case created, updated, conflicts; case taskIDs = "task_ids" }
}
