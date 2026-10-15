# Lumen — технический план

Составлено 15 октября 2026. Основа: макет `ui/` (все экраны и `src/lib/*`), локальный `claude` v2.1.278 (`claude --help`), документация Anthropic, Hermes Agent, MCP и agentskills.io (список в конце). Где я не проверил что-то сам, так и написано: **«не проверено»** или **«проверить в спайке»**.

Документ отвечает на вопрос «как заставить работать всё, что нажимается в макете». Про внешний вид здесь ничего нет.

---

## 0. Коротко

### Главный вывод в пяти строках

1. **Подписка законна только через официальный бинарник `claude`.** Lumen запускает его как подпроцесс (`claude -p --input-format stream-json --output-format stream-json`), а войти в аккаунт Рома должен сам, через `claude auth login`. Читать OAuth-токен из Связки ключей и самому слать запросы в API запрещено. Выдавать Lumen за Claude Code тоже нельзя. Для личного приложения Ромы это нормальное «индивидуальное использование». Раздавать Lumen другим людям со входом по подписке нельзя без согласования с Anthropic.
2. **У Lumen два движка.** «Движок Claude Code» (подпроцесс CLI) работает для подписки, для агента и для ботов. «Движок API» — свой HTTP/SSE-клиент на Swift (официального Swift SDK у Anthropic нет), он отвечает за чат по ключу, фоновые дешёвые вызовы (память, сжатие, классификация) и режим «Авто». Над ними одна абстракция `LLMProvider`, позже в неё же встанут Codex и OpenAI.
3. **«Отрезано в коде» — это отдельный процесс на каждого бота с урезанным набором инструментов.** Набор задают флаги `--tools` (что вообще существует) и `--disallowedTools` (что запрещено даже при обходе), плюс `--restricted`, `--strict-mcp-config` и `--permission-mode dontAsk`. Ещё нужны своя папка, песочница Bash (Seatbelt) и проверка прав на стороне собственного MCP-сервера Lumen. Промпт тут ничего не решает.
4. **Память живёт в SQLite + FTS5 (GRDB 7.11.1).** Факты хранятся с источником. После разговора их извлекает отдельный дешёвый вызов, а в ответ подставляются закреплённые факты и 5–10 найденных. Векторный поиск в MVP не нужен. Слабое место — русская морфология в FTS5, её надо решить отдельно (§5).
5. **Облако Claude Code из своего приложения управляется только частично.** Сессию можно создать (`claude --cloud`, проверить в спайке), дописать в неё (`claude -p "…" --cloud <id>`) и запустить routine через `/fire`. Публичного API, чтобы следить за ходом облачной сессии, нет: смотреть её можно по ссылке на claude.ai/code. Полностью наблюдаемое облако даёт только Managed Agents, но это API и за деньги (§9).

### Схема

```
┌──────────────────────────── Lumen.app (SwiftUI, без App Sandbox, Developer ID + нотаризация) ───────────────────────────┐
│  UI (SwiftUI)  ─── @Observable сторы (Чаты, Агент, Боты, Память, Люди, Характер, Инструменты, Расход, Голос)          │
│        │                                                                                                               │
│  ┌─────▼──────────────────────────── Оркестратор (actor) ──────────────────────────────────────────────┐               │
│  │  Turn pipeline: собрать промпт (Характер + память + люди + навыки) → выбрать движок → стрим → память│               │
│  │  Роутер @бот   ·  Политика прав (Capabilities → флаги/инструменты)  ·  Бюджет/лимиты/«Авто»        │               │
│  │  Группы ботов: доска задач (DAG) · очередь слова · worktree на бота · эскалация к человеку          │               │
│  └───┬───────────────────────┬──────────────────────────────┬──────────────────────────┬─────────────┘               │
│      │                       │                              │                          │                             │
│  ┌───▼──────────────┐  ┌─────▼───────────────────┐  ┌───────▼─────────┐  ┌─────────────▼─────────────┐               │
│  │ ClaudeCodeEngine │  │ AnthropicAPIEngine      │  │ (позже)         │  │ Память / Поиск            │               │
│  │ Process: claude  │  │ URLSession + SSE        │  │ CodexEngine     │  │ GRDB: SQLite+FTS5 (WAL)   │               │
│  │ -p stream-json   │  │ /v1/messages, tools,    │  │ OpenAIEngine    │  │ извлечение фактов (Haiku) │               │
│  │ (подписка/ключ)  │  │ caching, count_tokens   │  └─────────────────┘  │ USER.md / MEMORY.md (вид) │               │
│  └───┬──────────────┘  └─────┬───────────────────┘                       └───────────────────────────┘               │
│      │ --mcp-config          │ свой MCP-клиент (swift-sdk 0.12.1)                                                    │
│  ┌───▼───────────────────────▼───────────┐   ┌──────────────────────┐   ┌─────────────────────────────────┐           │
│  │ lumen-mcp (helper, stdio MCP-сервер): │   │ Навыки (SKILL.md),   │   │ Голос: AVAudioEngine (AEC) →    │           │
│  │ memory.*, people.*, delegate, skills  │◄──┤ lock.json, кэш       │   │ FlowLocal server.py (GIGAAM) →  │           │
│  │ права проверяет по токену бота        │   └──────────────────────┘   │ LLM → TTS (AVSpeech/нейро)      │           │
│  └───────────────────────────────────────┘                              │ Камера: AVCapture → кадры       │           │
│                                                                          └─────────────────────────────────┘           │
└──────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────┘
               │ XPC (Mach service)
┌──────────────▼──────────────────────────┐        ┌────────────────────────────────────────────┐
│ LumenAgent (LaunchAgent, SMAppService)   │        │ Внешнее: api.anthropic.com · claude.ai/code │
│ расписания ботов («Утро» 9:00), фоновые  │───────►│ (облачные сессии, routines /fire) ·          │
│ запуски, позже — шлюз Telegram           │        │ MCP-серверы · OAuth коннекторов              │
└──────────────────────────────────────────┘        └────────────────────────────────────────────┘
Хранилище: ~/Library/Application Support/Lumen/{lumen.sqlite, skills/, bots/, files/, backups/, logs/}; секреты — Связка ключей.
```

### Главные решения и причины

| Решение | Почему |
|---|---|
| Подписка — только через официальный `claude` в headless-режиме, вход — `claude auth login` | Правила Anthropic: OAuth только для «родных» приложений Anthropic и обычного использования Claude Code. Сторонним разработчикам запрещено предлагать вход claude.ai и пропускать запросы через Free/Pro/Max-учётки. Немодифицированный бинарник с собственной подпиской пользователя разрешён (§2.1). |
| Агентный режим и боты всегда идут через `claude` (и по подписке, и по ключу) | Готовые инструменты (Read/Edit/Bash/Grep/Web), права, песочница, сессии, сжатие, субагенты. Писать свой агентный цикл с правкой файлов — месяцы работы и риск. |
| Свой API-клиент на Swift (HTTP + SSE), без сторонних SDK | Официального Swift SDK нет. Есть общинный SwiftAnthropic 2.2.2, но API меняется быстро (effort, adaptive thinking, compaction, fallbacks), и свой тонкий клиент проще держать в актуальном виде. |
| SQLite + FTS5 через GRDB, без векторов в MVP | Так сделано в Hermes (FTS5, ~20 мс на запрос). Фактов будут сотни или тысячи, и FTS вместе с переранжированием моделью справится. Векторы — опция в v2. |
| Один постоянный процесс `claude` на активный разговор (stream-json на входе и выходе) | Нет задержки на запуск каждого хода. Отмена хода — управляющее сообщение `interrupt` в stdin (SIGINT гасит процесс, см. `docs/spikes.md`). При простое процесс гасится, следующий ход идёт через `--resume`. |
| Без App Sandbox, с Hardened Runtime, Developer ID, нотаризацией и Sparkle | Агенту нужен доступ к любым папкам, к `git`, `xcodebuild`, `claude`, `npx`. Из App Sandbox этого не сделать. В App Store приложение не попадёт. |
| Собственный MCP-сервер `lumen-mcp` для инструментов Lumen | Так память, люди и делегирование одинаково работают в обоих движках. Права проверяются на сервере по токену бота, и это вторая линия защиты. |
| Оркестрацию групп ботов делает сам Lumen, «agent teams» Claude Code не используются | По документации agent teams не работают в `-p` и Agent SDK, к тому же они экспериментальные (§14). |

---

## 1. Что именно надо сделать: макет → бэкенд

Сводка по экранам (`src/pages/*`, `src/lib/mock-data.ts`, `app-state.tsx`):

| Экран / элемент макета | Что должно работать по-настоящему | Раздел |
|---|---|---|
| Знакомство (имя, «ты/вы», через что думать, тема) | Первые факты о Роме; проверка `claude auth status` или API-ключа | §2, §5 |
| Чат: модель (Fable 5.1 / Opus 5.5 / Sonnet 5.5 / Haiku 5.5), «сколько думать» (Низкий…Максимальный, «Ультракод») | Выбор модели и effort для обоих движков | §2, §3 |
| Чат: стриминг, «Стоп», шаги («Читает файл…»), «Опирался на N воспоминаний», «Запомнил» + изменить/забыть | Стрим событий, отмена, память с цитированием | §3, §5 |
| «+»: интернет, глубокое исследование, память вкл/выкл, файл, бот | web_search/web_fetch, режим исследования, флаг памяти, вложения, @бот | §3, §8, §11 |
| Агент: папка, «Этот Мак / Облако Claude», карточка «Изменения» (+2 −1, Разница, Откатить, Закоммитить), «push только с OK» | Движок Claude Code в папке, снимок до и после, diff, git, запрет push | §2, §4, §9 |
| Правая панель: «Окно контекста 47 тыс. из 200 тыс.» по частям, «Сжать разговор», «Расход: подписка 5 ч / неделя» | Учёт токенов по частям промпта, сжатие, лимиты | §6, §11 |
| Боты: список, «Работают» (шаг 3 из 5), карточка делегирования, «Вне роли — заблокировано в коде», «Сделать задачу для @coder» | Процессы ботов, права, роутинг, передача задачи | §4, §14 |
| Бот: один постоянный чат, «Сжато: 1–12 окт, 380 → пересказ», паспорт (умеет, отрезано, навыки, чему научился, что нужно) | Постоянная сессия, сжатие, память бота, проверка требований | §4, §6, §8 |
| Конструктор бота (знак, цвет, @id, роль, инструкции, инструменты, подсказки) + «сам настраивается и качает навыки» | Генерация BotSpec моделью, установка навыков без повторов | §4, §8 |
| Память: факты по видам, закрепить / изменить / забыть, граф, «Прошлые разговоры» (поиск), USER.md / MEMORY.md, «Запоминать само» | Таблицы памяти, FTS5, сущности, извлечение | §5 |
| Люди: анкеты, «Что Lumen знает о нём», «упоминался в N чатах» | Таблица people, связь с сущностями и упоминаниями | §5 |
| Характер: ~15 настроек + правила + запрещённые слова → «инструкции, которые получает модель» (SOUL.md) | Детерминированная сборка системного промпта, кэш | §3 |
| Инструменты: навыки (каталог agentskills.io), MCP (команда или адрес + env), коннекторы (OAuth), внешние API (ключ, «Проверить») | Установщик навыков, MCP-клиент, OAuth, Связка ключей | §7, §8 |
| Настройки → Модели и оплата: Подписка / API / Авто, вход через браузер, ключ `sk-ant-…`, «в этом месяце $4,18», «остановиться на $ в месяц», Codex/OpenAI позже | Провайдеры, учёт денег, лимит, переключение | §2, §11 |
| Голос: голос Lumen, скорость, «читать ответы вслух», правый ⌥, FlowLocal | STT, TTS, VAD, перебивание | §13 |
| Данные: «всё на этом Маке», показать в Finder, выгрузить память | Папка данных, экспорт, бэкапы | §10.4 |

---

## 2. Как говорить с Claude через подписку законно и надёжно

### 2.1 Что разрешено и что запрещено (по документам)

Цитаты из официальных страниц:

- Agent SDK overview: *«Unless previously approved, Anthropic does not allow third party developers to offer claude.ai login or rate limits for their products, including agents built on the Claude Agent SDK.»*
- Legal and compliance → Authentication and credential use: OAuth предназначен для подписчиков и *«designed to support ordinary use of Claude Code and other native Anthropic applications»*. Разработчики продуктов должны использовать API-ключ. *«Anthropic does not permit third-party developers to offer Claude.ai login into their own applications, or to route requests through Free, Pro, or Max plan credentials on behalf of their users. Moreover, developers may not collect, store, or intermediate Claude.ai credentials or session tokens.»* При этом: *«Nor does it prevent an end user from signing in to the unmodified Claude Code binary with their own Claude subscription.»*
- Там же: *«Advertised usage limits for Pro and Max plans assume ordinary, individual usage of Claude Code and the Agent SDK.»*
- Брендинг (Agent SDK): нельзя называть свой продукт «Claude Code» или «Claude Code Agent» и подражать его виду. Можно писать «Claude Agent», «Powered by Claude».

**Что из этого следует для Lumen:**

