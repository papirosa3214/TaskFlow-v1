# Голос Секретаря через LiveKit — план реализации

> **Для агентов-исполнителей:** ОБЯЗАТЕЛЬНЫЙ САБ-СКИЛЛ — используй
> `superpowers:subagent-driven-development` (рекомендуется) или
> `superpowers:executing-plans`, чтобы выполнять план задача за задачей.
> Шаги отмечены чекбоксами (`- [ ]`) для отслеживания.

**Цель:** дать владельцу голосовой разговор с Секретарём — говоришь вслух,
слышишь ответ вслух, — на транспорте LiveKit (WebRTC) и мозге Gemini Live.

**Архитектура:** iPhone (LiveKit Swift SDK) ↔ LiveKit Cloud (комната,
WebRTC) ↔ Python-воркер на .110 (`livekit-agents` + плагин Gemini Live) ↔
Gemini Live API; вызовы инструментов из разговора — HTTP от воркера к
`/api/*` на том же .110, тем же Bearer-токеном, что уже использует
`u-secretary`.

**Технологии:** LiveKit Cloud, `livekit-server-sdk` 2.19.1 (Node),
`livekit-agents` 1.8.3 + `livekit-plugins-google` 1.8.3 (Python 3.12),
`LiveKit` Swift SDK (`livekit/client-sdk-swift`, тег `2.17.0`, продукт
`LiveKit`), Fastify (существующий сервер), systemd `--user` на .110.

**Спека:** [2026-09-25-secretary-voice-livekit-design.md](2026-09-25-secretary-voice-livekit-design.md)
(и открытый вопрос §3.2, который она закрывает, в
[основном плане](2026-09-25-secretary-voice-communicator-plan.md)).

## Global Constraints

- Секреты LiveKit/Gemini не покидают .110: на телефон уходит только
  короткоживущий room-токен, который минтит сервер (`LIVEKIT_API_SECRET`,
  `GEMINI_API_KEY` — из vault, уже в `LIVEKIT_URL`/`LIVEKIT_API_KEY`/
  `LIVEKIT_API_SECRET`/`GEMINI_API_KEY`).
- Мозг разговора — Gemini Live (`gemini-3.8-live`), не локальный STT/LLM/TTS
  (решение владельца 25.09.2026).
- Мостик Gemini↔LiveKit — отдельный Python-процесс на .110, НЕ встройка в
  Node-сервер; инструменты дёргает HTTP к `/api/*`, не напрямую `app.inject`.
- Auth на новых HTTP-эндпоинтах — `authOrApiToken` (`server/src/auth.ts`),
  тот же путь, что у всех остальных data-роутов.
- Только владелец может получить room-токен (роль `owner` в `users`, тот же
  паттерн проверки, что в `routes/task-intake.ts`).
- Единственный канонiчный iOS-репозиторий — `TaskFlowNativeBuild`; перед
  правкой `Sources/**` завести строку `IN_PROGRESS` в `AGENT-WORK-SCOPES.md`
  (см. Задачу 5).
- Серверный репозиторий — `~/Проекты/New-Todoist` на .110 (Node 22,
  Fastify, `better-sqlite3`, тесты — `vitest`; `server/.env` — гитигнорнутый
  файл секретов текущего процесса).

---

### Задача 1: Node — эндпоинт выдачи room-токена LiveKit

**Файлы:**
- Create: `server/src/routes/secretary-voice.ts`
- Modify: `server/src/index.ts` (импорт + регистрация роута, по образцу
  строк 18-61 и 258)
- Modify: `server/package.json` (добавить зависимость `livekit-server-sdk`)
- Modify: `server/.env` (добавить строки `LIVEKIT_URL=`, `LIVEKIT_API_KEY=`,
  `LIVEKIT_API_SECRET=` — значения руками из vault, шаг 6 ниже)
- Test: `server/test/secretary-voice.test.ts`

**Interfaces:**
- Produces: `POST /api/secretary/voice-token` → `200 { url: string, token: string, room: string }`
  для владельца; `403 { error: string }` для остальных. `room` — детерминированное
  имя `secretary-voice-${ownerId}` (переиспользуется между сессиями одного
  владельца — Задача 2 и 3 читают тот же формат).

- [ ] **Шаг 1: поставить зависимость**

```bash
cd ~/Проекты/New-Todoist/server && npm install livekit-server-sdk@2.19.1
```

- [ ] **Шаг 2: дописать `server/.env` (значения из vault, не хардкодить)**

```bash
ssh maksim '
echo "LIVEKIT_URL=$(python3 ~/.claude/vault-get.py --raw LIVEKIT_URL)" >> ~/Проекты/New-Todoist/server/.env
echo "LIVEKIT_API_KEY=$(python3 ~/.claude/vault-get.py --raw LIVEKIT_API_KEY)" >> ~/Проекты/New-Todoist/server/.env
echo "LIVEKIT_API_SECRET=$(python3 ~/.claude/vault-get.py --raw LIVEKIT_API_SECRET)" >> ~/Проекты/New-Todoist/server/.env
'
```

