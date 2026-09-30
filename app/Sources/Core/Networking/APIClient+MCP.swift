import Foundation

/// Ответ `GET /api/mcp/manifest` — что получает сторонний агент (Гермес,
/// Claude Code, DSH…), подключившись к TaskFlow по MCP. Сервер читает это
/// прямо из `mcp_server.py`, копии в приложении нет.
public struct MCPManifest: Decodable, Sendable {
    public struct Tool: Decodable, Sendable, Identifiable {
        public let name: String
        public let description: String
        public var id: String { name }
    }

    public let instructions: String
    public let tools: [Tool]
}

public extension APIClient {
    func mcpManifest() async throws -> MCPManifest {
        try await request(.get, "/mcp/manifest")
    }
}
