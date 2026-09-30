# Живая лента шагов роли в чате — Implementation Plan

> Исполнять по задачам: сначала красный тест, затем минимальная правка, затем проверка и отдельный коммит.

**Goal:** Пока роль отвечает в 1:1-чате, вместо статичных точек «печатает» владелец видит короткую живую подпись с тем, что роль делает прямо сейчас (читает файл, правит код, выполняет команду, ищет).

**Architecture:** Сервер (`.110`, репозиторий `~/Проекты/New-Todoist/server`) расширяет уже существующий сигнал `chats:typing` необязательным полем `tool`, подсматривая события хода роли изнутри `startChatRun` (`PiRuntimeAdapter.ts`), куда добавляется колбэк `onStep`. iOS-клиент (этот репозиторий) добавляет поле `tool` в разбор `chats:typing` и рендерит по нему строку шага вместо точек — только в 1:1-чате с ролью, групповой чат не трогаем.

**Tech Stack:** Сервер — TypeScript/Fastify/vitest (`~/Проекты/New-Todoist/server`, доступен только по `ssh maksim`). Клиент — Swift/SwiftUI, XCTest, SnapshotTesting (этот репозиторий, `TaskFlowNativeBuild`).

**Дизайн:** [DESIGN.md](DESIGN.md)

## Global Constraints

- Только живая лента, без истории — ничего не пишем в БД под старые шаги.
- Только 1:1-чат с ролью (`RoleChat.kind` ≠ `"group"`). В групповом чате поле
  `tool` клиент получает, но игнорирует — рендер не меняется.
- Никакого нового типа WS-события — расширяем существующий `chats:typing`
  необязательным полем `tool`.
- Сервер отдаёт голое имя инструмента строкой без интерпретации; подпись и
  иконку выбирает клиент.
- Название рантайма роли («Pi») нигде не всплывает в терминологии фичи,
  переменных или UI — только в файлах, где оно и так уже используется
  (`PiRuntimeAdapter.ts`).
- Токен-стриминг текста ответа и автосоздание 1:1-чата на каждую роль — вне
  этой задачи (см. спеку, раздел «Отложено»).

---

## File Structure

**Сервер (`~/Проекты/New-Todoist/server` на `.110`, редактируется через `ssh maksim`):**
- Modify: `src/runtime/PiRuntimeAdapter.ts` — новое поле `onStep` в
  `StartChatRunInput`, подписка на события хода внутри `startChatRun`.
- Modify: `src/routes/chats.ts` — функция `typing()` принимает необязательный
  `tool`, колбэк `onStep` передаётся в `startChatRun`.
- Modify: `test/chats-online.test.ts` — фейковый `RpcClient` получает рабочие
  `onEvent`/`emit` (сейчас там заглушки), мокается `../src/ws.js`, новый тест
  на проброс `tool` в бродкаст.

**Клиент (`TaskFlowNativeBuild`, этот репозиторий):**
- Modify: `Sources/Core/Realtime/RealtimeEvent.swift` — `tool` в кейсе
  `.roleChatTyping` и в `RoleTypingPayload`.
- Modify: `Tests/RoleChatRealtimeTests.swift` — тест на разбор `tool`.
- Modify: `Sources/Features/Chat/RoleChatsScreen.swift` — состояние текущего
  инструмента по тайписту, новая вьюха строки шага, рендер только в 1:1.
- Create: `SnapshotTests/RoleStepLineSnapshotTests.swift` — снэпшоты новой
  строки на паре инструментов.

---

## Task 1: Сервер — `tool` в `chats:typing`

**Files:**
- Modify: `server/src/runtime/PiRuntimeAdapter.ts:1011-1023` (интерфейс
  `StartChatRunInput`), `server/src/runtime/PiRuntimeAdapter.ts` внутри
  `startChatRun` — сразу после `activeChatRuns.set(runId, run);` (сейчас это
  происходит в блоке, начинающемся на строке ~1159 с `const newClient = new
  RpcClient({...})`).
- Modify: `server/src/routes/chats.ts:1056-1079` (функция `typing` и вызов
  `startChatRun`).
- Test: `server/test/chats-online.test.ts`.

**Interfaces:**
- Consumes: существующие `RpcClient.onEvent(listener)` (уже используется в
  `startRun`, тип события — `JsonAgentSessionEvent`, уже импортирован в
  файле), существующая `broadcastToUsers(userIds, event)` из `../ws.js`.
