# План реализации: паспорта серверных уведомлений

**Дата:** 29 сентября 2026
**Спека:** [2026-09-29-server-notification-passports-design.md](2026-09-29-server-notification-passports-design.md) — согласована по разделам 1–4
**Критерий готовности:** 6 red-green-refactor тестов из спеки § «Проверка» + controlled live rehearsal

## Фон (что уже сделано)

- `1741a53` в `~/infra-ops`: `notification_passports.json` добавлен под Git как есть (401 строка, безопасный нулевой шаг миграции).
- `alert_send.py` уже принимает параметр `source` — `source_id` в payload готов, нужно только зафиксировать контракт и поднять наверх в TaskFlow.
- `rendezvous.py` уже принимает `source` и пишет в `~/Проекты/taskflow-уведомления/inbox/<дата>/HHMMSS-<source>.md`. Этого достаточно, чтобы начать lookup паспорта по `source_id`.

## Границы (что НЕ трогаем)

- **iOS клиент** (TaskFlowNativeBuild) — экран «реестра наблюдателей» вне этого этапа (спека § «Открытая граница»). Паспорт приходит в iOS только как контекст в diagnostic task через уже работающий канал.
- **Не заменяем** `journalctl` / application logs / evidence-файлы единым журналом.
- **Не даём агенту** автоматическое право на перезапуск, удаление данных или изменение маршрутов (даже если команда есть в паспорте).
- **Не шлём** зелёное уведомление на каждый успешный watcher — только при сбое или расхождении аудита.
- **Не блокируем** поставку до зелёной миграции (Шаг 7 ниже) — первый рубеж в `warn-only`.

## Файлы

### `.110` — `~/infra-ops`

| Путь | Действие | Назначение |
|---|---|---|
| `notification_passports.json` | правка (Шаг 1) | Schema v1: плоский массив записей с `source_id`, `schema_version`, `purpose`, `observation`, `evidence`, `triage`, `notification`, `review` |
| `validate_notification_passports.py` | новый (Шаг 4) | JSON Schema + свечение declared paths/units с реальной ФС + inventory emitter'ов |
| `tests/test_validate_notification_passports.py` | новый (Шаг 4) | 6 red-green-refactor тестов из спеки § «Проверка» |
| `rendezvous.py` | правка (Шаг 5) | После записи в inbox: HTTP-запрос к TaskFlow server на lookup паспорта; payload обогащается `passport_snapshot` (или пустой объект, если паспорта нет — отдельное server-notification) |
| `alert_send.py` | правка (Шаг 5) | Явный комментарий-контракт: параметр `source` — это `source_id` реестра паспортов. Без изменений в рантайме, только docstring/assert |
| `notification_audit.py` | новый (Шаг 6) | Ночной аудит: `systemctl --user list-units` + список emitter'ов против реестра; при расхождении — один server-notification через `alert_send.send("passport-audit", ...)`; повторы дедуплицируются по `(missing_id, hash)` |
| `audit_dedupe_state.json` | новый (Шаг 6, в `~/infra-ops/`) | Локальный state для дедупа аудита |
| `.pre-commit-config.yaml` (или `hooks/pre-commit`) | новый (Шаг 7) | Локальный запуск `validate_notification_passports.py --warn` перед коммитом в `infra-ops` |
| `.github/workflows/passports.yml` | новый (Шаг 7) | CI: запускает валидатор на PR в `infra-ops`, `--warn` для первой итерации |

### `.110` — `~/Проекты/New-Todoist/server`

| Путь | Действие | Назначение |
|---|---|---|
| `src/notifications/passportLookup.ts` | новый (Шаг 5) | HTTP-клиент к `notifications-api.service` `.110:5198` для lookup паспорта по `source_id`. Кэширует на время запроса (одна задача — один запрос) |
| `src/notifications/inboxTriageWatcher.ts` | правка (Шаг 5) | При создании diagnostic task: обогащает payload задачи полем `passport_snapshot` (immutable, сохраняется как JSON-блок в evidence/контексте задачи) |
| `src/notifications/passportSnapshot.ts` | новый (Шаг 5) | Тип и сериализация snapshot; версия + хеш паспорта; используется в API задачи для immutable хранения |
| `test/notifications/passportSnapshot.test.ts` | новый (Шаг 5) | Тест «изменение паспорта после инцидента не меняет snapshot старой задачи» (спека § «Проверка», п. 4) |
| `test/notifications/passportLookup.integration.test.ts` | новый (Шаг 5) | Integration-test: уведомление известного источника → diagnostic task с контекстом из паспорта (спека § «Проверка», п. 5) |

