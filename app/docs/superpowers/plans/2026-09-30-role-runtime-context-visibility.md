# Role Runtime Context Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Show the owner the exact permanent rule layers used to launch a TaskFlow role from Settings → Team, without exposing live task/chat data or adding a second editable prompt.

**Architecture:** The server exposes one read-only role runtime-context resource built from the same resolved prompt and rule constants that task/chat execution uses. The iOS role editor opens a separate read-only sheet whose tabs are driven by that response; iOS stores no duplicated rule text.

**Tech Stack:** Fastify, TypeScript, Vitest; Swift 6, SwiftUI, XCTest/XCUITest.

**Spec:** docs/2026-09-30-role-runtime-context-visibility-design.md

## Global Constraints

- Return only permanent layers; never include task content, comments, dependencies, plan artifacts, chat messages, session IDs, tokens, MCP configuration, vault paths, or credentials.
- roles.prompt remains the only mutable role-personality source; NULL still resolves to scripts/role-prompts/<role>.md.
- Reuse actual runtime prompt, LOCAL_EXECUTION_POLICY, AGENT_RULES, and task/chat guidance; never copy their text into a route or iOS source.
- The iOS view is read-only and preserves existing RoleEditorSheet edit/create/enable flows.
- Final visual acceptance uses a temporary XCUITest and accessibility labels only; it never taps screenshot coordinates or mutates .110.

## Review Focus

- DB override must report roles.prompt; fallback must report the exact fallback path.
- Unknown and unauthenticated roles must receive existing 404/401 semantics, not an empty successful context.
- A role with active work or an existing chat session must not leak dynamic data through this resource.
- A future server layer ID must remain visible and selectable in iOS.
- A load failure must be visible without changing the editable instruction field.

---

## File Structure

### Server checkout on Mac: /Users/max/Проекты/New-Todoist-server/server

- Create src/runtime/roleRuntimeContext.ts — typed builder for six permanent layers.
- Modify src/runtime/inProcessRun.ts — export/reuse static task and plan guidance.
- Modify src/routes/chats.ts — export/reuse static chat guidance apart from history/user text.
- Modify src/routes/roles.ts — add GET /api/roles/:role/runtime-context.
- Create test/roleRuntimeContext.test.ts — unit and route coverage.

### iOS checkout

- Create Sources/Core/Models/RoleRuntimeContext.swift — Codable response model.
- Modify Sources/Core/Networking/APIClient+Roles.swift — request method.
- Create Sources/Features/Chat/RoleRuntimeContextSheet.swift — read-only tabs.
- Modify Sources/Features/Chat/RoleEditorSheet.swift — secondary action and presentation only.
- Create Tests/RoleRuntimeContextTests.swift — decoding and unknown-layer tests.
- Create then remove UITests/RoleRuntimeContextVisibilityUITests.swift for acceptance.

## Interfaces

~~~
export type RoleRuntimeContextLayer = {
  id: string;
  title: string;
  scope: string;
  source: string;
  editable: boolean;
  text: string;
};

export type RoleRuntimeContext = {
  role: string;
  layers: RoleRuntimeContextLayer[];
};

export function buildRoleRuntimeContext(role: RoleName): RoleRuntimeContext;
~~~

The fixed first six layer IDs are role, common, task, plan, chat, and boundaries. Task, plan and chat templates use neutral tokens such as {taskId}, {taskTitle}, and {roleTitle}, never real run data.

~~~
struct RoleRuntimeContext: Decodable, Sendable, Equatable {
    let role: String
    let layers: [RoleRuntimeContextLayer]
}

struct RoleRuntimeContextLayer: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let scope: String
    let source: String
    let editable: Bool
    let text: String
}
~~~

## Tasks

### Task 1: Build and expose the server truth

**Files:**

- Create: /Users/max/Проекты/New-Todoist-server/server/src/runtime/roleRuntimeContext.ts
- Modify: /Users/max/Проекты/New-Todoist-server/server/src/runtime/inProcessRun.ts
- Modify: /Users/max/Проекты/New-Todoist-server/server/src/routes/chats.ts
- Modify: /Users/max/Проекты/New-Todoist-server/server/src/routes/roles.ts
- Test: /Users/max/Проекты/New-Todoist-server/server/test/roleRuntimeContext.test.ts

**Interfaces:**