- [ ] **Шаг 3: написать падающий тест**

```typescript
// server/test/secretary-voice.test.ts
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/index.js";
import db from "../src/db.js";

describe("POST /api/secretary/voice-token — только владелец", () => {
  let app: FastifyInstance;
  let ownerToken: string;
  let ownerId: string;
  let agentToken: string;

  beforeAll(async () => {
    process.env.LIVEKIT_URL = "wss://test.livekit.cloud";
    process.env.LIVEKIT_API_KEY = "test-key";
    process.env.LIVEKIT_API_SECRET = "test-secret-at-least-32-bytes-long!!";

    app = await buildApp();

    const ownerReg = await app.inject({
      method: "POST",
      url: "/api/auth/register",
      payload: { name: "OwnerVoice", email: "owner@voice.test", password: "password123" },
    });
    ownerToken = ownerReg.json().token;
    ownerId = ownerReg.json().user.id;
    db.prepare("UPDATE users SET role = 'owner' WHERE id = ?").run(ownerId);

    const agentReg = await app.inject({
      method: "POST",
      url: "/api/auth/register",
      payload: { name: "AgentVoice", email: "agent@voice.test", password: "password123" },
    });
    agentToken = agentReg.json().token;
  });

  afterAll(async () => {
    await app.close();
  });

  it("владельцу — 200 с url/token/room", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/secretary/voice-token",
      headers: { authorization: `Bearer ${ownerToken}` },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.url).toBe("wss://test.livekit.cloud");
    expect(typeof body.token).toBe("string");
    expect(body.token.length).toBeGreaterThan(20);
    expect(body.room).toBe(`secretary-voice-${ownerId}`);
  });

  it("не-владельцу — 403", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/secretary/voice-token",
      headers: { authorization: `Bearer ${agentToken}` },
    });
    expect(res.statusCode).toBe(403);
  });

  it("без токена — 401", async () => {
    const res = await app.inject({ method: "POST", url: "/api/secretary/voice-token" });
    expect(res.statusCode).toBe(401);
  });
});
```

- [ ] **Шаг 4: прогнать тест, убедиться, что падает**

```bash
cd ~/Проекты/New-Todoist/server && npx vitest run test/secretary-voice.test.ts
```
Ожидание: FAIL — `server/src/routes/secretary-voice.ts` ещё не существует
(`Cannot find module`).

- [ ] **Шаг 5: написать роут**

```typescript
// server/src/routes/secretary-voice.ts
//
// POST /api/secretary/voice-token — короткоживущий LiveKit room-токен для
// голосового разговора с Секретарём. Только владелец. Комната одна и та же
// между сессиями одного владельца (`secretary-voice-<ownerId>`) — так
// Python-воркер (server/agents/secretary-voice) может использовать
// автоматический dispatch по факту создания комнаты, без ручной регистрации
// per-session. Секрет LiveKit не уходит на телефон — только подписанный JWT.
import type { FastifyInstance } from "fastify";
import { AccessToken } from "livekit-server-sdk";
import db from "../db.js";
import { authOrApiToken } from "../auth.js";

function ownerIdOrNull(): string | null {
  const row = db
    .prepare("SELECT id FROM users WHERE role = 'owner' ORDER BY created_at LIMIT 1")
    .get() as { id: string } | undefined;
  return row?.id ?? null;
}

export function registerSecretaryVoiceRoutes(app: FastifyInstance): void {
  app.post("/api/secretary/voice-token", { preHandler: authOrApiToken }, async (req: any, reply) => {
    const owner = ownerIdOrNull();
    if (!owner) return reply.code(404).send({ error: "владелец не найден" });
    if (req.userId !== owner) {
      return reply.code(403).send({ error: "только владелец" });
    }

    const url = process.env.LIVEKIT_URL;
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    if (!url || !apiKey || !apiSecret) {
      return reply.code(503).send({ error: "LiveKit не настроен на сервере" });
    }

    const room = `secretary-voice-${owner}`;
    const at = new AccessToken(apiKey, apiSecret, { identity: owner, ttl: "10m" });
    at.addGrant({ roomJoin: true, room, canPublish: true, canSubscribe: true });
    const token = await at.toJwt();

    return { url, token, room };
  });
}
```

- [ ] **Шаг 6: зарегистрировать роут в `server/src/index.ts`**

Рядом со строкой 60 (`import { registerTaskIntakeRoutes } from "./routes/task-intake.js";`):
```typescript
import { registerSecretaryVoiceRoutes } from "./routes/secretary-voice.js";
```
Рядом со строкой 258 (`registerTaskIntakeRoutes(app);`):
```typescript
  registerSecretaryVoiceRoutes(app);
```

- [ ] **Шаг 7: прогнать тест, убедиться, что проходит**

```bash
cd ~/Проекты/New-Todoist/server && npx vitest run test/secretary-voice.test.ts
```
Ожидание: PASS, все три `it`.