| Можно | Нельзя |
|---|---|
| Запускать установленный у Ромы, **немодифицированный** `claude` как подпроцесс (`claude -p …`) | Читать OAuth-токен Claude Code из Связки ключей или `~/.claude` и самому ходить с ним в `api.anthropic.com` |
| Просить Рому войти **самому**: кнопка «Войти через браузер» запускает `claude auth login` (вход идёт через собственный поток Anthropic) | Делать свой экран ввода логина и пароля claude.ai, хранить или пересылать его токены |
| Показывать в UI «через подписку Claude» и «Claude Code на этом Маке» как простой факт | Называть приложение или вкладку «Claude Code», рисовать его логотип и ASCII-заставку |
| Использовать `setup-token` (долгоживущий токен «requires Claude subscription») для LaunchAgent — **проверить в спайке**, разрешено ли его использование для фоновых запусков того же бинарника | Пускать по подписке Ромы других людей (например, через шлюз Telegram для друзей) |

Честная оговорка: Lumen как личное приложение Ромы, которое запускает его же `claude` под его же входом, — это «обычное индивидуальное использование Claude Code». Если Lumen когда-нибудь раздавать людям, режим «Подписка» становится серой зоной. Тогда безопасный путь — только API-ключ каждого пользователя, а для подписки нужно согласование с Anthropic (sales). Вторая оговорка: 24/7-боты и группы ботов на подписке могут выйти за «ordinary usage». Поэтому фоновые и долгие прогоны лучше по умолчанию отправлять через API, а подписку держать для живых разговоров. Это решение за Ромой (открытый вопрос №2).

### 2.2 Как запускать (рабочая архитектура)

У Ромы уже есть рабочий образец: `Мак-приложения/prog-dashboard/Sources/ClaudeJobs.swift`, где пульт запускает `claude -p --output-format stream-json --verbose --permission-mode acceptEdits --allowedTools … --disallowedTools …` и читает `out.jsonl`. Lumen делает то же, но интерактивно: процесс живёт, пока идёт разговор.

**Запуск одного разговора (чат по подписке):**

```bash
claude -p \
  --input-format stream-json --output-format stream-json --verbose \
  --include-partial-messages \
  --model opus --effort medium \
  --system-prompt-file "$LUMEN/run/<conv>/system.md" \  # полный SOUL — свой системный промпт вместо промпта Claude Code
  --tools "" \                                         # чат: ни одного встроенного инструмента
  --strict-mcp-config --mcp-config "$LUMEN/run/<conv>/mcp.json" \  # только lumen-mcp (память, люди, @бот)
  --setting-sources "" \                               # не читать ~/.claude настройки, хуки, CLAUDE.md — проверить в спайке, что пустой список принимается
  --permission-mode dontAsk --permission-prompts none \
  --session-id <uuid>                                  # свой UUID, чтобы потом --resume
```

Важно:

- `--bare` для подписки **не годится**: в bare-режиме CLI «never reads OAuth credentials or the system keychain», он работает только с `ANTHROPIC_API_KEY`. Зато для режима «API-ключ через CLI» bare как раз хорош: быстрее стартует и не грузит чужие хуки.
- Без `--bare` CLI в `-p` грузит хуки и `.mcp.json` проекта **без диалога доверия** («Only use this in directories you trust»). Для агента в папках prog это приемлемо. Например, у Ромы есть хук острова, который пишет статус сессии, и для агентных сессий Lumen это, может быть, даже хорошо (открытый вопрос №6). Для ботов и чата загрузку выключаем: `--setting-sources`, `--strict-mcp-config` или `--safe-mode`, который выключает кастомизации, но сохраняет авторизацию (проверить в спайке, глушит ли `--safe-mode` и `--mcp-config` тоже).
- `--system-prompt-snapshot on` (по умолчанию) фиксирует системный промпт на весь разговор до сжатия. Это хорошо для кэша, но правки «Характера» применятся только в новых разговорах. Макет же обещает «Применится со следующего ответа во всех чатах». Решение: менять характер в текущем разговоре через mid-conversation system message (§3.4). В CLI-движке так нельзя, поэтому там правка вступает в силу после ближайшего сжатия или в новом разговоре. В UI честно пишем: «со следующего разговора».

**Протокол.** Вход — строки JSON в stdin, выход — строки JSON в stdout. Основные события вывода (из справочника Agent SDK, типы `SDKMessage`):

```jsonc
{"type":"system","subtype":"init","session_id":"…","model":"…","tools":[…],"mcp_servers":[{"name":"lumen","status":"connected"}],"capabilities":["interrupt_receipt_v1", …]}
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Понял…"}}}  // при --include-partial-messages
{"type":"assistant","message":{/* BetaMessage */},"parent_tool_use_id":null,"context_usage":{…}}
{"type":"user","message":{"content":[{"type":"tool_result",…}]},"parent_tool_use_id":null}
{"type":"rate_limit_event","rate_limit_info":{"status":"allowed_warning","resetsAt":1760563800,"utilization":0.81}}
{"type":"system","subtype":"api_retry","attempt":1,"max_retries":10,"retry_delay_ms":2000,"error_status":429,"error":"rate_limit"}
{"type":"system","subtype":"compact_boundary","compact_metadata":{"trigger":"auto","pre_tokens":182340}}
{"type":"result","subtype":"success","session_id":"…","result":"…","total_cost_usd":0.0123,"usage":{…},"modelUsage":{"claude-opus-5-5":{"inputTokens":…,"outputTokens":…,"cacheReadInputTokens":…,"costUSD":…}},"permission_denials":[],"num_turns":3,"terminal_reason":"completed"}
```

Строка ввода (одно сообщение пользователя) выглядит так: `{"type":"user","message":{"role":"user","content":[{"type":"text","text":"…"}]}}`. **Точный формат сверить в спайке** по SDK-типу `SDKUserMessage`.

**Подводные камни CLI-протокола:**

- Формат событий меняется от версии к версии: в документации много пометок «Requires Claude Code v2.1.xxx». Поэтому декодер должен быть терпимым (`enum` с `case unknown(JSONValue)`). Возможности проверяем по `system/init.capabilities`, а не по номеру версии. Минимальную версию проверяем при старте (`claude --version`), сейчас у Ромы 2.1.278. Для протокола нужны контрактные тесты на записанных фикстурах.
- Отмена: **SIGINT завершает ход**, а SIGTERM убивает процесс с кодом 143 и оставляет ход незавершённым (раздел «Stop a run with SIGTERM» в headless-доке). Управляющие сообщения SDK (`interrupt`) — внутренний протокол, публично не описан. **Спайк показал:** после SIGINT в режиме stream-json `claude` завершается целиком, а `interrupt` останавливает ход за 0,07 с и оставляет процесс живым. Для «Стоп» шлём `interrupt`, SIGINT — только чтобы погасить процесс.
- В GUI-приложении `PATH` не как в терминале. Путь к `claude` (`~/.local/bin/claude`) и окружение берём из логин-шелла, как делает `Shell.env` в Пульте.
- `total_cost_usd` и `costUSD` — «client-side estimates». По подписке это «сколько стоило бы по API». Показываем это как «эквивалент», а не как списание.

### 2.3 Лимиты 5 часов / неделя

Документированных источников три, и ни один не идеален:

1. **`rate_limit_event`** в stream-json: `status` (`allowed` / `allowed_warning` / `rejected`), `resetsAt`, `utilization`, `errorCode: "credits_required"`. Тип окна (5 ч или неделя) в описанном типе **не указан**, это проверить в спайке на реальных событиях.
2. **Статусная строка** получает JSON с `rate_limits.five_hour.used_percentage / resets_at` и `rate_limits.seven_day.…`, но только у подписчиков Pro/Max и только после первого ответа. Это механизм интерактивного режима. Вызывается ли `statusLine` в `-p`, **не проверено** (скорее нет).
3. **`/usage` как промпт:** в доке написано, что вывод `/context` и `/usage`, отправленных промптом, приходит как `SDKAssistantMessage`. Значит, Lumen может раз в несколько минут спрашивать `/usage` в отдельном коротком процессе и разбирать текст. Это хрупко, потому что формат текста может поменяться.

План такой: в MVP берём 1 и 3. В спайке проверяем, есть ли в событиях тип окна. Если нет, показываем «Подписка: 81 %, сброс в 23:10» по последнему событию и раз в 10 минут уточняем через `/usage`.

### 2.4 Режим «Авто» (подписка → API)

- Признак переключения: `rate_limit_event.status == "rejected"`, либо `system/api_retry` с `error: "rate_limit"` несколько раз подряд, либо `result.api_error_status == 429`, либо `errorCode == "credits_required"`.
- Действие для **чата**: история хранится у Lumen в SQLite, поэтому следующий ход просто идёт в `AnthropicAPIEngine`. Историю переносим как текст, без thinking-блоков (они привязаны к модели и разговору, переносить их нельзя и не нужно). В UI одна строка: «Лимит подписки до 23:10 — продолжаю через API».
- Для **агента и бота**: перезапустить CLI с `ANTHROPIC_API_KEY` в окружении и `--resume <session_id>`. По документации переменная ключа «outranks» вход claude.ai. Что `--resume` подхватывает сессию при смене способа входа, **проверить в спайке**.
- Обратно: когда наступает `resetsAt`, следующий **новый** ход снова идёт по подписке.
- Предохранитель: месячный лимит в $ из настроек («Остановиться на $ в месяц»). Lumen ведёт свой журнал трат, CLI-флаг `--max-budget-usd` ставим на каждый запуск бота, а при упоре в лимит ставим разговор на паузу и спрашиваем Рому.

---

## 3. Anthropic API из Swift

### 3.1 Клиент

Официального Swift SDK нет: в справочнике Claude API перечислены Python, TypeScript, Java, Go, Ruby, C#, PHP. Есть общинный `jamesrochabrun/SwiftAnthropic` 2.2.2 (апрель 2026), но я бы его взял только как справку. Свой клиент — примерно 600–900 строк:

- `URLSession.bytes(for:)` → построчный разбор SSE (`event:` / `data:`).
- Заголовки: `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`, при необходимости `anthropic-beta: …`.
- События стрима: `message_start`, `content_block_start` (`text` / `thinking` / `tool_use` / `server_tool_use` / `web_search_tool_result`…), `content_block_delta` (`text_delta`, `thinking_delta`, `input_json_delta`, `signature_delta`), `content_block_stop`, `message_delta` (`stop_reason`, `usage`), `message_stop`, `ping`, `error`.
- Повторы: 429, 529, 5xx и сетевые ошибки с учётом `retry-after`, не больше 2–3 попыток, отмена через `Task.cancel()`.

```swift
public protocol LLMProvider: Sendable {
    var id: ProviderID { get }                       // .claudeCode(.subscription), .claudeCode(.apiKey), .anthropicAPI, .codex, .openAI
    func capabilities() async -> ProviderCapabilities // модели, effort, тулзы, лимиты, умеет ли агентный режим
    func send(_ turn: TurnRequest) -> AsyncThrowingStream<TurnEvent, Error>
    func cancel(_ turn: TurnID) async
}

public enum TurnEvent: Sendable {
    case started(sessionID: String?)
    case textDelta(String)
    case thinkingDelta(String)              // при display: "summarized" / "updates"
    case toolStarted(ToolCall)              // «Читает ShelfStorage.swift»
    case toolFinished(ToolCall.ID, ToolOutcome)
    case usage(TokenUsage)                  // input, output, cacheRead, cacheWrite, thinking
    case rateLimit(RateLimitInfo)
    case compacted(fromTokens: Int)
    case citedMemories([MemoryID])          // §5.6
    case finished(StopReason, cost: Money?)
}

public struct TurnRequest: Sendable {
    var conversation: ConversationID
    var model: ModelChoice                  // .fable51, .opus55, .sonnet55, .haiku55 (id тянем из /v1/models)
    var effort: Effort                      // .low … .max
    var system: [SystemBlock]               // стабильная часть (характер + закреплённое) — с cache_control
    var messages: [ChatMessage]
    var tools: [ToolSpec]                   // отсортированы детерминированно
    var webSearch: Bool, deepResearch: Bool, useMemory: Bool
    var attachments: [Attachment]
}
```

### 3.2 Модели, effort, thinking (актуальные правила)

Сводка из справочника Claude API (данные на 2026-10-06):

| Модель | ID | Цена вход/выход за 1M | Контекст | Особенности |
|---|---|---|---|---|
| Fable 5.1 | `claude-fable-5-1` | $10 / $50 | 1M | thinking всегда включён; `tool_choice` any/tool → 400 |
| Opus 5.5 | `claude-opus-5-5` | $4 / $20 (чтение кэша $0.20) | 1M | thinking **нельзя выключить**; effort по умолчанию **medium**, ставить явно; forced tool_choice → 400 |
| Sonnet 5.5 | `claude-sonnet-5-5` | $2 / $10 | 1M | выключить thinking можно только через `{type:"between_tools"}` |
| Haiku 5.5 | `claude-haiku-5-5` | $0.10 / $0.50 (до 100K) | 1M | для фоновой работы: память, классификация «не по роли», заголовки |

