# Визуальный аудит — TaskFlow Native (iOS, SwiftUI)

**Дата:** 2026-09-21
**Автор:** Hermes (read-only проход, без правок)
**Скоуп:** только визуал / косметика. Без фич, без рефакторинга сетей, без realtime-логики.

## 0. Исходные правила (что НЕ трогать без явной просьбы владельца)

Из `AGENTS.md` (обязательно):

> Если владелец просит «нативный», «оригинальный» или «системный» компонент,
> оставлять чистый SwiftUI-компонент **без собственных** `tint`, `background`,
> `overlay`, `scaleEffect`, рамок, материалов и имитаций — если владелец прямо
> не попросил именно эту настройку.

Из `CLAUDE.md`:

- Шапки экранов — общий компонент `Sources/DesignSystem/Components/TFNativeHeader.swift`.
  Экраны, рисующие шапку сами, обязаны совпадать с ним по геометрии.
- Свой навбар — экран со своей шапкой обязан скрывать системный
  (`.toolbar(.hidden, for: .navigationBar)`), иначе рисуется вторая стрелка.
- Ассеты обязаны быть в `sources:` в `project.yml`, ключа `resources` нет —
  каталог, положенный не туда, молча не попадает в бандл.

Из `spec/DESIGN-TOKENS.md` (источник истины по числам):

- Палитра: только через токены `bg/card/card2/stroke/text/sub/dim` + акценты;
  светлая тема переопределяет только 7 поверхностных.
- Шкала текста: 8 ступеней (title-large 28, title-task 20, title 17, input 16,
  body 15, row 14, action 13, meta 12, caption 11, micro 10).
- 16pt зарезервирован под поля ввода, использовать его вне `<input>` нельзя.
- Отступы xs/sm/md/lg/xl = 4/8/12/16/24. Радиусы sm/md/lg/xl/sheet/full =
  6/8/12/16/20/9999.
- Граница везде 1px, цвет `stroke`.
- Тап-зона ≥ 44×44pt, иначе псевдорасширение.
- Иконки: `xs/sm/md/lg` = 14/18/22/26; запрещено число вне шкалы без
  замера по конкретному месту.
- На native шрифт — системный SF Pro (`Font.system`), свой шрифт заводить
  не нужно.
- На native ассеты токенов живут в `Color("bg")` и т.п. в Asset Catalog
  с двумя вариантами (Any/Dark), акцентные — одним вариантом.

## 1. Что я фактически нашёл (read-only, точечно)

### 1.1 Покрытие экранов стандартной шапкой — ✅ чисто

`tfNativeHeader` встречается в **26 файлах**. Проверил поштучно каждый из
«свежих» экранов (LOCK-146/189) и места, где подозревал самописные
шапки. Все 7 свежих экранов настроек и `AgentProfileScreen` — на
`tfNativeHeader`, без `safeAreaInset(edge: .top)` (поиск по `Features/`
дал **0 вхождений**):

- `Settings/SettingsScreen.swift:40` — `tfNativeHeader("Настройки")`
- `Settings/VoiceModelsScreen.swift:82` — `tfNativeHeader("Модели и голоса")`
- `Settings/RuntimeStatusScreen.swift:90` — `tfNativeHeader("Pi Runtime")`
- `Settings/RuntimeProvidersScreen.swift:54` — `tfNativeHeader("Модели и провайдеры")`
- `Settings/ProviderDetailScreen.swift:189` — `tfNativeHeader(viewModel.provider?.name ?? "Провайдер")`
- `Settings/ServiceAccountsScreen.swift:176` — `tfNativeHeader("Service Accounts")`
- `Chat/AgentProfileScreen.swift:43` — `tfNativeHeader(profile?.title ?? "Профиль")`

Единственные места с `.navigationTitle(...) + .navigationBarTitleDisplayMode(.inline)`
вне `tfNativeHeader` — это **шторки/модалки/формы** (легитимно, это не
экраны):

- `Chat/RoleChatsScreen.swift:428` — шторка «Новый чат» (Form).
- `Chat/ChatScreen.swift:570` — внутри ChatScreen (комната, уже под tfNativeHeader на строке 45).
- `Features/Notes/FolderPickerSheet.swift:41` — пикер папки (модалка).
- `Features/Upcoming/UpcomingScreen.swift:328` — шторка «Срок».
- `Features/Task/TaskFormScreen.swift:1889` — шторка «Связать задачу».

