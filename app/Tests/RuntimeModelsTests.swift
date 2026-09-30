import XCTest
@testable import TaskFlow

/// LOCK-175, этап 1: DTO рантайма обязаны декодироваться ровно из того
/// JSON, который отдаёт серверный фасад (`server/src/routes/runtime.ts`).
/// Фикстуры — снятые вслух формы ответов; snake_case и camelCase в них
/// намеренно перемешаны так же, как на сервере.
final class RuntimeModelsTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testAgentProfileDecodesSnakeAndCamelKeys() throws {
        let profile = try decode(AgentProfile.self, #"""
        {
          "id": "architect",
          "role": "architect",
          "title": "Архитектор",
          "account_id": "role_architect",
          "runtime_id": "runtime:pi",
          "prompt": { "source": "/srv/scripts/role-prompts/architect.md", "size": 4242 },
          "skills": [ { "name": "planning", "description": "План работ" } ],
          "tools": ["taskflow_create_task", "taskflow_update_task"],
          "permissions": "can_create_tasks",
          "modelPolicy": { "primary": "claude-sonnet", "fallbacks": ["gpt-sol", "minimax"] },
          "status": "working"
        }
        """#)

        XCTAssertEqual(profile.id, "architect")
        XCTAssertEqual(profile.accountID, "role_architect")
        XCTAssertEqual(profile.runtimeID, "runtime:pi")
        XCTAssertEqual(profile.prompt.size, 4242)
        XCTAssertEqual(profile.skills.first?.name, "planning")
        XCTAssertEqual(profile.tools.count, 2)
        XCTAssertEqual(profile.modelPolicy.primary, "claude-sonnet")
        XCTAssertEqual(profile.modelPolicy.fallbacks, ["gpt-sol", "minimax"])
        XCTAssertEqual(profile.modelPolicy.orderedModels, ["claude-sonnet", "gpt-sol", "minimax"])
        XCTAssertEqual(profile.status, .working)
    }

    func testAgentProfileStatusFallsBackToUnknown() throws {
        let profile = try decode(AgentProfile.self, #"""
        {
          "id": "qa", "role": "qa", "title": "QA", "account_id": "role_qa",
          "runtime_id": "runtime:pi",
          "prompt": { "source": "x", "size": 0 },
          "skills": [], "tools": [], "permissions": null,
          "modelPolicy": { "primary": "gpt-luna", "fallbacks": [] },
          "status": "retired"
        }
        """#)
        XCTAssertEqual(profile.status, .unknown)
    }

    func testRuntimeModelDecodesCatalogFields() throws {
        let model = try decode(RuntimeModel.self, #"""
        {
          "id": "claude-sonnet",
          "provider": "anthropic",
          "runtime_id": "runtime:pi",
          "available": true,
          "name": "Claude Sonnet",
          "contextWindow": 200000,
          "maxTokens": 8192,
          "thinking": true,
          "images": true
        }
        """#)
        XCTAssertEqual(model.displayName, "Claude Sonnet")
        XCTAssertEqual(model.uid, "anthropic:claude-sonnet")
        XCTAssertTrue(model.available)
        XCTAssertEqual(model.contextWindow, 200000)
        XCTAssertEqual(model.thinking, true)
    }

    func testRuntimeProviderDecodesHTTPShape() throws {
        let provider = try decode(RuntimeProvider.self, #"""
        {
          "provider": "anthropic",
          "name": "Anthropic",
          "status": "connected",
          "authType": "oauth",
          "authMethods": ["api_key", "oauth"]
        }
        """#)
        XCTAssertEqual(provider.id, "anthropic")
        XCTAssertEqual(provider.status, .connected)
        XCTAssertEqual(provider.authType, .oauth)
        XCTAssertTrue(provider.supportsOAuth)
        XCTAssertTrue(provider.supportsAPIKey)
    }

    func testProviderAuthStartHandlesBothServerForms() throws {
        let apiKey = try decode(ProviderAuthStart.self, #"""
        { "provider": "openai", "status": "connected", "authType": "api_key" }
        """#)
        XCTAssertEqual(apiKey.status, .connected)
        XCTAssertEqual(apiKey.authType, .apiKey)
        XCTAssertNil(apiKey.authSessionID)

        let oauth = try decode(ProviderAuthStart.self, #"""
        { "authSessionId": "auth_123", "provider": "anthropic", "status": "starting" }
        """#)
        XCTAssertEqual(oauth.authSessionID, "auth_123")
        XCTAssertNil(oauth.authType)
    }

    func testRuntimeStatusEnvelope() throws {
        let envelope = try decode(RuntimeStatus.self, #"""
        { "id": "runtime:pi", "kind": "pi", "status": "ready", "version": "1.2.3", "endpoint": "cli" }
        """#)
        XCTAssertTrue(envelope.isOnline)
        XCTAssertEqual(envelope.statusTitle, "Online")
    }

    func testAuthSessionDecodesPromptAndEvents() throws {
        let session = try decode(AuthSession.self, #"""
        {
          "id": "auth_123",
          "provider": "anthropic",
          "status": "waiting_user",
          "createdAt": "2026-09-18T10:00:00.000Z",
          "expiresAt": "2026-09-18T10:10:00.000Z",
          "currentPrompt": {
            "type": "manual_code",
            "message": "Введите код",
            "placeholder": "xxxx",
            "options": [ { "id": "a", "label": "Первый" } ]
          },
          "error": null,
          "events": [
            { "seq": 1, "at": "2026-09-18T10:00:01.000Z", "type": "auth_url",
              "data": { "url": "https://example.test/auth" } }
          ]
        }
        """#)
        XCTAssertEqual(session.status, .waitingUser)
        XCTAssertEqual(session.currentPrompt?.type, .manualCode)
        XCTAssertEqual(session.currentPrompt?.options?.first?.label, "Первый")
        XCTAssertEqual(session.events.first?.type, "auth_url")
        XCTAssertEqual(session.events.first?.data["url"], .string("https://example.test/auth"))
        XCTAssertFalse(session.status.isFinished)
    }

    func testAgentRunSummaryDecodesAttemptsInOrder() throws {
        let run = try decode(AgentRunSummary.self, #"""
        {
          "id": "run_1",
          "task_id": "task_1",
          "agent_id": "builder",
          "runtime_id": "runtime:pi",
          "provider": "anthropic",
          "model": "claude-sonnet",
          "session_id": "sess_1",
          "status": "running",
          "started_at": "2026-09-18T10:00:00.000Z",
          "finished_at": null,
          "stop_reason": null,
          "attempts": [
            { "id": "a1", "model": "gpt-luna", "provider": "openai", "status": "failed",
              "outcome": "provider_limit", "started_at": "2026-09-18T09:00:00.000Z",
              "finished_at": "2026-09-18T09:01:00.000Z", "reason": "rate_limit" },
            { "id": "a2", "model": "claude-sonnet", "provider": "anthropic", "status": "running",
              "outcome": null, "started_at": "2026-09-18T10:00:00.000Z",
              "finished_at": null, "reason": null }
          ]
        }
        """#)
        XCTAssertEqual(run.status, .running)
        XCTAssertEqual(run.taskID, "task_1")
        XCTAssertEqual(run.attempts?.count, 2)
        XCTAssertEqual(run.attempts?[0].status, .failed)
        XCTAssertEqual(run.attempts?[0].outcome, "provider_limit")
        XCTAssertEqual(run.attempts?[1].status, .running)
    }
}
