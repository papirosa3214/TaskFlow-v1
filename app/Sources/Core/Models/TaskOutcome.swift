import Foundation

/// Итог карточки (`GET /api/tasks/:id/outcome`, владелец 01.10.2026): вердикт
/// проверяющего, что сдала каждая роль, документы по карточке, ветка с кодом.
public struct ApiTaskOutcome: Decodable, Sendable, Equatable {
    public struct Verdict: Decodable, Sendable, Equatable {
        public let verdict: String
        public let findings: String
        public let reviewerID: String
        public let createdAt: String

        enum CodingKeys: String, CodingKey {
            case verdict, findings
            case reviewerID = "reviewer_id"
            case createdAt = "created_at"
        }

        public var isApproved: Bool { verdict == "approved" }

        /// `created_at` из SQLite — «2026-09-30 10:12:34», UTC.
        public var createdDate: Date? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.date(from: createdAt)
        }

        public var title: String {
            switch verdict {
            case "approved": return "принято"
            case "changes_requested": return "вернуть на доработку"
            case "blocked": return "остановить"
            default: return verdict
            }
        }
    }

    public struct Node: Decodable, Sendable, Equatable, Identifiable {
        public let slotKey: String?
        public let role: String?
        public let title: String
        public let result: String?
        public let done: Bool

        public var id: String { (slotKey ?? "") + "|" + title }

        enum CodingKeys: String, CodingKey {
            case role, title, result, done
            case slotKey = "slot_key"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            slotKey = try c.decodeIfPresent(String.self, forKey: .slotKey)
            role = try c.decodeIfPresent(String.self, forKey: .role)
            title = try c.decode(String.self, forKey: .title)
            result = try c.decodeIfPresent(String.self, forKey: .result)
            // Сервер шлёт true/false, SQLite-ответы — 0/1: принимаем оба.
            if let flag = try? c.decode(Bool.self, forKey: .done) {
                done = flag
            } else {
                done = (try c.decodeIfPresent(Int.self, forKey: .done) ?? 0) != 0
            }
        }
    }

    public struct Document: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let updatedAt: String?
        public let isOutcome: Bool

        enum CodingKeys: String, CodingKey {
            case id, title
            case updatedAt = "updated_at"
            case isOutcome = "is_outcome"
        }
    }

    public struct Branch: Decodable, Sendable, Equatable {
        public let name: String
        public let commit: String
        public let subject: String
        public let ahead: Int
    }

    public let verdict: Verdict?
    public let nodes: [Node]
    public let documents: [Document]
    public let branch: Branch?

    /// Показывать ли секцию вообще: у обычной карточки итога нет.
    public var isEmpty: Bool {
        verdict == nil && nodes.isEmpty && documents.isEmpty && branch == nil
    }
}