- [ ] **Шаг 8: коммит**

```bash
cd ~/Проекты/New-Todoist && git add server/src/routes/secretary-voice.ts server/src/index.ts server/package.json server/package-lock.json server/test/secretary-voice.test.ts
git commit -m "feat(secretary-voice): эндпоинт выдачи LiveKit room-токена владельцу"
```

---

### Задача 2: Python-воркер — каркас, подключение к комнате

**Файлы:**
- Create: `server/agents/secretary-voice/worker.py`
- Create: `server/agents/secretary-voice/requirements.txt`
- Create: `server/agents/secretary-voice/.env` (не в git — секреты)
- Modify: `server/.gitignore` (добавить `agents/secretary-voice/.env`, если
  паттерн `.env` там ещё не покрывает подпапки — проверить перед правкой)
- Create: `~/.config/systemd/user/taskflow-secretary-voice.service` (на .110,
  не в git)
- Test: `server/agents/secretary-voice/test_worker.py`

**Interfaces:**
- Consumes: комнату `secretary-voice-<ownerId>`, создаваемую клиентом при
  подключении (Задача 1 выдаёт токен на неё).
- Produces: залогированное событие подключения участника — подтверждение,
  что dispatch воркера в комнату реально срабатывает, прежде чем подключать
  Gemini (Задача 3).

- [ ] **Шаг 1: venv и зависимости**

```bash
ssh maksim '
python3 -m venv ~/.venvs/secretary-voice
~/.venvs/secretary-voice/bin/pip install "livekit-agents[google]==1.8.3" python-dotenv
'
```

- [ ] **Шаг 2: `requirements.txt`**

```
livekit-agents[google]==1.8.3
python-dotenv
```

- [ ] **Шаг 3: `.env` воркера (значения из vault)**

```bash
ssh maksim '
mkdir -p ~/Проекты/New-Todoist/server/agents/secretary-voice
cat > ~/Проекты/New-Todoist/server/agents/secretary-voice/.env <<EOF
LIVEKIT_URL=$(python3 ~/.claude/vault-get.py --raw LIVEKIT_URL)
LIVEKIT_API_KEY=$(python3 ~/.claude/vault-get.py --raw LIVEKIT_API_KEY)
LIVEKIT_API_SECRET=$(python3 ~/.claude/vault-get.py --raw LIVEKIT_API_SECRET)
GEMINI_API_KEY=$(python3 ~/.claude/vault-get.py --raw GEMINI_API_KEY)
TASKFLOW_API_BASE=http://127.0.0.1:3001
TASKFLOW_AGENT_TOKEN=$(python3 ~/.claude/vault-get.py --raw TASKFLOW_AGENT_TOKEN)
EOF
chmod 600 ~/Проекты/New-Todoist/server/agents/secretary-voice/.env
'
```

- [ ] **Шаг 4: падающий тест (конфиг воркера обязан требовать все переменные)**

```python
# server/agents/secretary-voice/test_worker.py
"""Запуск: python3 -m unittest test_worker (из server/agents/secretary-voice)."""
import os
import unittest
from unittest.mock import patch

import worker


class LoadConfigTests(unittest.TestCase):
    def test_missing_gemini_key_raises(self):
        env = {
            "LIVEKIT_URL": "wss://x.livekit.cloud",
            "LIVEKIT_API_KEY": "k",
            "LIVEKIT_API_SECRET": "s",
            "TASKFLOW_API_BASE": "http://127.0.0.1:3001",
            "TASKFLOW_AGENT_TOKEN": "t",
        }
        with patch.dict(os.environ, env, clear=True):
            with self.assertRaises(worker.ConfigError):
                worker.load_config()

    def test_complete_env_loads(self):
        env = {
            "LIVEKIT_URL": "wss://x.livekit.cloud",
            "LIVEKIT_API_KEY": "k",
            "LIVEKIT_API_SECRET": "s",
            "GEMINI_API_KEY": "g",
            "TASKFLOW_API_BASE": "http://127.0.0.1:3001",
            "TASKFLOW_AGENT_TOKEN": "t",
        }
        with patch.dict(os.environ, env, clear=True):
            cfg = worker.load_config()
        self.assertEqual(cfg.gemini_api_key, "g")
        self.assertEqual(cfg.taskflow_api_base, "http://127.0.0.1:3001")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Шаг 5: прогнать, убедиться, что падает**

```bash
cd ~/Проекты/New-Todoist/server/agents/secretary-voice && ~/.venvs/secretary-voice/bin/python3 -m unittest test_worker
```
Ожидание: FAIL — `worker.py` ещё не существует (`ModuleNotFoundError`).

- [ ] **Шаг 6: написать `worker.py` (каркас — подключение и логирование, без Gemini)**

```python
"""Секретарь: голосовой воркер LiveKit. Запуск: см. systemd-юнит
taskflow-secretary-voice.service. Ручной прогон (dev):
  ~/.venvs/secretary-voice/bin/python3 worker.py dev
"""
from __future__ import annotations

