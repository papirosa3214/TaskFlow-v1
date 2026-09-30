import Foundation

/// Агенты/пользователи-исполнители — spec/API.md §5.5. Веб-клиент опрашивает
/// `GET /agents` раз в 15 секунд для «онлайн/офлайн»/«что делает сейчас»
/// (spec §8) — тот же ритм стоит повторить в `RootShellView`/сторе агентов,
/// когда экран «Агенты» появится (Волна 2). Удалены 2026-09-11 по
/// DEAD-CODE-CLEANUP-REPORT.md: `InviteAgentResponse`, `inviteAgent`,
/// `renameAgent` — старые контракты, заменены `AgentsAPI.swift` в
/// `Sources/Features/Chat/`.
public extension APIClient {

    func agents() async throws -> [ApiUser] {
        try await request(.get, "/agents")
    }

    /// Только владелец. 409, если у агента есть незавершённая работа.
    func deleteAgent(id: String) async throws {
        let _: APIOkResponse = try await request(.delete, "/agents/\(id)")
    }
}
