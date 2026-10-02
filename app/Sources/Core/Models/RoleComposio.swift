import Foundation

public struct RoleComposio: Decodable, Sendable {
    public let enabled: Bool
    /// nil means the whole catalog; an empty array grants no toolkits.
    public let toolkits: [String]?
    public let configured: Bool
    public let available: Bool
    public let catalog: [ComposioToolkit]
    public let error: String?
}

public struct ComposioToolkit: Decodable, Identifiable, Sendable {
    public let slug: String
    public let name: String
    public let connected: Bool
    public let noAuth: Bool
    public var id: String { slug }
}

public struct ComposioAuthorization: Decodable, Sendable {
    public let url: String
}

/// Changes one service without replacing unrelated role permissions.
struct ComposioAccessPolicy: Equatable, Sendable {
    var enabled: Bool
    var toolkits: [String]?

    func allows(_ toolkit: String?) -> Bool {
        guard enabled else { return false }
        guard let toolkit else { return toolkits == nil }
        return toolkits == nil || toolkits!.contains(toolkit)
    }

    func changing(_ toolkit: String?, allowed: Bool) throws -> Self {
        guard let toolkit else {
            return allowed ? Self(enabled: true, toolkits: nil) : Self(enabled: false, toolkits: toolkits)
        }
        // An unrestricted catalog cannot express a single-service exclusion.
        // Keep that existing permission explicit rather than revoking other services.
        if enabled && toolkits == nil {
            if !allowed { throw ComposioAccessError.wholeCatalog }
            return self
        }
        var services = Set(enabled ? (toolkits ?? []) : [])
        if allowed { services.insert(toolkit) } else { services.remove(toolkit) }
        return Self(enabled: allowed || (enabled && !services.isEmpty), toolkits: services.sorted())
    }
}

enum ComposioAccessError: LocalizedError {
    case wholeCatalog
    var errorDescription: String? {
        "У роли открыт весь каталог. Сначала измените доступ в разделе «Весь каталог»."
    }
}
