#!/usr/bin/env python3
"""Manual TaskFlow <-> Things 3 bridge for the owner's MacBook.

The bridge is intentionally pull-on-demand: POST /sync performs one merge and
returns a small JSON report. It never deletes projects or tasks.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import urllib.request
import urllib.parse
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

API = "http://192.168.1.110:3001/api"
AREA = "TaskFlow"
HOST = "0.0.0.0"
PORT = 8765
THINGS_AUTH_TOKEN = "1LzDO4-aTHSoMYl_he_A3Q"


def api_json(path: str, method: str = "GET", payload: dict[str, Any] | None = None) -> Any:
    data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode()
    request = urllib.request.Request(
        API + path,
        data=data,
        method=method,
        headers={"Content-Type": "application/json", "X-TaskFlow-Client": "ios-native"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def things_rows() -> list[dict[str, str]]:
    script = r'''
on cleanText(value)
    set s to value as text
    set s to my replaceText("|", "¦", s)
    set s to my replaceText(return, "⏎", s)
    set s to my replaceText(linefeed, "⏎", s)
    return s
end cleanText

on replaceText(findText, replaceWith, sourceText)
    set AppleScript's text item delimiters to findText
    set parts to every text item of sourceText
    set AppleScript's text item delimiters to replaceWith
    set resultText to parts as text
    set AppleScript's text item delimiters to ""
    return resultText
end replaceText

tell application "Things3"
    set output to ""
    repeat with p in every project
        try
            if name of area of p is "TaskFlow" then
                set output to output & "P|" & my cleanText(name of p) & linefeed
                repeat with t in every to do of p
                    set doneText to "0"
                    try
                        if (status of t as text) is "completed" then set doneText to "1"
                    end try
                    set dueText to ""
                    try
                        if (due date of t) is not missing value then set dueText to (time of (due date of t)) as text
                    end try
                    set output to output & "T|" & my cleanText(name of p) & "|" & my cleanText(id of t) & "|" & my cleanText(name of t) & "|" & my cleanText(notes of t) & "|" & doneText & "|" & dueText & linefeed
                end repeat
            end if
        end try
    end repeat
    return output
end tell
'''
    raw = subprocess.check_output(["/usr/bin/osascript", "-"], input=script.encode(), timeout=30).decode()
    rows: list[dict[str, str]] = []
    for line in raw.splitlines():
        parts = line.split("|")
        if parts[0] == "P" and len(parts) >= 2:
            rows.append({"kind": "project", "name": parts[1]})
        elif parts[0] == "T" and len(parts) >= 7:
            rows.append({"kind": "task", "project": parts[1], "id": parts[2], "title": parts[3], "notes": parts[4], "completed": parts[5], "due_epoch": parts[6]})
    return rows


def run_osascript(script: str) -> None:
    subprocess.run(["/usr/bin/osascript", "-"], input=script.encode(), check=True, timeout=30)


def apple_script_escape(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def things_url(command: str, **params: str) -> None:
    values = {"auth-token": THINGS_AUTH_TOKEN, **{k: v for k, v in params.items() if v}}
    query = urllib.parse.urlencode(values, quote_via=urllib.parse.quote)
    subprocess.run(["/usr/bin/open", f"things:///{command}?{query}"], check=True, timeout=10,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def task_when(task: dict[str, Any]) -> str:
    due_date = task.get("due_date") or ""
    start_time = task.get("start_time") or ""
    return f"{due_date} {start_time}".strip()


def checklist_text(task: dict[str, Any]) -> str:
    return "\n".join(str(item.get("title", "")).strip() for item in task.get("subtasks", []) if str(item.get("title", "")).strip())


def set_thing(project: str, title: str, notes: str, completed: bool | None = None, thing_id: str | None = None,
              task: dict[str, Any] | None = None) -> None:
    status_line = ""
    if completed is True:
        status_line = "\n                    set status of targetTodo to completed"
    elif completed is False:
        status_line = "\n                    set status of targetTodo to open"
    script = f'''tell application "Things3"
    repeat with p in every project
        if name of p is {apple_script_escape(project)} then
            repeat with targetTodo in every to do of p
                if name of targetTodo is {apple_script_escape(title)} then
                    set notes of targetTodo to {apple_script_escape(notes)}{status_line}
                    return
                end if
            end repeat
        end if
    end repeat
end tell
'''
    run_osascript(script)
    if thing_id and task:
        things_url("update", id=thing_id, **{
            "checklist-items": checklist_text(task),
            "when": task_when(task),
            "deadline": task.get("due_date") or "",
        })


def add_thing(project: str, title: str, notes: str, completed: bool, task: dict[str, Any]) -> None:
    things_url("add", title=title, notes=notes, list=project,
               **{"checklist-items": checklist_text(task), "when": task_when(task),
                  "deadline": task.get("due_date") or "", "completed": "true" if completed else ""})


def restore(value: str) -> str:
    return value.replace("¦", "|").replace("⏎", "\n")


def sync() -> dict[str, int]:
    projects = api_json("/projects")
    tasks = api_json("/tasks")
    thing_rows = things_rows()
    # The old one-off migration used a scratch project named exactly
    # "TaskFlow". Keep it untouched; real sync projects are the named
    # TaskFlow projects created from the server.
    thing_projects = {r["name"] for r in thing_rows if r["kind"] == "project" and r["name"] != "TaskFlow"}
    thing_tasks = [r for r in thing_rows if r["kind"] == "task"]
    task_by_id = {t["id"]: t for t in tasks}
    project_by_name = {p["name"]: p for p in projects}
    result = {"projects_created": 0, "imported": 0, "exported": 0, "updated": 0, "skipped": 0, "errors": 0}

    for project_name in sorted(thing_projects):
        if project_name not in project_by_name:
            try:
                created = api_json("/projects", "POST", {"name": project_name})
                project_by_name[project_name] = created
                result["projects_created"] += 1
            except Exception:
                result["errors"] += 1

    mapped_ids: set[str] = set()
    for row in thing_tasks:
        project = project_by_name.get(row["project"])
        if not project:
            continue
        notes = restore(row["notes"])
        marker = next((line.split(":", 1)[1].strip() for line in notes.splitlines() if line.startswith("TaskFlow ID:")), None)
        existing = task_by_id.get(marker) if marker else None
        try:
            if existing:
                mapped_ids.add(existing["id"])
                if row["completed"] == "1" and existing.get("status") != "completed":
                    api_json(f"/tasks/{existing['id']}", "PATCH", {"status": "completed"})
                    result["updated"] += 1
                set_thing(row["project"], restore(row["title"]), restore(row["notes"]),
                          existing.get("status") == "completed", row.get("id"), existing)
            else:
                created = api_json("/tasks", "POST", {"title": restore(row["title"]), "description": notes, "project_id": project["id"]})
                created_task = created.get("task", created)
                task_id = created_task.get("id")
                marker_notes = notes + ("\n\n" if notes else "") + "TaskFlow ID: " + str(task_id)
                set_thing(row["project"], restore(row["title"]), marker_notes, row["completed"] == "1")
                result["imported"] += 1
        except Exception:
            result["errors"] += 1

    for task in tasks:
        project_name = task.get("project_name")
        if not project_name or project_name not in thing_projects or task["id"] in mapped_ids:
            continue
        if any(f"TaskFlow ID: {task['id']}" in restore(r["notes"]) for r in thing_tasks if r["project"] == project_name):
            continue
        try:
            notes = task.get("description") or ""
            notes += ("\n\n" if notes else "") + "TaskFlow ID: " + task["id"]
            add_thing(project_name, task["title"], notes, task.get("status") == "completed", task)
            result["exported"] += 1
        except Exception:
            result["errors"] += 1
    return result


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"ok":true}')
            return
        self.send_error(404)

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/sync":
            self.send_error(404)
            return
        try:
            payload = json.dumps(sync(), ensure_ascii=False).encode()
            self.send_response(200)
        except Exception as error:
            payload = json.dumps({"error": str(error)}, ensure_ascii=False).encode()
            self.send_response(500)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_: object) -> None:
        return


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serve", action="store_true")
    args = parser.parse_args()
    if args.serve:
        ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
    else:
        print(json.dumps(sync(), ensure_ascii=False))


if __name__ == "__main__":
    main()
