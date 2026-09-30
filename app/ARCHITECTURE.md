# TaskFlow Native — архитектура

Нативный клиент TaskFlow на SwiftUI для iPhone. Сервер (Fastify + SQLite,
репозиторий `New-Todoist` на `.110`) и его API живут отдельно и здесь не
правятся.

> Переписан 22.09.2026 по живому коду. Прежняя редакция описывала структуру
> `native/…` внутри серверного репозитория и сборку через `scripts/sync-build.sh` —
> ни того, ни другого больше нет. Расходится документ с кодом — прав код.

## Где что лежит

| Путь | Что |
| --- | --- |
| `project.yml` | описание проекта для xcodegen; `.xcodeproj` генерится и в git не хранится |
| `Sources/App/` | точка входа, корневая навигация, таббар |
| `Sources/DesignSystem/` | `Theme` (токены), `Components`, `Navigation` |
| `Sources/Core/` | `Models`, `Networking`, `Realtime`, `Session`, `Stores`, `Speech`, `Common`, Live Activity, удержание фона |
| `Sources/Features/<Экран>/` | по папке на экран: `Chat`, `Directory`, `Markdown`, `Notes`, `Settings`, `Task`, `Today`, `Upcoming` |
| `Resources/` | Assets.xcassets, Info.plist, entitlements, шрифты |
| `Widgets/` | виджеты и Live Activity |
| `Tests/`, `UITests/`, `SnapshotTests/` | тесты |
| `VoiceMessageLab/` | отдельная песочница по голосовым сообщениям |
| `Tools/` | вспомогательные скрипты |
| `spec/` | спецификации, снятые с веб-версии в начале проекта |
| `graft/` | граф кода: ранжированный поиск по узлам с точными `file:line` |
| `docs/` | рабочие документы проекта |
| `archive/` | то, что выведено из работы, но выбрасывать рано |

Всего около 190 файлов Swift.

**Это единственный исходник клиента.** Копии на `.110` нет с 08.09.2026, код
переносится только через git (`origin` — Gitea `maksim/taskflow-native-ios`).
Любой файловый синк в этот каталог отклоняет хук
`.claude/hooks/guard-no-remote-sync.sh`.

## Технические решения

- **SwiftUI**, `deploymentTarget iOS 18.0` (`project.yml`). Порог занижен
  сознательно: новое включается через `#available`, а не поднятием планки.
- **Проект генерится xcodegen** из `project.yml`. Причина историческая и
  по-прежнему верная: общий `project.pbxproj` был бы вечным источником
  конфликтов, а xcodegen собирает таргет из содержимого папок.
- **Ассеты обязаны быть в `sources`** в `project.yml` — ключа `resources` у
  таргета в xcodegen нет, и каталог, положенный не туда, молча не попадёт в
  бандл.
- **Данные:** `@Observable`-сторы поверх `APIClient` (async/await, URLSession);
  реалтайм — `Sources/Core/Realtime`.
- **Bundle id:** префикс `com.maksim.taskflow`, у приложения —
  `com.maksim.taskflow.native`.

## Сборка

```bash
cd "$HOME/Проекты/TaskFlowNativeBuild" && xcodegen generate && \
  xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build_sim build
```

Каталоги `build_*` — результаты сборок, в git не входят и занимают десятки
гигабайт; чистить их безопасно.

## Порядок работы

1. **Весь код заморожен по умолчанию.** Править можно только файлы,
   перечисленные в строке со статусом `IN_PROGRESS` в `AGENT-WORK-SCOPES.md`.
   Взялся за работу — заведи строку, закончил — переведи в `REVIEW`.
2. **Ничего сверх задачи.** Увидел смежную проблему — скажи и дождись ответа.
3. **Сначала граф, потом поиск руками.** `graft ask "<что ищу>"` отдаёт узлы с
   точными `file:line`; ручной обход уводит в мёртвый код.
4. **Расходится `spec/` с кодом — верить коду.** Спецификации снимались с веба
   07.09.2026 и с тех пор не пересматривались.
5. **Правки интерфейса проверять кадром симулятора**, а не на глаз.

Полные правила — `CLAUDE.md` и `AGENTS.md` в корне.
