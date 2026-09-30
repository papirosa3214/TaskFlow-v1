# Role Dispatch End-to-End Implementation Plan

> Исполнять по задачам: сначала красный тест, затем минимальная правка, затем проверка и отдельный коммит.

**Goal:** Соединить существующие iOS, TaskFlow Server и Pi Harness в один детерминированный поток: надиктовка владельца превращается в одну карточку либо дерево, восемь ролей автоматически занимают подходящие позиции, ручной режим ждёт проверки и флага владельца, автоматический режим без участия владельца валидирует дерево, поднимает флаг и ставит работу в очередь, а Pi перед стартом получает отдельный справочный контекст.

**Architecture:** Сервер остаётся единственным владельцем состояния и оркестрации. Постановка, назначение роли, допуск дерева к запуску и сбор справки — четыре раздельные стадии с явными типами и тестами. Существующие role prompts, role skills, Pi MCP profiles, routing и attempt ladder не переносятся: новый фасад только собирает их в единый runtime-профиль. iOS показывает серверное состояние и вызывает атомарные серверные операции; Pi остаётся одной скрытой runtime-оболочкой для всех логических ролей.

**Tech Stack:** Swift 6 / SwiftUI / XCTest; Node.js 22 / TypeScript / Fastify / SQLite / Vitest; Python 3 / unittest; Pi Agent; RAGFlow KB и Mnemosyne на `.110`; systemd.

**Дизайн:** [DESIGN.md](DESIGN.md)

## Global Constraints

- Канонический iOS-клиент: `/Users/max/Проекты/TaskFlowNativeBuild`.
- Канонический сервер: `maksim@192.168.1.110:/home/maksim/Проекты/New-Todoist`.
- Перед каждым этапом занимать точный `IN_PROGRESS` scope в `AGENT-WORK-SCOPES.md`; не менять файлы вне него.
- Сначала тест, затем минимальная реализация, затем полный релевантный набор тестов и отдельный коммит.
- Не создавать вторую систему ролей. Канонические идентификаторы: `researcher`, `analyst`, `synthesizer`, `critic_verifier`, `architect`, `builder`, `qa`, `designer`.
- Не превращать Pi, Секретаря или исторические agent accounts в элементы команды либо доступных исполнителей. Исторические ссылки в старых карточках сохраняются.
- Снимок режима intake делается на сервере в момент приёма сообщения. Переключение тумблера после отправки не меняет уже начавшийся разбор.
- `task statement` — первичный контракт. Reference context собирается только после флага и не может менять текст карточки, дерево, проект, срок, приоритет, роль или флаг.
- Автоматический режим не создаёт пользовательского черновика и не ждёт UI. Невалидное дерево не запускается частично.
- Недоступный Pi не снимает валидный флаг: работа остаётся в очереди и подхватывается после восстановления runtime.
- Во время реализации не деплоить непроверенную промежуточную схему на живую БД. Перед миграцией сделать датированную копию SQLite.

## Canonical Contracts

```ts
export type TaskIntakeMode = "manual" | "automatic";

export type RoleId =
  | "researcher" | "analyst" | "synthesizer" | "critic_verifier"
  | "architect" | "builder" | "qa" | "designer";

export interface RoleRuntimeProfile {
  role: RoleId;
  roleAccountId: string;
  displayName: string;
  prompt: string;
  skills: string[];
  tools: string[];
  mcpProfilePath: string;
  permissions: string[];
  model: string;
  defaultShell: string;
  fallbacks: string[];
  attemptPolicy: { maxAttempts: number; retryableReasons: string[] };
  configValid: boolean;
  configErrors: string[];
  availability: "online" | "offline" | "misconfigured";
  activeTaskId: string | null;
  lastActivityAt: string | null;
}

export interface IntakeResult {
  draftId: string;
  mode: TaskIntakeMode;
  rootTaskId: string;
  taskIds: string[];
  state: "awaiting_owner" | "queued" | "clarification_required";
  clarificationQuestion: string | null;
}

export interface ReferenceItem {
  sourceKind: "task" | "kb" | "mnemosyne" | "repository";
  sourceName: string;
  author: string | null;
  createdAt: string | null;
  updatedAt: string | null;
  verifiedAt: string | null;
  primaryReference: string | null;
  knowledgeType: "stable" | "changeable";
  applicability: "direct" | "supporting" | "unclear";
  content: string;
}
```