- Thinking: `thinking: {type: "adaptive", display: "summarized"}`. Без `display` текст размышлений приходит пустым, и UI выглядит как долгая пауза. Шаги «Читает файл…» берём из `tool_use`, а «мысли» — из summarized. `budget_tokens` на этих моделях даёт **400**.
- Effort: `output_config: {effort: "low"|"medium"|"high"|"xhigh"|"max"}`. В макете шесть уровней, и **«Ультракод» в API нет**. Честный вариант: «Ультракод» = Fable 5.1 + `max` + task budget (beta `task-budgets-2026-03-13`) + разрешение на долгую работу и субагентов. Либо убрать этот пункт (открытый вопрос №4). В CLI: `--effort low…max`.
- Отказы: для Opus 5.5 и Fable справочник советует server-side fallback (`anthropic-beta: server-side-fallback-2026-07-01`, `fallbacks: "default"`) и обязательно проверять `stop_reason == "refusal"` до чтения контента.
- Без prefill ответа: последний ход ассистента в запросе → 400.
- История только дописывается: правка старых ходов ломает thinking-блоки (preserved thinking, для новых аккаунтов → 400). «Изменить сообщение» в Lumen поэтому означает форк разговора, а не правку истории.

Пример запроса (чат по API):

```json
POST /v1/messages
{
  "model": "claude-opus-5-5",
  "max_tokens": 64000,
  "stream": true,
  "cache_control": {"type": "ephemeral"},
  "thinking": {"type": "adaptive", "display": "summarized"},
  "output_config": {"effort": "medium"},
  "system": [
    {"type": "text", "text": "<SOUL: характер, правила, с кем говоришь>"},
    {"type": "text", "text": "<закреплённая память (снимок на начало разговора)>", "cache_control": {"type": "ephemeral", "ttl": "1h"}}
  ],
  "tools": [
    {"type": "web_search_20260209", "name": "web_search", "max_uses": 5},
    {"name": "memory_search", "description": "…", "input_schema": {…}, "strict": true},
    {"name": "remember", "description": "…", "input_schema": {…}, "strict": true}
  ],
  "messages": [
    …история…,
    {"role": "user", "content": [
      {"type": "text", "text": "<memory ids=\"m9,m2,m3\">…найденные факты…</memory>"},
      {"type": "text", "text": "Напомни, на чём мы остановились с Люменом?"}
    ]}
  ]
}
```

### 3.3 Prompt caching

- Кэш работает по совпадению префикса в порядке `tools → system → messages`. Любой изменившийся байт ломает всё, что идёт после него.
- Что стабильно: список инструментов (сортировать по имени, не менять посреди разговора), SOUL и снимок закреплённой памяти на начало разговора. Так же делает Hermes: «frozen snapshot… to preserve the LLM's prefix cache».
- Что меняется каждый ход: найденные факты, время, состояние папки. Их кладём **в сообщение пользователя**, а не в `system`.
- Проверка: `usage.cache_read_input_tokens > 0` со второго хода. Если там ноль, где-то сидит «тихий разрушитель» кэша (дата в system, неупорядоченный JSON).
- В CLI-движке кэшем управляет сам Claude Code.

### 3.4 Прочее из API, что пригодится

- **Mid-conversation system message** (`{"role":"system",…}` внутри `messages`) поддерживается на Opus 5.5, Fable 5.1, Sonnet 5.5 и Haiku 5.5 и не ломает кэш. Это канал для смены характера, режима «Без памяти» и подсказок оркестратора посреди разговора.
- **Подсчёт токенов:** `POST /v1/messages/count_tokens`, для кольца «Окно контекста» по частям. Сколько он стоит и какие у него лимиты, **не проверено**: можно считать редко и кэшировать.
- **Веб:** серверные `web_search_20260209` и `web_fetch_20260209`. Ошибка поиска приходит не исключением, а блоком с `error_code`.
- **Сжатие на сервере:** beta `compact-2026-01-12` (§6).
- **Batches** (−50 %) — для ночной уборки памяти по ключу.
- **Модели:** `GET /v1/models` отдаёт `max_input_tokens`, `max_tokens` и `capabilities`, по ним строим список в UI.

---

## 4. Боты: «всё вне роли отрезано в коде»

### 4.1 Принцип

Роль задаётся **набором возможностей** (`Capability`), а не текстом. Lumen переводит набор в флаги процесса. Чего нет в наборе, того нет в процессе вообще: модель даже не видит описания такого инструмента.

```swift
enum Capability: String, Codable, CaseIterable {
    case readFiles, writeFiles, runCommands, web, git, gitPush, memoryWrite, callBots
}

struct BotSpec: Codable, Identifiable {
    var id: String                    // @tester: [a-z0-9-]{2,32}
    var name: String, icon: BotIcon, hue: Int
    var role: String                  // одна строка
    var instructions: String
    var can: [String]                 // для паспорта и подсказок
    var capabilities: Set<Capability>
    var commandAllowlist: [String]    // для runCommands: ["./build.sh *", "xcodebuild test *", "swift test *"]
    var folders: [FolderGrant]        // [{path: "~/Documents/prog", write: false}]
    var skills: [SkillRef]            // имя + источник + хэш
    var mcpServers: [String]          // id из «Инструментов»
    var model: ModelChoice, effort: Effort
    var starters: [String]
    var handoff: String?              // id бота, кому отдавать чужое
    var schedule: Schedule?           // «Утро»: каждый день 9:00
    var budget: Budget                // $ на запуск, $ в месяц, макс. ходов
}
```

### 4.2 Как Capability превращается в ограничения

| Capability | CLI-движок (`claude -p`) | API-движок (свой цикл) |
|---|---|---|
| readFiles | `--tools` включает `Read,Glob,Grep`; `--add-dir` только для разрешённых папок | инструменты `read_file`, `grep` с проверкой пути внутри разрешённых папок |
| writeFiles | `Edit,Write` в `--tools` | `write_file`, `edit_file` |
| runCommands | `Bash` в `--tools` + песочница + `--allowedTools "Bash(./build.sh *)" …` + `--permission-mode dontAsk` (всё, что не в allow, отклоняется) | не даём (агентное — только через CLI) |
| web | `WebSearch,WebFetch` | серверные web_search / web_fetch |
| git | `Bash(git status *)`, `Bash(git diff *)`, `Bash(git commit *)` | — |
| gitPush | без неё всегда `--disallowedTools "Bash(git push *)"`. Scoped-правило из disallowed запрещает «in every mode, including bypassPermissions» | — |
| memoryWrite | в `mcp.json` бота у `lumen-mcp` есть `memory.write` | инструмент `remember` |
| callBots | в `lumen-mcp` есть `delegate` | инструмент `delegate` |

Общие флаги для каждого бота:

```bash
claude -p --input-format stream-json --output-format stream-json --verbose \
  --restricted \                              # убирает Bash/код и WebFetch, если --tools их не назвал; не читает user/project/local settings;
                                              # замыкает файловые тулы на рабочих папках; запрещает bypassPermissions
  --tools "Read,Glob,Grep,Bash" \             # для @tester
  --allowedTools "Bash(./build.sh *),Bash(xcodebuild test *),Bash(swift test *)" \
  --disallowedTools "Bash(git push *),Bash(rm *),Bash(curl *)" \
  --permission-mode dontAsk --permission-prompts none \
  --strict-mcp-config --mcp-config "$BOT/mcp.json" \
  --settings "$BOT/settings.json" \           # sandbox (ниже)
  --system-prompt-file "$BOT/system.md" \     # роль + инструкции + «чему научился»
  --add-dir "$BOT/skills" \                   # .claude/skills/ только с его навыками
  --max-budget-usd 2 \
  --resume "$BOT_SESSION_ID"                  # его единственный чат
# cwd = папка проекта (или worktree бота), а не ~
```

`settings.json` бота (песочница Bash; на macOS это Seatbelt):

```json
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false,
    "filesystem": { "denyWrite": ["~/Documents/prog"], "allowWrite": ["$BOT/scratch", "$PROJECT/build"] },
    "network": { "allowedDomains": [] }
  }
}
```

**Неочевидная дыра, о которой надо помнить.** «Запускать команды» почти всегда означает и «править файлы»: `echo > file` или `sed -i` пишут на диск без инструмента Edit. Поэтому у @tester (в макете read + run, но не write) запись надо закрыть не отсутствием Edit, а песочницей (`denyWrite` на проект, `allowWrite` только на `build/` и scratch) **и** белым списком команд в `--allowedTools` при `dontAsk`. Песочница действует только на Bash, а «file tools, MCP servers, and hooks run outside it». Поэтому файловые инструменты ограничиваем отдельно, через `--tools` и `--add-dir`.

Ключи `sandbox.filesystem.allowWrite/denyWrite` и `network.allowedDomains` упомянуты на странице sandboxing. Точную форму путей (`~`, переменные) **проверить в спайке**.

### 4.3 Защита на стороне Lumen (вторая линия)

- `lumen-mcp` — отдельный исполняемый файл в бандле (Swift, `modelcontextprotocol/swift-sdk` 0.12.1, сервер на stdio). Запускается от CLI по `mcp.json`, связь с приложением идёт через XPC или Unix-сокет. При запуске получает `LUMEN_BOT_TOKEN`, и приложение **само** проверяет, есть ли у этого токена `memoryWrite` или `callBots`. Даже если модель как-то позовёт инструмент, сервер ответит отказом.
- Журнал: каждый `tool_use`, каждый `permission_denials` из `result` и каждое `permission_denied` событие пишутся в `audit_log`. Из этого журнала наполняется паспорт бота («Отрезано в коде») и видно, кто во что упирался.
- «Вне роли» в UI — дешёвая вежливость: перед запуском бота Haiku классифицирует задачу (`in_role / off_role / unclear`) и при `off_role` сразу предлагает «Сделать задачу для @coder». Это **не** защита, защита — отсутствие инструментов. В макете `offTopic: RegExp` нужен только для имитации.
- Опционально (v2): запуск процесса бота через собственный профиль Seatbelt (`sandbox-exec -f bot.sb`) для запрета записи и сети уже на уровне ОС для всего процесса, включая файловые инструменты. `sandbox-exec` помечен Apple как устаревший, но работает, и Claude Code сам использует Seatbelt. **Проверить**, уживается ли внешний профиль с внутренней песочницей CLI (вложенный sandbox: в SDK есть `enableWeakerNestedSandbox`).

### 4.4 Один постоянный чат бота

- У бота одна CLI-сессия (`bot_sessions.cli_session_id`). Каждый запуск — `--resume <id>`. Сам CLI автоматически сжимает разговор (`compact_boundary`, флаг `--autocompact <auto|tokens>`). Lumen ловит событие и записывает строку «Сжато: даты, N сообщений → пересказ» (§6).
- Полную историю Lumen хранит у себя (таблица `messages`), потому что транскрипты CLI в `~/.claude/projects` удаляются по `cleanupPeriodDays`.
- «Чему научился»: после каждой задачи бот (или Haiku по транскрипту) предлагает 0–2 вывода. Они пишутся в `bot_memories` и попадают в `system.md` бота при следующем запуске.
- «Сжать сейчас»: послать в процесс бота промпт `/compact` (поддерживается в `-p`).

### 4.5 Бот сам настраивается при создании

1. Рома описывает роль одной фразой: «Нужен бот, который тестирует сборки».
2. Lumen (Opus 5.5, structured output: `--json-schema` в CLI или `output_config.format` в API) возвращает черновик `BotSpec`: имя, @id, цвет, роль, инструкции, **минимальный** набор capabilities, белый список команд, папки, подсказки, handoff, список нужных навыков (по каталогу §8) и чек-лист «Что нужно для работы» (Xcode? доступ к папке? TestFlight?).
3. **Права выбирает человек.** Черновик открывается в конструкторе с отмеченными инструментами, и Рома подтверждает. Модель только предлагает: давать ей самой раздавать себе права нельзя.
4. Установщик навыков ставит отсутствующие навыки и пропускает уже скачанные (сравнение по источнику, коммиту и sha256 содержимого, §8).
5. Проверка требований: `xcodebuild -version`, `FileManager.isReadableFile`, наличие MCP-сервера. Результат — галочки «ok / Дать» в паспорте.

### 4.6 Делегирование из любого чата (@id)

- Явное упоминание `@tester …` в поле ввода роутер ловит **до** модели и сразу запускает бота. Это дёшево и предсказуемо. Lumen показывает карточку делегирования (цвет и знак бота, шаги из `tool_use` бота, результат).
- Неявное («проверь фикс» без @): у главного Lumen есть инструмент `delegate(bot_id, task, context)` в `lumen-mcp`. Модель сама решает, кого звать, и оркестратор запускает бота.
- В CLI-сессии бот получает только задачу и контекст (как `goal` + `context` у Hermes `delegate_task`), а не всю историю чата. В ответ возвращается короткий итог: он попадает в чат Lumen и полностью сохраняется в постоянный чат бота.
- Глубина вызовов ограничена: бот с `callBots` может позвать другого, но максимум на 1 уровень. Дальше `delegate` отвечает «нельзя».

---

## 5. Память

### 5.1 Что хранится

