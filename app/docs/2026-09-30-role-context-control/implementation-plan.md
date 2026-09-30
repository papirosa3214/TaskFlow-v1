# Единый редактор контекста ролей — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for sequential execution or superpowers:subagent-driven-development if the owner explicitly selects delegation. Steps use checkbox syntax for tracking.

**Goal:** Владелец видит и редактирует действующие текстовые источники инструкций всех ролей; следующая соответствующая сборка запуска использует сохранённый текст.

**Architecture:** Каталог runtime-блоков + SQLite overrides и история. Общий resolver используется API редактора, заданиями, чатами, правилами инструментов и специальными путями Секретаря. Динамические данные и программные ограничения описываются отдельно.

**Tech Stack:** TypeScript/Fastify/better-sqlite3/Vitest, Python MCP/LiveKit, SwiftUI/XCTest/XCUITest.

**Spec:** [design.md](design.md).

## Global Constraints

- Разработка сервера: `/Users/max/Проекты/New-Todoist-server`; iOS: `/Users/max/Проекты/TaskFlowNativeBuild`; .110 — live-хост.
- Перед правкой добавить точные файлы в IN_PROGRESS scope соответствующего реестра; чужой dirty tree сохранять.
- Показ и запуск используют один источник; тексты не копируются в iOS.
- Личность остаётся в roles.prompt, не создаётся второй личный prompt.
- Override роли → override команды → исходный текст; допустимые scope задаёт каталог блока.
- Изменения не прерывают текущий ход и не стирают историю. Свежая инструкция действует в следующем запуске/ходе.
- Текстовая настройка не меняет tool schema, права, состояния и обработчики.
- Сохранение только владельцем, optimistic concurrency, журнал восстановления.
- Native SwiftUI без собственного tint/background/overlay/scale/рамок на системных компонентах.
- Визуальная проверка через XCUITest по accessibility, с XCTAttachment; действующий вход не менять.
- Выкладка и применение исправленных текстов на .110 требуют решения владельца; код редактора сначала сохраняет действующие дефолты.
- Документы задачи в этой папке. Старые ссылки сохраняются через индекс, документы не разбрасываются по новым папкам superpowers.

## Review Focus

1. После смены общего текста API и taskflow_rules не должны расходиться со стартовым промптом.
2. Сохранённая чат-сессия может нести прежние инструкции; UI показывает это, тест проверяет новый системный слой без удаления истории.
3. Конкурентная правка/сброс/восстановление возвращает 409 и сохраняет локальный черновик.
4. Отключённая и новая роль без fallback-файла доступны владельцу для настройки с точным source.
5. Секретарь, инструменты MCP и Pi system prompt не должны исчезнуть из manifest из-за отдельного runtime.

## Контракты

```ts
type ContextScope = "team" | `role:${string}`;
type ContextMode = "task" | "resume" | "plan" | "review" | "reply" | "chat" | "voice" | "summary";
type InstructionBlock = {
  id: string; group: string; title: string; source: string;
  modes: ContextMode[]; scopes: ContextScope[];
  editable: boolean; text: string; defaultText: string;
  disabled: boolean; version: number;
  effectiveScope: ContextScope | "default";
  placeholders: { name: string; required: boolean }[];
};
type InstructionMutation = {
  scope: ContextScope; expectedVersion: number;
  text: string; disabled: boolean;
};
type InstructionManifestEntry = {
  blockId: string; scope: ContextScope | "default";
  version: number; sha256: string; source: string;
};
```

API: GET `/api/roles/:role/runtime-context`; PATCH/DELETE `/api/roles/:role/runtime-context/:blockId`; GET `.../:blockId/history`; POST `.../:blockId/restore`. DELETE принимает scope/expectedVersion и снимает override. Restore принимает scope/expectedVersion/historyId и создаёт новую ревизию. Ответ чтения сохраняет legacy `layers` для прежнего клиента и добавляет `blocks`, `capabilities`, `canEdit`.

