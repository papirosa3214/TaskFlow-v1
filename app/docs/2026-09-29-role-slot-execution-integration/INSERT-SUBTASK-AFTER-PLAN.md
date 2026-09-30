# Вставка подзадачи в середину столбика — план реализации

> **Для агентской сессии:** REQUIRED SUB-SKILL: используй
> superpowers:executing-plans, шаги отмечаются чекбоксами `- [ ]`.
>
> **Перед первой правкой кода — прочитай `AGENT-WORK-SCOPES.md` в корне
> этого репозитория.** По умолчанию весь исходный код заморожен: заведи
> строку `IN_PROGRESS` (Lock ID, разрешённые файлы, цель, способ проверки)
> ДО Task 1, переведи в `REVIEW` в Task 4.

**Цель:** владелец может добавить подзадачу не только в конец списка, а
сразу после любой конкретной существующей — через долгое нажатие на
строку, без диалогов и без новых постоянных кнопок.

**Архитектура:** только iOS. Сервер уже всё умеет — `POST
/tasks/:id/subtasks` принимает `after_id` и сдвигает позиции остальных
подзадач транзакционно (`New-Todoist/server/src/routes/subtasks.ts:145-163`,
уже в проде, ничего менять на сервере не нужно). Задача — прокинуть этот
параметр через клиент и дать способ им воспользоваться в интерфейсе.

**Стек:** Swift, SwiftUI, TaskFlow native iOS client.

## Глобальные ограничения

- Канонический источник — `/Users/max/Проекты/TaskFlowNativeBuild`, ветка одна (`main`).
- Сборка/проверка:
  ```bash
  cd "$HOME/Проекты/TaskFlowNativeBuild" && xcodegen generate && xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build_sim build
  ```
- Правки интерфейса — проверять кадром симулятора, не на глаз (см. корневой `CLAUDE.md`).
- **Важно — не наступить на уже принятое решение.** В `TaskFormScreen.swift:1769-1774` явно
  задокументирован отказ владельца (11.09.2026) от отдельных кнопок
  добавления/редактирования подзадач: «просто тапаю и редактирую... никаких
  кнопок „изменить“, плюсов, галочек и крестиков». Новая возможность вставки
  ДОЛЖНА остаться скрытым жестом (долгое нажатие → контекстное меню), а не
  постоянной видимой кнопкой на строке. Если способ реализации это
  нарушает — сначала спросить владельца, не устанавливать самовольно.

## На что смотреть при ревью

- Обычное добавление в конец (нижняя строка списка) не меняется вообще.
- Вставленная подзадача появляется на правильном месте СРАЗУ, не только
  после следующего опроса сервера (`subtasks.insert(at:)`, не просто `append`).
- Ни одной новой постоянно видимой кнопки/иконки на строке подзадачи.

---

### Task 1: Прокинуть `after_id` в APIClient и ViewModel

**Файлы:**
- Изменить: `Sources/Core/Networking/APIClient+Subtasks.swift`
- Изменить: `Sources/Features/Task/TaskFormViewModel.swift`

- [ ] В `APIClient+Subtasks.swift` заменить:
  ```swift
  func createSubtask(taskId: String, title: String) async throws -> ApiSubtask {
      try await request(.post, "/tasks/\(taskId)/subtasks", body: ["title": title] as [String: String])
  }
  ```
  на:
  ```swift
  func createSubtask(taskId: String, title: String, afterId: String? = nil) async throws -> ApiSubtask {
      var body: [String: JSONValue] = ["title": .string(title)]
      if let afterId { body["after_id"] = .string(afterId) }
      return try await request(.post, "/tasks/\(taskId)/subtasks", body: body)
  }
  ```