```sql
-- факты
CREATE TABLE memories(
  id            TEXT PRIMARY KEY,          -- 'm_01J…' (ULID)
  text          TEXT NOT NULL,             -- одна мысль — один факт
  kind          TEXT NOT NULL,             -- you | project | decision | pref | people
  status        TEXT NOT NULL DEFAULT 'active',  -- active | forgotten | superseded
  pinned        INTEGER NOT NULL DEFAULT 0,
  source_conv   TEXT REFERENCES conversations(id),
  source_msg    TEXT REFERENCES messages(id),
  source_quote  TEXT,                      -- цитата-доказательство из разговора
  origin        TEXT NOT NULL,             -- user_explicit | auto_extracted | manual | bot:<id> | person_card
  confidence    REAL NOT NULL DEFAULT 0.8,
  superseded_by TEXT REFERENCES memories(id),
  created_at    INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  last_used_at  INTEGER, use_count INTEGER NOT NULL DEFAULT 0
);
CREATE VIRTUAL TABLE memories_fts USING fts5(text, content='memories', content_rowid='rowid',
  tokenize = "unicode61 remove_diacritics 2");          -- + см. «русская морфология»

-- сущности и граф
CREATE TABLE entities(id TEXT PRIMARY KEY, name TEXT, kind TEXT CHECK(kind IN ('me','project','person','place','thing')),
                      aliases TEXT /* JSON */, project_path TEXT, person_id TEXT REFERENCES people(id));
CREATE TABLE memory_entities(memory_id TEXT REFERENCES memories(id) ON DELETE CASCADE,
                             entity_id TEXT REFERENCES entities(id) ON DELETE CASCADE, PRIMARY KEY(memory_id, entity_id));

-- люди (анкеты)
CREATE TABLE people(id TEXT PRIMARY KEY, name TEXT, relation TEXT, work TEXT, dates TEXT,
                    how_to_talk TEXT, interests TEXT, created_at INTEGER, updated_at INTEGER);

-- разговоры и поиск по ним
CREATE TABLE conversations(id TEXT PRIMARY KEY, kind TEXT /* chat|agent|bot|group */, title TEXT, project_path TEXT,
                           place TEXT /* mac|cloud */, bot_id TEXT, cli_session_id TEXT, cloud_session_id TEXT,
                           summary TEXT, created_at INTEGER, updated_at INTEGER, archived INTEGER DEFAULT 0);
CREATE TABLE messages(id TEXT PRIMARY KEY, conv_id TEXT REFERENCES conversations(id), role TEXT, author TEXT,
                      body TEXT, blocks TEXT /* JSON: tool_use, результаты, картинки */, created_at INTEGER,
                      model TEXT, usage TEXT /* JSON */, cost_usd REAL);
CREATE VIRTUAL TABLE messages_fts USING fts5(body, title UNINDEXED, content='messages', content_rowid='rowid',
                                             tokenize = "unicode61 remove_diacritics 2");
CREATE TABLE message_memories(message_id TEXT, memory_id TEXT, role TEXT /* injected | cited | created */,
                              PRIMARY KEY(message_id, memory_id, role));
CREATE TABLE compactions(id TEXT PRIMARY KEY, conv_id TEXT, from_msg TEXT, to_msg TEXT, msg_count INTEGER,
                         pre_tokens INTEGER, summary TEXT, created_at INTEGER);
```

FTS-таблицы с внешним контентом синхронизируем триггерами (GRDB умеет `synchronize(withTable:)`).

### 5.2 Русская морфология — отдельная задача

Стемминг FTS5 `porter` работает только с английским, а `unicode61` для кириллицы делает лишь регистр и диакритику. Поэтому запрос «падение» не найдёт «падал» и «падает». Варианты:

1. **Префиксные запросы**: обрезаем слова запроса до основы примерно в 5–6 букв и добавляем `*` (`пада*`). Это дёшево и в MVP хватит.
2. **Свой токенайзер FTS5** со стеммером Snowball для русского. GRDB поддерживает собственные FTS5-токенайзеры на Swift (`FTS5CustomTokenizer`). Стеммер — порт Snowball Russian, около 300 строк. Это v1.
3. Токенайзер `trigram` (SQLite 3.34+) ищет подстроки, но индекс получается крупнее. Подходит для имён файлов и «ShelfStorage».

Рекомендация: два индекса. По `messages` — стеммер плюс `trigram` для кода и путей. По `memories` — стеммер.

### 5.3 Как факты попадают в память

1. **Явно**: «запомни, что…». У модели есть инструмент `remember(text, kind, about[])`. Факт пишется сразу, в ответе появляется плашка «Запомнил» с кнопками «Изменить» и «Забыть».
2. **Вручную**: «Запомнить факт», анкеты людей.
3. **Автоматически** («Запоминать само»): после простоя разговора 3–5 минут, при закрытии или перед сжатием запускается отдельный дешёвый вызов. Haiku 5.5 по API; по подписке — `claude -p --model haiku --tools "" --json-schema …`.

   - Вход: новые сообщения разговора, 20–30 похожих существующих фактов (FTS по ключевым словам, сущностям и людям) и список сущностей.
   - Выход (structured output):
   ```json
   {"ops":[
     {"op":"add","text":"Светлую тему в Lumen не делаем, только тёмные","kind":"decision","about":["lumen"],"quote":"светлую тему не делаем","confidence":0.95},
     {"op":"update","id":"m_…","text":"…новая формулировка…","quote":"…"},
     {"op":"forget","id":"m_…","reason":"Рома сказал, что это больше не так"},
     {"op":"noop"}
   ],
    "entities":[{"name":"Lumen","kind":"project"}]}
   ```
   - Правила в промпте: сохранять только то, что пригодится через неделю; не сохранять пересказ разговора; одна мысль — один факт; каждый факт с цитатой-доказательством.
   - Результат появляется плашкой «Запомнил N фактов» в конце разговора, и её можно отменить. Факты, извлечённые **из текста инструментов** (веб-страница, файл, письмо), получают `origin=auto_extracted` и `confidence ≤ 0.5` и требуют подтверждения. Это защита от «отравления памяти» через инъекцию в контент.

### 5.4 Дедупликация

- Перед `add`: FTS-поиск по тексту нового факта. Если находится похожий факт (высокий BM25 или общие сущности), он попадает в кандидаты, и решение add или update принимает модель (схема Mem0 ADD/UPDATE/DELETE/NOOP).
- Точный дубль (нормализованный текст совпал) отбрасывается, как в Hermes («Exact duplicate entries are rejected»).
- Старый факт при `update` получает `status=superseded`, `superseded_by=новый`. История сохраняется, и «Вернуть» работает.

### 5.5 Что подставляется в каждый ответ и сколько это стоит в токенах

| Блок | Куда | Бюджет |
|---|---|---|
| Характер (SOUL) | `system`, кэшируется | ~0,8–1,5 тыс. токенов |
| Закреплённые факты + «о тебе» (USER.md) | `system`, снимок на начало разговора | до ~1,5 тыс. (в Hermes: MEMORY.md 2200 знаков + USER.md 1375 знаков ≈ 1,3 тыс. токенов) |
| Найденные под текущий вопрос | в сообщение пользователя, `<memory ids="…">` | 5–10 фактов, до ~1,5–2 тыс. |
| Анкеты упомянутых людей | туда же | до ~0,5 тыс. на человека |
| Навыки (имя + описание) | `system` | ~100 токенов на навык (agentskills.io), полный текст по требованию |

Ранжирование найденного (без векторов):
`score = bm25_norm × 1.0 + entity_match × 0.8 + recency(updated_at, полураспад 30 дн) × 0.3 + log(1+use_count) × 0.2 + pinned ? ∞`.
Если кандидатов больше 30, Haiku быстро переранжирует их по вопросу. Это опционально: стоит около 1 тыс. токенов за ход, то есть почти ничего.

Переключатель «Без памяти» в «+» убирает оба блока памяти и инструменты памяти на этот разговор и отправляет mid-conversation system message «не опирайся на память».

### 5.6 «На какие воспоминания опирался ответ»

- Каждый подставленный факт помечен коротким id: `[m12] Только тёмные темы…`. Системный промпт требует: «если опирался на факты, вызови `cite_memories(["m12","m3"])` в конце ответа» (инструмент, а не текст, чтобы разбирать надёжно). Для CLI-движка этот инструмент живёт в `lumen-mcp`.
- В `message_memories` пишем две роли: `injected` (что дали) и `cited` (что модель назвала). Плашка «Опирался на N воспоминаний» показывает `cited`. Если модель ничего не назвала, показываем «Было под рукой: N» (это `injected`).
- Честно: самоотчёт модели не гарантирован. Цитирование — лучшая практическая оценка, а не доказательство. Можно добавить дешёвую проверку Haiku, «поддерживает ли ответ факт X», но в MVP это лишнее.

### 5.7 USER.md и MEMORY.md

- Источник правды — база. Файлы в `~/Library/Application Support/Lumen/memory/` — это **отрисовка**: USER.md (вид `you` и `pref`), MEMORY.md (проекты, решения, люди). Каждая строка вида `- текст <!-- m_01J… -->`.
- «Открыть в редакторе»: Lumen следит за файлом (FSEvents/`DispatchSource`). При сохранении diff по id: изменённая строка — update, удалённая — forget, строка без id — add (`origin=manual`).
- Hermes-совместимость (импорт `~/.hermes/memories/*.md`, разделитель `§`) — простой бонус, если когда-нибудь пригодится.

### 5.8 Граф

Граф собирается запросом: `entities` + `memory_entities` (+ `people`). Сущности приходят из того же вызова извлечения. Сущности-проекты заранее заводятся из списка папок prog (тот же обход, что делает `tools/status.sh`). «Упоминался в N чатах» у людей считается FTS-поиском имени и алиасов по `messages` и кэшируется.

### 5.9 Векторы: нужны ли

- **MVP: нет.** На масштабе в сотни и тысячи фактов FTS5 вместе с сущностями и дешёвым переранжированием моделью покрывают задачу. Hermes тоже обходится FTS5 для поиска по разговорам.
- **v2: опция**, если будут промахи на перефразах («как мне удобно отвечать» → факт про «коротко, по-русски»):
  - собственного embedding-API у Anthropic нет, документация рекомендует Voyage AI (`voyage-4`, `voyage-4-lite`, мультиязычные, с отдельным ключом и платой);
  - локально: открытая `voyage-4-nano` (Apache 2.0) или мультиязычная модель через CoreML/ONNX. У Ромы уже есть Python + onnx в FlowLocal. Качество для русского **не проверено**;
  - Apple `NLContextualEmbedding` (macOS 14+) — по памяти поддерживает русский, **проверить** качество;
  - хранение: BLOB в SQLite, перебор с Accelerate (на 10 тыс. векторов размерности 512 — миллисекунды), `sqlite-vec` не обязателен.

---

## 6. Окно контекста и сжатие, бесконечный чат бота

### 6.1 Показ «47 тыс. из 200 тыс.»

- API-движок: после каждого ответа `usage.input_tokens + cache_read + cache_creation` даёт полный размер. По частям (характер, память, разговор и файлы): системные блоки и блоки памяти считаем `count_tokens` один раз при изменении и кэшируем, разговор = остаток.
- CLI-движок: `SDKAssistantMessage.context_usage`; в `/context` есть разбивка (по `-p` её можно запросить промптом). Точную форму `context_usage` **проверить в спайке**.
- Размер окна берём из `/v1/models` (`max_input_tokens`): у текущих моделей 1M. В макете «из 200 тыс.» — устаревшая цифра, лучше показывать порог сжатия, а не теоретический максимум.

### 6.2 Когда и как сжимать

- **CLI** сжимает сам (`--autocompact auto` или размер окна 100k–1M). Lumen ставит окно примерно 200k: это быстрее и дешевле, чем держать 1M. На событие `compact_boundary` создаём запись в `compactions`.
- **API**, свой вариант (рекомендую для контроля и UI):
  1. порог — 60 % выбранного окна (например, 120k из 200k);
  2. **сначала извлечение памяти** по сжимаемому куску (§5.3), чтобы факты не пропали;
  3. Sonnet или Haiku пересказывает старую часть по шаблону: договорённости, решения, открытые вопросы, файлы и коммиты, что ждёт Рому;
  4. новый контекст: system + `[Пересказ: 1–12 окт, 380 сообщений]` + последние ~20 сообщений;
  5. история в базе сохраняется целиком, поиск по прошлым разговорам продолжает работать.
- Серверный вариант: beta `compact-2026-01-12`, `context_management.edits: [{type: "compact_20260112"}]`, порог по умолчанию 150k. Ограничение: надо возвращать `response.content` целиком, со служебными блоками. В свою базу пришлось бы класть непрозрачные блоки, поэтому для чатов Lumen свой вариант проще.
- Очистка старых результатов инструментов: beta `context-management-2025-06-27`, `clear_tool_uses_20250919`. Полезно для длинных агентных API-сессий, но они у нас в CLI.

### 6.3 «Бесконечный» чат бота

Цепочка выглядит так: CLI-сессия бота → автосжатие → `compactions` в базе → «чему научился» уходит в `bot_memories` → при очень длинной жизни (например, 5+ сжатий) Lumen начинает **новую** CLI-сессию с затравкой из последнего пересказа и списка «чему научился». Для пользователя чат один и тот же: это одна лента `conversations(kind='bot')`, а не одна CLI-сессия. Так мы не зависим от того, как долго CLI хранит транскрипты (`cleanupPeriodDays`).

---

## 7. MCP: клиент, stdio-серверы, OAuth коннекторов

### 7.1 Библиотека

Официальный Swift SDK: `github.com/modelcontextprotocol/swift-sdk`, последний релиз **0.12.1** (7 мая 2026). Swift 6.0+, macOS 13+, спецификация MCP **2025-11-25**. Транспорты: `StdioTransport`, `HTTPClientTransport` (Streamable HTTP; отдельного SSE-транспорта нет). Клиентские возможности: tools, resources, prompts, sampling, elicitation. OAuth 2.1 на HTTP-клиенте (PKCE, client credentials, свои провайдеры токенов).

```swift
.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1")
```