import logging
import os
from dataclasses import dataclass

from dotenv import load_dotenv

from livekit.agents import AgentServer, JobContext, cli

load_dotenv()

logger = logging.getLogger("secretary-voice")


class ConfigError(Exception):
    """Обязательная переменная окружения не задана."""


@dataclass(frozen=True)
class Config:
    livekit_url: str
    livekit_api_key: str
    livekit_api_secret: str
    gemini_api_key: str
    taskflow_api_base: str
    taskflow_agent_token: str


REQUIRED_VARS = (
    "LIVEKIT_URL",
    "LIVEKIT_API_KEY",
    "LIVEKIT_API_SECRET",
    "GEMINI_API_KEY",
    "TASKFLOW_API_BASE",
    "TASKFLOW_AGENT_TOKEN",
)


def load_config() -> Config:
    missing = [v for v in REQUIRED_VARS if not os.environ.get(v)]
    if missing:
        raise ConfigError(f"не заданы переменные окружения: {', '.join(missing)}")
    return Config(
        livekit_url=os.environ["LIVEKIT_URL"],
        livekit_api_key=os.environ["LIVEKIT_API_KEY"],
        livekit_api_secret=os.environ["LIVEKIT_API_SECRET"],
        gemini_api_key=os.environ["GEMINI_API_KEY"],
        taskflow_api_base=os.environ["TASKFLOW_API_BASE"],
        taskflow_agent_token=os.environ["TASKFLOW_AGENT_TOKEN"],
    )


server = AgentServer()


@server.rtc_session()
async def entrypoint(ctx: JobContext) -> None:
    ctx.log_context_fields = {"room": ctx.room.name}
    logger.info("secretary-voice: подключаюсь к комнате %s", ctx.room.name)

    @ctx.room.on("participant_connected")
    def _on_participant(participant) -> None:  # noqa: ANN001
        logger.info("secretary-voice: участник подключился: %s", participant.identity)

    # Задача 3 подставит сюда AgentSession с Gemini Live вместо простого
    # логирования — на этом шаге цель ровно одна: подтвердить, что dispatch
    # воркера в комнату реально срабатывает.


if __name__ == "__main__":
    load_config()  # падаем рано и явно, не на первом же job
    cli.run_app(server)
```

- [ ] **Шаг 7: прогнать тест, убедиться, что проходит**

```bash
cd ~/Проекты/New-Todoist/server/agents/secretary-voice && ~/.venvs/secretary-voice/bin/python3 -m unittest test_worker
```
Ожидание: PASS, оба теста.

- [ ] **Шаг 8: systemd-юнит (на .110, не в git)**

```bash
ssh maksim 'cat > ~/.config/systemd/user/taskflow-secretary-voice.service <<EOF
[Unit]
Description=TaskFlow — голосовой воркер Секретаря (LiveKit + Gemini Live)
After=network-online.target taskflow-server.service

[Service]
Type=simple
WorkingDirectory=/home/maksim/Проекты/New-Todoist/server/agents/secretary-voice
EnvironmentFile=/home/maksim/Проекты/New-Todoist/server/agents/secretary-voice/.env
ExecStart=/home/maksim/.venvs/secretary-voice/bin/python3 worker.py start
Restart=always
RestartSec=5
StandardOutput=append:/home/maksim/Проекты/New-Todoist/server/agents/secretary-voice/worker.log
StandardError=append:/home/maksim/Проекты/New-Todoist/server/agents/secretary-voice/worker.log

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now taskflow-secretary-voice.service
systemctl --user status taskflow-secretary-voice.service --no-pager
'
```
Ожидание: `Active: active (running)` — `livekit-agents`' `cli.run_app` в
режиме `start` сам подключается к LiveKit Cloud и ждёт job'ы (никакой
локальный порт слушать не нужно).

Проверка живого dispatch (ручная, до Задачи 3): создать комнату
`secretary-voice-test` через LiveKit Cloud consol или `lk room create`,
проверить в `worker.log`, что появилась строка «подключаюсь к комнате».

- [ ] **Шаг 9: коммит (без `.env`, без systemd-юнита — они не в git)**

```bash
cd ~/Проекты/New-Todoist && git add server/agents/secretary-voice/worker.py server/agents/secretary-voice/requirements.txt server/agents/secretary-voice/test_worker.py server/.gitignore
git commit -m "feat(secretary-voice): каркас Python-воркера LiveKit, подключение к комнате"
```

---

### Задача 3: Python-воркер — Gemini Live вместо логирования

**Файлы:**
- Modify: `server/agents/secretary-voice/worker.py`
- Test: ручная живая проверка (голосовой пайплайн не юнит-тестируется
  дёшево — см. порядок проверки в спеке)

**Interfaces:**
- Consumes: `Config` из Задачи 2 (`gemini_api_key`).
- Produces: `Assistant` — класс-агент, который Задача 4 расширит
  `@function_tool`-методом `create_task`.

- [ ] **Шаг 1: заменить тело `entrypoint` на реальную голосовую сессию**

```python
# server/agents/secretary-voice/worker.py — заменить entrypoint целиком
from livekit.agents import Agent, AgentSession, JobContext, cli
from livekit.plugins.google.realtime import RealtimeModel