## Task 1: Полная инвентаризация фактического runtime

**Files:** создать `sources.md` в этой папке; читать server/src/runtime/{inProcessRun,PiRuntimeAdapter,roleRunAccess,taskContextBridge,secretaryVoiceBridge}.ts, server/src/lib/{secretaryReply,secretaryTaskSummary,ownerDraft}.ts, server/src/routes/{chats,ai}.ts, server/scripts/{mcp_server,task_context,task_context_bridge}.py, server/agents/secretary-voice/worker.py. Читать локальный установленный Pi dist/core/{system-prompt,resource-loader,compaction/compaction}.js и dist/cli/args.js, без изменения dependencies.

**Produces:** таблица block_id/source/channel/owner/modes/default_text_origin и список реальных loader-ресурсов. Каналы: system, user template, tool description, tool-returned rules, MCP initialize, memory/session, model sub-operation.

- [ ] По Graft построить карту; при отсутствии server graph использовать `graft build` для структуры, не заказывать LLM-индексацию. Проверить точные исходники по найденным spans.
- [ ] Установить подключение локальных/global AGENTS, SYSTEM.md, APPEND_SYSTEM.md, skills, extensions, prompt templates и Pi compaction. Читая live-конфиг, не печатать токены и секреты.
- [ ] Сопоставить источники задачи и чата; записать различия, не объявлять profiles неиспользуемыми там, где roleRunAccess читает их.
- [ ] Добавить voice, summary, приветствие голоса, user task-intake prompts, описания встроенных и MCP tools, инструкции initialize. Для existing owner prompts оставить нынешнее хранилище, подключить его в каталог.
- [ ] Проверить обнаруженные устаревшие ссылки на consultation и утверждение «памяти нет» по реальным данным/инструментам. Не удалять инструкцию только из-за возраста документа.
- [ ] Завершить sources.md перечислением каждого обнаруженного слоя и способом его управления; ни одного скрытого источника не помечать как проверенный без evidence.

## Task 2: Каталог, overrides, ревизии и шаблоны

**Files:** создать server/src/runtime/instructions/{catalog,store,templates,types}.ts, server/test/instructionStore.test.ts; изменить server/src/migrations.ts и server/src/roleRouting.ts. Новую миграцию назвать следующей свободной, сверив конец массива migrations (сейчас последняя 078).

**Consumes:** источники Task 1. **Produces:** `resolveInstruction(role, blockId): InstructionBlock`, `renderInstruction(role, blockId, values): {text, manifest}`, `saveInstruction(role, blockId, mutation, actorId)`, `resetInstruction(...)`, `instructionHistory(...)`, `restoreInstruction(...)`. Все формы мутации проверяют текущую ревизию атомарно.

- [ ] Создать failing tests:
```ts
it("isolates role overrides and resets to the team value", () => {
  saveInstruction("builder", "common.execution", {scope:"team",expectedVersion:0,text:"TEAM",disabled:false}, ownerId);
  saveInstruction("builder", "common.execution", {scope:"role:builder",expectedVersion:0,text:"BUILDER",disabled:false}, ownerId);
  expect(resolveInstruction("builder","common.execution").text).toBe("BUILDER");
  expect(resolveInstruction("qa","common.execution").text).toBe("TEAM");
});
```
- [ ] `npm test -- --run test/instructionStore.test.ts`: убедиться, что новый модуль отсутствует, а не тест падает от неверного окружения.
- [ ] Миграция: таблицы instruction_overrides(scope,block_id,text,disabled,version,updated_by,updated_at) и instruction_history(id,scope,block_id,text,disabled,operation,version,actor_id,created_at). Unique(scope,block_id), tombstone/revision сохранены после reset, чтобы reset не возвращал версию 0 и не создавал ABA-конфликт.
- [ ] Для roles.prompt история и контроль версии проходят через общий store, сама инструкция остаётся в roles. Existing patch роли использует тот же путь, чтобы сторонняя правка не обходила revision.
- [ ] Шаблоны заменяют только объявленные `{name}`; неизвестные placeholder → 422; отсутствующий обязательный → 422; текст ограничен 64 КБ на блок; disabled — явное значение, whitespace не означает reset.
- [ ] Проверить reset/restore, два сохранения с одной версией, чужой role scope, пользовательские фигурные скобки внутри JSON-примеров (не распознавать их как placeholder), отсутствующий fallback.
- [ ] Запустить tests и `npm run build`, коммитить только scope.