- Produces: `StartChatRunInput.onStep?: (tool: string) => void` — вызывается
  на каждом начале использования инструмента в ходе роли. `typing(active:
  boolean, tool?: string)` — при `tool` кладёт его доп. полем в бродкаст
  `chats:typing`.

- [ ] **Step 1: Прочитать спеку перед правкой**

Открыть [DESIGN.md](DESIGN.md)
в этом репозитории (TaskFlowNativeBuild) — там разобраны все edge cases,
которые должны остаться верными после правки (реконнект, неизвестный
инструмент, оборванный ход).

- [ ] **Step 2: Добавить `onStep` в `StartChatRunInput`**

В `~/Проекты/New-Todoist/server/src/runtime/PiRuntimeAdapter.ts`, в
интерфейсе `StartChatRunInput` (строки 1011-1023), после поля `timeoutMs`:

```ts
export interface StartChatRunInput {
  chatId: string;
  role: RoleName;
  roleId: string;
  prompt: string;
  sessionId?: string | null;
  timeoutMs?: number;
  /** Вызывается на каждом начале использования инструмента в ходе — для
   *  живой ленты «что роль делает сейчас» в чате (owner UI). Необязательный:
   *  вызовы без колбэка (если такие появятся) работают как раньше. */
  onStep?: (tool: string) => void;
}
```

- [ ] **Step 3: Подписаться на события хода внутри `startChatRun`**

В той же функции `startChatRun`, сразу после строки `activeChatRuns.set(runId,
run);` (следует за созданием `const newClient = new RpcClient({...})` и
`const run: ActiveChatRun = {...}`), добавить:

```ts
    newClient.onEvent((event: JsonAgentSessionEvent) => {
      if (
        event.type === "message_update" &&
        event.assistantMessageEvent.type === "toolcall_start"
      ) {
        input.onStep?.(event.assistantMessageEvent.toolName);
      }
    });
```

`JsonAgentSessionEvent` уже импортирован в этом файле (используется в
`startRun` чуть выше) — новый импорт не нужен. Это единственное место в
`startChatRun`, где сейчас вообще нет `onEvent`-подписки — до этой правки
события хода полностью отбрасывались.

- [ ] **Step 4: Расширить `typing()` в `chats.ts`**

В `~/Проекты/New-Todoist/server/src/routes/chats.ts`, строки 1056-1067:

```ts
  const typing = (active: boolean, tool?: string) => {
    const name =
      (db.prepare("SELECT name FROM users WHERE id = ?").get(roleUserId) as
        | { name?: string }
        | undefined)?.name ?? role;
    broadcastToUsers(memberIds(chatId), {
      type: "chats:typing",
      chat_id: chatId,
      user_id: roleUserId,
      name,
      active,
      ...(tool ? { tool } : {}),
    });
  };
```

- [ ] **Step 5: Передать `onStep` в вызов `startChatRun`**

Там же, строки 1071-1079:

```ts
  typing(true);
  try {
    reply = await startChatRun({
      chatId,
      role,
      roleId: roleUserId,
      prompt,
      sessionId: previousSessionId,
      onStep: (tool) => typing(true, tool),
    });
```

Остальное тело (`catch`/`finally` с `typing(false)`) не меняется — обрыв
хода без явного последнего шага уже покрыт существующим `finally`.

- [ ] **Step 6: Сделать фейковый `RpcClient` в тесте рабочим**

В `~/Проекты/New-Todoist/server/test/chats-online.test.ts` сейчас
`onEvent`/`emit` у фейкового клиента — заглушки (`onEvent: vi.fn(() => ()
=> {})`, `emit: () => {}`), в отличие от `test/runtime/PiRuntimeAdapter.test.ts`,
где они реально хранят и зовут слушателей. Заменить в
`makeFakeRpcClient` (там же, где определён `FakeRpcClient`):

```ts
interface FakeRpcClient {
  options: any;
  start: ReturnType<typeof vi.fn>;
  stop: ReturnType<typeof vi.fn>;
  prompt: ReturnType<typeof vi.fn>;
  abort: ReturnType<typeof vi.fn>;
  getState: ReturnType<typeof vi.fn>;
  getLastAssistantText: ReturnType<typeof vi.fn>;
  promptAndWait: ReturnType<typeof vi.fn>;
  onEvent: ReturnType<typeof vi.fn>;
  emit: (event: unknown) => void;
}
```

(сигнатура не меняется, меняется только реализация в `makeFakeRpcClient`):

