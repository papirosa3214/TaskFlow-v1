#!/usr/bin/env python3
"""Часовой у рабочего каталога iOS-клиента.

История: на .110 лежала вторая копия этих исходников и `scripts/sync-build.sh`,
который делал `rsync -az --delete` с .110 сюда. Каждый его запуск стирал работу,
сделанную на маке. Копия и скрипт удалены 08.09.2026, но привычка «залить с
.110» живёт в старых транскриптах и в чужой памяти, поэтому здесь стоит запрет:
команды, массово переписывающие этот каталог извне, до выполнения не доходят.

Подключён как PreToolUse-хук на Bash (см. .claude/settings.json).
Выход 2 = отказ, текст на stderr возвращается агенту как объяснение.

Проверяется ИМЯ ЗАПУСКАЕМОЙ команды, а не любое вхождение строки: иначе хук
отклонял бы собственные коммиты и заметки, где эти слова упомянуты.
"""

import json
import re
import shlex
import sys

GUARDED_DIR = "TaskFlowNativeBuild"
PREFIXES = {"env", "sudo", "time", "nohup", "exec", "command"}


def deny(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(2)


def main() -> None:
    try:
        command = json.load(sys.stdin).get("tool_input", {}).get("command", "")
    except Exception:
        return
    if not command.strip():
        return

    # Разбор на отдельные запуски: то, что стоит после ; && || | и перевода строки.
    for piece in re.split(r"(?:\|\||&&|[;|\n])", command):
        piece = piece.strip()
        if not piece:
            continue
        try:
            words = shlex.split(piece)
        except ValueError:  # незакрытая кавычка — тут не наше дело
            continue

        # Снимаем префиксы вида `env A=1`, `sudo`, `cd path &&` уже отрезан выше.
        while words and (words[0] in PREFIXES or re.fullmatch(r"[A-Za-z_]\w*=.*", words[0])):
            words = words[1:]
        if not words:
            continue

        # `bash script.sh` / `sh -x script.sh` — интересен сам скрипт, не оболочка.
        if words[0].rsplit("/", 1)[-1] in {"bash", "sh", "zsh"}:
            rest = [w for w in words[1:] if not w.startswith("-")]
            words = rest or words[1:]
            if not words:
                continue

        name = words[0].rsplit("/", 1)[-1]
        args = words[1:]

        if name.startswith("sync-build"):
            deny(
                "Отказано: sync-build.sh — тот самый синк с .110, который затирал работу\n"
                "на маке. Он удалён вместе со второй копией исходников. iOS-клиент\n"
                "разрабатывается только здесь, в /Users/max/Проекты/TaskFlowNativeBuild,\n"
                "и заливать сюда ничего не нужно."
            )

        if name in {"rsync", "scp"} and any(GUARDED_DIR in a for a in args):
            deny(
                f"Отказано: {name} в /Users/max/Проекты/TaskFlowNativeBuild.\n"
                "Этот каталог — единственный исходник iOS-клиента, его нельзя\n"
                "перезаписывать копией с другой машины (именно так пропадали правки).\n"
                "Перенос кода делается через git: коммит и push в origin\n"
                "(Gitea maksim/taskflow-native-ios). Нужен один файл для сравнения —\n"
                "копируй во временный каталог, например /tmp."
            )


if __name__ == "__main__":
    main()