### 1.2 `.font(.system(size:))` — ⚠️ главная косметическая находка

**115 вхождений** в 39 файлах. По спеке §2 и по комментарию в самом
`Typography.swift:14–17` правило звучит так: 16pt зарезервирован под
текстовые поля, остальное — через ступени `TFFont`/`tfText(...)`, а
промежуточных размеров (9/18/19/20 кроме заголовка задачи) **нет** —
контент подтягивается к ближайшей ступени.

Топ-файлов по плотности «ручных размеров»:

| Файл                                  | Вхождений | Природа (по контексту)                                       |
| ------------------------------------- | --------- | ----------------------------------------------------------- |
| `Features/Task/QuickAddTaskView.swift`| 6         | legacy-fallback iOS 18 + кнопки со своей геометрией         |
| `Features/Settings/IntegrationsScreen.swift`| 5  | аккордеоны, иконки (между шкалой 14/18/22/26)              |
| `Features/Settings/TemplatesScreen.swift`| 5      | список шаблонов (иконки, метки)                            |
| `Features/Chat/ChatVoiceComposer.swift`| 5        | LOCK-194 IN_PROGRESS, новое — иконки + индикаторы           |
| `Features/Settings/VoiceModelsScreen.swift`| 4    | LOCK-189 REVIEW, новые строки + иконки                      |
| `Features/Today/TodayTaskRow.swift`   | 2         | строка задачи «Сегодня» — должно быть через TFFont         |
| `Features/Directory/NotificationsScreen.swift`| 3  | бейджи/иконки                                               |
| `Features/Directory/OverviewScreen.swift`| 4       | плитки «Обзора»                                             |
| `Features/Directory/ActivityScreen.swift`| 7       | график/сводка — часть легитимна (числовые оси)              |
| `Features/Chat/ChatComposer.swift`    | 4         | LOCK-194 IN_PROGRESS                                        |
| `Features/Directory/LabelsScreen.swift`| 4        | чипы меток                                                  |
| `Features/Directory/ActivityChart.swift`| 3       | оси графика, легитимны                                      |
| `Features/Today/TodayScreen.swift`    | 2         | фильтр-меню, заголовки разделов                             |
| `DesignSystem/Components/TFCheckbox.swift`| 4     | компонент дизайн-системы (можно, но проверить шкалу)        |
| `DesignSystem/Components/TFTextField.swift`| 3    | компонент дизайн-системы — внутри `TFFont.input`, ОК        |
| `DesignSystem/Components/TFBadge.swift`| 2        | компонент дизайн-системы — `caption`/мелочь, проверить      |

**Конкретные точки под вопросом** (требуют замера по спеке):

- `Features/Directory/OverviewScreen.swift` — 4 вхождения, плитки «Обзора»
  должны быть либо через `tfText()`, либо явно отмечены в спеке.
- `Features/Today/TodayTaskRow.swift:2` — **строка задачи** должна быть
  через `TFFont.body`/`TFFont.meta`/`TFFont.action` (15/12/13).
- `Features/Directory/NotificationsScreen.swift:3` — тексты бейджей,
  должны идти через `TFFont.caption`/`TFFont.meta`.
- `Features/Settings/VoiceModelsScreen.swift:4` — LOCK-189 уже REVIEW,
  но 4 ручных размера внутри — либо обоснованы, либо пропущены.
- `Features/Settings/IntegrationsScreen.swift:5` — LOCK-029 ещё до
  свежих — 5 ручных размеров в одном экране это сигнал «не сводилось».
- `Features/Settings/TemplatesScreen.swift:5` — то же.

**Это готовый предмет для LOCK `DS-AUDIT-FONT-SYSTEM`** — заменить
`.font(.system(size:))` на `tfText(...)`/`TFFont.*` там, где это не
компонент дизайн-системы и не замеренное число вне шкалы.

### 1.3 `scaleEffect` — ✅ ожидаемо

**8 вхождений**, все ожидаемые по AGENTS.md:

- `DesignSystem/Components/TFButton.swift:137` — `tap-scale` (0.94 на нажатии).
- `DesignSystem/Components/TFToggle.swift:15` — бегунок тумблера.
- `DesignSystem/Components/TFCheckbox.swift:184,266` — галка чекбокса.
- `Features/Today/TimelineScreen.swift:96` — `scaleEffect(active ? 1 : 0.95)` —
  переключение слоёв таймлайна (компонент собственного типа, ОК).
- `Features/Today/TodayHoursView.swift:286` — `scaleEffect(1.015)` на
  предпросмотре плашки (drag-визуал). Не через `TFAnimation.dragLift` —
  кандидат на унификацию.
- `Features/Upcoming/UpcomingHoursView.swift:759` — то же.

**Конкретный пункт:** если у `dragLift` есть токен (`TFAnimation.dragLift =
0.22`), то **сама длительность** — но `1.015` это не длительность, это
коэффициент scale. У `TFShadow.dragLift*` тоже нет «коэффициента
масштаба». Документация в `Metrics.swift` фиксирует только длительность.
Спека §5 требует `scale(1.04)` для drag-lift. У нас в коде `1.015` —
отличается от спеки в 7 раз. Это **расхождение со спекой**, на которое
стоит обратить внимание.

### 1.4 Материалы и `.ultraThinMaterial` — ⚠️ один кейс

Поиск по проекту (`Material\.`) — **0 вхождений**. Но `ultraThinMaterial`
встречается в **1 месте**: `Features/Task/QuickAddTaskView.swift:84` —
`.fill(.ultraThinMaterial)` поверх `Rectangle` для **затемнения фона**
под legacy-формой (iOS 18 fallback).

Это **легитимно по спеке** (`TaskFilterSheet` и т.п. используют
`.ultraThinMaterial` на нижней шторке), но **конфликтует с AGENTS.md**
«без собственных материалов и имитаций». По спеке скрим у нижней шторки
— «сплошной прозрачно-чёрный, без блюра». Это **прямое расхождение**:
у шторки `QuickAdd` есть блюр, у шторки `TaskForm` — нет (проверить).
Кандидат на «согласовать скрим-стиль между шторками».

### 1.5 `Color(hex:)` в `Features/` — ✅ ноль

Поиск `Color\(hex:` в `Sources/Features` — **0 вхождений**. Все цвета
идут через `tfRed`, `tfCard`, `tfSub` и т.п. из `Color+Palette.swift`.
Единственные 3 локальных `Color(hex:)` в `ActivityChart.swift:40–42`
(`chartGreen`/`chartBlue`/`chartCoral`) — это `Color+Palette.tfGreen`,
`tfBlue`, `tfCoral` соответственно. Дубли, готовые к замене одной строкой.

### 1.6 `clipShape(Circle())` — ⚠️ одно место

`clipShape(Circle())` в `Sources/` — **1 вхождение**:
`Features/Settings/EditProfileSheet.swift:191`. По спеке §Аватар:
**загруженное фото — `rounded-lg` 8pt (НЕ круг)**, инициалы — круг.
Если в `EditProfileSheet` это фото профиля — нарушение спеки. Если
инициалы-заглушка — то ок, но тогда должно быть `rounded-full`.

Кандидат на точечный разбор этого места.

### 1.7 Три реализации аватара — ⚠️ конкретный пункт

В проекте **3 реализации** «аватар агента/пользователя с фото»:

1. `DesignSystem/Components/TFAvatar.swift` — общий компонент дизайн-системы.
2. `Features/Chat/AgentRow.swift:59` — `RoleAvatarView` (приватный, 36pt).
3. `Features/Chat/AgentWorkTaskRow.swift:18` — `AgentWorkAvatarView`
   (приватный, переменный size).

В `AgentWorkTaskRow.swift:15–17` **сам комментарий** пишет:

> Третий дубль пары «аватар с фото / инициалы» в проекте (после TFAvatar
> и приватного AgentAvatarView в AgentRow.swift) — кандидат на вынос в
> DesignSystem с параметром размера, в отчёте оркестратору.