```ts
function makeFakeRpcClient(options: any): FakeRpcClient {
  const argsList: string[] = options?.args ?? [];
  const sessionIdx = argsList.indexOf("--session-id");
  const resumedSessionId = sessionIdx >= 0 ? argsList[sessionIdx + 1] : null;
  const index = fakeClients.length;
  const listeners: Array<(event: unknown) => void> = [];
  const client: FakeRpcClient = {
    options,
    start: vi.fn(async () => {}),
    stop: vi.fn(async () => {}),
    prompt: vi.fn(async () => {}),
    abort: vi.fn(async () => {}),
    getState: vi.fn(async () => ({
      sessionId: resumedSessionId ?? `sess-${options?.model ?? "x"}-${fakeClients.length + 1}`,
      model: {
        provider: options?.provider ?? "anthropic",
        id: options?.model ?? "claude-sonnet-5",
      },
    })),
    getLastAssistantText: vi.fn(async () => "ответил агент"),
    promptAndWait: vi.fn(async () => {
      if (!blockedPromptIndexes.has(index)) return;
      const slot = { resolve: () => {} };
      promptWaiters[index] = slot;
      await new Promise<void>((resolve) => {
        slot.resolve = resolve;
      });
    }),
    onEvent: vi.fn((listener: (event: unknown) => void) => {
      listeners.push(listener);
      return () => {};
    }),
    emit: (event: unknown) => {
      for (const listener of listeners) listener(event);
    },
  };
  fakeClients.push(client);
  promptWaiters.push({ resolve: () => {} });
  return client;
}
```

- [ ] **Step 7: Замокать `broadcastToUsers`, чтобы ловить бродкасты в тесте**

В начале `~/Проекты/New-Todoist/server/test/chats-online.test.ts`, рядом с
существующим `vi.mock("../src/lib/embeddingClient.js", ...)`, добавить:

```ts
const broadcastCalls: Array<{ userIds: unknown; event: any }> = [];

vi.mock("../src/ws.js", () => ({
  broadcastToUsers: vi.fn((userIds: unknown, event: any) => {
    broadcastCalls.push({ userIds, event });
  }),
  broadcastTaskEvent: vi.fn(),
  alsoPushToIsland: vi.fn(),
}));
```

Если `vi.mock` на `../src/ws.js` уронит другие тесты этого файла (модуль
может экспортировать больше функций, которые где-то ещё используются) —
проверить фактический список экспортов `grep -n "^export" server/src/ws.ts`
на `.110` и домокать недостающие как `vi.fn()`.

В `beforeEach` добавить `broadcastCalls.length = 0;` рядом с остальными
сбросами состояния.

- [ ] **Step 8: Написать тест на проброс `tool`**

В `describe("Чаты (этап 2, онлайн-сессия Пи)", ...)`, рядом с существующим
тестом `"explicit @роль в тексте → ..."`:

```ts
  it("во время хода роли chats:typing несёт tool из toolcall_start", async () => {
    const chat = await createChat({
      title: "Диалог с архитектором",
      kind: "group",
      member_ids: ["role_architect", "role_qa"],
    });
    const chatId = chat.json().chat.id;

    blockPromptFor(0);
    const sendPromise = app.inject({
      method: "POST",
      url: `/api/chats/${chatId}/messages`,
      headers: ownerAuth,
      payload: { text: "@architect подскажи архитектуру" },
    });
    await tick(30);

    const client = lastClient();
    client.emit({
      type: "message_update",
      assistantMessageEvent: { type: "toolcall_start", id: "t1", toolName: "read" },
    });
    await tick(30);

    releasePromptWaiter(0);
    const sent = await sendPromise;
    expect(sent.statusCode).toBe(200);
    await tick(30);

    const stepCall = broadcastCalls.find(
      (c) => c.event?.type === "chats:typing" && c.event?.tool === "read",
    );
    expect(stepCall).toBeDefined();
    expect(stepCall?.event.active).toBe(true);
    expect(stepCall?.event.chat_id).toBe(chatId);

    const finalStop = broadcastCalls.find(
      (c) => c.event?.type === "chats:typing" && c.event?.active === false,
    );
    expect(finalStop).toBeDefined();
    expect(finalStop?.event.tool).toBeUndefined();
  });
```

- [ ] **Step 9: Прогнать тесты**

```bash
ssh maksim 'cd ~/Проекты/New-Todoist/server && npx vitest run test/chats-online.test.ts'
```

