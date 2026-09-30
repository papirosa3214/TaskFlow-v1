#!/bin/bash
# Добавить задачу в Things 3 (область TaskFlow)
# Использование: things3-add.sh "Проект" "Название задачи" ["Описание"]

AREA="TaskFlow"
PROJECT="$1"
TITLE="$2"
NOTES="${3:-}"

if [ -z "$PROJECT" ] || [ -z "$TITLE" ]; then
  echo "Использование: $0 \"Проект\" \"Название задачи\" [\"Описание\"]"
  exit 1
fi

osascript <<EOF
tell application "Things3"
  set taskFlowArea to missing value
  repeat with a in every area
    if name of a is "$AREA" then
      set taskFlowArea to a
      exit repeat
    end if
  end repeat

  set targetProject to missing value
  repeat with p in every project
    set areaName to ""
    try
      set areaName to name of area of p
    end try
    if name of p is "$PROJECT" and areaName is "$AREA" then
      set targetProject to p
      exit repeat
    end if
  end repeat

  if targetProject is missing value then
    set targetProject to make new project with properties {name:"$PROJECT", area:taskFlowArea}
  end if

  set todoNotes to "$NOTES"
  if todoNotes is "" then
    make new to do with properties {name:"$TITLE", project:targetProject}
  else
    make new to do with properties {name:"$TITLE", notes:todoNotes, project:targetProject}
  end if
end tell
EOF

echo "✓ $PROJECT → $TITLE"