The TypeScript JSON keys are camelCase at the API boundary. SQLite stays snake_case. Swift models use camelCase plus explicit `CodingKeys`. Python keeps snake_case internally and serializes the exact reference packet expected by Pi.

---

## Task 1: Persist the owner intake mode and the per-message snapshot

**Files:**

- Modify: server `server/src/migrations.ts`
- Modify: server `server/src/db.ts`
- Create: server `server/src/routes/task-intake.ts`
- Modify: server `server/src/index.ts`
- Create: server `server/test/task-intake.test.ts`

### Steps

- [ ] Add failing migration tests for an existing database and a fresh database. Assert migration `037_task_intake_pipeline` adds:

  ```sql
  ALTER TABLE users ADD COLUMN task_intake_mode TEXT NOT NULL DEFAULT 'manual'
    CHECK (task_intake_mode IN ('manual', 'automatic'));
  ALTER TABLE chat_task_drafts ADD COLUMN intake_mode TEXT NOT NULL DEFAULT 'manual'
    CHECK (intake_mode IN ('manual', 'automatic'));
  ALTER TABLE tasks ADD COLUMN needs_clarification INTEGER NOT NULL DEFAULT 0;
  ALTER TABLE tasks ADD COLUMN clarification_question TEXT;
  ```

- [ ] Run `cd server && npm test -- task-intake.test.ts`; confirm the new columns/routes fail before implementation.
- [ ] Implement owner-only routes:

  ```text
  GET   /api/task-intake/settings -> { mode: "manual" | "automatic" }
  PATCH /api/task-intake/settings body { mode } -> { mode }
  ```

  Reject unknown modes with 400 and non-owner callers with 403. Do not store this in `UserDefaults` as the source of truth.

- [ ] Add a transaction helper that reads `users.task_intake_mode` and inserts `chat_task_drafts.intake_mode` before model work begins. Return that stored value to the caller; later stages must never reread the mutable user setting for the same message.
- [ ] Test default manual, persistence across app/server reload, owner authorization, invalid value, and snapshot stability when the setting changes after the draft row was inserted.
- [ ] Run `cd server && npm test -- task-intake.test.ts && npm run build` and expect all tests plus TypeScript build to pass.
- [ ] Commit: `feat(server): persist task intake mode`

## Task 2: Expose one runtime façade for the eight roles

**Files:**

- Create: server `server/src/lib/roleConfig.ts`
- Modify: server `server/src/routes/roles.ts`
- Modify: server `server/src/roleRouting.ts`
- Modify: server `server/test/roles.test.ts`

### Steps

- [ ] Extend `roles.test.ts` first. Assert `GET /api/roles` returns exactly the eight canonical roles in the configured order, never Pi, Secretary, owner, or historic agents, and every row matches `RoleRuntimeProfile`.
- [ ] Add failure cases for missing role prompt, malformed `~/.pi/agent/taskflow-profiles/<role>.json`, unknown skill, missing role account and invalid routing entry. The endpoint must return the role with `configValid=false`, `availability="misconfigured"`, and concrete `configErrors`, not silently invent defaults.
- [ ] Run `cd server && npm test -- roles.test.ts`; confirm the new contract fails.
- [ ] Move the current inline assembly from `routes/roles.ts` into:

  ```ts
  export function listRoleRuntimeProfiles(): RoleRuntimeProfile[];
  export function getRoleRuntimeProfile(role: RoleId): RoleRuntimeProfile;
  export function assertExecutableRole(role: RoleId): RoleRuntimeProfile;
  ```

  Read, do not duplicate: `server/scripts/role-prompts/*.md`, `role_skills`, `~/.pi/agent/taskflow-profiles/*.json`, and `loadRoleRouting()`.