Это готовое предложение, оформленное самим автором кода, но не оформленное
как `IN_PROGRESS` в `AGENT-WORK-SCOPES.md`. **Конкретный LOCK-кандидат**:
`DS-AVATAR-CONSOLIDATION` — параметризовать `TFAvatar(urlPath:initials:size:tint:)`,
перевести `RoleAvatarView` и `AgentWorkAvatarView` на него.

### 1.8 `.tint(...)` и кастомные модификаторы цвета

7 вхождений `.tint(...)`:

- `DesignSystem/Components/TFToggle.swift` (×2) — компонент, ОК.
- `DesignSystem/Components/TFEmptyState.swift` — компонент, ОК.
- `Features/Task/QuickAddTaskView.swift` — проверить контекст.
- `Features/Task/TaskFormScreen.swift` — проверить контекст.
- `Features/Chat/AgentProfileScreen.swift` — LOCK-146, проверить.
- `Features/Chat/ChatVoiceComposer.swift` — LOCK-194, проверить.

Все четыре в `Features/` — **свежие** LOCK (146/194) или legacy. Если
`.tint` ставится поверх нативной кнопки iOS 26 — это легитимно
(`.glass`-кнопка подразумевает системный tint). Если поверх ручной —
нарушает AGENTS.md. Кандидат на проверку в рамках своего LOCK.

### 1.9 `.foregroundStyle(Color.…)` / `.foregroundColor(Color.…)` — ✅ ноль вне токенов

0 вхождений в `Features/`. Везде — `Color.tfSub`/`Color.tfText` и т.п.

### 1.10 `.opacity(0.X)` — крупный пласт (60 вхождений)

60 вхождений в 28 файлах. **Не всё плохо** — большая часть легитимна
(тогглы, даш-кольца, активные состояния). Но есть конкретные места с
«имитацией объёма через opacity + shadow + градиент» — кандидаты на
«нативное вместо имитации»:

- `Features/Task/QuickAddTaskView.swift:438–446` — `warmGlow` (тёплое
  свечение под капсулой инструментов в legacy-форме). Lock-144 это
  уже убирал на iOS 26 пути; осталось в legacy. **Легитимно по
  назначению** (legacy-форка), но **проверить, нельзя ли и там
  использовать системный `.glass`/`.buttonStyle(.bordered)`** на iOS 18.

- `Features/Today/TimelineLayers.swift:15, 78` — `LinearGradient(colors:
  [.clear, .white.opacity(0.2), .clear])` — fade-кромки слоёв. Это
  типовая имитация blur, для таймлайна легитимна (не «украшение»).

- `Features/Directory/ActivityChart.swift` — 11 вхождений. Большая
  часть — фон-альфы для секторов кольца/линии. Легитимны.

### 1.11 Голосовое (LOCK-194 IN_PROGRESS) — конкретные косметические риски

`Features/Chat/ChatVoiceComposer.swift` (LOCK-194):

- 5 вхождений `.font(.system(size:))` — рекорд для одного экрана. Это
  новое голосовое, **ещё не закрыто** — приёмка владельцем впереди.
  Сейчас владельцу важно «вид и поведение один-в-один с вебом», но
  когда закроют — имеет смысл прогнать аудит по шкале размеров.
- 1 вхождение `.tint(...)` — то же замечание, что в §1.8.

Это всё **не «улучшить сейчас»** — это «прогнать аудит сразу после
закрытия LOCK-194, пока контекст свежий».

### 1.12 Новые экраны настроек (LOCK-146/189) — точечный риск

Из 4 свежих экранов настроек:

- `RuntimeStatusScreen.swift` — 3 ручных размера, 1 `tfNativeHeader` ✅
- `RuntimeProvidersScreen.swift` — 1 ручный размер, 1 `tfNativeHeader` ✅
- `ProviderDetailScreen.swift` — 0 ручных размеров (чисто)
- `ServiceAccountsScreen.swift` — 2 ручных размера, 1 `tfNativeHeader` ✅
- `VoiceModelsScreen.swift` — 4 ручных размера, 1 `tfNativeHeader` ✅
- `EditProfileSheet.swift` — есть `clipShape(Circle())` (см. §1.6) ⚠️

