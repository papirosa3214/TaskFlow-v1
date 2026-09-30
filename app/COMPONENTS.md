# TaskFlow — каталог UI-компонентов (по коду, 24.09.2026)

Источник истины — `Sources/DesignSystem/`. Цель файла: перед тем как рисовать
новую кнопку/карточку/бейдж/строку — сначала проверить здесь, нет ли уже
готового компонента. Одна и та же кнопка с другим радиусом/размером — это не
новый компонент, а забытый параметр существующего.

**Правило использования:**
1. Нужен UI-элемент — сначала ищи в этом файле, потом в `Sources/DesignSystem/`.
2. Похожий компонент есть, но не хватает варианта/размера — расширь его
   параметром (новый `case` в его enum, новый именованный аргумент), не заводи
   параллельный. Компонент не в `IN_PROGRESS` в `AGENT-WORK-SCOPES.md` — сначала
   завести строку по правилам `CLAUDE.md`.
2.1. Правка компонента задевает несколько экранов сразу — это и есть
   ожидаемое поведение дизайн-системы, а не повод его форкнуть под один экран.
3. Совсем новый паттерн, которого точно нет ниже, — заводи в
   `Sources/DesignSystem/Components/`, с публичным `init`, и добавь строку в
   этот файл в том же коммите.
4. Токены (цвета, отступы, радиусы, шрифты) — не здесь, а в [DESIGN.md](DESIGN.md)
   (`Sources/DesignSystem/Theme/`). Этот файл — про готовые View, DESIGN.md —
   про сырые значения, из которых они собраны.
5. Шапка экрана — не компонент из списка ниже, а системный модификатор
   `.tfNativeHeader(_:displayMode:)`, свои шапки не рисуем (см. `CLAUDE.md`).

Актуальность сверяй по факту: комментарии в коде часто новее, чем этот файл.

---

## Кнопки — `Components/TFButton.swift`

| Компонент | Что это | Параметры |
|---|---|---|
| `TFButtonVariant` | `enum`: `.primary` (red-solid), `.secondary` (card2 + рамка), `.outline` (прозрачный + рамка) | — |
| `TFButton` | Полноширинная кнопка, `height` 48 (растёт с Dynamic Type), радиус `TFButtonMetrics.radius` (=`TFRadius.lg`=12) | `title, icon: String? = nil, variant: TFButtonVariant = .primary, isEnabled: Bool = true, action` |
| `TFIconButton` | Кнопка-иконка, прозрачный фон, тап-зона 44×44, иконка `size: CGFloat = TFIconSize.sm` (18) | `icon, label: String` (обязателен — VoiceOver), `size`, `action` |
| `TFTapScaleStyle` | `ButtonStyle`: мгновенное сжатие до 0.94 без анимации возврата — реакция на тап по умолчанию | — |
| `TFTapRowStyle` | `ButtonStyle`: лёгкая подсветка фона при нажатии — для строк списка | — |
| `TFTapFadeStyle` | `ButtonStyle`: снижение непрозрачности до 0.85 — для текстовых ссылок/CTA | — |

Нужна кнопка с иным радиусом/высотой — это не третий вариант `TFButton`,
а нарушение единой шкалы (все кнопки 48pt/12px радиус). Сначала спросить,
точно ли нужно расходиться с образцом.

## Карточки, секции, строки списка — `Components/TFCard.swift`

| Компонент | Что это | Параметры |
|---|---|---|
| `TFCard<Content>` | Универсальная карточка: скруглённый фон-подложка + контент | `padding: CGFloat = TFSpacing.lg, @ViewBuilder content` |
| `TFSectionHeader` | Заголовок секции приглушённым текстом с отступами экрана | `_ title: String` |
| `TFListRow` | Универсальная строка списка: иконка (цветная/простая), заголовок, подзаголовок, `trailing`, действие по тапу | `icon, iconTint: Color = .tfRed, iconStyle: IconStyle = .tinted, title, subtitle: String? = nil, trailing: AnyView? = nil, titleStyle: TFTextStyle = .body, verticalPadding: CGFloat = TFSpacing.md, action: (() -> Void)? = nil` |
| `TFListRow.IconStyle` | `enum`: стиль отображения иконки в строке (`.tinted` / простая) | — |
| `TFDivider` | Горизонтальный разделитель между строками | `inset: CGFloat = 0, dimmed: Bool = false` |