- [ ] Map each role to its existing system `users` row and expose `roleAccountId`; derive runtime availability from Pi heartbeat/runtime state without exposing Pi itself as a role.
- [ ] Keep existing role detail routes backward-compatible where used, but make them delegate to the façade. Do not turn the current read-only prompt route into a second prompt store.
- [ ] Run `cd server && npm test -- roles.test.ts && npm run build`.
- [ ] Commit: `refactor(server): unify role runtime configuration`

## Task 3: Separate semantic role assignment from the ready flag

**Files:**

- Create: server `server/src/lib/roleAssignment.ts`
- Modify: server `server/src/enricher.ts`
- Modify: server `server/src/routes/enrichment.ts`
- Modify: server `server/test/enrichment.test.ts`
- Create: server `server/test/role-assignment.test.ts`

### Steps

- [ ] Write failing tests for `assignRoleToTask(taskId, options)`:

  ```ts
  type AssignmentOptions = { overwrite: boolean };
  type AssignmentResult = {
    taskId: string;
    role: RoleId;
    roleAccountId: string;
    method: "deterministic" | "semantic";
    score: number | null;
  };
  ```

  Cover deterministic match, semantic fallback through existing `role_embeddings`, preservation of an owner-selected assignee when `overwrite=false`, explicit override only when authorized, and no `ready_for_pickup` mutation.

- [ ] Run the two focused Vitest files and confirm the existing enrichment coupling makes the new assertions fail.
- [ ] Replace the legacy profile map (`claude_bot`, `hermes`, and peers) with the eight canonical `RoleId` values. Deterministic rules remain the first pass; semantic similarity is the fallback, not a competing background writer.
- [ ] Persist only the chosen role account into `tasks.assignee_id` and an auditable assignment event/metadata already supported by the event system. Labels may mirror the role for compatibility but are not the source of truth.
- [ ] Change `/api/tasks/:id/enrich` to call the service without lifting the flag. Preserve its response shape where possible and explicitly return the chosen role.
- [ ] Run `cd server && npm test -- enrichment.test.ts role-assignment.test.ts && npm run build`.
- [ ] Commit: `feat(server): assign canonical roles without starting work`

## Task 4: Make tree validation and flagging atomic

**Files:**

- Create: server `server/src/lib/taskAdmission.ts`
- Modify: server `server/src/routes/tasks.ts`
- Modify: server `server/src/index.ts`
- Create: server `server/test/task-admission.test.ts`
- Modify: server `server/test/tasks.test.ts`

### Steps

- [ ] Write failing tests for:

  ```text
  POST /api/tasks/:rootId/ready-tree
  body { "ready": true }
  -> { rootTaskId, taskIds, ready: true, queued: true }
  ```

  Test a single task, parent plus children, nested descendants, an already-ready idempotent call, and `{ready:false}`.

- [ ] Add all-or-nothing rejection tests: executable leaf without a canonical role account, role with invalid runtime config, dependency pointing outside the tree, missing dependency, cycle, clarification marker, archived/deleted task, and caller without owner authority. Assert no task in the tree changes on failure.
- [ ] Define `validateTaskTree(rootId)` to return the complete tree, executable leaves and topological order. Parent containers may carry the visual ready flag but must never be claimed as work when they only summarize children.
- [ ] In one SQLite transaction update all tree readiness fields (`ready_for_pickup`, `ready_set_at`, `ready_set_by`). Emit realtime/task events only after commit; a retry must not duplicate meaningful events.
- [ ] Reuse the same service from the existing per-task PATCH ready handler so old clients keep working, but direct them through single-task validation.
- [ ] Verify Pi offline is not an admission error: `availability="offline"` queues a valid tree; only `misconfigured` blocks it.
- [ ] Run `cd server && npm test -- task-admission.test.ts tasks.test.ts && npm run build`.
- [ ] Commit: `feat(server): admit task trees atomically`

## Task 5: Implement the two-layer task-intake prompt and strict parsing

**Files:**