### `.110` — `~/Проекты/taskflow-уведомления`

| Путь | Действие | Назначение |
|---|---|---|
| `format/svodka-template.md` | правка (Шаг 1, единственная) | Добавить секцию-пояснение, что паспорт прикладывается к diagnostic task автоматически и не редактируется из приложения |

## Шаги

Каждый шаг — отдельный коммит. Перед кодом — red-тест, после кода — green.

### Шаг 1. Schema v1 (один коммит в `~/infra-ops`)

**Что:** преобразовать `notification_passports.json` из dict-по-категориям в плоский массив записей `[{schema_version, source_id, title, purpose, owner, observation, evidence, triage, notification, review}]`.

**Источник маппинга** (старый → новый):
- категория-имя → `title`
- `raw_names` + `how_it_breaks` → `triage.symptoms[]` (`[{match, meaning}]`)
- `verify` (строка) → разделить на `triage.verify_command` + `triage.expected_after_fix`
- `owner` (`{files, units}`) → `owner` (`{repo, units, files}`); `repo` = `"/home/maksim/infra-ops"` (или подставить из контекста)
- `logs` → `evidence.logs[]`
- `source_aliases` → `notification.source_aliases[]`
- `notes` → источник для `purpose` + `observation.cadence`
- новые обязательные поля: `schema_version: 1`, `source_id`, `observation.metric`, `observation.normal`, `review.reviewed_at: "2026-09-29"`, `review.reviewed_reason: "initial migration"`

**`source_id` берётся** из `source_aliases[0]` (например, `runaway-110`, `autonomy-110`, `kb-add`). Если `source_aliases` пусто — ставится как `slug(категория)` (например, `"memory_consolidation"`).

**Граница:** в этом коммите — только преобразование структуры, без semantic enrich (метрика/норма/cadence) и без свечения с реальной ФС. Это Шаги 2 и 3.

**Проверка:** `python3 -m json.tool` + grep по `source_id` (15 уникальных) + `jq '. | length'` = 15.

### Шаг 2. Inventory реальных systemd user units и emitter'ов (коммит в `~/infra-ops`)

**Что:** создать `~/infra-ops/notification_inventory.json` — слепок фактического состояния:
- `systemctl --user list-units --type=service,timer --no-legend --no-pager` — все user units, кроме явно системных
- рекурсивный `grep -lE "alert_send\.send|rendezvous\.write" ~/infra-ops/*.py ~/Проекты/taskflow-уведомления/**/*.sh` — emitter'ы
- `format/svodka-template.md` парсится на список raw_names (markdown-сводки, упоминания как `"доставка тревог: ..."`)

**Проверка:** файл валидный JSON, содержит секции `units[]`, `emitters[]` с путями; используется как вход для валидатора (Шаг 4).

### Шаг 3. Миграция 15 записей по schema v1 (коммит в `~/infra-ops`)

**Что:** для каждой записи из Шага 1 дополнить:
- `observation.metric` — извлечь из `check_source` и `notes` (что измеряется)
- `observation.normal` — нормальное состояние (часто есть в `how_it_breaks` как «всё хорошо» или в `notes`)
- `observation.cadence` — частота (например, «каждые 5 минут», «раз в сутки в 02:00»)
- `evidence.state` — если в `notes` упоминается state-файл (например, `/home/maksim/.claude/runaway-watch-seen.json`), вынести в отдельное поле
- `review` — поставить `reviewed_at: "2026-09-29"`, `reviewed_reason: "initial migration from draft"`

**Результат Шага 2 + 3:** файл `notification_passports.json` — массив из 15 записей, schema v1, semantic complete. Это та точка, от которой начинается валидатор.

**Граница:** если для какой-то записи невозможно однозначно извлечь метрику/норму — помечать поле как `null` и писать в `review.reason: "metric pending owner clarification"`. Не выдумывать.

### Шаг 4. `validate_notification_passports.py` (коммит в `~/infra-ops`)

**Что:** новый скрипт, делает 5 вещей:
1. Проверяет JSON Schema (встроенная или через `jsonschema`).
2. Свечение declared `owner.files` и `owner.units` с реальной ФС / `systemctl --user list-unit-files`.
3. Строит inventory emitter'ов и сообщает источники без паспорта.
4. Проверяет aliases: каждый `source` из `inbox/` (за последние 24 ч) однозначно разрешается в паспорт.
5. Diff-проверка: если изменён watcher/unit (git diff в `~/infra-ops` или `~/Проекты/taskflow-уведомления/`), но соответствующий паспорт не менялся — ошибка (или warning, см. Шаг 7).