- [ ] В `TaskFormViewModel.swift` заменить `addSubtask`:
  ```swift
  func addSubtask(_ title: String) async {
      guard let taskID else { return }
      do {
          let created = try await apiClient.createSubtask(taskId: taskID, title: title)
          subtasks.append(created)
      } catch {
          saveErrorMessage = Self.message(error)
      }
  }
  ```
  на версию с опциональным `afterId`, вставляющую результат в правильную
  позицию массива (не только `append`):
  ```swift
  func addSubtask(_ title: String, afterId: String? = nil) async {
      guard let taskID else { return }
      do {
          let created = try await apiClient.createSubtask(taskId: taskID, title: title, afterId: afterId)
          if let afterId, let index = subtasks.firstIndex(where: { $0.id == afterId }) {
              subtasks.insert(created, at: index + 1)
          } else {
              subtasks.append(created)
          }
      } catch {
          saveErrorMessage = Self.message(error)
      }
  }
  ```
- [ ] Собрать проект — существующие вызовы `addSubtask(title)` продолжают
  работать без изменений, так как `afterId` по умолчанию `nil`.

### Task 2: Жест «добавить после» на строке подзадачи

**Файлы:**
- Изменить: `Sources/Features/Task/TaskFormScreen.swift`

- [ ] Добавить состояние: `@State private var insertAfterSubtaskID: String?`
  и `@FocusState`-поле для фокуса новой строки вставки.
- [ ] На `nativeSubtaskRow` (строка ~1052) добавить `.contextMenu` с одним
  пунктом «Добавить подзадачу после» — по тапу выставляет
  `insertAfterSubtaskID = subtask.id` и переносит фокус на строку вставки.
- [ ] В `subtasksContent` (`ForEach(viewModel.subtasks)`, строка ~1777) —
  если `insertAfterSubtaskID == subtask.id`, сразу после `nativeSubtaskRow(subtask)`
  рендерить инлайн-поле ввода (тот же паттерн, что у `newSubtaskRow`,
  строка ~1797: однострочный `TextField`, `onSubmit` вызывает
  `viewModel.addSubtask(title, afterId: insertAfterSubtaskID)`, затем сбрасывает
  `insertAfterSubtaskID = nil` и очищает текст).
- [ ] Не добавлять отдельную кнопку рядом со строкой — только контекстное
  меню по долгому нажатию, ничего постоянно видимого.

### Task 3: Проверка в симуляторе

- [ ] `xcodegen generate && xcodebuild ... build` — BUILD SUCCEEDED.
- [ ] Запустить в симуляторе с `TASKFLOW_DEBUG_TOKEN` (см. корневой `CLAUDE.md`),
  открыть реальную задачу минимум с 3 подзадачами.
- [ ] Долгое нажатие на среднюю подзадачу → «Добавить подзадачу после» →
  ввести текст → отправить.
- [ ] Кадром подтвердить: новая подзадача появилась МЕЖДУ средней и
  следующей, а не в конце списка.
- [ ] Проверить, что обычное добавление в конец (нижняя строка) работает
  как раньше — без регрессии.
- [ ] Удалить тестовую подзадачу, созданную для проверки (свой тестовый
  мусор, по правилу CLAUDE.md).

### Task 4: Обновить AGENT-WORK-SCOPES.md и закоммитить

- [ ] Перевести заведённую в начале строку `IN_PROGRESS` в `REVIEW`,
  описать сделанное и результат сборки/проверки.
- [ ] Один коммит: изменённые файлы + `AGENT-WORK-SCOPES.md`, сообщение —
  что сделано, со ссылкой на этот план.

---

## Самопроверка плана

- Task 1 не требует серверных изменений — `after_id` там уже реализован и
  протестирован (`server/test/subtasks.test.ts`, если там есть покрытие —
  проверить перед стартом, но менять сервер не нужно в любом случае).
- Task 2 — единственный шаг с творческим решением; не должен вводить
  постоянно видимую кнопку — это явно отвергнутое владельцем решение
  (11.09.2026), не мелочь.
- Task 3 требует реальной проверки в симуляторе, не «выглядит правильно
  по коду».