- Modify: server `server/src/routes/ai.ts`
- Create: server `server/src/lib/taskIntake.ts`
- Create: server `server/test/task-intake-ai.test.ts`
- Modify: server `server/test/ownerDictation.test.ts`

### Steps

- [ ] Move dictation parsing behind a testable interface:

  ```ts
  export async function structureDictationToCards(
    rawText: string,
    projects: Array<{ id: string; name: string }>,
    options: AiOptions & { ownerId: string },
  ): Promise<DictationCards>;
  ```

- [ ] Write failing tests proving that server contract and owner prompt are separate layers. Read `user_ai_prompts` scope `task_intake`; compose it as an owner preference section after the immutable JSON/schema rules. The owner addition may guide wording and decomposition but cannot alter allowed fields or inject reference context.
- [ ] Replace the current permissive fallback (“bad children means one card”) for automatic admission with a strict validator. Validation must distinguish:

  ```ts
  type ParsedIntake =
    | { kind: "valid"; cards: DictationCards }
    | { kind: "clarification"; question: string; reason: string };
  ```

  Manual mode may still materialize a clearly marked clarification card for owner repair. Automatic mode must not start a partial/fallback tree.

- [ ] Test one result vs parent/children, `after` dependency indexes, nonexistent project, contradictory deadlines, empty titles, invalid JSON, uncertain decomposition, and prompt-injection text inside dictation. Assert only projects from the supplied list can be selected.
- [ ] Keep `extract_tasks` and `journal_assist` scopes unchanged. Add `task_intake` to existing prompt CRUD via its already generic scope validation; do not add a second prompt table.
- [ ] Run `cd server && npm test -- task-intake-ai.test.ts ownerDictation.test.ts && npm run build`.
- [ ] Commit: `feat(server): add deterministic two-layer task intake`

## Task 6: Orchestrate manual and automatic owner-chat intake

**Files:**

- Modify: server `server/src/lib/ownerDraft.ts`
- Modify: server `server/src/routes/chat.ts`
- Modify: server `server/test/ownerDictation.test.ts`
- Create: server `server/test/owner-intake-e2e.test.ts`

### Steps

- [ ] Add integration tests around the owner channel. At message receipt, assert the mode is stored before the mocked model promise resolves.
- [ ] Manual-mode test: create card/tree in one transaction, persist real `task_dependencies`, run role assignment on executable leaves, leave all flags down, and send a Secretary message with the root link plus a precise “проверьте и поднимите флаг” status.
- [ ] Automatic-mode test: create the same committed cards, assign roles, validate the whole tree, atomically raise flags and return `state="queued"`. Assert there is no draft-review/open-confirmation event and no owner action is required.
- [ ] Add tests for explicit assignee preservation. If the owner selected a role before flagging in manual mode, admission uses it; if no one is selected, the automatic assignment stands.
- [ ] Add clarification tests. Manual: create a root marked `needs_clarification=1`, never flag it, and show the question. Automatic: store the intake result/error for audit, do not create or flag a partial executable tree, and have Secretary report the concrete reason/question.
- [ ] Make processing idempotent by the existing draft/message identity. Re-delivery must return the original `IntakeResult`, not duplicate tasks, dependencies, assignments, or flags.
- [ ] Ensure chat request latency remains independent of model latency if that is the existing API contract, while failures are surfaced by the Secretary and draft state.
- [ ] Run `cd server && npm test -- ownerDictation.test.ts owner-intake-e2e.test.ts && npm run build`.
- [ ] Commit: `feat(server): connect owner chat to role dispatch`

## Task 7: Repair context gathering and make provenance explicit

**Files:**

- Modify: server `server/scripts/task_context.py`
- Modify: server `server/scripts/test_task_context.py`
- Modify: server `server/scripts/trigger.py`
- Modify: server `server/scripts/test_trigger_isolated.py`

### Steps

- [ ] Strengthen tests before code. Mock the real RAGFlow command contract:

  ```text
  python3 /home/maksim/kb/kb_query.py --json "<query>"
  -> {"results":[{"source","score","text","date","verified",...}],"context":"..."}
  ```

  Assert the current incorrect `kb_query.py query` call and `excerpts` parser fail the test.