**Самый «грязный» по ручным размерам** — `VoiceModelsScreen` (4). Это
экран ИИ-настроек, до него добрался LOCK-189 (REVIEW), но он самый
свежий и косметика ещё может быть «временной».

(Секции §1.2–§1.11 старой версии поглощены новым блоком §1.1–§1.12 выше.)

## 2. Что НЕ входит в этот план

- Любые фичи (новые экраны, новые сценарии, новая навигация).
- Любая серверная часть (`server/` живёт в `~/Projects/New-Todoist`, не
  наша).
- Web (`src/`), Capacitor (`ios/`).
- Realtime-логика, состояние стора, сетевой код.
- Drag-and-drop (есть свой цикл багфиксов, см. скилл `taskflow-app-development`
  для Mac-репо, а здесь не трогать без LOCK).
- Виджеты и Live Activity (`Widgets/`) — отдельный контур.
- Сборка, проект-структура, зависимости.

## 3. Конкретные LOCK-кандидаты (что предлагаю делать)

Ниже — **готовые** к оформлению в `AGENT-WORK-SCOPES.md` пункты, с
явными файлами и способом проверки. Приоритет по «конкретность /
готовность к одному коммиту».

### 3.1 `DS-AVATAR-CONSOLIDATION` — частично отменяется, частично подтверждается

**Перечитал `TFAvatar.swift`, `AgentRow.swift`, `AgentWorkTaskRow.swift`.**

В проекте три реализации, но **две из них — НЕ дубли**, а специализации:

1. `DesignSystem/Components/TFAvatar.swift` — общий компонент с двумя
   ветками (фото / инициалы), 5 размеров (`xs/sm/md/lg/xl`).
   **Общий файл — правит только каркасный исполнитель** (ARCHITECTURE.md).

2. `Features/Chat/AgentRow.swift:59` — `RoleAvatarView`. Только инициалы,
   `size * 0.4` (а не 0.43 как в `TFAvatar`), размер задаётся
   параметром. **Специализация** — здесь нет ветки с фото, потому что
   роль агента показывается всегда через инициалы (нет смысла грузить
   аватарку роли, она не настоящий человек). Спека §Аватар делит поведение
   на «фото — НЕ круг» / «инициалы — круг» — этот случай попадает во
   второе. **Не дубль, не правим.**

3. `Features/Chat/AgentWorkTaskRow.swift:18` — `AgentWorkAvatarView`.
   Имеет обе ветки (фото через `AnimatedImage` + инициалы), буквально
   повторяет логику `TFAvatar` (фото — `RoundedRectangle(8)`, инициалы —
   `Circle`). **Это настоящий дубль.** Сам комментарий в коде
   (`AgentWorkTaskRow.swift:15–17`) признаёт это.

**Что делать:** параметризовать вызов `TFAvatar` так, чтобы он
принимал URL (или `AnimatedImage`-обёртку) для ветки с фото, и заменить
`AgentWorkAvatarView` на `TFAvatar(urlPath:, initials:, tint:, size:)`.

**Файлы:**
- `Sources/DesignSystem/Components/TFAvatar.swift` (правка API — каркасный исполнитель).
- `Sources/Features/Chat/AgentWorkTaskRow.swift` — удалить `AgentWorkAvatarView`,
  использовать `TFAvatar`.

**Не трогать:**
- `Sources/Features/Chat/AgentRow.swift` — `RoleAvatarView` оставить как есть.

**Проверка:** `xcodebuild` + 1 кадр симулятора для
«Работа агентов» (`AgentWorkScreen`). Сравнить визуально до/после:
фото агента остаётся в `rounded-lg` 8pt (не круг), инициалы — круг.

### 3.2 `DS-AUDIT-FONT-SYSTEM` — пересмотрен, осталось меньше, чем казалось

**Перечитал 7 самых «грязных» файлов построчно. Главная находка:** большинство
вхождений `.font(.system(size:))` — это **иконки** (`Image(systemName:)`), а
не текст. Для иконок уже есть шкала `TFIconSize.xs/sm/md/lg = 14/18/22/26`,
и большинство размеров её соблюдает. Реальная проблема — **числа между
ступенями**: 10, 13, 16, 17, 20 для иконок (в шкале нет), плюс текстовые
13pt вместо `tfText(.action)`.