**Аргументы CLI:**
- `--warn` — только предупреждения (для CI первое время)
- `--strict` — exit 1 при любом нарушении (для blocking mode)
- `--check diff` — только пункт 5
- `--check inventory` — только пункты 3-4

**Тесты `tests/test_validate_notification_passports.py`** — 6 red-green-refactor кейсов из спеки § «Проверка»:
1. Новый watcher без паспорта → exit 1
2. Неверный alias / несуществующий unit → exit 1
3. Создание diagnostic task без сохранённого passport snapshot → exit 1 (мокаем TaskFlow server)
4. Изменение паспорта после инцидента не меняет snapshot старой задачи → pass (snapshot immutable)
5. Уведомление известного источника → diagnostic task с контекстом из паспорта (integration)
6. Controlled live rehearsal (Шаг 8) — за пределами unit-тестов

**Проверка:** `cd ~/infra-ops && python3 -m unittest tests.test_validate_notification_passports` — 5 тестов OK.

### Шаг 5. Snapshot в diagnostic task (коммиты в `~/Проекты/New-Todoist/server` и `~/infra-ops/rendezvous.py`)

**Что:** при срабатывании тревоги:
1. `rendezvous.py` после записи в inbox делает HTTP POST на TaskFlow server: `POST /api/notifications/passport-lookup {source_id, ts}` → получает `passport_snapshot` (или `null` + флаг «unknown source»).
2. `inboxTriageWatcher.ts` на TaskFlow server при создании diagnostic task включает `passport_snapshot` в payload задачи (immutable, сохраняется как JSON-блок в `task.evidence.passport_snapshot`).
3. Если паспорт не найден (`unknown source`) — отдельное server-notification через `alert_send.send("passport-audit", "error", ...)`, диагностическая задача получает явную причину «паспорт отсутствует».
4. Старые инциденты не переписываются: snapshot хранится в evidence задачи, изменение реестра не трогает старые задачи.

**Тесты:**
- `passportSnapshot.test.ts` — snapshot сериализуется с `version` и `hash`; повторный lookup того же паспорта в новой версии не меняет старый snapshot
- `passportLookup.integration.test.ts` — реальный HTTP к `notifications-api :5198` (если доступен в CI) или мок
- `rendezvous.test.py` (новый в `~/infra-ops/tests/`) — `rendezvous.write` обогащает payload `passport_snapshot`

**Проверка:** запустить на живой `notifications-api :5198` + живой TaskFlow server; создать диагностическую задачу через сценарий тревоги; убедиться, что в `task.evidence.passport_snapshot` лежит валидный JSON с `version` и `hash`.

### Шаг 6. Ночной аудит (коммит в `~/infra-ops`)

**Что:** новый скрипт `notification_audit.py`:
1. Читает реестр.
2. Делает inventory реальных user units и emitter'ов (как Шаг 2, но в runtime).
3. Находит расхождения: `units` без паспорта, `source_id` без соответствующего unit, объявленные в паспорте unit, которых нет.
4. Если есть расхождения И они отличаются от `audit_dedupe_state.json` (хеш списка) — шлёт ОДНО server-notification через `alert_send.send("passport-audit", "error", "Расхождение реестра паспортов", список)`. Сохраняет хеш в state.
5. Если расхождений нет — ничего не шлёт (никакого зелёного спама).

**Расписание:** systemd user timer `passport-audit.timer`, `OnCalendar=*-*-* 03:30:00` (после обычной ночной сводки 03:00). Unit `passport-audit.service` — `Type=oneshot`, `ExecStart=/home/maksim/infra-ops/notification_audit.py`.

**Тесты:** `tests/test_notification_audit.py` — три кейса: нет расхождений (молчит), есть новые (шлёт один раз), повтор того же расхождения (дедуп).

**Проверка:** запустить руками на `.110`, убедиться, что при известном наборе паспортов скрипт молчит; добавить фейковый watcher без паспорта, перезапустить — приходит одно уведомление.

### Шаг 7. CI / pre-commit hook (коммит в `~/infra-ops`)

**Что:** два уровня, как в спеке § «Автоматизация и контроль»:
1. **Pre-commit hook** (локальный, `hooks/pre-commit` или `.pre-commit-config.yaml` через `pre-commit` framework): запускает `python3 validate_notification_passports.py --warn`. Не блокирует коммит (только warning), но печатает список нарушений.
2. **CI** (`.github/workflows/passports.yml`, если Gitea Actions поддерживает; иначе — отдельный серверный скрипт, который запускается по `post-receive` hook в `~/infra-ops/.git/hooks/`): тот же валидатор, exit code — warning в первой итерации.

