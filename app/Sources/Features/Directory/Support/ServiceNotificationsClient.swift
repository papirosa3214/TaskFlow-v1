import Foundation

/// HTTP-клиент отдельного сервиса `notifications-api.service` на `.110`
/// (`http://192.168.1.110:5198`) — НЕ тот же сервер, что основной
/// `APIClient` (порт 3001, с Bearer-токеном). Без авторизации, LAN.
/// docs/2026-09-27-notifications-service-tickets-spec.md.
public struct ServiceNotificationsClient: Sendable {
    public static let baseURL = URL(string: "http://192.168.1.110:5198")!

    private let session: URLSession

    public init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
    }

    public enum ClientError: Error {
        case badStatus(Int)
        case decoding(Error)
    }

    public func fetchInbox(date: String) async throws -> [ServiceTicketSummary] {
        var url = Self.baseURL.appendingPathComponent("notifications/digest")
        url.append(queryItems: [URLQueryItem(name: "date", value: date)])
        let (data, response) = try await session.data(from: url)
        try Self.checkStatus(response)
        do {
            return try JSONDecoder().decode(ServiceTicketInboxResponse.self, from: data).items
        } catch {
            throw ClientError.decoding(error)
        }
    }

    public func fetchRaw(path: String) async throws -> String {
        var url = Self.baseURL.appendingPathComponent("notifications/raw")
        url.append(queryItems: [URLQueryItem(name: "path", value: path)])
        let (data, response) = try await session.data(from: url)
        try Self.checkStatus(response)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ClientError.badStatus(code)
        }
    }
}

private extension URL {
    mutating func append(queryItems: [URLQueryItem]) {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return }
        components.queryItems = queryItems
        if let url = components.url { self = url }
    }
}
