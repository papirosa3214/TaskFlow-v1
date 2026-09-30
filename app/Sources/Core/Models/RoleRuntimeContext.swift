import Foundation

public struct RoleRuntimeContext: Decodable, Sendable, Equatable {
    public let role: String
    public let layers: [RoleRuntimeContextLayer]
    public let blocks: [RoleInstructionBlock]?
    public let canEdit: Bool?
    public let notice: String?
}
public struct RoleRuntimeContextLayer: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let scope: String
    public let source: String
    public let editable: Bool
    public let text: String
}
public struct RoleInstructionBlock: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let group: String
    public let scope: String
    public let source: String
    public let editable: Bool
    public let text: String
    public let teamText: String?
    public let defaultText: String
    public let version: Int
    public let commandVersion: Int
    public let modes: [String]
    public let placeholders: [String]
    public let allowsTeam: Bool
}
public struct RoleInstructionHistory: Decodable, Sendable, Identifiable {
    public var id: Int { version }
    public let version: Int
    public let action: String
    public let at: String
    public let byUserId: String
    public let reason: String?
    public let text: String
}
public struct RoleInstructionHistoryEnvelope: Decodable, Sendable {
    public let history: [RoleInstructionHistory]
}
/// Conflict never replaces the local draft; adopting a new revision is explicit.
struct RoleInstructionDraft {
    var text: String
    var expectedVersion: Int
    var hasConflict = false
    mutating func conflict() { hasConflict = true }
    mutating func adoptRevision(_ revision: Int) { expectedVersion = revision; hasConflict = false }
}