`TFListRow` — универсальная строка настроек/меню с иконкой слева. Для строки
задачи используй `TFTaskRow` (ниже), не `TFListRow` — у неё другая модель.

## Бейджи и пилюли — `Components/TFBadge.swift`

| Компонент | Что это | Параметры |
|---|---|---|
| `TFPill` | Базовая пилюля: текст на полупрозрачном или сплошном фоне заданного цвета | `_ text: String, color: Color, backgroundOpacity: Double = 0.15, solidBackground: Color? = nil` |
| `TFPriorityArrows` | Иконка приоритета задачи (стрелки) | `_ priority: TaskPriority` |
| `TFLabelPill` | Пилюля метки задачи, фон 15% | `_ title: String, color: Color` |
| `TFOverduePill` | Фиксированная пилюля «Просрочено», красная 15% | `()` — без параметров |
| `TFDuePill` | Пилюля срока (дата/время) на фоне карточки, серый текст | `_ text: String` |
| `TFAccentTag` | Акцентный тег для разделов (напр. «Second Brain»), фон 18%, полужирный | `_ text: String, color: Color` |

Любая новая «плашка с текстом и цветом» — сначала проверь, не покрывает ли её
`TFPill` напрямую (это база, на которой построены остальные четыре).

## Аватар — `Components/TFAvatar.swift`

| Компонент | Что это | Параметры |
|---|---|---|
| `TFAvatar` | Фото (радиус `TFRadius.md`, НЕ круг) или инициалы-заглушка (круг, цвет пользователя) | `size: Size = .lg, image: Image? = nil, initials: String, tint: Color = ..., accessibilityLabel: String? = nil` |
| `TFAvatar.Size` | `enum: CGFloat` — `.xs`=18 (строка карточки доски), `.sm`=20 (строка задачи), `.md`=30, `.lg`=32 (по умолчанию), `.xl`=44 (список чатов, ведущий элемент строки) | — |

Новый размер аватара — это новый `case` в `TFAvatar.Size`, а не отдельный
компонент.

## Строка задачи — `Components/TFTaskRow.swift`

| Компонент | Что это | Параметры |
|---|---|---|
| `TFTaskRowModel` | Данные строки: проект, исполнитель, статус, приоритет, дедлайн, метки | `projectName, projectColor, assigneeInitials, assigneeColor, title, isDone, description, agentStatus, agentStatusColor, subtasksDone, subtasksTotal, priority: TaskPriority?, isOverdue, dueText, labels: [(title, color)]` — все опциональные кроме `title` |
| `TFTaskRow` | Строка задачи с асимметричными отступами, условный рендер бейджей приоритета/статуса | `_ model: TFTaskRowModel, action: @escaping () -> Void` |

Единственный компонент для отображения задачи строкой — используется на
«Сегодня», в проектах, «Предстоящих», «Работе агентов». Новый экран со списком
задач — сюда, не новую строку с нуля.

## Чекбоксы и статусы подзадач — `Components/TFCheckbox.swift`

| Компонент | Что это | Параметры |
|---|---|---|
| `TFCheckbox` | Бинарный статус: заполненный зелёный круг с галочкой / контурное кольцо | `isChecked: Bool, label: String? = nil, action: (() -> Void)? = nil` |
| `TFSubtaskState` | `enum`: `.done, .running, .pending, .blocked, .review` — пять состояний подзадачи, у каждого `label` для VoiceOver | — |
| `TFSubtaskStatusRing` | Визуальный индикатор состояния подзадачи (кольцо/точки/треугольник/глаз в зависимости от состояния), с анимацией для активных | `_ state: TFSubtaskState` |