SECRETARY_INSTRUCTIONS = (
    "Ты — Секретарь, голосовой помощник Максима в TaskFlow. Отвечай кратко "
    "и по-русски. Не используй эмодзи и markdown — тебя слушают, а не читают. "
    "Карточку задачи создавай только по явной просьбе («создай задачу», "
    "«запиши») или когда сам уверен, что это задача; при сомнении — "
    "переспроси коротким вопросом, не создавай молча."
)


class Assistant(Agent):
    def __init__(self) -> None:
        super().__init__(instructions=SECRETARY_INSTRUCTIONS)

    async def on_enter(self) -> None:
        self.session.generate_reply(instructions="поздоровайся коротко и спроси, чем помочь")


server = AgentServer()


@server.rtc_session()
async def entrypoint(ctx: JobContext) -> None:
    ctx.log_context_fields = {"room": ctx.room.name}
    cfg = load_config()

    session = AgentSession(
        llm=RealtimeModel(
            model="gemini-3.8-live",
            api_key=cfg.gemini_api_key,
            voice="Puck",
        ),
    )
    await session.start(agent=Assistant(), room=ctx.room)
```

(`AgentServer` и `server = AgentServer()` уже объявлены выше в файле — не
дублировать; переставить `@server.rtc_session()` на новую функцию.)

- [ ] **Шаг 2: живая проверка на iPhone заготовкой из LiveKit (до готовности iOS-экрана, Задача 5)**

LiveKit Cloud даёт тестовый sandbox-клиент в вебе (playground) для любой
комнаты проекта — самый дешёвый способ услышать Gemini до того, как готов
iOS-экран:
```
open "https://cloud.livekit.io/projects/p_2jmgvmw08ej/sandbox"
```
Подключиться к комнате `secretary-voice-<ownerId у себя в БД>`,
сказать «привет», услышать голосовой ответ. Записать в журнал этого файла
(Задача 6, шаг журнала) результат.

- [ ] **Шаг 3: коммит**

```bash
cd ~/Проекты/New-Todoist && git add server/agents/secretary-voice/worker.py
git commit -m "feat(secretary-voice): подключить Gemini Live вместо заглушки-логирования"
```

---

### Задача 4: Python-воркер — инструмент `create_task`

**Файлы:**
- Modify: `server/agents/secretary-voice/worker.py`
- Test: `server/agents/secretary-voice/test_create_task_tool.py`

**Interfaces:**
- Consumes: `Config.taskflow_api_base`, `Config.taskflow_agent_token` (Задача 2).
- Produces: `create_task_via_api(title: str, base_url: str, token: str) -> dict`
  — чистая функция, дальше обёрнутая `@function_tool`-методом `Assistant.create_task`.

- [ ] **Шаг 1: падающий тест**

```python
# server/agents/secretary-voice/test_create_task_tool.py
"""Запуск: python3 -m unittest test_create_task_tool."""
import unittest
from unittest.mock import AsyncMock, patch

from worker import create_task_via_api


class CreateTaskViaApiTests(unittest.IsolatedAsyncioTestCase):
    async def test_posts_title_and_returns_task_id(self):
        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.json = AsyncMock(return_value={"id": "task-123", "title": "Купить молоко"})

        mock_post_cm = AsyncMock()
        mock_post_cm.__aenter__ = AsyncMock(return_value=mock_response)
        mock_post_cm.__aexit__ = AsyncMock(return_value=False)

        with patch("worker.aiohttp.ClientSession.post", return_value=mock_post_cm) as mock_post:
            result = await create_task_via_api(
                "Купить молоко", base_url="http://127.0.0.1:3001", token="tok"
            )

        mock_post.assert_called_once_with(
            "http://127.0.0.1:3001/api/tasks",
            json={"title": "Купить молоко"},
            headers={"Authorization": "Bearer tok"},
        )
        self.assertEqual(result["id"], "task-123")

    async def test_server_error_raises(self):
        mock_response = AsyncMock()
        mock_response.status = 400
        mock_response.json = AsyncMock(return_value={"error": "название задачи не может быть пустым"})

        mock_post_cm = AsyncMock()
        mock_post_cm.__aenter__ = AsyncMock(return_value=mock_response)
        mock_post_cm.__aexit__ = AsyncMock(return_value=False)

        with patch("worker.aiohttp.ClientSession.post", return_value=mock_post_cm):
            with self.assertRaises(RuntimeError):
                await create_task_via_api("", base_url="http://127.0.0.1:3001", token="tok")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Шаг 2: прогнать, убедиться, что падает**