Пример в README показывает `StdioTransport()` без аргументов, а это вариант для сервера на своих stdin/stdout. Для клиента, который запускает дочерний процесс, нужен `Process` с `Pipe` и инициализация транспорта на дескрипторах этих труб. Точную сигнатуру **проверить по исходникам** 0.12.1.

### 7.2 Где какой MCP

| Движок | Как подключаются серверы из «Инструментов» |
|---|---|
| CLI (агент, боты, чат по подписке) | Lumen генерирует `mcp.json` и передаёт `--mcp-config` (+ `--strict-mcp-config`, чтобы не тянуть чужие). Серверы запускает и авторизует сам CLI. Ошибки видны в `system/init.mcp_servers` / `mcp_server_errors`. |
| API (чат по ключу) | Свой клиент на swift-sdk: Lumen сам запускает stdio-серверы и превращает их tools в `tools[]` запроса (имя `mcp__<server>__<tool>`). Удалённые серверы можно отдать прямо API через MCP connector (`mcp_servers` + `tools: [{type: "mcp_toolset", mcp_server_name}]`, beta `mcp-client-2025-11-20`), тогда API вызывает их сам. |

### 7.3 stdio-серверы на Маке

- Без App Sandbox это обычный `Process`. `npx` и `uvx` требуют правильного `PATH`, поэтому окружение берём из логин-шелла. Переменные окружения из формы «по одной на строку» хранятся в Связке ключей, а не в базе, и подставляются при запуске.
- Жизненный цикл: ленивый старт при первом вызове, общий процесс на все разговоры, рестарт при падении (не больше 3 раз за 5 минут), гашение при простое.
- Удалённые серверы: Streamable HTTP + OAuth.

### 7.4 OAuth для коннекторов (GitHub, Gmail, Календарь, Notion, Figma, Linear, Vercel)

По спецификации MCP 2025-11-25 для HTTP-серверов клиент **обязан**:

- находить сервер авторизации через Protected Resource Metadata (RFC 9728: `WWW-Authenticate: … resource_metadata=` или well-known);
- поддерживать оба вида метаданных сервера авторизации (RFC 8414 и OIDC Discovery);
- использовать PKCE `S256` и отказываться, если сервер не публикует `code_challenge_methods_supported`;
- передавать `resource` (RFC 8707) и в запросе авторизации, и в запросе токена;
- регистрироваться через Client ID Metadata Document (HTTPS-URL с JSON о клиенте; приоритет), иначе Dynamic Client Registration, иначе заранее выданный client_id;
- redirect только на `localhost` или HTTPS;
- для stdio-серверов эту схему **не** применять: секреты передаются через окружение.

На Маке: `ASWebAuthenticationSession` (или системный браузер + loopback `http://127.0.0.1:<порт>/callback`), токены и refresh-токены — в Связке ключей.

**Короткий путь для подписки (проверить в спайке).** В Agent SDK есть тип `McpClaudeAIProxyServerConfig`, то есть Claude Code, вошедший по claude.ai, может пользоваться коннекторами аккаунта claude.ai (Gmail, Календарь, Notion, Linear, Vercel — такие у Ромы уже подключены). Если в `-p` они доступны, коннекторы в режиме подписки достаются без своего OAuth. Но `--strict-mcp-config` их, видимо, отключит, и для каждого бота придётся решать отдельно. В API-режиме этот путь не работает, там нужен свой OAuth.

**Календарь** проще и приватнее сделать нативно, через EventKit (локальный доступ к календарям Мака, без OAuth). Это сочетается с замыслом Ромы о «своём календаре».

---

## 8. Навыки (SKILL.md)

### 8.1 Формат (agentskills.io/specification)

- Папка `имя-навыка/` с обязательным `SKILL.md` и необязательными `scripts/`, `references/`, `assets/`.
- Фронтматтер: `name` (обязательно; 1–64 символа, `a-z0-9-`, без `--`, без дефиса по краям, **совпадает с именем папки**), `description` (обязательно; до 1024 символов: что делает и когда применять), `license`, `compatibility` (до 500), `metadata` (строки → строки), `allowed-tools` (экспериментально).
- Постепенная загрузка: метаданные (~100 токенов) у всех навыков сразу, тело (<5000 токенов, <500 строк) по требованию, ресурсы по требованию.
- Проверка: `skills-ref validate ./skill`. В Lumen делаем ту же проверку на Swift.

### 8.2 Где взять навыки

У agentskills.io **нет каталога или API** (по `llms.txt` у сайта только спецификация, гайды и витрина клиентов). Значит, «Каталог навыков» в Lumen — это:

1. собственный JSON-индекс (лежит в репозитории Lumen, обновляется Sparkle-подобно): список источников вида `github:owner/repo/path@ref` с описанием. Например, официальный репозиторий навыков Anthropic `github.com/anthropics/skills` (сам я его не открывал, **проверить**, что именно там лежит);
2. установка по ссылке на GitHub или на прямой `SKILL.md`, как в Hermes (`hermes skills install https://…/SKILL.md`);
3. «Создать навык» из формы (название, когда применять, шаги) → Lumen пишет `SKILL.md`. Навыки «сам научился» модель предлагает после сложной задачи, а Рома подтверждает (как `skill_manage` + `write_approval` в Hermes).

### 8.3 Установка, кэш, версии, «уже скачано — не качать»

```
~/Library/Application Support/Lumen/skills/
  status-prog/SKILL.md
  pdf/SKILL.md, scripts/…
  .hub/lock.json      # что, откуда, какой хэш
  .hub/quarantine/    # не прошедшие проверку
```

```json
{"skills": {
  "pdf": {"source": "github:anthropics/skills/pdf", "ref": "main", "commit": "a1b2c3…",
          "sha256": "…хэш всего содержимого папки (отсортированные пути + байты)…",
          "version": "1.0", "installed_at": 1760550000, "origin": "catalog", "locally_modified": false,
          "scan": {"verdict": "ok", "findings": []}}
}}
```

- **«Уже скачано»**: перед загрузкой сравниваем `source+commit`, а после загрузки `sha256`. Совпало — пропускаем. У бота навыки — ссылки на общий кэш (симлинки в `bots/<id>/skills/.claude/skills/`), а не копии.
- Обновления: «Проверить обновления» сравнивает свежий commit или хэш upstream. Локально изменённые навыки не перезаписываются без явного «обновить всё равно» (так делает Hermes: «Locally edited skills are skipped by update unless --force»).
- GitHub API без токена — 60 запросов в час. Если подключён коннектор GitHub, используем его токен (5000 в час).
- Проверка при установке: поиск подозрительного в `scripts/` и теле (сеть + чтение `~/.ssh`, `curl | sh`, `rm -rf`, base64-блобы, невидимый Unicode). Перед первым включением показываем diff. Навык со `scripts/` разрешён только ботам с `runCommands`.

### 8.4 Как навыки попадают к модели

- CLI-движок: папка с навыками бота передаётся через `--add-dir` (bare-режим тоже «loads skills from its `.claude/skills/` folder»). Без bare можно `--plugin-dir`. **Проверить**, что CLI видит навыки из `--add-dir` при `--setting-sources ""`.
- API-движок: в `system` кладём список «имя — описание», инструмент `load_skill(name, path?)` отдаёт тело или файл. Это та же постепенная загрузка, что Level 0/1/2 в Hermes. Скрипты навыка выполняются только у ботов с `runCommands`, то есть через CLI.
- Счётчик «использован N раз»: в CLI по `tool_use` с именем `Skill`, в API по вызовам `load_skill`.

---

## 9. Облачные сессии Claude Code

### 9.1 Что документировано

- Создать: `claude --cloud "задача"` в папке репозитория. VM клонирует GitHub-remote текущей ветки (локальные коммиты надо сначала запушить) или загружает бандл, если remote нет (до 100 МБ, без неотслеживаемых файлов, `.env` и ключи не уходят). В `-p` вместе с описанием задачи **отклоняется**. Значит, создание идёт через интерактивный режим, где CLI показывает чек-лист подготовки. Выдаёт ли он ID сессии без TTY, **проверить в спайке**.
- Дописать: `claude -p "сообщение" --cloud <session-id> --output-format json` → `{ok, session_id, url}`. Стрима нет (`stream-json` не поддерживается).
- Забрать к себе: `claude --teleport <id>` (чистое дерево, тот же репозиторий, ветка запушена).
- Routines (research preview): `POST https://api.anthropic.com/v1/claude_code/routines/<trig_…>/fire` с `Authorization: Bearer <токен из веб-UI>` и `anthropic-beta: experimental-cc-routine-2026-04-01` → `{claude_code_session_id, claude_code_session_url}`. Лимиты: 30 запусков в час на routine и 100 в час на аккаунт. Создаются и редактируются в вебе.
- Облачные сессии и routines тратят **те же лимиты подписки**. Отдельной платы за VM нет.

### 9.2 Чего нет

Публичного способа **читать ход** облачной сессии (события, шаги, diff) из своего приложения я не нашёл. Есть только веб `claude.ai/code`, мобильное приложение и `--teleport`.

### 9.3 Предложение для Lumen

- **v1 «Облако Claude» = запуск + ссылка + дописки.** Lumen создаёт сессию (`--cloud` или routine `/fire`), сохраняет `cloud_session_id` и URL, а в треде показывает карточку «Работает в облаке → Открыть» и поле «Дописать», которое вызывает `-p --cloud <id>`. Статус «running / done / waiting» честно показать не получится: показываем «отправлено», «последнее сообщение», «открыть». Кнопка «Забрать на Мак» делает `--teleport` в папке проекта. Облачко на облачных сессиях, как в макете.
- **v2 (опция, по API-ключу): Managed Agents.** Anthropic размещает агентный цикл и песочницу и отдаёт поток событий по SSE, поэтому Lumen может показывать шаги вживую. Это beta, `managed-agents-2026-04-01`, платно по токенам и не по подписке. Подходит для «ночного обхода сайтов».
- Требования: GitHub подключён к claude.ai (GitHub App или `/web-setup`); репозитории prog на GitHub. У Lumen его пока нет, у остальных проектов есть.

---

## 10. Архитектура Swift-приложения

### 10.1 Модули (один репозиторий, Swift Package + Xcode-проект или `build.sh`, как в других проектах prog)

```
Lumen/
  App/                       — @main, окна, меню, горячие клавиши (⌘K, ⌘N, ⌘1–4, ⌘., правый ⌥)
  Packages/
    LumenCore/               — доменные типы (Conversation, Message, Memory, Person, BotSpec, Persona…), ошибки, ID
    LumenStorage/            — GRDB: схема, миграции, FTS5, бэкапы, наблюдение (ValueObservation → сторы)
    LumenProviders/          — LLMProvider, AnthropicAPIEngine (HTTP/SSE), ClaudeCodeEngine (Process+stream-json),
                               цены, лимиты, «Авто»; позже CodexEngine/OpenAIEngine
    LumenOrchestrator/       — сборка промпта, роутер @бот, политика прав, группы ботов, расписания
    LumenMemory/             — извлечение, дедуп, ранжирование, отрисовка USER.md/MEMORY.md, граф
    LumenTools/              — MCP-клиент (swift-sdk), навыки (установщик, lock), коннекторы/OAuth, внешние API
    LumenVoice/              — AVAudioEngine, VAD, мост к FlowLocal, TTS, камера
    LumenUI/                 — SwiftUI-экраны (только SwiftUI, без WebView)
  Helpers/
    lumen-mcp/               — исполняемый stdio MCP-сервер (memory.*, people.*, delegate, cite_memories, load_skill)
    LumenAgent/              — LaunchAgent: расписания, фоновые прогоны, позже шлюз Telegram
```

Слои: **UI (SwiftUI) → сторы `@Observable` (@MainActor) → сервисы (actors) → провайдеры и хранилище**. Сторы ничего не знают о процессах. Сервисы публикуют `AsyncStream`, сторы на него подписываются.

- Каждый активный разговор — `actor ConversationSession` со своим `TurnEvent`-потоком.
- Дельты текста склеиваются и отдаются в UI не чаще раза в 30–50 мс. Без этого SwiftUI будет перерисовываться на каждый токен.
- Без глобальных синглтонов, внедрение через `Environment`.

### 10.2 Фоновые процессы

- **LumenAgent** — LaunchAgent из бандла: `SMAppService.agent(plistName:)` (macOS 13+). Plist лежит в `Contents/Library/LaunchAgents/`, связь с приложением идёт через XPC (Mach service). Задачи агента:
  - расписания ботов («Утро» в 9:00). В launchd `StartCalendarInterval` пропущенный из-за сна запуск выполняется после пробуждения. Свой таймер в агенте тоже проверяет «пропущенное с прошлого раза»;
  - фоновые прогоны ботов, которые должны пережить закрытие окна (как `nohup` в Пульте, но с контролем);
  - позже — шлюз Telegram.
- Сами процессы `claude` агент запускает в своей группе процессов, а их PID пишет в базу. После перезапуска Lumen находит «осиротевшие» прогоны и либо ждёт их, либо помечает «прервано».
- Если Мак спит, локальный бот не сработает. Для «Ночного обхода сайтов» подходит облако (routine), потому что ему не нужен локальный диск.

### 10.3 Песочница, подпись, обновления

