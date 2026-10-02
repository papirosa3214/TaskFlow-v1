# Обновление из GitHub — 01.10.2026

Источник: https://github.com/papirosa3214/TaskFlow-v1/tree/claude/fervent-fermi-2lswkc, 61dfcc2a; 6 коммитов после снимка b96ba125.
Перенесены изменения app/ в каноническую копию без замены локальных настроек и артефактов. Серверные изменения перенесены отдельно в New-Todoist-server.

## Проверка
- xcodegen generate; сборка приложения и XCTest на iPhone 17 Pro ED3C7DF7-F895-45B6-8A28-F67C02362103: TEST SUCCEEDED.
- CollaborationPlanLiveTests: 4/4; ChatRichContentTests: 7/7; RoleChatLiveTurnTests: 13/13; RoleChatRealtimeTests: 7/7. Всего 31/31.
- Исправлены ошибки облачной ветки: методы inline/listRow/attributed возвращены в RoleReplyMarkdown; добавлен await для UIApplication.open в ChatHTMLView.
- xcresult: /tmp/taskflow-oct01-final.xcresult; журнал: /tmp/taskflow-oct01-ios-final.log.
- Сервер: TypeScript build, 723/723 теста. Миграция 082 проверена на резервной копии живой базы, integrity_check=ok.

Проверка взаимодействия с новым живым графом и HTML/виджетами через XCUITest не выполнялась: данная приёмка подтверждает сборку и unit-тесты.
QA и критика задачи 15c2db1f не переоткрыты: ожидается решение владельца.