```bash
cd ~/Проекты/New-Todoist/server/agents/secretary-voice && ~/.venvs/secretary-voice/bin/python3 -m unittest test_create_task_tool
```
Ожидание: FAIL — `create_task_via_api` не существует (`ImportError`).

- [ ] **Шаг 3: реализация — добавить в `worker.py`**

```python
import aiohttp
from livekit.agents import RunContext, function_tool


async def create_task_via_api(title: str, base_url: str, token: str) -> dict:
    async with aiohttp.ClientSession() as http:
        async with http.post(
            f"{base_url}/api/tasks",
            json={"title": title},
            headers={"Authorization": f"Bearer {token}"},
        ) as resp:
            body = await resp.json()
            if resp.status != 200:
                raise RuntimeError(f"TaskFlow отказал: {body.get('error', resp.status)}")
            return body
```

И метод у `Assistant` (тело `__init__`/`on_enter` не трогать, добавить
рядом):

```python
    @function_tool
    async def create_task(self, context: RunContext, title: str) -> str:
        """Завести карточку задачи в TaskFlow.

        Вызывай ТОЛЬКО когда владелец явно попросил («создай задачу»,
        «запиши это») или когда абсолютно уверен, что реплика — задача.
        При сомнении сначала переспроси голосом, не вызывай этот инструмент.

        Args:
            title: Короткое название задачи, как оно должно выглядеть в списке.
        """
        cfg = load_config()
        try:
            task = await create_task_via_api(
                title, base_url=cfg.taskflow_api_base, token=cfg.taskflow_agent_token
            )
        except RuntimeError as exc:
            return f"Не получилось завести задачу: {exc}"
        return f"Готово, завёл задачу «{task['title']}»."
```

- [ ] **Шаг 4: прогнать тест, убедиться, что проходит**

```bash
cd ~/Проекты/New-Todoist/server/agents/secretary-voice && ~/.venvs/secretary-voice/bin/python3 -m unittest test_create_task_tool
```
Ожидание: PASS, оба теста.

- [ ] **Шаг 5: подключить инструмент к `Assistant` и перезапустить воркер**

```bash
ssh maksim 'systemctl --user restart taskflow-secretary-voice.service && sleep 2 && systemctl --user status taskflow-secretary-voice.service --no-pager'
```

- [ ] **Шаг 6: живая проверка (LiveKit sandbox-плеер, как в Задаче 3)**

Сказать «создай задачу купить молоко», убедиться голосом и в TaskFlow
(`taskflow_project_tasks` или веб), что карточка реально появилась.

- [ ] **Шаг 7: коммит**

```bash
cd ~/Проекты/New-Todoist && git add server/agents/secretary-voice/worker.py server/agents/secretary-voice/test_create_task_tool.py
git commit -m "feat(secretary-voice): инструмент create_task в голосовом разговоре"
```

---

### Задача 5: iOS — экран голосового разговора, зависимость LiveKit

**Перед правкой:** завести строку в `AGENT-WORK-SCOPES.md`
(`/Users/max/Проекты/TaskFlowNativeBuild/AGENT-WORK-SCOPES.md`) — `Lock ID`
следующий свободный номер (на 25.09.2026 последний — `LOCK-215`), статус
`IN_PROGRESS`, Scope ID `IOS-SECRETARY-VOICE`, разрешённые файлы — список
ниже.

**Файлы:**
- Modify: `project.yml` (SwiftPM-пакет `LiveKit`, зависимость таргета
  `TaskFlow`)
- Create: `Sources/Features/Chat/SecretaryVoiceScreen.swift`
- Create: `Sources/Core/Networking/APIClient+SecretaryVoice.swift`
- Modify: `Sources/App/Navigation/AppRoute.swift` (новый case)
- Modify: `Sources/App/Navigation/RouteDestinationView.swift` (обработка case)
- Modify: `Sources/Features/Chat/RoleChatsScreen.swift` (кнопка входа в
  голосовой режим из комнаты `chat-secretary`, в toolbar рядом с «Ещё»)
- Modify: `AGENT-WORK-SCOPES.md`

**Interfaces:**
- Consumes: `POST /api/secretary/voice-token` (Задача 1) → `{ url, token, room }`.
- Produces: экран `SecretaryVoiceScreen`, маршрут `AppRoute.secretaryVoiceCall`.

- [ ] **Шаг 1: добавить пакет в `project.yml`**

Рядом со строкой 239 (после `SDWebImageWebPCoder`, перед `schemes:`):
```yaml
  LiveKit:
    url: https://github.com/livekit/client-sdk-swift.git
    from: 2.17.0
```
В `targets: TaskFlow: dependencies:`, рядом со строкой 52
(`- package: SDWebImageWebPCoder`):
```yaml
      - package: LiveKit
```

- [ ] **Шаг 2: перегенерировать проект и убедиться, что пакет резолвится**

