#!/bin/bash
# Зеркалит РОВНО один файл (план «Супер Секретарь») с Мака на .110.
# Ничего больше не трогает: ни папок, ни --delete, ни других файлов.
set -euo pipefail

SRC="/Users/max/Проекты/TaskFlowNativeBuild/docs/ПЛАН Супер Секретарь/2026-09-25-secretary-voice-communicator-plan.md"
DEST_DIR="/home/maksim/Проекты/New-Todoist/docs/ПЛАН Супер Секретарь"
DEST="$DEST_DIR/2026-09-25-secretary-voice-communicator-plan.md"

last_hash=""
while true; do
  if [ -f "$SRC" ]; then
    hash=$(shasum -a 256 "$SRC" | awk '{print $1}')
    if [ "$hash" != "$last_hash" ]; then
      cat "$SRC" | ssh maksim "cat > '$DEST'" \
        && echo "$(date '+%Y-%m-%d %H:%M:%S') синхронизировано ($hash)"
      last_hash="$hash"
    fi
  fi
  sleep 5
done