- Consumes: rolePromptText, roleTitle, LOCAL_EXECUTION_POLICY, AGENT_RULES, existing task/plan/chat launch text.
- Produces: buildRoleRuntimeContext(role) and the GET endpoint.

- [ ] **Step 1: Write failing tests**

~~~
it("returns six ordered permanent layers for Architect", () => {
  expect(buildRoleRuntimeContext("architect").layers.map((x) => x.id))
    .toEqual(["role", "common", "task", "plan", "chat", "boundaries"]);
});

it("reports DB override provenance", () => {
  db.prepare("UPDATE roles SET prompt = ? WHERE key = 'architect'")
    .run("Собственная инструкция");
  expect(buildRoleRuntimeContext("architect").layers[0])
    .toMatchObject({ source: "roles.prompt", text: "Собственная инструкция" });
});

it("keeps the route private and rejects unknown roles", async () => {
  expect((await app.inject({ method: "GET", url: "/api/roles/architect/runtime-context" })).statusCode).toBe(401);
  expect((await app.inject({ method: "GET", url: "/api/roles/no_such_role/runtime-context", headers: auth(ownerToken) })).statusCode).toBe(404);
});
~~~

- [ ] **Step 2: Verify failure**

Run: cd /Users/max/Проекты/New-Todoist-server/server && npm test -- --run test/roleRuntimeContext.test.ts

Expected: FAIL because the builder and route do not exist.

- [ ] **Step 3: Implement one source-of-truth builder**

Create roleRuntimeContext.ts. Resolve role text through rolePromptText; inspect roles.prompt only to label DB versus fallback provenance. Export static guidance from task and chat runtime code instead of retyping prose. The builder must not query task, comments, chat or session tables.

- [ ] **Step 4: Register the read-only endpoint**

In registerRoleRoutes, add authenticated GET /api/roles/:role/runtime-context before generic GET /api/roles/:role. Validate with allRoles(); return existing 404 for an absent/disabled role; return only the builder response.

- [ ] **Step 5: Verify server behaviour**

Run: cd /Users/max/Проекты/New-Todoist-server/server && npm test -- --run test/roleRuntimeContext.test.ts test/roles.test.ts test/rolesManage.test.ts test/chat-session-runtime.test.ts && npx tsc --noEmit

Expected: selected tests PASS and TypeScript exits 0.

- [ ] **Step 6: Commit only the server scope**

Inspect the Mac checkout status, stage only the five listed server files, and commit: feat: expose permanent role runtime context.

### Task 2: Decode and render the context on iOS

**Files:**

- Create: Sources/Core/Models/RoleRuntimeContext.swift
- Modify: Sources/Core/Networking/APIClient+Roles.swift
- Create: Sources/Features/Chat/RoleRuntimeContextSheet.swift
- Modify: Sources/Features/Chat/RoleEditorSheet.swift
- Test: Tests/RoleRuntimeContextTests.swift

**Interfaces:**

- Consumes: GET /api/roles/:role/runtime-context.
- Produces: APIClient.roleRuntimeContext(role:) and RoleRuntimeContextSheet(role:).

- [ ] **Step 1: Write a failing decoding test**