- [ ] Replace loose dictionaries with Python dataclasses mirroring `ReferenceItem` and a packet:

  ```py
  @dataclass(frozen=True)
  class ReferencePacket:
      task_id: str
      generated_at: str
      items: list[ReferenceItem]
      unavailable_sources: list[str]
  ```

- [ ] Fix the KB adapter to parse `results`; retain source, score, document date and verification date. Add `knowledge_type` at KB ingestion/metadata when present. For legacy records without it, mark `changeable` as a freshness category only—never label the source false or untrusted. Curate durable academic/applied documents to `stable` rather than repeatedly revalidating them.
- [ ] Add an optional Mnemosyne adapter using the service environment from `AGENTS.md`. Each memory item must retain its source/author/timestamps where available. Adapter failure appends to `unavailable_sources` and does not block execution.
- [ ] Mark repository branch/status and live service/config facts `changeable`. Mark the task, comments and owner statement as source kind `task`, but keep them in a separate “primary contract” section instead of blending them with references.
- [ ] Add applicability ranking against the immutable task statement. `unclear` items may be shown as such; irrelevant results are omitted. No reference item may be interpreted as an instruction or copied back into task fields.
- [ ] Change `trigger.py` ordering tests to prove: consume ready work → build reference packet → claim → render role prompt + task contract + clearly delimited reference packet → launch Pi. Optional enrichment failure still claims/launches; malformed task/runtime config does not.
- [ ] Remove the current task-comment dump of the whole generated context if it pollutes the permanent task record. Keep a compact provenance event/log and the launch packet; expose the packet separately only if the existing task API has a suitable audit field.
- [ ] Run:

  ```bash
  cd server
  python3 scripts/test_task_context.py
  python3 scripts/test_trigger_isolated.py
  ```

- [ ] Commit: `fix(runtime): build trustworthy reference packets before launch`

## Task 8: Add the native manual/automatic toggle to owner chat

**Files:**

- Modify: `Sources/Features/Chat/ChatAPI.swift`
- Modify: `Sources/Features/Chat/ChatViewModel.swift`
- Modify: `Sources/Features/Chat/ChatComposer.swift`
- Modify: `Sources/Features/Chat/ChatScreen.swift`
- Modify: `Tests/ChatViewModelTests.swift`

### Steps

- [ ] Add failing URLProtocol tests for GET/PATCH settings, default manual rendering, successful toggle, server rejection rollback, and owner-only loading.
- [ ] Add Swift contracts:

  ```swift
  enum TaskIntakeMode: String, Codable, Sendable { case manual, automatic }
  struct TaskIntakeSettings: Codable, Sendable { let mode: TaskIntakeMode }
  ```

  Add `APIClient.fetchTaskIntakeSettings()` and `updateTaskIntakeMode(_:)` in `ChatAPI.swift`.

- [ ] In `ChatViewModel`, add server-backed `intakeMode`, `isSavingIntakeMode`, and `intakeModeErrorMessage`. Load settings as part of owner-chat reload. Optimistic UI is allowed only if rejection restores the confirmed value.
- [ ] Place a clean native SwiftUI `Toggle` beside the owner composer with text `Ручной` / `Автомат`. Keep the system keyboard and its dictation. Remove the dead custom microphone affordance; do not add tint, custom background, overlay, scale effect, frame imitation, or custom material to the system control.
- [ ] Update owner empty-state/help copy: manual explains review + flag; automatic says the task is created, assigned and queued without confirmation.
- [ ] Run the focused iOS tests, then the simulator build:

  ```bash
  xcodegen generate
  xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:TaskFlowTests/ChatViewModelTests test
  xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
  ```

- [ ] Commit: `feat(ios): add owner task intake mode toggle`

## Task 9: Replace the Team UI and new assignee pickers with roles

**Files:**

