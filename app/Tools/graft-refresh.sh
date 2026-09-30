#!/bin/bash
# Пересборка описаний графа graft этого репозитория (graft/*.md, сводки по
# файлам) — LOCK-235, владелец 27.09.2026.
#
# Карту кода graft обновляет сам перед каждым запросом; описания собирает
# только `graft build --deep` моделью, и с 10.09 их никто не пересобирал.
#
# Сам скрипт пересборки ОДИН — на .110 (server/scripts/graft_refresh.py в
# New-Todoist): забираем его по ssh, копии здесь нет. Модель — основная
# локальная в Ollama .110; занятую чужой работой карту не трогаем.
# Итог (~/.local/state/graft-refresh/ios.json) отдаём на .110 — там сторож
# graft-refresh-watch пишет владельцу, если граф перестал обновляться.
#
#   Tools/graft-refresh.sh               — пересобрать, если устарел (ночью, launchd)
#   Tools/graft-refresh.sh --background  — отвязанно и сразу выйти (хук начала
#                                          сессии); дособирает, только если
#                                          устаревших файлов не больше
#                                          SESSION_MAX_STALE, иначе — ночью
set -u

REPO="/Users/max/Проекты/TaskFlowNativeBuild"
STATE="$HOME/.local/state/graft-refresh"
mkdir -p "$STATE"

# Владелец 27.09.2026 (LOCK-240): при входе в проект — только мелкая
# дособорка. Большой хвост (166 файлов после простоя с 10.09) час держал
# видеокарту .110 — его разбирает ночной запуск.
SESSION_MAX_STALE=10

if [ "${1:-}" = "--background" ]; then
    nohup "$0" --session >>"$STATE/ios.run.log" 2>&1 </dev/null &
    exit 0
fi

export PATH="/Users/max/.local/bin:/opt/homebrew/bin:/usr/bin:/bin"
export GRAFT_BIN="/Users/max/.local/graft/node_modules/.bin/graft"

if [ "${1:-}" = "--session" ]; then
    # «! путь#символ» — устаревшая сводка, «+ путь» — файла нет в графе.
    stale=$("$GRAFT_BIN" check "$REPO" 2>/dev/null \
        | sed -nE 's/^  [!+] ([^#]+).*/\1/p' | sort -u | wc -l | tr -d ' ')
    if [ "$stale" -gt "$SESSION_MAX_STALE" ]; then
        echo "$(date '+%F %T') вход в проект: устарело файлов $stale > $SESSION_MAX_STALE — оставлено ночному запуску"
        exit 0
    fi
fi
export GRAFT_NODE_BIN="/Users/max/.local/bin"
export GRAFT_OLLAMA="http://192.168.1.110:11434"
export GRAFT_GPU_SSH="maksim"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=15 maksim)

echo "$(date '+%F %T') старт"
if ! SCRIPT=$("${SSH[@]}" 'cat ~/Проекты/New-Todoist/server/scripts/graft_refresh.py'); then
    # .110 недоступен — ни модели, ни сторожа; сторож заметит по возрасту итога.
    echo "$(date '+%F %T') .110 недоступен — пропуск"
    exit 1
fi
# Модель — через прокладку без размышлений на .110 (~/infra-ops/
# ollama_nothink_shim.py, слушает только 127.0.0.1:11500): туннель на время
# пересборки. Владелец 27.09.2026: граф пересобирать с отключёнными
# рассуждениями.
"${SSH[@]}" -N -o ExitOnForwardFailure=yes -L 11501:127.0.0.1:11500 &
TUNNEL=$!
trap 'kill $TUNNEL 2>/dev/null' EXIT
for _ in $(seq 1 20); do
    nc -z 127.0.0.1 11501 2>/dev/null && break
    sleep 0.5
done
export GRAFT_LLM_URL="http://127.0.0.1:11501"
printf '%s' "$SCRIPT" | /usr/bin/python3 - --repo "$REPO" --name ios --if-stale --respect-gpu
code=$?
"${SSH[@]}" 'mkdir -p ~/.local/state/graft-refresh && cat > ~/.local/state/graft-refresh/ios.json' <"$STATE/ios.json"
echo "$(date '+%F %T') готово, код $code"
exit $code