## Task 3: Owner API редактора

**Files:** server/src/routes/roles.ts, новый server/src/routes/role-runtime-context.ts, server/src/runtime/roleRuntimeContext.ts, server/test/roleRuntimeContext.test.ts. Использовать c0f9bbc как исходный diff; переносить изменения выборочно, не перезаписывать последующие commits main.

**Consumes:** Task 2 store; **Produces:** API выше и `buildRoleRuntimeContext(role)` из эффективных блоков.

- [ ] Failing test: unauthenticated GET → 401, обычный пользователь PATCH → 403, owner PATCH меняет block.text; stale expectedVersion → 409; неизвестная роль → 404; отключённая существующая роль доступна owner.
```ts
expect((await app.inject({method:"PATCH",url:"/api/roles/builder/runtime-context/common.execution",headers:auth(otherToken),payload:{scope:"team",expectedVersion:0,text:"x",disabled:false}})).statusCode).toBe(403);
```
- [ ] Реализовать handlers с isOwner, validate role/block/scope, transactional store. History читает только авторизованный владелец. Ответ не содержит сессий, задач, vault или MCP credentials.
- [ ] Собрать legacy layers из тех же blocks для совместимости; canEdit — фактические права запроса.
- [ ] Тесты GET/PATCH/DELETE/restore/history, rev conflicts, disabled и новая роль; `npm run build`; scope commit.

## Task 4: Подключить задачу, план, проверку и продолжение

**Files:** server/src/runtime/inProcessRun.ts, server/src/agentState.ts, server/src/routes/{agent-state,subtasks}.ts (только возврат текстовых rules), server/src/runtime/instructions/manifest.ts, server/test/instructionRuntime.test.ts. Точные дополнительные callers AGENT_RULES включить в scope после `graft callers`/полного поиска импортов.

**Produces:** `assembleRoleInstructions({role,mode,values})`, manifest переданный в запуск и сохранённый рядом с session metadata без содержимого задачи.

- [ ] Failing test подменяет createAgentSession/session.prompt и проверяет system/user: override реально попал в вызов, дефолт исчез, другая роль не изменилась.
```ts
expect(capturedSystemPrompt).toContain("OWNER_COMMON_OVERRIDE");
expect(capturedUserPrompt).toContain("OWNER_REVIEW_OVERRIDE");
expect(manifest.map(x=>x.blockId)).toContain("task.review");
```
- [ ] Извлечь defaultTaskPrompt, planSubtaskPrompt, resumePrompt, reviewPromptFor, replyPrompt, documentation, repo guidance в каталог с теми же дефолтами. Данные карточки остаются аргументами render, не settings.
- [ ] Заменить все возвраты AGENT_RULES эффективным текстом для вызывающей роли; не менять canTransition и refusal-код. taskflow_rules и claim/state/subtask ответы берут resolver.
- [ ] Описания taskflowTools и встроенных tools подключить к каталогу; сохранить имена, schema, execute. Runtime supplemental system layers перечислить в manifest.
- [ ] Проверить шесть task modes, сессию с историей, input.prompt override caller, manifest версии, изоляцию изменения описания tool от handler/schema.
- [ ] Регрессии inProcessRun, roleRunQueue, planSubtaskAdmission, state/subtasks; build; scope commit.

## Task 5: Чат, MCP, внешние ресурсы и компакция