Простое «сделано/не сделано» — `TFCheckbox`. Пять состояний подзадачи (в
работе/ожидает/заблокировано/на проверке/готово) — `TFSubtaskStatusRing`, не
изобретай шестое состояние без согласования (см. открытый вопрос №2 в
DESIGN.md про разные наборы статус-иконок по экрану).

## Поля ввода — `Components/TFTextField.swift`

| Компонент | Что это | Параметры |
|---|---|---|
| `TFTextField` | Поле ввода: фон карточки, скругление, шрифт 16px (`.input`), опциональная иконка слева | `_ placeholder: String, text: Binding<String>, icon: String? = nil` |
| `TFFieldRow` | Строка в группе полей: иконка + заголовок + значение справа + шеврон, тап открывает действие | `icon, title, value, valueColor: Color = .tfSub, action: @escaping () -> Void` |
| `TFFieldGroup<Content>` | Карточка-контейнер для группы `TFFieldRow` | `@ViewBuilder content` |
| `TFFieldDivider` | Разделитель между строками внутри `TFFieldGroup` | `()` |

`TFFieldRow`+`TFFieldGroup` — стандартный паттерн для «списка настроек в
карточке» (см. экраны настроек). Не собирай такую карточку вручную из `VStack`.

## Тумблер — `Components/TFToggle.swift`

| Компонент | Что это | Параметры |
|---|---|---|
| `TFToggle` | Системный `Toggle`, масштаб 82%, `.tint(.tfRed)` | `isOn: Binding<Bool>` |

Единственный тумблер в приложении. Не ставь голый системный `Toggle()` —
у него другой масштаб и системный (не красный) акцент.

## Нижняя шторка — `Components/TFBottomSheet.swift`

| Компонент | Что это | Параметры |
|---|---|---|
| `TFBottomSheetContent<Content>` | `NavigationStack`-обёртка: заголовок + кнопка действия, без кастомного хрома | `title: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil, onClose, @ViewBuilder content` |
| `.tfBottomSheet(...)` | Модификатор `View`, подключает системную нижнюю шторку с детентами и индикатором | `isPresented: Binding<Bool>, title, actionTitle, action, @ViewBuilder content` |

Любая шторка/лист — через `.tfBottomSheet(...)`, не через ручной `.sheet` со
своим фоном/индикатором.

## Пустые состояния, загрузка, ошибки — `Components/TFEmptyState.swift`, `Components/TFLoading.swift`

| Компонент | Что это | Параметры |
|---|---|---|
| `TFEmptyState` | Обёртка над `ContentUnavailableView` — единый вид пустого состояния | `icon: String? = nil, text, description: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil` |
| `TFLoading` | Индикатор загрузки, `.inline` (встроенный текст) или блочный (центрированная панель с анимацией) | `_ variant: Variant = .inline` |
| `TFErrorBanner` | Сообщение об ошибке, `.inline` или блочная панель с иконкой; скрывается при пустом `message` | `_ message: String?, variant: Variant = .inline` |

## Подложка шапки — `Components/TFHeaderBackdrop.swift`

| Компонент | Что это | Параметры |
|---|---|---|
| `TFHeaderBackdrop` | Плотная верхняя часть + градиентный хвост для плавного затухания контента при скролле под шапкой | `tail: CGFloat = 26, opacity: Double = 1` |

## Шапка экрана — `Components/TFNativeHeader.swift`

| Компонент | Что это | Параметры |
|---|---|---|
| `.tfNativeHeader(_:displayMode:)` | Модификатор: `navigationTitle` + `toolbarTitleDisplayMode`, без своего фона/блюра — рисует система | `_ title: String, displayMode: ToolbarTitleDisplayMode = .large` |
| `.tfPlannerToolbarControl()` | Единый размер тап-зоны для элементов тулбара планировщика | — |
| `TFPlannerToolbarIcon` | Унифицированная иконка тулбара планировщика (стиль шрифта + цвет) | — |
| `.tfSoftTopScrollEdge()` | Мягкий верхний край при скролле под шапкой | — |

