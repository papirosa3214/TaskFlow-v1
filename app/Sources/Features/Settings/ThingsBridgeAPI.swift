import Foundation

struct ThingsBridgeSyncResult: Decodable, Sendable {
    let projectsCreated: Int
    let imported: Int
    let exported: Int
    let updated: Int
    let skipped: Int
    let errors: Int

    enum CodingKeys: String, CodingKey {
        case projectsCreated = "projects_created"
        case imported, exported, updated, skipped, errors
    }
}

struct ThingsBridgeAPI: Sendable {
    static let shared = ThingsBridgeAPI()

    /// Ключ настройки с адресом моста. Тот же ключ читает поле в
    /// «Настройки → Интеграции → Things 3».
    static let addressKey = "things_bridge_address"
    /// Порт моста фиксирован скриптом на MacBook — в адресе его можно не
    /// писать.
    static let defaultPort = 8765
    /// Куда стучаться, пока владелец ничего не вбил.
    static let defaultAddress = "192.168.1.102"

    /// Адрес моста живёт в настройках, а не в коде: MacBook получает его по
    /// DHCP, адрес периодически меняется, и раньше каждая такая смена
    /// требовала правки исходника и пересборки (владелец 15.09.2026:
    /// «в интерфейсе сделай — поменяется, чтобы я сам вбил, и всё»).
    private var baseURL: URL {
        Self.url(for: UserDefaults.standard.string(forKey: Self.addressKey))
    }

    /// Собирает адрес из того, что вбил человек. Принимает и голый IP, и
    /// `хост:порт`, и полный URL со схемой — писать «http://» и порт руками
    /// никто не обязан.
    static func url(for raw: String?) -> URL {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let address = trimmed.isEmpty ? defaultAddress : trimmed
        let withScheme = address.contains("://") ? address : "http://\(address)"

        guard var components = URLComponents(string: withScheme) else {
            return URL(string: "http://\(defaultAddress):\(defaultPort)")!
        }
        if components.port == nil { components.port = defaultPort }
        // Хвостовой путь в адресе моста только мешает: методы дописываются
        // сами через `appendingPathComponent`.
        components.path = ""
        return components.url ?? URL(string: "http://\(defaultAddress):\(defaultPort)")!
    }

    func health() async throws -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return (try? JSONDecoder().decode([String: Bool].self, from: data)["ok"]) == true
    }

    func sync() async throws -> ThingsBridgeSyncResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("sync"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ThingsBridgeError.unavailable
        }
        return try JSONDecoder().decode(ThingsBridgeSyncResult.self, from: data)
    }
}

enum ThingsBridgeError: LocalizedError {
    case unavailable

    var errorDescription: String? { "Мост Things на MacBook недоступен" }
}