**Files:** server/src/routes/chats.ts, server/src/runtime/PiRuntimeAdapter.ts, server/src/runtime/roleRunAccess.ts, новый server/src/runtime/instructions/chatResources.ts, server/scripts/mcp_server.py, server/test/{chat-session-runtime,instructionChat}.test.ts, server/scripts/test_instruction_mcp.py.

**Consumes:** resolver/manifest и Task 1 inventory. **Produces:** `prepareChatInstructions(role, runId)` со снимком текстов конкретного хода и manifest; временные snapshots не содержат credentials и удаляются после завершения.

- [ ] Failing test проверяет RpcClient args/options + prompt: эффективные system/chat/MCP/tool тексты совпали с редактором, история осталась.
- [ ] Передать явный system prompt из resolver вместо неучтённого Pi default. Для существующих auto-discovered AGENTS/skills/extensions применить явный manifest загрузки: не отключать действующие ресурсы молча. Resource content виден как отдельный управляемый слой; snapshot override не переписывает чужие global files.
- [ ] MCP initialize instructions и tools/list description читают snapshot текущего run; taskflow_rules продолжает читать актуальную серверную инструкцию. Шаблон RPC подключения с токеном не отдаётся в editor/manifest.
- [ ] Pi compaction text и branch-summary guidance перечислить по реальным включённым путям. Управляемые TaskFlow wrappers используют catalog; для upstream текста применить поддержанный SDK hook/customInstructions, без патча node_modules. Если API не поддерживает полную замену, отображать точное ограничение и не маркировать блок editable.
- [ ] Тест: один слой возвращается system и MCP, соседний scope не затронут; snapshot не меняется посреди хода; следующий ход получает новую версию; cleanup при abort/timeout/error.
- [ ] Запустить chat tests, Python MCP tests современным Python, build; scope commit.

## Task 6: Все модельные пути Секретаря

**Files:** server/src/lib/{secretaryReply,secretaryTaskSummary,ownerDraft}.ts, server/src/routes/ai.ts (только существующие owner prompt resolvers), server/src/runtime/secretaryVoiceBridge.ts, server/agents/secretary-voice/{worker,test_worker}.py, server/test/{secretaryVoiceBridge,secretaryTaskSummary,instructionSecretary}.test.ts.

**Produces:** эффективные secretary.chat, secretary.quickReplies, secretary.voice, secretary.greeting, secretary.summary и alias существующих owner task-intake settings.

- [ ] Failing tests подменяют startChatRun/callUnifiedAi/голосовую модель, проверяют именно полученную инструкцию, а не только GET endpoint.
- [ ] Разделить динамическую history/userText от текста secretaryReply; quick replies protocol оставить машинным контрактом, пользовательская инструкция управляется блоком.
- [ ] Unix bridge добавить чтение voice instruction через GET внутреннего socket до каждой новой голосовой сессии. owner checks для mutating tools остаются. Недоступный fetch явно логируется; источник fallback отображён, отказ не выдаётся за применение override.
- [ ] Voice worker получает snapshot инструкций и manifest в новой сессии; приветствие тоже catalog block. Не менять активный звонок ради новой настройки.
- [ ] Сводка и постановка: общий resolver включает существующие owner prompts без второго хранилища; даты/users JSON остаются динамическими значениями.
- [ ] Тесты chat/voice/summary/intake, прежние secretarial tests, Python unittest; build; scope commit.

## Task 7: Native редактор и история

**Files:** Sources/Core/Models/RoleRuntimeContext.swift, Sources/Core/Networking/APIClient+Roles.swift, Sources/Features/Chat/{RoleRuntimeContextSheet,RoleEditorSheet}.swift; новые Sources/Features/Chat/{RoleInstructionEditor,RoleInstructionHistorySheet}.swift; Tests/{RoleRuntimeContextTests,RoleInstructionDraftTests}.swift. Все файлы заранее перечислить в IN_PROGRESS scope.