**3 группы по файлам:**

**Группа A — числа вне шкалы иконок (правка тривиальная):**
- `OverviewScreen.swift:117` — `Image(...).font(.system(size: 20))` → `TFIconSize.md` (22) или `TFIconSize.sm` (18). Размер 20 не из шкалы.
- `OverviewScreen.swift:141` — `size: 18` → `TFIconSize.sm`. Уже шкала, можно унифицировать.
- `OverviewScreen.swift:160,201` — `size: 13` для шеврона → `TFIconSize.xs` (14) или `caption` (11). 13pt — текстовая ступень `action`, для иконок не из шкалы.
- `NotificationsScreen.swift:135` — `Text(...).font(.system(size: 14, weight: .semibold))` на инициалах — это **текст** в кружке 36×36. Должно быть `tfText(.meta)` (12/semibold) или `tfText(.row)` (14). Проверить замером.
- `NotificationsScreen.swift:142` — `size: 17` для `gearshape` → `TFIconSize.sm` (18). 17 не из шкалы.
- `LabelsScreen.swift:100,123,132` — `size: 16` → между `xs/sm`. Заменить на `TFIconSize.sm` (18) или `xs` (14).
- `TodayTaskRow.swift:168` — `size: 10` для иконки «number» → `TFIconSize.xs` (14, слишком большой) или оставить 10 как замеренное число. **По спеке**: «10px иконка внутри бейджей» — это разрешённое место вне шкалы.
- `IntegrationsScreen.swift:296,544,584,597,632` — все на иконках: `16, 11, 15, 13, 12`. Все вне шкалы для иконок. 16 → `TFIconSize.sm` или `xs`; 13, 12 → либо `TFIconSize.xs` либо явно замеренные.
- `TemplatesScreen.swift:78,180,347,351,378` — `TFIconSize.xs` (легитимно), `size: 12` (вне шкалы), `TFIconSize.xs` (легитимно), `TFIconSize.xs`, `size: 13`. 12 и 13 — вне шкалы.

**Группа B — текст через `.font(.system)` вместо `tfText`:**
- `VoiceModelsScreen.swift:358,697,731` — `.font(.system(size: 13, weight: .medium))` на тексте кнопок. Должно быть `tfText(.action)` (`13pt/regular`). Разница только в weight (.medium vs .regular) — нужно решить, осознанная или нет.
- `IntegrationsScreen.swift:597` — `.font(.system(size: 13))` на подписи → `tfText(.action)`.

**Группа C — не трогаем:**
- `ChatVoiceComposer.swift:46,71,100,118,158` — LOCK-194 в работе, `size: 20/medium` — это новая ступень или `taskTitle` с другим весом. До приёмки не правим.
- `QuickAddTaskView.swift` legacy-fallback — отдельная ветка для iOS 18.

**Что делать:** один LOCK `DS-AUDIT-FONT-SYSTEM` — заменить числа вне шкалы и текстовые места в группах A и B. ~15 правок в ~7 файлах. Не один коммит, а **серия** (по файлу).

**Проверка:** `xcodebuild` + кадры симулятора по одному на экран + сравнение с тем, что было.

**Грабли:** `tfText(...)` сейчас — `Font.system(size:weight:)`, без
`design: monospaced`. Если где-то нужен моноширинный — это `tfMonospaced`,
не `tfText`. Проверить построчно. Также `tfText(.action)` = 13/regular,
а в `VoiceModelsScreen` код использует 13/medium — перед заменой
сверить, что владельцу подходит regular (вероятно да — это кнопка-чип).

### 3.3 `DS-AUDIT-DRAG-GHOST-SCALE` — `1.015` осознанно, но без токена

**Перечитал.** Эти `scaleEffect(1.015)` — **не drag-lift задачи**, а
**ghost-плашка в сетке часов** при перетаскивании (`ghostView(_:)`).
Другая механика, другое число, осознанно малое (визуальный «призрак»
не должен прыгать при движении пальца).

**Что делать:** вынести `1.015` в `Metrics.swift` как токен, чтобы
число не висело числом в коде.

**Файлы:**
- `Sources/DesignSystem/Theme/Metrics.swift` — добавить
  `dragGhostScale: CGFloat = 1.015` в группу `TFAnimation` (или новая группа).