```bash
cd "$HOME/Проекты/TaskFlowNativeBuild" && xcodegen generate && xcodebuild -resolvePackageDependencies -project TaskFlow.xcodeproj -scheme TaskFlow 2>&1 | tail -20
```
Ожидание: `Resolved source packages` включает `LiveKit`, без ошибок.

- [ ] **Шаг 3: сетевой клиент — получить room-токен**

```swift
// Sources/Core/Networking/APIClient+SecretaryVoice.swift
import Foundation

struct SecretaryVoiceToken: Decodable {
    let url: String
    let token: String
    let room: String
}

extension APIClient {
    // request(.post, path) без body — тот же приём, что markRoleChatRead()
    // в APIClient+RoleChats.swift (path без "/api" — префикс добавляет
    // buildRequest() внутри APIClient сам).
    func secretaryVoiceToken() async throws -> SecretaryVoiceToken {
        try await request(.post, "/secretary/voice-token")
    }
}
```

- [ ] **Шаг 4: маршрут**

В `Sources/App/Navigation/AppRoute.swift`, рядом со строкой 79
(`case secretaryChat`):
```swift
    case secretaryVoiceCall
```
В `Sources/App/Navigation/RouteDestinationView.swift`, рядом со строкой 114
(`case .secretaryChat:`):
```swift
    case .secretaryVoiceCall:
        SecretaryVoiceScreen()
```

- [ ] **Шаг 5: сам экран — состояния, подключение, микрофон**

```swift
// Sources/Features/Chat/SecretaryVoiceScreen.swift
import SwiftUI
import LiveKit

enum SecretaryVoiceState: Equatable {
    case connecting
    case listening
    case thinking
    case speaking
    case failed(String)
}

@MainActor
@Observable
final class SecretaryVoiceViewModel {
    var state: SecretaryVoiceState = .connecting
    private let room = Room()
    private let api = APIClient()

    func start() async {
        do {
            let token = try await api.secretaryVoiceToken()
            try await room.connect(url: token.url, token: token.token)
            try await room.localParticipant.setMicrophone(enabled: true)
            state = .listening
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        await room.disconnect()
    }
}

struct SecretaryVoiceScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SecretaryVoiceViewModel()

    var body: some View {
        VStack(spacing: TFSpacing.lg) {
            Spacer()
            stateLabel
            Spacer()
            Button("Закрыть") { Task { await viewModel.stop(); dismiss() } }
                .buttonStyle(TFTapScaleStyle())
        }
        .padding(TFSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tfBackground.ignoresSafeArea())
        .task { await viewModel.start() }
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch viewModel.state {
        case .connecting: Text("Подключаюсь…").tfText(.title).foregroundStyle(Color.tfSub)
        case .listening: Text("Слушаю").tfText(.title).foregroundStyle(Color.tfText)
        case .thinking: Text("Секретарь думает…").tfText(.title).foregroundStyle(Color.tfSub)
        case .speaking: Text("Секретарь говорит").tfText(.title).foregroundStyle(Color.tfRed)
        case .failed(let message):
            Text("Не получилось: \(message)").tfText(.title).foregroundStyle(Color.tfRed)
        }
    }
}
```

(`TFTapScaleStyle`, `Color.tfBackground`, `.tfText(.title)` — уже
существующие элементы дизайн-системы, сверить точные имена модификаторов
перед вставкой: `grep -rn "tfText(\.title)\|TFTapScaleStyle" Sources/DesignSystem`.
Состояния `.thinking`/`.speaking` в этой задаче не запитаны реальными
событиями комнаты — это делает Задача 6.)

- [ ] **Шаг 6: точка входа из комнаты Секретаря**

В `RoleChatsScreen.swift`, `RoleChatRoomScreen.body`, в `.toolbar` рядом со
строкой 712 (`ToolbarItem(placement: .topBarTrailing) { Menu { ... } }`,
только для комнаты `chat-secretary` — добавить ДО существующего `Menu`,
отдельным `ToolbarItem`):
```swift
if chat.id == "chat-secretary" {
    ToolbarItem(placement: .topBarTrailing) {
        NavigationLink(value: AppRoute.secretaryVoiceCall) {
            Image(systemName: "waveform")
        }
        .accessibilityLabel("Голосовой разговор с Секретарём")
    }
}
```

- [ ] **Шаг 7: сборка и живая проверка микрофона на устройстве**

Микрофон не работает в симуляторе — только на iPhone:
```bash
cd "$HOME/Проекты/TaskFlowNativeBuild" && xcodegen generate && xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow -destination 'generic/platform=iOS' build
```
Установить на телефон обычным путём проекта, открыть чат «Секретарь»,
нажать иконку waveform, сказать «привет», услышать голосовой ответ.

- [ ] **Шаг 8: перевести строку `AGENT-WORK-SCOPES.md` в `REVIEW`**

С описанием сделанного и результатом живой проверки — по образцу
`LOCK-215`/`LOCK-214`.

- [ ] **Шаг 9: коммит**

