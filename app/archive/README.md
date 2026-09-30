# Archive — устаревшие компоненты TaskFlow Native

Сюда перенесены отдельные компоненты, которые больше не используются в
production target, но сохранены как законченные модули (могут пригодиться
позже как образцы архитектуры или как стартовая точка для возврата
функциональности).

## Дата архивирования: 2026-09-11

Источник — разбор мёртвого кода от 11.09.2026. Сам отчёт
(`DEAD-CODE-CLEANUP-REPORT.md`) убран из репозитория 22.09.2026 как
одноразовый: перечень перенесённого целиком повторён ниже, а история правок
лежит в git.

## Структура

| Подпапка | Что внутри | Откуда |
| --- | --- | --- |
| `Keyboard-2026-09-11/` | Своя экранная клавиатура (демо-прототип) | `Sources/Keyboard/` |
| `task-fields-2026-09-11/` | Пять отдельных полей формы задачи (Assignee, Labels, Priority, Project, DueDate) + `FlowLayout` + вырезанные компоненты из `SubtaskFormFieldView`/`AttachmentsFieldView` | `Sources/Features/Task/Fields/` |
| `design-system-2026-09-11/` | Старая шапка экрана (`TFScreenHeader` + `TFHeaderAction`) | `Sources/DesignSystem/Components/` |
| `directory-2026-09-11/` | Старая кнопка «Назад» в Справочнике | `Sources/Features/Directory/Support/` |
| `planner-2026-09-11/` | Старые компоненты чипов проекта (`PlannerProjectChips`, `UpcomingPlannerProjectChips`) | `Sources/Features/Today/`, `Sources/Features/Upcoming/` |

## Что НЕ сюда

- Методы сетевого API (`APIClient+Search`, методы `APIClient+Chat`,
  `APIClient+Agents`) — удаляются, не компоненты.
- Заглушки (`ScreenStub`) — удаляются.
- Зарезервированные API (`subtasks`, `claimTask`, `agentRules`, и т.д.) —
  не трогаются.
- `TaskDetailScreen`/`TaskDetailViewModel`/`TaskJournalView` — чистятся
  в `LOCK-120` у Claude Code.

## Как вернуть

Файлы перенесены через `git mv` — история изменений сохранена, можно
посмотреть `git log --follow <file>`.