- **App Sandbox: нет.** Дочерние процессы наследуют песочницу, и `claude`, `git`, `xcodebuild` и `npx` не смогут работать с произвольными папками. Вместо неё ставим **Hardened Runtime** (с нужными исключениями: например, для запуска Python FlowLocal может понадобиться `com.apple.security.cs.disable-library-validation`, **проверить**).
- **TCC**: доступ к `~/Documents`, `~/Desktop` и `~/Downloads` macOS всё равно спросит. Дочерние процессы получают права «ответственного» процесса, то есть Lumen. Значит, нужен шаг онбординга «дать доступ к папке prog» и `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`, (позже) Screen Recording.
- Подпись Developer ID + нотаризация (`notarytool`) + степлинг. Без App Store.
- Обновления: **Sparkle 2.10.0** (сентябрь 2026), подпись EdDSA, appcast на GitHub Pages, как у Заметочек и FlowLocal.

### 10.4 Хранение и секреты

```
~/Library/Application Support/Lumen/
  lumen.sqlite (+ -wal, -shm)    — всё: разговоры, память, люди, боты, доска задач, журнал трат, аудит
  memory/USER.md, MEMORY.md      — отрисовка памяти
  skills/                        — навыки + .hub/lock.json
  bots/<id>/                     — system.md, mcp.json, settings.json, skills/ (симлинки), scratch/
  run/<conv>/                    — временные файлы запуска CLI
  files/<sha256>                 — вложения (дедуп по хэшу)
  backups/lumen-YYYY-MM-DD.sqlite
  logs/
```

- **GRDB 7.11.1** (июнь 2026; `swift-tools-version:6.1`): `DatabasePool` (WAL), миграции `DatabaseMigrator`, `ValueObservation` для живых списков, собственные FTS5-токенайзеры.
- **Секреты**: API-ключ Anthropic, ключи внешних API, OAuth-токены коннекторов, env MCP-серверов → Связка ключей (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). В базе — только ссылка. В лог и в промпт секреты не попадают никогда. Отдельный `ANTHROPIC_API_KEY` кладётся в окружение дочернего `claude` только на время запуска.
- **Шифрование**: на диске данные защищает FileVault. Дополнительно, если нужно (v2): SQLCipher (GRDB умеет собираться с ним) с ключом в Связке ключей. Цена — своя сборка SQLite и потеря системного.
- **Бэкапы**: раз в сутки `try db.backup(to:)` (онлайн-бэкап SQLite), храним 7 штук. Плюс Time Machine. «Выгрузить память» → zip из `memories.json`, `people.json`, USER.md и MEMORY.md.

---

## 11. Стоимость и производительность

- **Стрим везде.** Первая дельта в UI сразу, «Стоп» → `interrupt` в stdin или отмена `Task`.
- **Кэш промпта.** Стабильный префикс экономит 90 % на входе со второго хода. TTL 1 ч для системного блока долгих разговоров.
- **Дешёвые модели для фона.** Извлечение памяти, заголовки, классификация «не по роли» и переранжирование — Haiku 5.5 ($0.10/$0.50). Это копейки за разговор.
- **Batch API (−50 %)** для ночной уборки памяти и пересказов (только по ключу).
- **Параллельность**: не больше 3 одновременных процессов ботов (настройка). У каждого `--max-budget-usd`. Подписка общая на всё, включая облачные сессии («Running multiple tasks in parallel consumes more rate limits proportionately»).
- **Цена CLI-движка для чата.** Системный промпт и описания инструментов Claude Code занимают много токенов. Через `--system-prompt` и `--tools ""` чат становится «лёгким». Реальный расход на ход **замерить в спайке**: подписочный лимит тратится и на это.
- **Учёт денег.** Журнал `spend(ts, conv_id, provider, model, input, output, cache_read, cache_write, usd, estimated)`. Для API считаем по таблице цен (в приложении, обновляется вместе с ним), для CLI берём `modelUsage.costUSD` с пометкой «оценка». «В этом месяце $4,18» = сумма по API. Подписка показывается отдельно, процентами.
- **Холодный старт CLI** — порядка секунды и больше (проверить замером). Поэтому держим «тёплый» процесс на активный разговор и стартуем его заранее, при открытии треда.

---

## 12. Риски и что сделать первым

| Риск | Насколько серьёзно | Что делаем |
|---|---|---|
| Правила использования подписки (личное ок, раздача — нет; 24/7-боты — «не обычное использование») | Высоко для будущего, низко для личного | Только официальный бинарник и вход Ромы; фоновые и групповые прогоны по API по умолчанию; не публиковать Lumen со входом по подписке |
| Протокол stream-json меняется | Средне | Терпимый декодер, `capabilities`, минимальная версия, фикстуры-тесты, экран «версия claude не подходит» |
| Утечка прав бота (Bash пишет файлы, MCP вне песочницы) | Средне | `--tools` + `--restricted` + `dontAsk` + allowlist команд + песочница с `denyWrite` + проверка в `lumen-mcp`; тест «бот-тестировщик не может изменить файл» в CI |
| Инъекции через веб, файлы, MCP и навыки → отравление памяти, вредные команды | Средне | Факты из инструментов — только с подтверждением; навыки со сканом и diff; боты с вебом без записи; secrets не в промпте |
| Русский поиск без морфологии | Средне | Префиксы → стеммер-токенайзер (§5.2) |
| Облако не наблюдаемо | Низко (честный UI) | Ссылка + дописки; Managed Agents позже |
| Подписочные лимиты не видны в `-p` | Средне | `rate_limit_event` + `/usage`; проверить в спайке |
| Переписывание истории ломает thinking (400) | Средне | Только дописываем; «изменить» = форк |
| TCC и PATH в GUI | Низко | Онбординг доступа, окружение из логин-шелла |

**Первым делом — спайк на неделю** (до любого UI), маленькие консольные проверки на Swift:

1. Долгоживущий `claude -p` со `stream-json` на входе и выходе: 3 хода подряд, SIGINT посреди ответа, `--resume` после убийства процесса.
2. По подписке: `--system-prompt` + `--tools ""` + `--setting-sources ""` (или `--safe-mode`). Ответ приходит, хуки острова не срабатывают, сколько токенов уходит на ход.
3. Появляются ли `rate_limit_event` и с какими полями; разбор вывода `/usage` в `-p`.
4. `lumen-mcp` (swift-sdk 0.12.1) через `--mcp-config`: вызов `remember`, отказ по токену бота.
5. Права бота: `--restricted --tools "Read,Grep,Bash" --permission-mode dontAsk` + песочница с `denyWrite`. Убедиться, что `echo x > file` и Edit не проходят.
6. `claude --cloud` без TTY: можно ли получить ID; `-p --cloud <id>`.
7. Доступны ли claude.ai-коннекторы в `-p`, и как они ведут себя со `--strict-mcp-config`.
8. Смена входа: `ANTHROPIC_API_KEY` + `--resume` той же сессии.

---

## 13. Голос и камера (как Advanced Voice с видео)

### 13.1 Что есть у Anthropic

Публичного API для распознавания или синтеза речи у Anthropic **нет**: в документации ничего не нашёл, а голосовой режим есть только в приложениях Claude. По сообщениям прессы и списку субпроцессоров, синтез речи в мобильных приложениях делает ElevenLabs (источник — the-decoder; первоисточник, trust center, я не открывал). Аналога OpenAI Realtime (речь↔речь в одном соединении) у Claude нет. Поэтому голос Lumen — **каскад**: микрофон → VAD → распознавание (локально) → Claude (стрим текста) → синтез по предложениям → динамик.

### 13.2 Звук

- **Захват**: `AVAudioEngine`. На `inputNode` включаем `setVoiceProcessingEnabled(true)`, это системное эхоподавление и шумоподавление Apple (VPIO). Без него Lumen будет «слышать сам себя» из динамиков, и перебивание сломается. Название и поведение API по памяти, **сверить** с документацией Apple (macOS 10.15+). Формат для FlowLocal: 16 кГц, моно, float32 (`AVAudioConverter`).
- **Распознавание — FlowLocal** (у Ромы уже работает). `Мак-приложения/flow-local/mac/backend/server.py` — процесс с протоколом JSON-строк по stdin/stdout, звук сырыми байтами:
  ```
  -> {"cmd":"begin","id":7,"lang":"auto"}
  -> {"cmd":"audio","id":7,"samples":4000} + байты      каждые ~0,25 с
  -> {"cmd":"finish","id":7}
  <- {"id":7,"text":"…","lang":"ru","sec":0.31,…}
  ```
  Распознавание идёт **на ходу** (речь режется по паузам), после «finish» остаётся хвост примерно в 0,1 с. Lumen запускает `server.py` Python-ом FlowLocal (`~/Library/Application Support/FlowLocal/Python/bin/python3`). Это зависимость от установленного FlowLocal: если его нет, предлагаем установить или откатываемся на Apple Speech (качество русского на macOS 26 **не проверено**). Промежуточные слова для живых субтитров протокол сейчас не отдаёт, только итог. Если субтитры «по словам» нужны, в FlowLocal надо добавить событие `partial`, но это правка чужого проекта и только по просьбе Ромы.
- **VAD (конец фразы)**: двухступенчато. Энергия сигнала (дёшево, на Swift) плюс Silero VAD (ONNX, около 2 МБ) в том же Python-процессе или через onnxruntime. Конец реплики — 600–800 мс тишины. Чтобы Lumen не перебивал на вдохе, порог выше, если фраза оборвалась на союзе.
- **Режим «держать правый ⌥»** (push-to-talk) не требует VAD вообще. Это самый надёжный режим, и в макете он есть.

### 13.3 Перебивание (barge-in)

1. Пока Lumen говорит, микрофон слушает уже очищенный (AEC) сигнал.
2. Если речь длится дольше 250–300 мс и это не эхо (уровень выше порога после AEC), сразу останавливаем синтез (`AVSpeechSynthesizer.stopSpeaking(at: .immediate)` или стоп плеера), отменяем стрим LLM (SIGINT или `Task.cancel`) и чистим очередь фраз.
3. В историю пишем то, что Lumen **успел сказать**, с пометкой «перебит». Без этого модель будет думать, что сказала всё.
4. Новая реплика Ромы идёт следующим ходом.

### 13.4 Синтез речи

| Вариант | Плюсы | Минусы |
|---|---|---|
| `AVSpeechSynthesizer` (системные русские голоса; Personal Voice) | бесплатно, офлайн, мгновенно, по предложениям | звучит «системно» |
| Локальная нейро-модель (Piper / Silero с русскими голосами) в Python-окружении FlowLocal | офлайн, лучше звучит, быстро на M-чипах | лицензии голосов **проверить**; ещё один процесс |
| Облачные (ElevenLabs, OpenAI TTS) | лучшее качество, эмоции | деньги, задержка сети, текст уходит третьей стороне, отдельный ключ |

Три голоса из настроек («Спокойный / Яркий / Низкий») отображаются на конкретный голос и параметры движка: скорость, тон. В MVP — `AVSpeechSynthesizer`, в v1 — локальный нейро-движок как опция.

Поток: дельты текста режутся на предложения (`.`, `?`, `!`, `…`, перенос строки, не короче ~40 знаков), каждое предложение сразу уходит в синтез. Markdown и код вслух не читаем: перед синтезом чистим разметку, а для кода говорим «код в чате».

### 13.5 Камера

- Захват: `AVCaptureSession` → `AVCaptureVideoDataOutput` (кадры в фоне). Для экрана — ScreenCaptureKit.
- **Видеопоток Claude не принимает, только картинки.** Поэтому кадры отправляются **снимками**:
  - по умолчанию **1 кадр в конце каждой реплики** (самый свежий) плюс, если сцена заметно менялась во время реплики, ещё 1–2 кадра. Изменение сцены определяем дешёвой разницей уменьшенных кадров;
  - кнопка «Посмотри» — кадр по требованию;
  - режим «смотри постоянно» не больше 1 кадра в 2–5 с и только при изменении сцены. Это дорого, поэтому показываем счётчик.
- **Размер и цена.** Стоимость кадра — `⌈w/28⌉ × ⌈h/28⌉` визуальных токенов (Claude 4.7+ видит до 2576 px по длинной стороне и 4784 токенов). Рекомендую сжимать до 1024×576, JPEG q≈0.7:
  - 1024×576 → 37 × 21 = **777 токенов**: Opus 5.5 ≈ $0.0031, Sonnet 5.5 ≈ $0.0016, Haiku 5.5 ≈ $0.00008 за кадр;
  - 1920×1080 без сжатия → 2691 токен (×3,5 дороже);
  - 1 кадр в секунду 10 минут = 600 × 777 ≈ 466 тыс. токенов ≈ $1.9 на Opus, $0.9 на Sonnet **плюс** повторная отправка истории.
- **Главный подводный камень**: картинки в истории **переотправляются каждый ход**. Старые кадры надо заменять текстовым описанием («[кадр 21:04: Рома держит плату]»), а живым оставлять 1–2 последних. Иначе цена растёт квадратично.
- Для голоса с камерой берём Sonnet 5.5 на `low`/`medium`: Opus медленнее отвечает.

### 13.6 Задержки (оценка, замерить)

| Этап | Время |
|---|---|
| конец фразы (VAD) | 0,6–0,8 с (push-to-talk: 0) |
| хвост распознавания FlowLocal | ~0,1 с |
| первый токен Claude по API (тёплое HTTP/2-соединение, effort low) | ~0,5–1,5 с (не замерял) |
| первая фраза в синтез (AVSpeech) | ~0,1–0,3 с |
| **итого до первого звука** | **~1,5–3 с** |