- Create: `Sources/Core/Models/RoleDetails.swift`
- Create: `Sources/Core/Networking/APIClient+Roles.swift`
- Create: `Sources/Features/Chat/RolesViewModel.swift`
- Create: `Sources/Features/Chat/RoleRow.swift`
- Modify: `Sources/Features/Chat/AgentsScreen.swift`
- Modify: `Sources/Features/Task/TaskFormViewModel.swift`
- Modify: `Sources/Features/Task/TaskFormScreen.swift`
- Modify: `Sources/Features/Task/QuickAddTaskView.swift`
- Create: `Tests/RolesViewModelTests.swift`
- Modify: `Tests/TaskFormViewModelTests.swift`

### Steps

- [ ] Write decoding and view-model tests asserting exactly the server-provided eight roles, stable display order, prompt/skills/tools/MCP/model/fallback/attempt/config status, and role account IDs.
- [ ] Add `RoleDetails` matching the canonical API contract and `APIClient.roles()` / `role(id:)`.
- [ ] Replace the contents of `AgentsScreen` with a roles-only screen backed by `RolesViewModel`. Remove create/delete/rename/token actions and do not display Pi, Secretary, owner, or historic agents.
- [ ] Build `RoleRow` as a read-only integration view of the existing configuration: role status, active task, prompt, skills, MCP/tools, model and fallbacks. Configuration mutation remains in its canonical files/routes until a separately specified editor exists.
- [ ] Change new-task and edit-task assignee pickers to role choices, posting `roleAccountId` as `assignee_id`. Keep a currently assigned historic agent visible on an old task as a non-selectable legacy value until the owner chooses a role; never erase history during decode/save.
- [ ] Do **not** replace `/agents` in Today/Upcoming historical classification providers: those lists still need to recognize old agent-owned tasks.
- [ ] Leave obsolete `AgentRow`, `AgentsViewModel`, and agent-token code unreferenced first. Delete files only after `rg` proves no live imports and Xcode project regeneration removes them safely.
- [ ] Run focused model/view-model tests and a full simulator build.
- [ ] Commit: `feat(ios): present canonical roles as the team`

## Task 10: Use atomic ready-tree admission from iOS

**Files:**

- Modify: `Sources/Core/Networking/APIClient+Tasks.swift`
- Modify: `Sources/Features/Task/TaskFormViewModel.swift`
- Modify: `Sources/Features/Task/TaskFormScreen.swift`
- Modify: `Sources/Features/Task/QuickAddTaskView.swift`
- Modify: `Tests/TaskFormViewModelTests.swift`

### Steps

- [ ] Add a failing regression test demonstrating the current parent-then-children loop can leave a partially flagged tree after the second request fails.
- [ ] Add `APIClient.setTaskTreeReady(rootTaskId:ready:)` for the new endpoint and decode the returned task IDs/state.
- [ ] Replace sequential child PATCHes in `toggleReadyFlag` with one atomic call. Reload the affected root/tree and shared stores only after success; on failure preserve displayed state and show the server validation reason.
- [ ] Disable flagging while a task has `needsClarification`; surface `clarificationQuestion` in the card without hiding the original statement.
- [ ] Verify explicit owner reassignment followed by flagging uses the newly chosen role and does not rerun assignment with overwrite.
- [ ] Run `TaskFormViewModelTests`, then full iOS tests/build.
- [ ] Commit: `feat(ios): flag task trees atomically`

## Task 11: Cross-layer contract and regression verification

**Files:**

- Create: server `server/test/role-dispatch-contract.test.ts`
- Create: `Tests/RoleDispatchContractTests.swift`
- Modify only if failures expose a contract defect in files already scoped by Tasks 1–10.

### Steps

- [ ] Add checked JSON fixtures for `RoleRuntimeProfile`, intake settings, intake result, admission success and admission rejection. Decode the same fixture expectations in TypeScript and Swift to catch snake/camel-case drift.
- [ ] Run the complete server suite:

  ```bash
  cd /home/maksim/Проекты/New-Todoist/server
  npm test
  npm run build
  python3 scripts/test_task_context.py
  python3 scripts/test_trigger_isolated.py
  ```