Свои шапки (`TFScreenHeader`, `FrostedGlass` и т.п.) удалены и лежат в
`archive/design-system-2026-09-11` — не воскрешать, см. `CLAUDE.md`.

## Нижняя навигация — `Navigation/TFTabBar.swift`

| Компонент | Что это | Параметры |
|---|---|---|
| `TFTabItem` | Данные одной вкладки: иконка, метка a11y, бейдж, «показывать дату» | `icon, accessibilityLabel, badgeCount: Int? = nil, showsTodayDate: Bool = false` |
| `TFTodayDateIcon` | Иконка календаря с текущим числом (обновляется на смену суток) | — |
| `TFTabBar` | Панель навигации: 2–4 вкладки симметрично + центральная кнопка создания | `items: [TFTabItem], selectedIndex: Binding<Int?>, isCreateMenuOpen: Bool, onSelect: @escaping (Int) -> Void, onCreateTap: @escaping () -> Void` |
| `TFCreateMenuItem` | Пункт всплывающего меню создания | `icon, title, subtitle: String? = nil, action` |
| `TFCreateMenu` | Всплывающая карточка меню создания (список пунктов + разделители) | `items: [TFCreateMenuItem]` |
| `TFTapMenuStyle` | `ButtonStyle` для пунктов меню — подсветка фона 6% при нажатии | — |

Единственная нижняя навигация в приложении — горб убран владельцем
27.08.2026, панель ровная. Боковой веер (`FanMenu`) — легаси, не используется.

## Жест горизонтального свайпа — `Components/HorizontalPan.swift`

Инфраструктура свайп-действий строк (не самостоятельный визуальный
компонент, а «мотор» под ним):

| Компонент | Что это |
|---|---|
| `TFSwipeRowRegistry` | `@Observable`-синглтон: следит, какая строка сейчас открыта свайпом, закрывает её при скролле списка |
| `TFRowSwipe` | Константы порогов смещения/скорости защёлкивания (скопированы с веба) |
| `TFRowActionWidth` | Ширина панели действий при свайпе — `84` |
| `HorizontalPanRecognizer` / `HorizontalPan` | `UIGestureRecognizerRepresentable`, блокирует вертикальный скролл только при горизонтальном движении |

Системный `.swipeActions`/`.draggable` в часовых сетках ненадёжен — здесь
своя реализация жеста, см. `native-drag-reschedule-pattern` в памяти. Новый
свайп по строке — через `HorizontalPan`, не через системный модификатор.

---

## Токены, на которые опираются компоненты (см. полностью в DESIGN.md)

- `TFSpacing` (xs=4…xl=24), `TFRadius` (sm=6…full=9999), `TFBorder.width`=1,
  `TFHitTarget.min`=44 — `Theme/Metrics.swift`.
- `TFIconSize` (xs=14…lg=26) — размер иконки = размеру шрифта рядом, не
  константа «24 на всё».
- `TFFont` / `TFTextStyle` — 10-ступенчатая типографика с Dynamic Type
  (`@ScaledMetric`), модификатор `.tfText(_:)` — `Theme/Typography.swift`.
- Цвета — `Color+Palette.swift`, подробности и предупреждения про похожие
  оттенки (`tfSub`/`tfDim`, `tfGreen`/`tfTeal`, `tfCard`/`tfCard2`) — в
  DESIGN.md.

## Известные особые случаи (не компонент дизайн-системы, но переиспользуются)

- `VoiceMessageLab/Presentation/VoiceMessageBubble.swift` — пузырь голосового
  сообщения, общий между прототипом VoiceMessageLab и чатом (см. LOCK-195 в
  `AGENT-WORK-SCOPES.md`).
