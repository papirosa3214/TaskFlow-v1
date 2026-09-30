# LOCK-193 · Проверка моделей чатов iOS

Дата: 21.09.2026. Ветка `feature/reviewer-first-review`.

## Изменения

- `RoleChatTests` проверяет декодирование чата, участников, превью и сообщения из форм JSON серверных маршрутов `/api/chats` и `/api/chats/:id/messages`. Проверены `snake_case`, необязательные поля, `null` и лишние серверные поля.
- `RoleChat.displayTitle(excluding:)` обрабатывает пробельное название как пустое, исключает текущего пользователя и собирает заголовок из имён ролей. Когда иных участников нет, группа получает заголовок «Групповой чат».
- Пять тестов покрывают именованную группу, группу без названия, личный чат, полное сообщение и сообщение с пустыми полями автора.

## Проверка

- `xcodegen generate` — успешно.
- `xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow -configuration Debug -destination 'platform=iOS Simulator,id=ED3C7DF7-F895-45B6-8A28-F67C02362103' -derivedDataPath /tmp/taskflow-lock193-derived -resultBundlePath /tmp/taskflow-lock193.xcresult -only-testing:TaskFlowTests/RoleChatTests CODE_SIGNING_ALLOWED=NO test` — `TEST SUCCEEDED`, 5 тестов, 0 ошибок.
- `git diff --check` — успешно.

## Не проверено

- Живое отображение списка чатов, создание и переписка в UI; интеграция с работающим API. Тесты проверяют модель на JSON-фикстурах.
- Остальные тесты `TaskFlowTests` не запускались; выполнена только группа `RoleChatTests`.

Сервер и веб не менялись. Ранее существовавший незатреканный `build_reviewer/` оставлен без изменений.
