# Нативный клиент TaskFlow (iOS, SwiftUI)

> **Перед первой правкой кода — `AGENT-WORK-SCOPES.md` в корне.** По умолчанию
> весь исходный код заморожен: менять можно только файлы, перечисленные в
> строке со статусом `IN_PROGRESS`. Взялся за работу — заведи строку (что
> чиним, какие файлы разрешены, как проверим), закончил — переведи в `REVIEW`
> и опиши сделанное; всё, что сделано сверх поставленной задачи, назови
> отдельно.
>
> Ссылка появилась здесь 09.09.2026: реестр существовал с самого начала, но
> `CLAUDE.md` о нём молчал, и целая сессия прошла мимо — с правками файлов
> сверх того, о чём просил владелец. То же правило для остальных агентов —
> в `AGENTS.md`. Напоминание при старте сессии кладёт хук
> `.claude/hooks/session_start_notice.sh`.
>
> **И главное правило поверх реестра:** не менять ничего сверх того, о чём
> попросил владелец. Увидел смежную проблему — скажи и дождись ответа, а не
> переделывай молча.

> **Это единственный исходник iOS-клиента.** Каталог на `.110`
> (`~/Проекты/New-Todoist/native`) удалён 08.09.2026 вместе с
> `scripts/sync-build.sh`: тот делал `rsync --delete` с .110 сюда и стирал
> работу, сделанную на маке. Ничего сюда извне не заливать — код переносится
> только через git (`origin` — Gitea `maksim/taskflow-native-ios`).
>
> Запрет держит хук `.claude/hooks/guard-no-remote-sync.sh`: `sync-build`
> и `rsync`/`scp` в этот каталог отклоняются до выполнения.

Сборка (xcodegen генерирует `.xcodeproj` из `project.yml`, он в `.gitignore`):

```bash
cd "$HOME/Проекты/TaskFlowNativeBuild" && xcodegen generate && xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build_sim build
```
- **Ассеты обязаны быть в `sources` в `project.yml`** — ключа `resources`
  у таргета в xcodegen нет. Каталог, положенный не туда, молча не попадает
  в бандл (так пропадал `Assets.car` и вместе с ним альтернативные значки).
- **Шапки экранов — системные, свои не рисуем.** Модификатор
  `.tfNativeHeader(_:displayMode:)` из
  `Sources/DesignSystem/Components/TFNativeHeader.swift`: внутри только
  `navigationTitle` + `toolbarTitleDisplayMode`. Фон и блюр не задаём —
  на нашем deploymentTarget систему рисует сама (scroll edge effect).
  Мягкий верхний край — `.tfSoftTopScrollEdge()`.
  Самодельные `TFScreenHeader`, `FrostedGlass`, `SettingsHeaderChrome`,
  `DirectoryCompactHeader` заменены и лежат в `archive/design-system-2026-09-11`
  (правка 22.09.2026: до неё здесь был предписан `TFScreenHeader`, удалённый
  ещё 11.09 — по этому указанию сессии искали несуществующий файл).
- **Экран логина в симуляторе — не преграда.** В отладочной сборке есть штатный
  вход по токену: переменная окружения `TASKFLOW_DEBUG_TOKEN` кладётся прямо в
  Keychain при старте (`SessionStore.bootstrap()`, блок `#if DEBUG`). Токен —
  ключ `TASKFLOW_AGENT_TOKEN` в vault, а vault ЖИВЁТ НА .110: на маке
  `vault-run.py` нет вовсе. Значение в чат не печатать — забирать в
  переменную и сразу отдавать потребителю:
  `TOKEN=$(ssh maksim 'python3 ~/.claude/vault-get.py --raw TASKFLOW_AGENT_TOKEN')`,
  дальше `SIMCTL_CHILD_TASKFLOW_DEBUG_TOKEN="$TOKEN" xcrun simctl launch <udid> com.maksim.taskflow.native`.
  Работать этим токеном ПРЯМО НА .110 (curl к API и т.п.) — через обёртку,
  она сама вычищает секрет из вывода:
  `ssh maksim 'python3 ~/.claude/vault-run.py --secret T=ИМЯ_КЛЮЧА -- команда'`
  (синтаксис именно `ПЕРЕМЕННАЯ=КЛЮЧ`, дальше `--` и команда). Бандл —
  `com.maksim.taskflow.native`, не `com.taskflow.native`. В UI-тесте:
  `app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = <токен>`.
  Рядом работает `TASKFLOW_DEBUG_ROUTE` — открыть нужный экран сразу при старте
  (`overview`, `settings`, `notes`, `projects`, `notifications`, `chat`, `today`,
  `upcoming`, `noteeditor:<id>`, `task:<id>`, `expand`, `quickadd`).
  Проверено 02.09.2026: приложение снесено с симулятора и запущено с токеном —
  «Обзор» открылся с данными, экрана входа не было.
- **Проверка правок интерфейса — кадром симулятора**, а не на глаз: временный
  XCUITest со `XCTAttachment(screenshot:)`, потом `xcrun xcresulttool export
  attachments` и замер пикселей. Временный тест удалять после сверки.
- **Навигация по экрану для проверки — тоже через XCUITest, не через
  скриншот+ручной тап по координате.** `mcp__Claude_Code_iOS_Simulator__control`
  (`tap`/`swipe`) годится только для запуска/скриншота готового состояния —
  не для «дойти до нужного экрана». В `tap` координаты — в points (402×874 у
  iPhone 17 Pro), а скриншот отдаётся в пикселях retina (×3) и вдобавок может
  быть смасштабирован для показа — из-за этого каждый тап требует пересчёта
  и с высокой вероятностью промахивается (правило появилось именно после
  серии промахов). В XCUITest элементы ищутся по `accessibilityIdentifier`/
  `label` (`app.buttons["..."].tap()`, `app.staticTexts["..."].tap()`) — это
  не гадание по пикselям, а прямой адресный тап, и он же остаётся
  единственным способом снять `XCTAttachment(screenshot:)` для приёмки.
  Владелец 29.09.2026, после серии промахов мимо нужных элементов на кадрах:
  «ты заебал, когда ты уже начнёшь это делать нормально» — писать
  одноразовый XCUITest-сценарий (open→найти элемент по identifier→tap),
  а не листать скриншоты с ручной линейкой.
- **Жест/UI-баг не поддаётся со второй попытки на глаз — сразу `NSLog` в
  подозрительное место**, не гонять третью-пятую попытку вслепую по
  скриншотам/синтетическим свайпам. `print()` не долетает ни до `simctl
  launch --stdout`, ни до `log show` — только `NSLog`. Читать так:
  `xcrun simctl spawn <device-udid> log show --last Nm --predicate 'process == "TaskFlow"' --style compact`.
  Пример 07.09.2026: `UpcomingHoursView.swift` — драг не давал заблокировать
  скролл; один `NSLog` в `handleUIGestureRecognizerAction` показал, что
  `recognizer.view` у `UIGestureRecognizerRepresentable` — это хостинг-view
  ВСЕГО экрана, а не вьюха карточки, и настоящий `UIScrollView` от SwiftUI
  `ScrollView` — его ПОТОМОК, а не предок, поэтому поиск вверх по
  `.superview` всегда возвращал `nil`. Без лога это гадание заняло бы ещё
  десяток кругов.
- **Несколько booted-симуляторов сразу — указывать `device`/UDID явно.**
  `launch` без явного устройства молча берёт первый booted, который может
  быть не тем, за которым наблюдает владелец — путаница «я ничего не менял,
  а фикс не появился» именно отсюда.
