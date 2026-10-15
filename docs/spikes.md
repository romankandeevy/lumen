# Спайки (этап 0) — итоги

Проверено 15 октября 2026 на `claude` 2.1.278, macOS 27.2, по подписке Max. Проверки из §12 техплана. Скрипты проверок одноразовые, в репозиторий не кладём: всё нужное перенесено в `ClaudeCodeEngine`.

| № | Вопрос | Ответ | Вывод для Lumen |
|---|---|---|---|
| 1 | Долгоживущий `claude -p` со stream-json на входе и выходе | **Да.** Два хода в одном процессе, контекст помнит. Строка ввода: `{"type":"user","message":{"role":"user","content":[{"type":"text","text":"…"}]}}` | Один тёплый процесс на открытый разговор |
| 1 | «Стоп» = SIGINT | **Да, 0,06 с** от сигнала до `result`. Процесс **живёт дальше** и принимает следующий ход | «Стоп» шлёт SIGINT, процесс не перезапускаем |
| 1 | `--resume` после убийства процесса | **Да.** Тот же `session_id`, кодовое слово из прошлого хода вспомнил | При простое гасим процесс, следующий ход идёт через `--resume` |
| 1 | `--session-id <uuid>` | **Да,** CLI берёт наш UUID | ID разговора задаёт Lumen |
| 2 | Свой системный промпт + `--tools ""` по подписке | **Да.** `tools: []`, около 600 входных токенов на ход (Haiku) | Чат лёгкий, промпт Claude Code не тянется |
| 2 | Хуки `~/.claude` (остров) | С `--setting-sources ""` **молчат**, без флага **срабатывают** | Чат: `--setting-sources ""`. Агент: без флага, чтобы сессия была видна на острове (решение Ромы №6) |
| 3 | `rate_limit_event` | **Есть,** с полем `rateLimitType: "five_hour"`, `status`, `resetsAt` | Окно видно прямо из события |
| 3 | `/usage` в `-p` | **Работает:** «Current session: 44 % used · resets …», «Current week (all models): 7 % …», отдельно Fable | Раз в 10 минут спрашиваем `/usage` (как остров, с `ISLAND_USAGE_PROBE`-подобным флагом) |
| 4 | Свой MCP-сервер через `--mcp-config` в чате без инструментов | **Да.** `--tools "" --strict-mcp-config --mcp-config … --allowedTools mcp__lumen__remember` → у модели есть только `remember`, вызов дошёл до сервера | Память работает через `lumen-mcp`. Swift-версия сервера (swift-sdk) — вместе с памятью |
| 5 | Права бота: `--restricted --tools "Read,Grep,Bash"` + песочница `denyWrite` | **Да.** Edit — «No such tool», `echo >`, `sed -i`, `python open(w)`, `xattr -d` — «Operation not permitted». Файл не изменился | «Отрезано в коде» работает. Рабочие флаги в `docs/spikes.md` и в `BotPolicy` (2.0) |
| 6 | `claude --cloud` | **Не проверяем:** Рома решил облако только через Managed Agents (§18.5) | — |
| 7 | claude.ai-коннекторы в `-p` | **Не проверяем:** решено делать свои коннекторы (§18.11) | — |
| 8 | `ANTHROPIC_API_KEY` + `--resume` той же сессии | **Не проверено:** ключа в окружении нет | Проверить, когда Рома введёт ключ в Lumen |

## Модели в CLI

| `--model` | Что получилось |
|---|---|
| `claude-fable-5-1` | Работает |
| `claude-sonnet-5-5` | Работает (в stderr предупреждение `unrecognized_model`, на ответ не влияет) |
| `claude-haiku-5-5` | Работает (то же предупреждение) |
| `claude-opus-5-5` | **Ошибка 400:** «Claude Code 2.1.278 does not support this model; version 2.1.280 or newer is required» |
| `opus` / `sonnet` / `haiku` | Старые модели: `claude-opus-5`, `claude-sonnet-5`, `claude-haiku-4-5` — короткие имена **не использовать** |

Вывод: Lumen передаёт полные ID. Ошибку «version … or newer is required» показывает как «Обнови Claude Code: `claude update`», а не как сырую ошибку API. Минимальную версию проверяем при старте (`claude --version`).

## Рабочие команды

Чат (подписка):

```bash
claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages \
  --model claude-sonnet-5-5 --effort medium --system-prompt-file system.md \
  --tools "" --setting-sources "" --strict-mcp-config --permission-mode dontAsk --session-id <uuid>
```

Агент (подписка, видно на острове): то же, но `cwd` = папка проекта, без `--tools ""` и без `--setting-sources ""`.

Бот без записи:

```bash
claude -p … --restricted --tools "Read,Grep,Bash" --strict-mcp-config --setting-sources "" \
  --settings '{"sandbox":{"enabled":true,"autoAllowBashIfSandboxed":true,"filesystem":{"denyWrite":["."]}}}' \
  --permission-mode dontAsk
```

## Мелочи

- Флаги-списки (`--allowedTools`, `--tools`) съедают следующий аргумент: текст запроса ставить **до** них или слать через stdin.
- Без stdin `claude -p` ждёт 3 с и пишет предупреждение: запускать с `stdin` = `/dev/null` или пайпом.
- Событие `system/post_turn_summary` приходит после каждого хода: служебное, в UI не показываем.
- `thinking` в событиях приходит пустым (`"thinking": ""`), есть только счётчик `system/thinking_tokens`.