- `Sources/Features/Today/TodayHoursView.swift:286` — `.scaleEffect(1.015)` → `.scaleEffect(TFAnimation.dragGhostScale)`.
- `Sources/Features/Upcoming/UpcomingHoursView.swift:759` — то же.

**Не трогать** число `1.015` → не увеличивать до `1.04` (это другая механика).

**Проверка:** `xcodebuild` + кадр симулятора «Сегодня → По часам» при
перетаскивании плашки.

### 3.4 ~~`DS-AUDIT-SHEET-SCRIM`~~ — отменяется

**Перечитал.** В `TFBottomSheet.swift` шторка **не использует свой
фон вообще** — там `NavigationStack` поверх системного `.sheet`, скрим
идёт системный. А `QuickAddTaskView.swift:84` с `.fill(.ultraThinMaterial)`
— это **фон legacy-форка iOS 18**, а не скрим затемнения. Контекст
другой, механика другая. AGENTS.md разрешает «своё» в legacy-форке для
старых ОС. **Пункт снимается.**

### 3.5 `DS-AUDIT-EDIT-PROFILE-AVATAR-CLIP` — `clipShape(Circle())` в `EditProfileSheet`

**Что:** `EditProfileSheet.swift:191` — единственное место с
`clipShape(Circle())` на аватаре в проекте. Спека §Аватар прямо
запрещает круг для фото.

**Файлы:**
- `Sources/Features/Settings/EditProfileSheet.swift:191`

**Проверка:** открыть «Настройки → Редактировать профиль», посмотреть
как клипится фото профиля. Если это фото — нарушение спеки (должно
быть `RoundedRectangle(cornerRadius: TFRadius.md)`). Если это инициалы —
ОК, но всё равно проверить, что фон не «слипается» с цветом карточки.

### 3.6 `DS-AUDIT-ACTIVITY-CHART-COLORS` — три локальных hex в `ActivityChart`

**Что:** `ActivityChart.swift:40–42` объявляет
`chartGreen/chartBlue/chartCoral = Color(hex: ...)`, которые буквально
совпадают с `Color+Palette.tfGreen/tfBlue/tfCoral` (`Color+Palette.swift:67/57/63`).

**Файлы:**
- `Sources/Features/Directory/ActivityChart.swift:40–42` — удалить,
  заменить обращения на `Color.tfGreen/tfBlue/tfCoral`.

**Проверка:** `xcodebuild` + кадр симулятора «Активность».

### 3.7 `DS-AUDIT-VOICEMODELS-ICONS` — после закрытия LOCK-194/189

**Перечитал.** `ChatVoiceComposer.swift:46,71,100,118,158` — все 5 вхождений
`.font(.system(size: 20, weight: .medium))`. Это **20pt/medium** — почти
`taskTitle` (20/semibold), но с другим weight. LOCK-194 в работе,
приёмка владельцем впереди. До приёмки **не правим** — может быть
задуманная новая ступень для голосового композитора.

`VoiceModelsScreen.swift:358,697,731` — три `.font(.system(size: 13, weight:
.medium))` на тексте кнопок. LOCK-189 REVIEW, но это **текст**, и замена
на `tfText(.action)` (13/regular) тривиальна. **Можно править независимо
от LOCK-189** (этот код уже сдан, не в работе).

**Что делать:**
- `VoiceModelsScreen.swift:358,697,731` — заменить на `tfText(.action)`.
  Сверить визуально, не стало ли тоньше (regular vs medium).
- `ChatVoiceComposer.swift` — **отложить** до LOCK-194 → DONE.

### 3.8 `DS-AUDIT-LIGHT-THEME-DYNAMIC` — ассеты не используются

**Перечитал `Resources/Assets.xcassets/` и `project.yml`.**

В `Resources/Assets.xcassets/` — **нет ни одного colorset**. Все
цветовые токены (`tfBackground/tfCard/tfCard2/tfStroke/tfText/tfSub/
tfDim`) живут в `Color+Palette.swift` через `dynamic(dark:light:)`.

В `project.yml:65` стоит `UIUserInterfaceStyle: Dark` — принудительная
тёмная тема на уровне Info.plist.

