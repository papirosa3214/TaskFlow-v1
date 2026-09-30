# Things 3 Manual Sync Implementation Plan

> Исполнять по задачам: сначала красный тест, затем минимальная правка, затем проверка и отдельный коммит.

**Goal:** Добавить ручную двустороннюю синхронизацию области `TaskFlow` в Things 3 по кнопке.

**Architecture:** Небольшой Mac bridge использует AppleScript для чтения/записи Things и HTTP API для TaskFlow. Нативный экран интеграций запускает bridge вручную и отображает результат; идентификатор связи хранится в заметках Things.

**Tech Stack:** SwiftUI, XCTest, AppleScript/osascript, Python 3 stdlib, TaskFlow HTTP API.

**Дизайн:** [DESIGN.md](DESIGN.md)

## Global Constraints

- Работа только в `/Users/max/Проекты/TaskFlowNativeBuild`.
- Не удалять данные из TaskFlow или Things автоматически.
- Не трогать проекты Things вне области `TaskFlow`.
- Ручной запуск только по кнопке; LaunchAgent и таймеры не добавлять.

### Task 1: Merge algorithm tests

**Files:**
- Create: `Tests/ThingsSyncTests.swift`
- Create: `Sources/Features/Settings/ThingsSyncMerge.swift`

- [x] Write tests for marker parsing, duplicate prevention, and status/date merge.
- [x] Run the focused XCTest target and verify the tests fail because the merge types do not exist.
- [x] Implement pure Foundation merge helpers.
- [x] Run the focused XCTest target and verify it passes.

### Task 2: Mac bridge

**Files:**
- Create: `Tools/taskflow-things-sync.py`
- Create: `Tools/taskflow-things-sync.sh`

- [x] Add JSON API fetches for projects/tasks and AppleScript serialization.
- [x] Restrict reads to the `TaskFlow` area and make project/task creation idempotent by name plus marker.
- [x] Emit a compact JSON result and keep per-item failures non-fatal.
- [x] Run the bridge in dry-run mode and then against a disposable test item.

### Task 3: Integrations UI

**Files:**
- Modify: `Sources/Features/Settings/IntegrationsScreen.swift`
- Modify: `Sources/Features/Settings/IntegrationsLocalPrefs.swift`

- [x] Add a Things accordion with button-only manual sync and result/error state.
- [x] Call the Mac bridge without adding a background sync timer; the listener is idle until the button sends `/sync`.
- [x] Run Swift tests and build the iOS target.

### Task 4: Verification

**Files:**
- Modify: `AGENT-WORK-SCOPES.md`
- Create: `docs/things-sync.md`

- [x] Record the active work scope and operator setup requirements.
- [x] Verify `git diff --check`, focused tests, and a live Mac sync.