Expected: все тесты файла PASS, включая новый.

- [ ] **Step 10: Прогнать полный серверный набор (нет ли регрессии в других файлах)**

```bash
ssh maksim 'cd ~/Проекты/New-Todoist/server && npx vitest run'
```

Expected: PASS. Если что-то в другом файле упало из-за мока `../src/ws.js` —
добавить недостающий экспорт как `vi.fn()` в мок (Step 7) и повторить.

- [ ] **Step 11: Commit**

```bash
ssh maksim 'cd ~/Проекты/New-Todoist/server && git add src/runtime/PiRuntimeAdapter.ts src/routes/chats.ts test/chats-online.test.ts && git commit -m "feat(chats): поле tool в chats:typing — живой шаг роли в 1:1-чате"'
```

---

## Task 2: iOS — `tool` в `RealtimeEvent.roleChatTyping`

**Files:**
- Modify: `Sources/Core/Realtime/RealtimeEvent.swift:33` (кейс),
  `Sources/Core/Realtime/RealtimeEvent.swift:45-50` (`RoleTypingPayload`),
  `Sources/Core/Realtime/RealtimeEvent.swift:97-101` (разбор).
- Test: `Tests/RoleChatRealtimeTests.swift`.

**Interfaces:**
- Consumes: JSON от сервера — `{"type":"chats:typing","chat_id":...,
  "user_id":...,"name":...,"active":...,"tool":"read"}` (поле `tool`
  опционально, из Task 1).
- Produces: `RealtimeEvent.roleChatTyping(chatId: String, userId: String,
  name: String, active: Bool, tool: String?)` — используется в Task 3.

- [ ] **Step 1: Написать падающий тест**

В `Tests/RoleChatRealtimeTests.swift`, рядом с `testTypingStartAndStop`:

```swift
    func testTypingCarriesCurrentTool() {
        let withTool = parse(#"""
        {"type":"chats:typing","chat_id":"chat-1","user_id":"role_builder",
         "name":"Разработчик","active":true,"tool":"read"}
        """#)
        guard case .roleChatTyping(_, _, _, _, let tool) = withTool else {
            return XCTFail("ожидали roleChatTyping")
        }
        XCTAssertEqual(tool, "read")

        let withoutTool = parse(#"""
        {"type":"chats:typing","chat_id":"chat-1","user_id":"role_builder",
         "name":"Разработчик","active":true}
        """#)
        guard case .roleChatTyping(_, _, _, _, let noTool) = withoutTool else {
            return XCTFail("ожидали roleChatTyping")
        }
        XCTAssertNil(noTool)
    }
```

- [ ] **Step 2: Запустить тест и убедиться, что он не компилируется**

```bash
cd "$HOME/Проекты/TaskFlowNativeBuild" && xcodegen generate && xcodebuild test -project TaskFlow.xcodeproj -scheme TaskFlow -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TaskFlowTests/RoleChatRealtimeTests/testTypingCarriesCurrentTool 2>&1 | tail -40
```

Expected: FAIL на компиляции — `.roleChatTyping` сейчас принимает 4
элемента, не 5, и `RoleTypingPayload` не знает про `tool`.

- [ ] **Step 3: Добавить `tool` в кейс и разбор**

В `Sources/Core/Realtime/RealtimeEvent.swift`, строка 33:

```swift
    case roleChatTyping(chatId: String, userId: String, name: String, active: Bool, tool: String?)
```

Строки 45-50 (структура `RoleTypingPayload`):

```swift
    private struct RoleTypingPayload: Decodable {
        let chat_id: String
        let user_id: String
        let name: String?
        let active: Bool
        let tool: String?
    }
```

Строки 97-101 (разбор `"chats:typing"`):

```swift
        case "chats:typing":
            guard let p = try? decoder.decode(RoleTypingPayload.self, from: data) else {
                return .unknown(type: envelope.type, raw: raw)
            }
            return .roleChatTyping(chatId: p.chat_id, userId: p.user_id, name: p.name ?? "", active: p.active, tool: p.tool)
```

- [ ] **Step 4: Запустить тест и убедиться, что он проходит**

Та же команда, что в Step 2. Expected: PASS.

- [ ] **Step 5: Прогнать весь `RoleChatRealtimeTests` (нет ли регрессии по числу параметров кейса в других местах)**

```bash
cd "$HOME/Проекты/TaskFlowNativeBuild" && xcodebuild test -project TaskFlow.xcodeproj -scheme TaskFlow -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TaskFlowTests/RoleChatRealtimeTests 2>&1 | tail -60
```