Через CLI-движок по подписке к этому добавляется накладная процесса. Держим тёплый процесс со `stream-json`-входом. Если замер покажет больше 3 с, голос по умолчанию идёт через API.

### 13.7 Приватность

- Звук не покидает Мак: распознавание идёт локально. Наружу уходит только текст реплики и, если камера включена, кадры, и то только в Anthropic.
- Записи звука и кадров по умолчанию не храним. В интерфейсе всегда виден индикатор «камера включена», плюс системный индикатор macOS.
- Голосовой режим с камерой выключен по умолчанию и включается кнопкой на время разговора.

---

## 14. Группы ботов

Пример: группа «тестировщик, дизайнер, кодер» получает задачу «нужен полноценный сайт».

### 14.1 Как это сделано у других (кратко)

| Система | Как координируют | Что берём |
|---|---|---|
| **Claude Code agent teams** (эксперимент) | Лид и тиммейты (отдельные сессии), общая доска задач со статусами pending / in progress / completed и **зависимостями**, захват задачи с **файловой блокировкой**, почтовые ящики (JSON-файлы), хуки `TeammateIdle`, `TaskCreated`, `TaskCompleted` (код 2 = «не принимаю, вот замечание»). Советуют 3–5 тиммейтов, по 5–6 задач на каждого, и не править один файл вдвоём. **Не работает в `-p` и Agent SDK**, нет вложенных команд, нет возобновления | Доску с зависимостями, «приёмку» задачи по критериям, правило «один файл — один владелец» |
| **Hermes `delegate_task`** | Изолированные дети со свежим контекстом (только `goal` + `context`), до 10 параллельно, глубина 1 по умолчанию. Детям запрещены `delegate_task`, `clarify`, `memory`, `send_message`, `cronjob`. Опционально `worktree_isolation` (свой git worktree). Контроль зависаний: 450 с без прогресса | Изоляцию контекста, запрет детям трогать память и звать человека напрямую, worktree на исполнителя, сторож зависаний |
| **CrewAI, hierarchical process** | Менеджер-LLM раздаёт задачи по ролям и проверяет результат; задачи заранее не назначены | Координатора-LLM для **планирования и приёмки**, а не для каждого шага |
| **AutoGen SelectorGroupChat** | LLM выбирает следующего говорящего, по умолчанию тот же не говорит дважды подряд; условия остановки `TextMentionTermination` и `MaxMessageTermination` | Явные условия остановки и лимит сообщений |
| **LangGraph** | Явный граф состояний, чекпойнты, `interrupt()` для человека с продолжением по `thread_id` (по вторичным источникам) | Детерминированную машину состояний и сохранение после каждого шага |

Вывод: свободный групповой чат, где все говорят со всеми, — источник шума и зацикливания. Нужна **детерминированная оркестрация в коде** плюс LLM-координатор только там, где нужен ум: план, разбор блокеров, приёмка.

### 14.2 Схема Lumen

```
           Рома ◄──────── эскалации, утверждение плана, финальная приёмка
             │
   ┌─────────▼─────────┐   пишет план и доску; отвечает на вопросы; принимает работу
   │ Координатор (LLM) │   (Lumen, Opus 5.5; сам код не пишет)
   └─────────┬─────────┘
             │ события
   ┌─────────▼──────────────────────────────────────────────────────┐
   │ GroupRunner (Swift actor, без LLM)                              │
   │  доска задач (DAG) · планировщик · очередь слова · бюджеты ·    │
   │  сторож зацикливания · git worktree на бота · слияние           │
   └────┬───────────────────┬────────────────────┬──────────────────┘
        │                   │                    │
   @designer            @coder               @tester         ← отдельные процессы claude со своими правами
   worktree:design      worktree:coder       worktree:test (только чтение + сборка/тесты)
```

### 14.3 Этапы

1. **Постановка.** Рома: «нужен полноценный сайт» плюс (если есть) папка или репозиторий. GroupRunner создаёт ветку `group/<slug>` и общий файл `GROUP.md` (цель, ограничения, критерии готовности).
2. **Договорённость, ровно один раунд.**
   - Координатор пишет план и доску задач: у каждой задачи владелец, зависимости, критерии приёмки, **файлы во владении** (`files_glob`) и оценка бюджета.
   - Каждый бот **параллельно и независимо** получает свои задачи и отвечает структурированно: `accept`, `concern(текст)` или `question(текст)`. Боты не видят ответы друг друга, поэтому не спорят по кругу.
   - Координатор правит план один раз. Оставшиеся разногласия выносятся Роме в одном сообщении: «вот план, вот 2 спорных места, выбери».
   - **Рома утверждает план.** Это обязательная точка.
3. **Работа.**
   - Планировщик запускает задачи в статусе `ready` (все зависимости `done`), параллельно до N (по умолчанию 2–3).
   - У каждого бота **свой git worktree** (`git worktree add ../.lumen-wt/<group>/<bot> -b group/<slug>/<bot>`). Боты физически не пишут в одни и те же файлы.
   - Правило владения: правки вне `files_glob` задачи GroupRunner видит по `git diff --name-only` после завершения. Такая задача уходит на приёмку с пометкой, и координатор либо принимает, либо возвращает.
   - Дизайнер, у которого нет `writeFiles`, отдаёт артефакты сообщением `result` (ТЗ, макет). GroupRunner сохраняет их в `docs/design/` от своего имени, это действие кода, а не бота.
4. **Слияние.** GroupRunner сливает ветки ботов в `group/<slug>` **последовательно** в порядке DAG (`git merge --no-ff`). Конфликт становится задачей `resolve-conflict` для владельца файла. Push не делается никогда, только с OK Ромы.
5. **Проверка.** @tester запускается на слитой ветке. Найденные баги становятся задачами для владельцев (не больше 2 кругов «починил → проверил» на баг, потом эскалация).
6. **Сдача.** Координатор пишет итог: что сделано, что проверено, что осталось. Рома принимает работу или возвращает с замечаниями.

### 14.4 Доска задач

```sql
CREATE TABLE groups(id TEXT PRIMARY KEY, title TEXT, goal TEXT, repo_path TEXT, base_branch TEXT,
                    status TEXT /* planning|awaiting_plan_ok|running|blocked|review|done|stopped */,
                    budget_usd REAL, spent_usd REAL, deadline INTEGER, created_at INTEGER);
CREATE TABLE group_tasks(id TEXT PRIMARY KEY, group_id TEXT REFERENCES groups(id), title TEXT, owner_bot TEXT,
                    status TEXT /* pending|ready|running|blocked|review|done|failed|cancelled */,
                    deps TEXT /* JSON [task_id] */, acceptance TEXT, files_glob TEXT,
                    attempts INTEGER DEFAULT 0, max_attempts INTEGER DEFAULT 2,
                    budget_usd REAL, spent_usd REAL, branch TEXT, result_ref TEXT, updated_at INTEGER);
CREATE TABLE group_messages(id TEXT PRIMARY KEY, group_id TEXT, task_id TEXT, from_id TEXT, to_id TEXT /* bot|coordinator|human|all */,
                    kind TEXT /* question|answer|result|blocker|handoff|review_request|decision|status */,
                    body TEXT, refs TEXT /* JSON: файлы, коммиты */, reply_to TEXT, created_at INTEGER);
```

- Статусы меняет **только** GroupRunner (один actor, без гонок; аналог «file locking» из agent teams, только проще). Бот просит «готово» или «блокер» через инструменты `lumen-mcp`: `task_done(result, refs)`, `task_blocked(reason)`, `ask(to, question)`.
- Приёмка: при `task_done` координатор проверяет критерии (по аналогии с хуком `TaskCompleted`, который может вернуть «не принято + замечание»).

### 14.5 Протокол сообщений и «очередь слова»

- Боты **не пишут в общий чат напрямую**. Каждое сообщение — типизированный вызов инструмента. Тип `ask` адресуется конкретному адресату: боту, координатору или человеку.
- Общий тред, который видит Рома, — это **лента событий** (кто что взял, что сдал, что спросил) плюс сообщения координатора. Ход каждого бота виден в его карточке, а не в общем потоке.
- «Очередь слова» в общем треде — мьютекс: говорит один (координатор или бот, которому координатор дал слово). Остальные сообщения ставятся в очередь и показываются по порядку. Так в UI ничего не перемешивается.
- Сообщения человека имеют **приоритет**: GroupRunner останавливает выдачу новых задач, координатор читает реплику Ромы первым.
- Вопрос бота боту доставляется получателю **между его ходами** (в CLI-сессию получателя дописывается сообщение). Если получатель занят, ответ на вопрос становится частью его текущей задачи или первой строкой следующей.

### 14.6 Когда звать человека

1. Утвердить план (всегда).
2. Действие наружу или необратимое: push, деплой, публикация, удаление веток, оплата.
3. Блокер не снят за один раунд вопрос–ответ.
4. Разногласие ботов, которое координатор не закрыл за один раунд.
5. Потрачено 80 % бюджета или времени.
6. У задачи кончились попытки (`attempts == max_attempts`).
7. Решение вне критериев приёмки: вкус, тексты для папы, цены.
8. Финальная приёмка.

Эскалация — одно сообщение с вариантами ответа (кнопками), а не поток вопросов.

### 14.7 Бюджет, время и защита от зацикливания

- Бюджет группы в $ и по времени (например, $15 и 2 часа), бюджет на задачу, `--max-budget-usd` на каждый запуск бота.
- Не больше 2 попыток на задачу. Не больше 4 сообщений между одной парой ботов по одной задаче: после этого вопрос уходит координатору.
- Сторож зацикливания:
  - повтор сообщения (нормализованный текст похож на одно из 5 последних того же отправителя) → эскалация;
  - «пинг-понг» A→B→A с тем же вопросом → эскалация;
  - нет прогресса (нет новых коммитов, файлов или смены статуса) за 10–15 минут → прервать задачу (SIGINT) и спросить координатора. Это аналог сторожа зависаний Hermes (450 с);
  - лимит ходов на задачу.
- «Стоп всей группы» — одна кнопка: SIGINT всем процессам, статус `stopped`, worktree сохраняются.
- Подписка и группы: группа сжигает лимиты в разы быстрее («significantly more tokens»). По умолчанию группы идут через API (открытый вопрос №2).

### 14.8 Как это ложится на Claude Agent SDK и CLI

- Каждый бот группы — **отдельный процесс `claude -p`** со своими правами (§4), своим cwd (свой worktree) и своей сессией. Субагенты внутри одной сессии наследуют режим прав родителя и делят его процесс. Для «отрезано в коде» и раздельных папок это слабее, чем отдельные процессы.
- Внутри своего процесса бот может использовать встроенного субагента (инструмент `Agent`), если ему разрешено. Например, @coder отдаёт поиск по коду субагенту «Explore», чтобы не засорять свой контекст. Это нормально и дёшево.
- Agent teams Claude Code не годятся по трём причинам: «In non-interactive mode with the -p flag, including Agent SDK sessions, Claude doesn't spawn teammates», это эксперимент, и у тиммейтов нет раздельных прав. Но их устройство (доска с зависимостями, почтовые ящики, хуки приёмки) — хороший образец, и Lumen воспроизводит его у себя.

---

## 15. План работ по этапам

Оценки — для одного разработчика вместе с Claude, в рабочих неделях, грубо.

### Этап 0 — спайки (≈1 неделя)

Восемь проверок из §12. **Готово, когда:** на каждую есть «да или нет» с выводом, записанным в `docs/spikes.md`, и решены развилки: `--safe-mode` или `--setting-sources`, источник лимитов, способ запуска облака.

### MVP (≈5–7 недель): «Lumen, который помнит»

Порядок работ:
1. Каркас: Swift Package-модули, GRDB-схема и миграции, `@Observable`-сторы, три вкладки и боковая панель (по макету, без переноса кнопок).
2. `ClaudeCodeEngine`: долгоживущий процесс, декодер событий, «Стоп» через `interrupt`, `--resume`, тёплый старт.
3. `AnthropicAPIEngine`: SSE, thinking summarized, effort, кэш, ретраи, fallbacks, `web_search`.
4. Характер → SOUL (детерминированная сборка, превью — реальный короткий вызов Haiku вместо шаблона).
5. Память v0: `remember`, закреплённое, FTS-поиск (префиксы), подстановка, `cite_memories`, плашки «Запомнил» и «Опирался на».
6. Прошлые разговоры: FTS по сообщениям, открыть найденное место.
7. Агент на этом Маке: папка, шаги из `tool_use`, снимок до и после (как `ClaudeReview` в Пульте), карточка «Изменения» (diff, откатить, закоммитить), push только с OK.
8. Модели и оплата: Подписка / API (ключ в Связке, «Проверить»), учёт денег, лимиты подписки (источник по итогам спайка), месячный предохранитель.
9. Знакомство, данные (папка, экспорт, бэкап).

**Проверить на выходе:** 20 реальных разговоров Ромы. Кэш работает (`cache_read > 0`). «Стоп» прерывает за меньше чем 0,5 с. Поиск находит «падал Shelf» по запросу «падение». Факт «светлую тему не делаем» всплывает в новом чате. В агенте push невозможен без OK. Без сети и без ключа — понятные ошибки.

### v1 (≈7–9 недель): боты, инструменты, голос