- [ ] Run the complete iOS suite and build on the actually installed simulator destination. If `iPhone 17 Pro` is unavailable, resolve an installed destination with `xcrun simctl list devices available`; record the exact replacement instead of silently skipping.
- [ ] Run `rg` checks proving production iOS Team/new assignee paths no longer call `/api/agents`, while historical task classification still does.
- [ ] Run `git diff --check` in both repositories and inspect diffs for unrelated user changes.
- [ ] Commit: `test: cover role dispatch contracts end to end`

## Task 12: Safe rollout on `.110` and live end-to-end acceptance

**Files:**

- Modify existing TaskFlow project documentation through its API/UI (no throwaway local report).
- Create/update one KB lesson under `/home/maksim/kb/lessons/` only if implementation yields a reusable recipe or repeatable failure analysis, then ingest it with `kb_add.py`.

### Steps

- [ ] Query KB once more for fresh deployment/runtime lessons immediately before rollout.
- [ ] Back up the exact production SQLite file to a dated, explicit sibling path and verify the copy opens with `PRAGMA integrity_check`; do not use a broad or unresolved delete/copy target.
- [ ] Deploy server files, install dependencies only if lockfile changed, run migration 037, and verify all eight role profiles with a read-only diagnostic before service restart.
- [ ] Restart `taskflow-server.service` and `taskflow-trigger.service`; inspect status and recent logs. Confirm the trigger is idle/healthy before creating an acceptance task.
- [ ] Manual acceptance:

  1. Set `Ручной` in iOS.
  2. Dictate one multi-result request using the system keyboard.
  3. Confirm parent/children and real dependency edges appear, roles are preassigned, all flags remain down.
  4. Change one role manually and raise the root flag.
  5. Confirm atomic admission, queued state, role preservation, separate reference packet and Pi launch.

- [ ] Automatic acceptance:

  1. Set `Автомат` and send a valid single-task dictation.
  2. Confirm no review/draft interaction appears; card, role and flag are created and work enters the queue.
  3. Stop Pi trigger briefly through the controlled service operation, send another valid task, confirm its flag remains raised/queued, restore the service and confirm pickup.
  4. Send an intentionally ambiguous decomposition request; confirm no partial work starts and Secretary gives the clarification reason.

- [ ] Context acceptance: inspect one stable KB fact, one changeable service/repository fact and one irrelevant hit. Confirm provenance/dates/type are visible, stable data is not falsely called untrusted, changeable data exposes freshness, irrelevant data is omitted, and none changes the card or role.
- [ ] Record the final behavior and operational locations in the existing TaskFlow project documentation before moving the implementation card to review.
- [ ] If a reusable lesson was found, write one lesson file, ingest it with `python3 ~/kb/kb_add.py <exact-file>`, and verify retrieval with `kb_query.py --get`. Do not duplicate the same facts into Mnemosyne and project docs.
- [ ] Final commit after documentation references: `docs: record role dispatch rollout`

## Definition of Done

- iOS Team contains exactly eight logical roles; Pi/Secretary/history are absent from new selection UI.
- Every role row is backed by the real prompt, skills, MCP/tools, permissions, model, fallback and attempt configuration used by Pi.
- Owner-chat dictation deterministically yields one task or a valid tree with dependencies.
- Manual mode stops after cards + role placement; owner can override and atomically flag.
- Automatic mode requires no draft review and immediately queues a valid result.
- Invalid/ambiguous automatic intake starts nothing and reports a concrete clarification.
- Pi offline means queued, not rejected or silently unflagged.
- Reference context is gathered only after flagging, preserves provenance/freshness/type/applicability, is delimited as reference material, and never mutates the task contract.
- Full server, Python and iOS suites pass; live manual, automatic, offline-queue and clarification scenarios are recorded in TaskFlow project documentation.

## Execution Choice

1. **Subagent-driven (recommended):** execute one task at a time in this session with a fresh worker and review gates between tasks.
2. **Inline execution:** execute this plan sequentially in the current task, stopping at the same test/commit/review checkpoints.