Expected: PASS. Если где-то ещё в проекте матчится `.roleChatTyping` с 4
параметрами (например в `RoleChatsScreen.swift` до Task 3) — сборка упадёт
там же, это ожидаемо и чинится в Task 3.

- [ ] **Step 6: Commit**

```bash
cd "$HOME/Проекты/TaskFlowNativeBuild" && git add Sources/Core/Realtime/RealtimeEvent.swift Tests/RoleChatRealtimeTests.swift && git commit -m "feat(chat): tool в RealtimeEvent.roleChatTyping"
```

---

## Task 3: iOS — строка шага в `RoleChatRoomScreen`

**Files:**
- Modify: `Sources/Features/Chat/RoleChatsScreen.swift:591` (состояние),
  `Sources/Features/Chat/RoleChatsScreen.swift:790-792` (обработчик
  события), `Sources/Features/Chat/RoleChatsScreen.swift:799` (сброс при
  реконнекте), `Sources/Features/Chat/RoleChatsScreen.swift:901-904`
  (рендер), плюс новая приватная вьюха рядом с `RoleChatTypingLine`
  (строка 350).
- Test: `SnapshotTests/RoleStepLineSnapshotTests.swift` (новый файл).

**Interfaces:**
- Consumes: `RealtimeEvent.roleChatTyping(chatId:, userId:, name:, active:,
  tool:)` из Task 2; `RoleChat.kind: String` (уже существует, `"group"` —
  групповой чат).
- Produces: ничего, конечная точка фичи.

- [ ] **Step 1: Добавить состояние текущего инструмента по тайписту**

В `RoleChatRoomScreen`, рядом со строкой 591:

```swift
    @State private var typists: [String: String] = [:]
    /// Текущий инструмент по тайписту (userId → имя инструмента с сервера,
    /// например "read"/"edit"/"bash") — только пока `active == true` и
    /// сервер прислал `tool`. Живёт ровно как `typists`: без истории.
    @State private var typistTools: [String: String] = [:]
```

- [ ] **Step 2: Обновлять/чистить `typistTools` вместе с `typists`**

Строки 790-792, разбор события:

```swift
                case .roleChatTyping(let id, let userID, let name, let active, let tool) where id == chatID:
                    if active {
                        typists[userID] = name.isEmpty ? "Участник" : name
                        typistTools[userID] = tool
                    } else {
                        typists[userID] = nil
                        typistTools[userID] = nil
                    }
```

Строка 799 (сброс при реконнекте):

```swift
                typists = [:]
                typistTools = [:]
```

- [ ] **Step 3: Написать новую вьюху строки шага**

Рядом с `RoleChatTypingLine` (после строки 373), добавить:

```swift
/// Подпись/иконка по имени инструмента с сервера — сервер имя не
/// интерпретирует, это целиком презентационная таблица клиента.
private enum RoleStepPresentation {
    static func label(forTool tool: String) -> String {
        switch tool {
        case "read": return "Читает"
        case "edit", "write": return "Правит"
        case "bash": return "Выполняет команду"
        case "grep", "glob": return "Ищет"
        default: return "Работает"
        }
    }

    static func symbol(forTool tool: String) -> String {
        switch tool {
        case "read": return "doc.text"
        case "edit", "write": return "pencil.line"
        case "bash": return "bolt"
        case "grep", "glob": return "magnifyingglass"
        default: return "gearshape"
        }
    }
}

/// Строка «роль делает шаг прямо сейчас» — замена `RoleChatTypingLine`
/// в 1:1-чате, когда для роли пришёл `tool`. По мотивам референсного
/// AgentActivityFeed (26.09.2026, брейнсторм с владельцем).
private struct RoleStepLine: View {
    let name: String
    let tool: String

    var body: some View {
        HStack(spacing: TFSpacing.sm) {
            Image(systemName: RoleStepPresentation.symbol(forTool: tool))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.tfSub)
                .symbolEffect(.pulse, options: .repeating)
            Text("\(name): \(RoleStepPresentation.label(forTool: tool))")
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(RoleStepPresentation.label(forTool: tool))")
    }
}
```

- [ ] **Step 4: Ветвление рендера — строка шага только в 1:1**

Строки 901-904:

```swift
                    if !typists.isEmpty {
                        if chat.kind != "group", let onlyUserID = typists.keys.first,
                           let tool = typistTools[onlyUserID] {
                            RoleStepLine(name: typists[onlyUserID] ?? "Роль", tool: tool)
                                .id("typing-line")
                        } else {
                            RoleChatTypingLine(names: typists.values.sorted())
                                .id("typing-line")
                        }
                    }
```

`chat.kind != "group"` гарантирует ровно одного тайписта (в 1:1-чате
собеседник один), поэтому `typists.keys.first` безопасен — но код всё
равно не падает, даже если это предположение вдруг нарушится (fallback на
`typists.values.sorted())` через `else`).

- [ ] **Step 5: Собрать проект**

```bash
cd "$HOME/Проекты/TaskFlowNativeBuild" && xcodegen generate && xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build_sim build 2>&1 | tail -60
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Снэпшот-тест новой строки**

Создать `SnapshotTests/RoleStepLineSnapshotTests.swift` по образцу
`SnapshotTests/TaskRowSnapshotTests.swift` (тот же `deviceConfig`,
`record`-флаг, `@testable import TaskFlow`):

```swift
import XCTest
import SnapshotTesting
import SwiftUI
@testable import TaskFlow

final class RoleStepLineSnapshotTests: XCTestCase {
    private let deviceConfig: ViewImageConfig = .iPhone13Pro
    private var record: Bool { false }

    private func snapshot(tool: String, name: String = "Разработчик") -> some View {
        RoleStepLine(name: name, tool: tool)
            .padding()
            .background(Color.tfBackground)
            .frame(width: 320)
    }

    func testReadStep() {
        assertSnapshot(of: snapshot(tool: "read"), as: .image(layout: .device(config: deviceConfig)),
                        record: record)
    }

    func testBashStep() {
        assertSnapshot(of: snapshot(tool: "bash"), as: .image(layout: .device(config: deviceConfig)),
                        record: record)
    }

    func testUnknownToolFallsBackToGenericLabel() {
        assertSnapshot(of: snapshot(tool: "some_future_tool"), as: .image(layout: .device(config: deviceConfig)),
                        record: record)
    }
}
```

`RoleStepLine`/`RoleStepPresentation` сейчас `private` в
`RoleChatsScreen.swift` — снэпшот-тест лежит в отдельном таргете
(`SnapshotTests`), поэтому либо убрать `private` (оставить `internal`,
видимый в рамках модуля `@testable import TaskFlow`), либо, если конвенция
проекта требует `private` для файловых вьюх, перенести обе декларации в
`internal`. Простой путь — убрать `private` перед `enum
RoleStepPresentation` и `struct RoleStepLine` (они всё равно не публичный
API, `internal` по умолчанию достаточно для видимости из тестового таргета
через `@testable import`).

- [ ] **Step 7: Записать эталоны и прогнать снэпшот-тесты**

```bash
cd "$HOME/Проекты/TaskFlowNativeBuild"
# Временно во всех трёх тестах record: true, прогнать, вернуть record: false
xcodebuild test -project TaskFlow.xcodeproj -scheme TaskFlow -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapshotTests/RoleStepLineSnapshotTests 2>&1 | tail -60
```

Expected после записи эталонов и возврата `record = false`: PASS. Эталоны
(PNG в `SnapshotTests/__Snapshots__/RoleStepLineSnapshotTests/`) закоммитить
в git — как и у `TaskRowSnapshotTests`, иначе CI/чистая копия будут красными.

- [ ] **Step 8: Живая проверка на реальном 1:1-чате (обязательна по CLAUDE.md проекта)**

Собрать и поставить на симулятор с debug-токеном (см. корневой
`CLAUDE.md`, раздел про `TASKFLOW_DEBUG_TOKEN`/`TASKFLOW_DEBUG_ROUTE`),
открыть существующий 1:1-чат с любой ролью, отправить сообщение,
провоцирующее реальный ход (например `@builder ...`), кадром симулятора
убедиться, что вместо/вместе с точками на короткое время появляется строка
шага, а после ответа — пропадает. Групповой чат проверить отдельно: строка
шага там не должна появляться, только прежние точки.

- [ ] **Step 9: Commit**

```bash
cd "$HOME/Проекты/TaskFlowNativeBuild" && git add Sources/Features/Chat/RoleChatsScreen.swift SnapshotTests/RoleStepLineSnapshotTests.swift SnapshotTests/__Snapshots__/RoleStepLineSnapshotTests && git commit -m "feat(chat): живая строка шага роли в 1:1-чате вместо точек"
```
