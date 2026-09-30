import Foundation

struct ThingsSyncTaskSnapshot: Equatable, Sendable {
    let id: String
    let title: String
    let notes: String
    let isCompleted: Bool
    let dueDate: String?
}

enum ThingsSyncDecision: Equatable, Sendable {
    case createTask
    case updateTask
    case skip
}

enum ThingsSyncMerge {
    private static let marker = "TaskFlow ID:"

    static func taskFlowID(from notes: String) -> String? {
        for line in notes.components(separatedBy: .newlines) {
            guard line.hasPrefix(marker) else { continue }
            let id = line.dropFirst(marker.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty { return String(id) }
        }
        return nil
    }

    static func decision(
        thingID: String,
        title: String,
        notes: String,
        isCompleted: Bool,
        dueDate: String?,
        existingTask: ThingsSyncTaskSnapshot?
    ) -> ThingsSyncDecision {
        guard existingTask != nil else { return .createTask }
        guard let id = taskFlowID(from: notes), !id.isEmpty else { return .createTask }
        return .updateTask
    }
}