~~~
func testRuntimeContextPreservesKnownAndFutureLayers() throws {
    let data = Data(#"{"role":"architect","layers":[{"id":"role","title":"Роль","scope":"Все режимы","source":"roles.prompt","editable":true,"text":"x"},{"id":"future","title":"Новое","scope":"Тест","source":"server","editable":false,"text":"y"}]}"#.utf8)
    let context = try JSONDecoder().decode(RoleRuntimeContext.self, from: data)
    XCTAssertEqual(context.layers.map { $0.id }, ["role", "future"])
}
~~~

- [ ] **Step 2: Verify failure**

Run: xcodebuild test -project /Users/max/Проекты/TaskFlowNativeBuild/TaskFlow.xcodeproj -scheme TaskFlow -destination 'platform=iOS Simulator,id=ED3C7DF7-F895-45B6-8A28-F67C02362103' -only-testing:TaskFlowTests/RoleRuntimeContextTests

Expected: FAIL because the model does not exist.

- [ ] **Step 3: Add model and API call**

Implement the declared Codable models and:

~~~
func roleRuntimeContext(role: String) async throws -> RoleRuntimeContext {
    try await request(.get, "/roles/\(role)/runtime-context")
}
~~~

Do not add fallback text, Russian layer copy or server defaults to iOS.

- [ ] **Step 4: Implement the read-only sheet**

Load once on appearance. Use response order for tabs and hold selected tab as String, so unknown IDs display under their server title. Show title, scope, source and selectable monospaced text. Use an existing system-native selector; add no custom background, glass, tint, scale or border. Show loading and explicit error state.

- [ ] **Step 5: Wire it into the role editor**

In edit mode only, add secondary action Как запускается роль before enable/disable controls. It opens the sheet using the stable role key. It must not change prompt state, dismiss the editor, or send PATCH.

- [ ] **Step 6: Verify iOS**

Run: xcodegen generate && xcodebuild test -project /Users/max/Проекты/TaskFlowNativeBuild/TaskFlow.xcodeproj -scheme TaskFlow -destination 'platform=iOS Simulator,id=ED3C7DF7-F895-45B6-8A28-F67C02362103' -only-testing:TaskFlowTests/RoleRuntimeContextTests && xcodebuild build -project /Users/max/Проекты/TaskFlowNativeBuild/TaskFlow.xcodeproj -scheme TaskFlow -destination 'platform=iOS Simulator,id=ED3C7DF7-F895-45B6-8A28-F67C02362103'

Expected: model test PASS and build succeeds.

- [ ] **Step 7: Commit only the iOS scope**

Inspect the dirty tree, stage only the five listed iOS files, and commit: feat: show role launch rules in Team.

### Task 3: Verify the owner journey without changing data

**Files:**

- Create then remove: UITests/RoleRuntimeContextVisibilityUITests.swift
- Modify: none

**Interfaces:**

- Consumes: the Как запускается роль accessibility label and six layer titles.
- Produces: an XCResult screenshot attachment proving tab reachability.

- [ ] **Step 1: Add a temporary XCUITest**

~~~
func testOwnerCanInspectPermanentRoleRules() {
    let app = XCUIApplication()
    app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = ProcessInfo.processInfo.environment["TF_DEBUG_TOKEN"]
    app.launch()
    app.buttons["Настройки"].tap()
    app.staticTexts["Команда"].tap()
    app.staticTexts["Архитектор"].tap()
    app.buttons["Как запускается роль"].tap()
    ["Роль", "Общее", "Задача", "План", "Чат", "Границы"].forEach {
        app.buttons[$0].tap()
        XCTAssertTrue(app.staticTexts[$0].exists)
    }
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.lifetime = .keepAlways
    add(attachment)
}
~~~

- [ ] **Step 2: Run with vault token and inspect attachment**

Run: TF_DEBUG_TOKEN=$(ssh maksim 'python3 ~/.Codex/vault-get.py --raw TASKFLOW_AGENT_TOKEN') xcodebuild test -project /Users/max/Проекты/TaskFlowNativeBuild/TaskFlow.xcodeproj -scheme TaskFlow -destination 'platform=iOS Simulator,id=ED3C7DF7-F895-45B6-8A28-F67C02362103' -only-testing:TaskFlowUITests/RoleRuntimeContextVisibilityUITests

Expected: PASS. Export the XCResult attachment with xcrun xcresulttool export attachments and inspect it before calling visual behaviour verified.

- [ ] **Step 3: Remove temporary test and regenerate**

Run: rm UITests/RoleRuntimeContextVisibilityUITests.swift && xcodegen generate && git diff --check

Expected: no temporary test remains and no whitespace errors exist.

- [ ] **Step 4: Record evidence**

Update task documentation with exact server, iOS and XCUITest results. If authentication/navigation cannot reach the screen without changing a session, record that gap rather than claiming visual verification.

## Plan Self-Review

- Spec coverage: Task 1 owns the six real layers, provenance, privacy and authorisation; Task 2 owns read-only tabs, unknown layers and error state; Task 3 owns owner-flow acceptance.
- Placeholder scan: every task has an exact file set, command and expected outcome.
- Type consistency: server and client use RoleRuntimeContext and RoleRuntimeContextLayer; iOS preserves layer IDs as strings.
- Review-focus coverage: override/fallback, auth/privacy are tested in Task 1; future layer and failure state are tested in Task 2; six-tab reachability is tested in Task 3.