**Produces:** DTO blocks/history/capabilities; API save/reset/restore; состояние draft/dirty/version/conflict. API method signatures: `saveRoleInstruction(role:blockID:scope:expectedVersion:text:disabled:)`, `resetRoleInstruction(...)`, `roleInstructionHistory(...)`, `restoreRoleInstruction(...)`.

- [ ] Failing decoding tests: future group, disabled, missing legacy-compatible optional fields, canEdit=false. Draft test после 409 сохраняет локальный текст и отдельно держит current server version.
```swift
XCTAssertEqual(draft.text, "Несохранённая правка")
XCTAssertTrue(draft.hasConflict)
```
- [ ] Вкладки групп строятся по ответу; в каждой список блоков. Native navigation + Picker/TextEditor, не втискивать весь каталог в один тесный segmented control.
- [ ] У блока effective/default/source/modes/scope/placeholders и кнопки сохранить/отменить/вернуть исходное/история. Team scope сообщает число затронутых ролей; unknown group остаётся видимой.
- [ ] Save/reset/restore не закрывает экран при ошибке; локальный draft сохраняется. Dismiss dirty предупреждает о несохранённом тексте. Capability/schema не получают текстовый редактор.
- [ ] Существующий roles.prompt editor и новый блок личности синхронизировать после сохранения/сброса, чтобы старый draft не перезаписал новую инструкцию при закрытии родительской формы.
- [ ] `xcodegen generate`; targeted XCTest; TaskFlow build на iPhone 17 Pro simulator; scope commit только этих файлов.

## Task 8: Приёмка, аудит инструкций и передача

**Files:** временный UITests/RoleInstructionControlUITests.swift; docs в этой папке: sources.md, text-audit.md, verification.md; registry обоих репозиториев.

- [ ] Временный XCUITest с локальным изолированным backend fixture: пройти Команда → роль → все вкладки, сохранить override, проверить повторную загрузку, 409/draft, историю и восстановление. Использовать accessibilityIdentifier, XCTAttachment. Удалить temporary test после выгрузки attachments. Живые settings не менять тестом.
- [ ] `PATH=/opt/homebrew/bin:$PATH npm test`, `npm run build`, соответствующие Python tests, XCTest, TaskFlow build; inspect attachment. Доказательства local/real runtime различать.
- [ ] Подготовить text-audit.md с before/after для каждого обнаруженного устаревшего текста. Проверить противоречия «памяти нет», result envelope чата, MCP/AGENT_RULES review, отсутствующие consultation tools. Не заменять личности семи ролей одной универсальной инструкцией.
- [ ] Согласовать именно diff текстов и deploy; указать сохраняемые активные сессии/звонки и какой новый ход получит настройки.
- [ ] После разрешённой выкладки сверить API editor и manifest реальной задачи/чата/Секретаря. Если реальная проверка требует мутации прод-задачи, согласовать выбранный сценарий отдельно.
- [ ] verification.md: что реализовано, какие paths проверены реально, где только tests; точные commits, команды и runtime gaps. Registry → REVIEW, не объявлять полноту до покрытия sources.md.

## Самопроверка плана

Spec coverage: хранение/API — 2–3; все task modes — 4; чат/Pi/MCP/tools — 5; Секретарь — 6; редактор — 7; audit и приёмка — 8. Inventory 1 задаёт перечень источников, который остальные задачи должны закрыть.

Review focus: единый текст taskflow_rules — 4–5; история чат-сессии — 5; конкуренция/draft — 2–3/7; disabled/new role — 2–3; особые источники — 1/5–6. Контракты функций и API описаны выше, product defaults при подключении не переписываются.

Рекомендованный способ: последовательно в этой сессии. Изменения зависят от единого resolver и схемы; параллельная правка одних runtime-файлов создаст лишние конфликты. Делегирование без выбора владельца не запускается.