**Граница:** в этом шаге — **только `warn-only`**. Блокирующий режим (`--strict`) включается **отдельной строкой** в `AGENT-WORK-SCOPES.md` (точнее, в эквиваленте реестра для `infra-ops` — нужно завести, см. Шаг 9) после того, как:
- все 15 паспортов прошли миграцию (Шаг 3);
- валидатор проходит на текущем состоянии без warning;
- controlled live rehearsal (Шаг 8) завершён.

**Проверка:** сделать коммит с фейковым watcher'ом без паспорта — pre-commit печатает warning, но коммит проходит. В CI — то же самое, статус «warning», не «failure».

### Шаг 8. Controlled live rehearsal (коммит в `~/infra-ops` + ручной прогон)

**Что:** для **одного некритичного** источника (например, `runaway-110`) провести полный сценарий:
1. Убедиться, что паспорт `runaway-110` в реестре, валидатор зелёный.
2. Сэмулировать сбой: остановить `runaway-watch.timer` на `.110` (`systemctl --user stop runaway-watch.timer`).
3. Дождаться, пока `autonomy-report.py` сформирует сводку с тревогой.
4. Убедиться, что в `~/Проекты/taskflow-уведомления/inbox/<дата>/` появился файл с `source=runaway-110` И что при создании diagnostic task в TaskFlow server к задаче прикладывается `passport_snapshot` с правильным содержимым.
5. Вернуть `runaway-watch.timer` (`systemctl --user start runaway-watch.timer`), дождаться следующей тревоги с текстом «восстановлено» (или эквивалент), убедиться, что в задаче появилась запись о восстановлении с фактической командой проверки и её результатом.
6. **Никаких ложных тревог пользователю** на каждом шаге — только одно server-notification о самой演练е, если она его требует.

**Тест:** это не unit-тест. Это ручной чек-лист, описанный в `docs/2026-09-27-notifications-service-tickets/2026-09-29-server-notification-passports-rehearsal.md` (создаётся в этом шаге) с галочками.

**Проверка:** rehearsal пройден, чек-лист заполнен, ни одного ложного уведомления владельцу.

### Шаг 9. Реестр ограничений работ (коммит в `~/infra-ops`)

**Замечание:** сейчас реестра ограничений работ для `~/infra-ops` нет — `AGENT-WORK-SCOPES.md` существует только для `~/Проекты/TaskFlowNativeBuild`. После Шага 5 стоит завести `~/infra-ops/AGENT-WORK-SCOPES.md` (или аналог) с записью `LOCK-PASS-001 IN_PROGRESS PASS-IMPL` (или любая другая схема нумерации), чтобы будущие правки шли через те же правила «по умолчанию ничего не трогать, кроме файлов из активной строки».

**Содержимое строки:** Scope ID = `INFRA-PASSPORTS-MIGRATION`, файлы = списки из шагов 1–8 (все файлы выше), проверка = `python3 -m unittest tests.test_validate_notification_passports tests.test_notification_audit` + ручной rehearsal (Шаг 8).

## Резюме: 8 коммитов + 1 реестр

| # | Шаг | Где | Что |
|---|---|---|---|
| 1 | Schema v1 (структура) | `~/infra-ops` | Преобразовать dict в массив |
| 2 | Inventory | `~/infra-ops` | Слепок реальных units/emitter'ов |
| 3 | Миграция 15 записей | `~/infra-ops` | Semantic complete паспорта |
| 4 | Валидатор + тесты | `~/infra-ops` | `validate_notification_passports.py` + 5 unit-тестов |
| 5 | Snapshot в diagnostic task | `~/Проекты/New-Todoist/server` + `~/infra-ops/rendezvous.py` | `passportLookup.ts`, `passportSnapshot.ts`, тесты |
| 6 | Ночной аудит | `~/infra-ops` | `notification_audit.py` + systemd timer |
| 7 | CI / pre-commit | `~/infra-ops` | warn-only валидатор |
| 8 | Controlled live rehearsal | `~/infra-ops` (документ) | Чек-лист + ручной прогон |
| 9 | Реестр ограничений работ | `~/infra-ops` | `AGENT-WORK-SCOPES.md` (новый) |

## Где остановиться после каждого шага

После каждого шага — отдельное сообщение владельцу с тремя пунктами:
1. **Что сделано** (один-два абзаца, ссылка на коммит).
2. **Чем проверено** (какие тесты, какие команды, какой результат).
3. **Что осталось риском** (если есть).

Без простыней. Без повторов согласованного дизайна. Без «продолжаем?» в конце.