```bash
cd "$HOME/Проекты/TaskFlowNativeBuild"
git add project.yml Sources/Features/Chat/SecretaryVoiceScreen.swift Sources/Core/Networking/APIClient+SecretaryVoice.swift Sources/App/Navigation/AppRoute.swift Sources/App/Navigation/RouteDestinationView.swift Sources/Features/Chat/RoleChatsScreen.swift AGENT-WORK-SCOPES.md
git commit -m "feat(secretary-voice): экран голосового разговора через LiveKit"
```

---

### Задача 6: барж-ин, состояния «думает/говорит», журнал плана

**Файлы:**
- Modify: `Sources/Features/Chat/SecretaryVoiceScreen.swift`
- Modify: [2026-09-25-secretary-voice-livekit-design.md](2026-09-25-secretary-voice-livekit-design.md) (журнал)
- Modify: [2026-09-25-secretary-voice-communicator-plan.md](2026-09-25-secretary-voice-communicator-plan.md) (журнал основного плана — этап 3 закрыт)

**Interfaces:**
- Consumes: `Room` из `SecretaryVoiceViewModel` (Задача 5).

- [ ] **Шаг 1: подписка на события участников для состояний думает/говорит**

`Room.Delegate` (проверено по исходнику SDK,
`Sources/LiveKit/Protocols/RoomDelegate.swift`) даёт ровно то, что нужно:
`func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant])`
— список говорящих участников на этот момент; `func room(_ room: Room, didDisconnectWithError error: LiveKitError?)`
— разрыв соединения, сюда же кладём `.failed` вместо необработанного
зависания. `SecretaryVoiceViewModel` реализует `RoomDelegate`, в `start()`
ставит `room.add(delegate: self)` до `room.connect(...)`:

```swift
extension SecretaryVoiceViewModel: RoomDelegate {
    func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        let agentSpeaking = participants.contains { $0.identity != room.localParticipant.identity }
        state = agentSpeaking ? .speaking : .listening
    }

    func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        state = .failed(error?.localizedDescription ?? "соединение разорвано")
    }
}
```

Состояние `.thinking` — по умолчанию Gemini Live говорит почти без паузы
(realtime-модель, не отдельный LLM-шаг); если реальной паузы «думает» не
наблюдается на живой проверке — этот кейс сворачивается в `.listening` без
отдельной анимации (не выдумывать несуществующий сигнал ради красоты).

- [ ] **Шаг 2: барж-ин**

Касание экрана во время `.speaking` — `room.localParticipant` продолжает
публиковать микрофон постоянно (не мьютить на время ответа): барж-ин
целиком обрабатывает Gemini Live через LiveKit-плагин на стороне воркера
(спека, §«Компоненты»/iOS) — с клиента ничего специально вызывать не нужно,
проверить это утверждение живьём (сказать поверх ответа, убедиться, что
Секретарь замолкает и слушает).

- [ ] **Шаг 3: живая проверка на iPhone**

Полный разговор: несколько реплик, одно прерывание на середине ответа,
один разрыв Wi-Fi (выключить и включить) — проверить, что экран показывает
`.failed` вместо зависания и подключение можно повторить кнопкой «Закрыть»
→ заново открыть.

- [ ] **Шаг 4: журнал — обе спеки**

В `2026-09-25-secretary-voice-livekit-design.md`, секция «Журнал», дописать
запись о завершении (что реально заработало, что не проверялось живьём —
честно, без «всё готово», если что-то не проверено).

В `2026-09-25-secretary-voice-communicator-plan.md`, секция «Журнал»,
дописать: этап 3 (голос) сделан на транспорте LiveKit + Gemini Live,
ссылка на design/plan-документы.

- [ ] **Шаг 5: коммит**

```bash
cd "$HOME/Проекты/TaskFlowNativeBuild"
git add Sources/Features/Chat/SecretaryVoiceScreen.swift "docs/ПЛАН Супер Секретарь/2026-09-25-secretary-voice-livekit-design.md" "docs/ПЛАН Супер Секретарь/2026-09-25-secretary-voice-communicator-plan.md"
git commit -m "feat(secretary-voice): барж-ин, состояния разговора, закрытие этапа 3"
```

---

## Что осознанно не покрыто этим планом

Найдено на самопроверке плана против спеки — не забыто, а отложено:

- **Статусное текстовое сообщение через LiveKit data-канал**, когда Gemini
  недоступен/лимит исчерпан (спека, раздел «Отказы»). MVP закрывает этот
  случай частично: падение вызова инструмента `create_task` Секретарь и так
  озвучивает голосом (Задача 4, `except RuntimeError`); полный отказ сессии
  Gemini при старте разговора сейчас выглядит на телефоне как разрыв
  участника → `.failed` (Задача 6, `didDisconnectWithError`) — сигнал есть,
  но без объяснения причины. Отдельный data-канал с текстом причины — по
  запросу владельца отдельной задачей, если разрыв без объяснения окажется
  на практике непонятным.