1. `lumen-mcp` (memory, people, delegate, task-tools, load_skill) с проверкой прав по токену.
2. Боты: `BotSpec`, политика Capability → флаги, песочница, один постоянный чат, сжатие и «чему научился», @-роутинг и карточка делегирования, «вне роли» (Haiku-классификатор + handoff), «Работают сейчас».
3. Конструктор: генерация `BotSpec` моделью + подтверждение прав человеком + проверка требований.
4. Навыки: установщик, `lock.json`, «уже скачано», скан, каталог-индекс, создание навыка.
5. MCP: `--mcp-config` для CLI, свой клиент для API, stdio-серверы, удалённые с OAuth (начать с GitHub). Коннекторы claude.ai в режиме подписки (если спайк подтвердил). Календарь через EventKit.
6. Автоизвлечение памяти + дедуп + граф + люди + русский стеммер.
7. Режим «Авто».
8. Голос: FlowLocal + AEC + VAD + перебивание + AVSpeechSynthesizer, правый ⌥.
9. LumenAgent + расписания (бот «Утро»).
10. Облако: запуск, ссылка, дописки, teleport.
11. Sparkle, подпись, нотаризация.

**Проверить:** тест «@tester не может изменить файл ни Edit-ом, ни `echo >`»; «@designer без инструмента кода отвечает „не моя роль“ и делает задачу для @coder»; бот не качает навык повторно; «Утро» срабатывает после сна Мака; голос: перебивание за меньше чем 0,5 с, эхо не распознаётся как речь; облако: сессия создана, ссылка открывается, дописка доходит.

### v2 (≈6–10 недель, по приоритетам Ромы)

- Группы ботов (§14): доска, worktree, слияние, координатор, сторож, эскалации.
- Камера и экран в голосовом режиме (§13.5), нейро-TTS.
- Векторный поиск в памяти (локальные эмбеддинги).
- Провайдеры Codex и OpenAI (через ту же `LLMProvider`; для Codex по подписке ChatGPT — те же вопросы правил, что и у Anthropic, **изучить отдельно**).
- Облако через Managed Agents (по ключу) с живым потоком.
- Шлюз Telegram в LumenAgent: long polling Bot API (сервер не нужен), список разрешённых пользователей и код сопряжения, как в Hermes; голосовые — через FlowLocal; **только для самого Ромы** (правила подписки).
- SQLCipher, профили Seatbelt на процесс бота.

---

## 16. Открытые вопросы к Роме

1. **Только для себя или когда-нибудь для других?** От этого зависит, остаётся ли режим «Подписка» вообще (§2.1).
2. **Боты и группы — на подписке или на API по умолчанию?** Подписка «бесплатна», но рискует выйти за «обычное использование» и съедает лимит, нужный для живой работы. Предлагаю: живые чаты и агент — подписка, фоновое, расписание и группы — API с месячным лимитом.
3. **Сколько в месяц готов тратить на API** (предохранитель по умолчанию)?
4. **«Ультракод»** — убрать или оставить как пресет «Fable 5.1 + max + долгий бюджет»? В API такого уровня нет.
5. **Облако**: устроит ли «запустить + ссылка + дописать» без живого хода в Lumen? Готов ли выложить нужные репозитории на GitHub (Lumen пока только локальный)?
6. **Хук острова**: должны ли агентные сессии Lumen показываться на острове (тогда не глушим настройки `~/.claude` для агента) или Lumen живёт отдельно?
7. **FlowLocal как зависимость голоса**: нормально требовать установленный FlowLocal? Можно ли добавить в его `server.py` промежуточные результаты (`partial`) для живых субтитров (это правка другого проекта)?
8. **Синтез речи**: устроит ли системный голос macOS на старте, или сразу нужна нейро-озвучка (локальная или облачная, платная)?
9. **Память из инструментов**: факты, найденные в письмах, файлах и вебе, — сохранять только после твоего «да» (как я предлагаю) или автоматически?
10. **USER.md / MEMORY.md**: файлы как «вид» на базу (предлагаю) или наоборот, файлы — главное (как в Hermes)?
11. **Коннекторы**: какие нужны в первую очередь? Gmail и Календарь через claude.ai (если спайк подтвердит) или свои?
12. **Telegram**: нужен ли вообще и когда (в ПЛАН.md это тоже ждёт решения)?

---

## 17. Источники

Прочитано в этой работе:

- Agent SDK overview (правило про claude.ai login, брендинг): https://code.claude.com/docs/en/agent-sdk/overview
- Legal and compliance (OAuth только для «родных» приложений, запрет на посредничество, «ordinary, individual usage»): https://code.claude.com/docs/en/legal-and-compliance
- Run Claude Code programmatically (`-p`, `--bare` и вход, stream-json, SIGINT/SIGTERM, `--permission-prompts`, `--resume`, `api_retry`, `system/init`): https://code.claude.com/docs/en/headless
- Agent SDK TypeScript reference (`SDKRateLimitEvent`, `SDKResultMessage`, `SDKCompactBoundaryMessage`, `SandboxSettings`, `ThinkingConfig`, `AgentDefinition`, `McpClaudeAIProxyServerConfig`): https://code.claude.com/docs/en/agent-sdk/typescript
- Claude Code in the cloud (`--cloud`, `-p --cloud <id>`, `--teleport`, бандлы, лимиты): https://code.claude.com/docs/en/claude-code-on-the-web
- Routines (`/fire`, beta-заголовок, лимиты): https://code.claude.com/docs/en/routines
- Agent teams (доска с зависимостями, почтовые ящики, хуки, «не работает в -p»): https://code.claude.com/docs/en/agent-teams
- Status line (`rate_limits.five_hour/seven_day`, `context_window`): https://code.claude.com/docs/en/statusline
- Sandboxing (Seatbelt на macOS, что под песочницей и что нет): https://code.claude.com/docs/en/sandboxing
- Локально: `claude --help`, `claude auth --help`, `claude agents --help` (Claude Code 2.1.278)
- Справочник Claude API (встроенный навык claude-api, кэш от 2026-10-06): модели и цены, adaptive thinking и effort, prompt caching, compaction, mid-conversation system messages, fallbacks, web search, MCP connector
- Vision (стоимость `⌈w/28⌉×⌈h/28⌉`, лимиты, высокое разрешение у 4.7+): https://platform.claude.com/docs/en/build-with-claude/vision
- Embeddings (своих нет, Voyage AI, `voyage-4-nano` открытая): https://platform.claude.com/docs/en/build-with-claude/embeddings
- Hermes Agent README: https://github.com/NousResearch/hermes-agent
- Hermes: память (MEMORY.md 2200 / USER.md 1375 знаков, замороженный снимок, FTS5 `state.db`): https://hermes-agent.nousresearch.com/docs/user-guide/features/memory
- Hermes: навыки (`lock.json`, хэши, скан, постепенная загрузка): https://hermes-agent.nousresearch.com/docs/user-guide/features/skills
- Hermes: делегирование (`delegate_task`, запреты детям, worktree, сторож): https://hermes-agent.nousresearch.com/docs/user-guide/features/delegation
- Hermes: шлюз мессенджеров (allowlist, сопряжение, launchd): https://hermes-agent.nousresearch.com/docs/user-guide/messaging
- Agent Skills specification: https://agentskills.io/specification и индекс https://agentskills.io/llms.txt (каталога и API нет)
- MCP Swift SDK: https://github.com/modelcontextprotocol/swift-sdk
- MCP Authorization, спецификация 2025-11-25: https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization
- Версии библиотек — GitHub Releases API на 15.10.2026: GRDB.swift v7.11.1, Sparkle 2.10.0, swift-sdk 0.12.1, SwiftAnthropic 2.2.2
- CrewAI hierarchical process (по выдаче поиска): https://docs.crewai.com/en/learn/hierarchical-process
- AutoGen Selector Group Chat (по выдаче поиска): https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/selector-group-chat.html
- LangGraph interrupts и checkpointer — только вторичные источники, официальную доку не открывал: https://dev.to/jamesbmour/interrupts-and-commands-in-langgraph-building-human-in-the-loop-workflows-4ngl
- Голос Claude и ElevenLabs (пресса, не первоисточник): https://the-decoder.com/anthropics-claude-uses-elevenlabs-technology-for-speech-features-rather-than-an-in-house-model/
- Свои проекты: `Мак-приложения/prog-dashboard/Sources/ClaudeJobs.swift` (запуск `claude -p` из Swift), `Мак-приложения/flow-local/mac/backend/server.py` (протокол распознавания)

**Не проверено и взято по памяти** (сверить перед реализацией): API Apple (`AVAudioInputNode.setVoiceProcessingEnabled`, `SMAppService.agent`, ScreenCaptureKit, `NLContextualEmbedding`, Apple Speech для русского); заголовки лимитов API `anthropic-ratelimit-*`; стоимость и лимиты `count_tokens`; точная форма строки ввода stream-json; поведение `--setting-sources ""`, `--safe-mode` с `--mcp-config`, `claude --cloud` без TTY, коннекторов claude.ai в `-p`; содержимое `github.com/anthropics/skills`; лицензии голосов Piper и Silero; официальные удалённые MCP-серверы GitHub, Notion, Linear, Vercel, Figma и Google.

---

## 18. Решения Ромы (15 октября)

Ответы на вопросы из §16. Они важнее того, что предлагалось выше.

1. **Для кого.** Для Ромы и, возможно, для папы. Проект **с открытым кодом**. Поэтому сразу закладываем провайдеры Codex и OpenAI (ChatGPT) рядом с Claude. ⚠ Из §2.1: другим людям нельзя давать режим входа по подписке Claude «как наш». Каждый, кто ставит Lumen, сам входит в **свой** официальный `claude` или вводит **свой** ключ API. Перед публикацией ещё раз сверить с правилами Anthropic, что режим «через установленный у пользователя Claude Code» для открытого кода допустим. Если нет — в публичной сборке оставить только ключ API.
2. **Подписка или API для ботов и групп.** Решение «чтобы работало»: живые чат и агент идут по подписке, а фоновое, расписания, боты и группы — по API. На API у Ромы есть **$100 в месяц, которые входят в Max 5x** (подтверждено: platform.claude.com/docs/en/about-claude/api-credits-for-subscribers). Они покрывают Claude API, Managed Agents и Agent SDK, но не интерактивный Claude Code, и сгорают в конце месяца. Расход — без жёсткой экономии, главное скорость. Когда кредиты кончились — предупредить, дальше по решению Ромы.
3. **Лимит API.** По умолчанию — $100 кредитов Max в месяц. Предохранитель нужен только чтобы не уйти в платное без спроса.
4. **«Ультракод»** — убрать (убрано из макета).
5. **Облако** — **только через API: Managed Agents**, полностью видно ход работы. Облачные сессии Claude Code по подписке не используем, у них нет наблюдения. Тратит те же $100 кредитов.
6. **Остров** — да, агентные сессии Lumen обязательно показываются на острове.
7. **FlowLocal для голоса** — да, можно доработать. Схема из **двух потоков**: быстрый черновой поток сразу пишет слова, которые Рома говорит прямо сейчас, а второй тут же заменяет черновик на обработанный чистый текст. Это стандартная схема «промежуточные + окончательные результаты» (partial → final); в `server.py` FlowLocal добавить выдачу `partial`.
8. **Озвучка** — **локальная нейро-озвучка**, максимально быстрая и хорошая. Кандидаты проверить на слух на русском в спайке: **Silero TTS** (snakers4/silero-models: русские голоса, очень быстрая на CPU; лицензия некоммерческая — для личного ок, для открытого кода проверить), **Piper** (быстрая, CPU, проверить наличие русских голосов; лицензия GPL-3.0 у новой ветки), **XTTS v2** (многоязычная, есть русский, клонирование голоса, медленнее, лицензия некоммерческая), **Qwen3-TTS** (заявлен русский, свежая — проверить скорость и лицензию). Выбор — по слепому прослушиванию и задержке до первого звука.
9. **Память из писем, файлов и интернета** — Рома не решил. Берём безопасный вариант по умолчанию: такие факты сохраняются только после «да» (защита от подброшенных инструкций), в настройках можно разрешить автоматически.
10. **USER.md / MEMORY.md** — Рома не решил. Берём вариант из §5: главная — база, файлы — это вид на неё.
11. **Коннекторы** — около 20 самых популярных (GitHub, Vercel, Supabase, Gmail, Google Календарь, Google Диск, Notion, Linear, Figma, Slack, Stripe, Sentry, Cloudflare, Netlify, Jira, Asana, Dropbox, Airtable, PostHog, Firebase) + **свои коннекторы**: любой MCP-сервер по адресу, вход через браузер, по ключу или без входа.
12. **Telegram** — пока не нужен, позже.

### Новое: песочница сбоку
Отдельная панель справа, как браузер в Claude Code, но своя. В ней агент и боты показывают результат: сайт на localhost, любой сайт из интернета, видео, 3D-модель, файл. В приложении это WKWebView для браузера и превью (это содержимое, а не интерфейс, правило «только SwiftUI» не нарушается), AVPlayer для видео, RealityKit / QuickLook для USDZ и файлов. Песочница отделена от файлов Мака: отдельный WKWebsiteDataStore, без доступа к ~/Documents.

### Версии
Ступени и правило выкладки — в `docs/versions.md`. Порядок работ из §15 перекладывается на эти ступени: 0.1 Чат → 0.2 Агент → 0.3 Память → … → 1.0.