Светлая тема в коде **достижима**, но только если пользователь
временно переключит `.environment(\.colorScheme, .light)` (DEBUG-превью
или будущий тумблер).

**Что делать:** один LOCK `DS-AUDIT-LIGHT-THEME-DYNAMIC` — проверить,
что **все 7 поверхностных токенов** имеют обе ветки `dynamic()`:

```
tfBackground: ✓ dynamic("#171717", "#f4f4f5")        (Color+Palette.swift:26)
tfCard:       ✓ dynamic("#242424", "#ffffff")        (28)
tfCard2:      ✓ dynamic("#2b2b2b", "#ececee")        (30)
tfStroke:     ✓ UIColor динамически                  (39–43)
tfText:       ✓ dynamic("#ffffff", "#171717")        (32)
tfSub:        ✓ dynamic("#a6a6a6", "#5c5c5c")        (34)
tfDim:        ✓ dynamic("#949494", "#9a9a9a")        (36)
```

**Все 7 уже имеют обе ветки.** Пункт не требует правки кода — это
**проверка, что будущий тумблер светлой темы работает «из коробки»**.

**Что НЕ делать:** не убирать `UIUserInterfaceStyle: Dark` из
`project.yml` — это явное решение владельца (LIGHT отключён намеренно).

**Проверка:** временно в DEBUG-экране сделать переключатель
`.environment(\.colorScheme, .light)` и снять кадры всех основных
экранов. Это **вне обычных коммитов**, отдельный одноразовый скрипт.

### 3.9 ~~`DS-AUDIT-TAP-ZONES-A11Y`~~ — отменяется

**Перечитал все 16 мест `onTapGesture` в 9 файлах.**

**Каждое** имеет `contentShape(...)` перед `.onTapGesture`:
- `contentShape(Rectangle())` — для строк (тап-зона = вся строка, высота 44+).
- `contentShape(Circle())` — для круглых тап-целей (например,
  `ActivityChart.swift:396`, frame `width: 32, height: 32` — меньше 44,
  но это тап по сектору кольца графика, у которого «полная» тап-зона —
  вся окружность вокруг).

Все тап-цели либо ≥44pt сами по себе (строки, кнопки), либо расширены
через `contentShape()`. **Нарушений нет. Пункт снимается.**

### 3.10 ~~`DS-AUDIT-SHEET-RADIUS-RECURSIVE`~~ — отменяется

**Проверено ранее**, в `Features/` — **ноль** `RoundedRectangle(cornerRadius: 20)`.
Все скругления идут через токены `TFRadius.sheet` (20pt только для
нижней шторки), `TFRadius.xl/lg/md` для остального. **Пункт снимается.**

## 4. Что я НЕ делал и почему

- Не открывал каждый файл из списка выше — это уже **правки**, а не
  аудит. Read-only инвентаризация без открытия каждой вьюхи даёт
  только верхнеуровневую карту (как этот план). Точечные находки —
  следующий шаг, и только под конкретный LOCK в `AGENT-WORK-SCOPES.md`.
- Не делал `xcodebuild` и не запускал симулятор — это требует живого
  окружения, UDID и debug-токена; регламент сборки — в `CLAUDE.md`.
- Не правил ни одного файла — ни одного `patch`/`write_file` в коде.
  Этот файл создан в `docs/`, а не в `Sources/`, чтобы `xcodegen` его
  не подхватил и чтобы он не считался «исходником».

## 5. Связанные артефакты

- `AGENT-WORK-SCOPES.md` — реестр задач; каждый пункт из §3 станет
  отдельной строкой со статусом `IN_PROGRESS` и явным списком файлов.
- `ARCHITECTURE.md` — кто что правит; здесь работает только
  каркасный исполнитель (правки в `Core/`, `DesignSystem/`, `App/`,
  `project.yml` — не моё).
- `spec/DESIGN-TOKENS.md` — источник истины по числам. Любая
  косметическая правка сверяется с этой спекой.
- `CLAUDE.md` — регламент сборки и проверки; UI-баг проверяется
  кадром симулятора, не на глаз.
- `AGENTS.md` — правило «нативный = чистый, без своих модификаторов».