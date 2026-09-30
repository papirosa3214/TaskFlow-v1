# TaskFlow — эталон дизайн-системы (по коду, 23.09.2026)

Источник истины — сам код приложения. Файл не придумывает новых значений,
только собирает то, что уже есть в `Sources/DesignSystem/Theme/`, чтобы
дальше сверять экраны с одним местом, а не искать по всему проекту.

## Цвета (Color+Palette.swift)

### Фон и поверхности
| Токен | Тёмная тема | Светлая тема | Назначение |
|---|---|---|---|
| `tfBackground` | `#171717` | `#f4f4f5` | фон экрана |
| `tfCard` | `#242424` | `#ffffff` | карточка / плашка |
| `tfCard2` | `#2b2b2b` | `#ececee` | вторая, более светлая поверхность (когда карточка на карточке) |
| `tfSheetBackground` | `#1D1D1D` | — | фон шторки/меню, между tfBackground и tfCard |

⚠️ `tfCard` и `tfCard2` отличаются всего на 7 пунктов яркости (#242424 vs
#2b2b2b) — на глаз почти не различить. Прежде чем заводить третий оттенок,
свериться, действительно ли обоим нужно разное значение, или это можно свести
к одному.

### Текст
| Токен | Тёмная тема | Назначение |
|---|---|---|
| `tfText` | `#ffffff` | основной текст |
| `tfSub` | `#a6a6a6` | подзаголовок, вторичный текст (185 мест в коде) |
| `tfDim` | `#949494` | приглушённая иконка/лейбл (158 мест в коде) |

⚠️ `tfSub` (#a6a6a6) и `tfDim` (#949494) — два очень похожих светло-серых,
разница 18 пунктов. Оба активно используются (185 и 158 раз). Разделение по
смыслу («текст» vs «иконка») существует, но визуально почти неразличимо —
кандидат на объединение или явную проверку, точно ли разница нужна.

### «Чёрный», которого не должно быть
В приложении НЕТ сплошной заливки чёрным (`Color.black` только с прозрачностью
0.09–0.55 для теней/оверлеев — это нормально). То, что читается как чёрный, —
это `tfBackground` (#171717), он специально настолько тёмный, что визуально
неотличим от настоящего чёрного. Не баг, но стоит решить: это осознанный выбор
или фон стоит сделать заметно светлее, чтобы не путать с чёрным.

### Обводка
`tfStroke` — единственная граница: белая (тёмная тема) / чёрная (светлая) с
прозрачностью 9%, не сплошной цвет.

### Акценты (одинаковы в обеих темах)
| Токен | Hex | Назначение |
|---|---|---|
| `tfRed` | `#e44332` | главный акцент: активная вкладка, «сегодня», просрочка, удаление |
| `tfRedSolid` | `#d63a28` | заливка под белый текст (у tfRed недостаточный контраст 4.08:1) |
| `tfOrange` | `#ff9a14` | предупреждение, высокий приоритет, «заблокировано» |
| `tfBlue` | `#4a9fd8` | средний приоритет, «на проверке/ревью» |
| `tfGreen` | `#15937e` | успех/готово (не всегда — см. находку №4) |
| `tfTeal` | `#35b8a3` | ещё один зелёно-бирюзовый — используется отдельно от tfGreen |
| `tfPurple` | `#a78bfa` | роль «Агент» |
| `tfPink` | `#ff7a8a` | — |
| `tfYellow` | `#f7d038` | — |
| `tfCoral` | `#ff6b6b` | — |

⚠️ `tfGreen` (#15937e) и `tfTeal` (#35b8a3) — оба зелёно-бирюзовые, оба
встречаются как обозначение «успех/выполнено/в работе» в разных местах
(см. находку №4). Нужно решить, какой из них — канонический «успех».

## Отступы и радиусы (Metrics.swift)
- `TFSpacing`: xs=4, sm=8, md=12, lg=16, xl=24
- `TFRadius`: sm=6, md=8, lg=12, xl=16, sheet=20, full=9999, pill=4
- `TFBorder.width` = 1
- Тап-зона минимум: 44pt

## Иконки — правило
Только SF Symbols, системные, без своих SVG-аналогов. Размер = размеру шрифта
рядом (`TFIconSize.sm`=18 и т.д.), не константа "24 на всё".

## Шапки экранов
Только `.tfNativeHeader(_:displayMode:)`, без своих `TFScreenHeader`/`FrostedGlass`
и т.п. (см. правило в CLAUDE.md). displayMode по умолчанию `.large`.

## Повторяющиеся навигационные элементы — аудит 25.09.2026

По просьбе владельца: посчитано по всему `Sources/` (без `archive/`), с точными
координатами `file:line`, чтобы потом можно было сразу открыть место, а не
искать заново.

### Кнопка «Назад»
Своя стрелка (не системная кнопка `NavigationStack`) — только 2 места, и обе
осознанно:
- [Directory/ActivityChart.swift:128](../Sources/Features/Directory/ActivityChart.swift) — «назад» из drill-down графика, локальное состояние, не экранная навигация.
- [Chat/ChatScreen.swift:54](../Sources/Features/Chat/ChatScreen.swift) — своя стрелка только когда экран корневой во вкладке (иначе рисовалась вторая поверх системной, LOCK-195, разбор в коде).

Не дубль — не трогать.

### Всплывающие окна («снизу»)
6 разных механизмов вместо одного:

| Механизм | Мест | Файлов |
|---|---|---|
| `.sheet(` сырой | 32 | 17 |
| `.tfBottomSheet(` (общий компонент) | 8 | 7 |
| `.confirmationDialog(` | 12 | — |
| `.alert(` (по центру, не снизу) | 19 | — |
| `.fullScreenCover(` | 5 | — |
| `.popover(` | 3 | — |

Живой пример разницы (проверено в симуляторе 25.09.2026, iPhone 17 Pro):
- Сырой `.sheet(item: $sheetTaskID)` — [Today/TodayScreen.swift:178-188](../Sources/Features/Today/TodayScreen.swift): открытие карточки задачи. Сам ставит `.presentationDetents([.medium, .large])`, `.presentationDragIndicator(.visible)`, `.presentationCornerRadius(TFRadius.sheet)`, `.presentationBackground(Color.tfSheetBackground)`. Визуально — своя шапка внутри контента: `X` слева, заголовок «Задача» по центру, «…» справа, как отдельный навбар.
- `.tfBottomSheet(isPresented: $isEditProfilePresented)` — [Settings/SettingsScreen.swift:43](../Sources/Features/Settings/SettingsScreen.swift), контент [Settings/EditProfileSheet.swift](../Sources/Features/Settings/EditProfileSheet.swift): «Редактировать профиль». Визуально — только тонкий системный грабер сверху, заголовок — обычный жирный текст ПЕРВОЙ строкой контента (не в навбаре), закрытие — кнопками «Отмена»/«Сохранить» внизу, никакого отдельного `X`/`…`.

Оба открывают «окно снизу», но с разной анатомией шапки/закрытия — это и есть предмет разбора: осознанная разница жанров (карточка-документ vs форма-редактор) или дрейф, который стоит свести к одному компоненту. Сырых `.sheet(` в 4 раза больше, чем через `TFBottomSheetContent`. 14 файлов
ни разу не заходят в общий компонент шторки: `App/Navigation/RootShellView.swift`,
`Chat/AgentProfileScreen.swift`, `Chat/AgentWorkScreen.swift`,
`Directory/LabelTasksScreen.swift`, `Chat/RoleChatsScreen.swift`,
`Chat/ChatBubble.swift`, `Chat/AgentsScreen.swift`, `Task/TaskFormScreen.swift`,
`Directory/ProjectTasksScreen.swift`, `Task/Support/TaskConfirm.swift`,
`Directory/Support/DirectoryConfirm.swift`, `Upcoming/UpcomingScreen.swift`,
`Notes/NotesScreen.swift`. Часть — законно системные (`.confirmationDialog`/
`.alert`, другой смысл), но часть сырых `.sheet(` — кандидаты на перевод в
`TFBottomSheetContent`, если у них тот же паттерн «заголовок + кнопка
действия». Смотреть предметно по каждому файлу — не решать здесь.

### Кнопка «Фильтр»
3 разных SF Symbol под одно понятие:
- `line.3.horizontal.decrease` — [Upcoming/UpcomingScreen.swift:405](../Sources/Features/Upcoming/UpcomingScreen.swift), [Today/TodaySectionView.swift:271](../Sources/Features/Today/TodaySectionView.swift), [Today/TodayScreen.swift:288](../Sources/Features/Today/TodayScreen.swift), [Directory/ActivityScreen.swift:84](../Sources/Features/Directory/ActivityScreen.swift) — лидер, 4 места.
- `line.3.horizontal.decrease.circle.fill` — [Directory/ProjectsScreen.swift:138](../Sources/Features/Directory/ProjectsScreen.swift).
- `slider.horizontal.3` — [Directory/SystemControlSection.swift:184](../Sources/Features/Directory/SystemControlSection.swift) — там смысл скорее «настройка», а не фильтр списка; проверить по месту, не дрейф ли это.

(`TFButton.swift:166` — строка `#Preview`, не реальное использование, в счёт не идёт.)

### Кнопка «Ещё» (три точки)
11 мест, символ один и тот же (`ellipsis`) — порядок, не проблема:
[Today/TodayScreen.swift:170](../Sources/Features/Today/TodayScreen.swift),
[Task/TaskFormScreen.swift:1420,1099](../Sources/Features/Task/TaskFormScreen.swift),
[Notes/NotesScreen.swift:250,200](../Sources/Features/Notes/NotesScreen.swift),
[Notes/NoteEditorScreen.swift:251](../Sources/Features/Notes/NoteEditorScreen.swift),
[Directory/ProjectsScreen.swift:196](../Sources/Features/Directory/ProjectsScreen.swift),
[Chat/RoleChatsScreen.swift:755,1251](../Sources/Features/Chat/RoleChatsScreen.swift),
[Chat/ChatScreen.swift:86](../Sources/Features/Chat/ChatScreen.swift).

### Кнопка «Закрыть» (крестик)
2 варианта: голый `xmark` — 13 мест, `xmark.circle`(`.circle`/`.circle.fill`) — 3 места:
[Settings/ServerStatusSection.swift:162](../Sources/Features/Settings/ServerStatusSection.swift),
[Settings/IntegrationsScreen.swift:475](../Sources/Features/Settings/IntegrationsScreen.swift),
[Chat/RoleChatsScreen.swift:730](../Sources/Features/Chat/RoleChatsScreen.swift).

### Кнопка подтверждения
Как самостоятельная иконка-кнопка в тулбаре (`checkmark`, не чекбокс/бейдж/
отметка выбора) — ровно 2 места, в обоих паре с `xmark` слева на закрытие:
- [Chat/RoleChatsScreen.swift:502](../Sources/Features/Chat/RoleChatsScreen.swift) — «Создать чат».
- [Upcoming/UpcomingScreen.swift:299](../Sources/Features/Upcoming/UpcomingScreen.swift) — «Готово».

Текстом: `"Готово"` — 7 мест, `"Сохранить"` — 8 мест (итого 15 текстовых
подтверждений). Остальные ~70 вхождений `checkmark*` по проекту — чекбоксы,
отметки выбора в списках и бейджи «проверено» (`checkmark.seal`), это другая
сущность, не кнопка подтверждения — в сводку не включены.

### Круглые подложки под кнопками тулбара — НЕ код
То, что визуально выглядит как «кругляшки» вокруг иконок в шапке — не
собственная разметка: `TFIconButton` (`Components/TFButton.swift:105-127`)
рисует только иконку + тап-зону 44×44, без `Circle()`/фона. По всему `Sources/`
`.clipShape(Circle())` встречается 1 раз (аватар в `EditProfileSheet.swift:191`,
не кнопка), `.background(Circle(` — 0 раз. Круглую/стеклянную подложку тулбара
рисует сама система (iOS 26), одинаково для всех кнопок в `ToolbarItem` — то
же самое явление, что и системный скролл-эффект шапки (см. правило в
`CLAUDE.md` про `.tfNativeHeader`). Единообразно по определению — сверять не
с чем.

## Открытые вопросы дизайна (не решать в одиночку — спросить владельца)
1. Поиск: кнопка-переход (Обзор) vs инлайн-поле (Проекты/База знаний) — выбрать один паттерн.
2. Состояния задачи «в работе/на проверке/заблокировано/выполнено» — три независимых набора иконок+цветов (Обзор / карточка проекта / строка агента в чате). Нужен один источник.
3. tfSub vs tfDim, tfGreen vs tfTeal, tfCard vs tfCard2 — решить, оставлять ли оба или сводить к одному.
4. Фильтр — 3 разных SF Symbol на одно понятие (`line.3.horizontal.decrease` / `.circle.fill` / `slider.horizontal.3`) — свести к одному или оставить осознанно разным (см. аудит выше).
5. 14 файлов используют сырой `.sheet(` мимо общего `TFBottomSheetContent` — решить, что из них стоит перевести на общий компонент, а что законно остаётся системным (см. аудит выше).
6. Крестик закрытия — `xmark` vs `xmark.circle` (3 места) — свести к одному варианту или оставить.
