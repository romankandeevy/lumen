// Заглушки макета: правдоподобные данные из жизни prog. Никуда не отправляются.

// ── память ──

export type MemoryKind = "you" | "project" | "decision" | "pref" | "people"

export type Memory = {
  id: string
  text: string
  kind: MemoryKind
  source: string // из какого разговора
  when: string
  pinned?: boolean
  about: string[] // с чем связан факт — узлы графа
}

export const memoryKinds: { id: MemoryKind | "all"; name: string }[] = [
  { id: "all", name: "Всё" },
  { id: "you", name: "О тебе" },
  { id: "project", name: "Проекты" },
  { id: "decision", name: "Решения" },
  { id: "pref", name: "Как тебе удобно" },
  { id: "people", name: "Люди" },
]

/// Узлы графа памяти: ты в центре, вокруг проекты и люди
export const entities: { id: string; name: string; kind: "me" | "project" | "person" }[] = [
  { id: "me", name: "Рома", kind: "me" },
  { id: "lumen", name: "Lumen", kind: "project" },
  { id: "shelf", name: "Shelf", kind: "project" },
  { id: "dash", name: "Пульт", kind: "project" },
  { id: "island", name: "Island", kind: "project" },
  { id: "site", name: "kandeev.com", kind: "project" },
  { id: "flow", name: "FlowLocal", kind: "project" },
  { id: "papa", name: "Папа", kind: "person" },
  { id: "lesha", name: "Лёша", kind: "person" },
]

export const initialMemories: Memory[] = [
  { id: "m1", kind: "you", text: "Рома делает Mac-приложения на Swift и сайты; работает в ~/Documents/prog", source: "Знакомство", when: "1 окт", pinned: true, about: ["me"] },
  { id: "m2", kind: "pref", text: "Не двигать существующие кнопки, когда внедряю мокап или фичу, — только по просьбе", source: "Ревью Пульта перед релизом", when: "14 окт", pinned: true, about: ["me", "dash"] },
  { id: "m3", kind: "pref", text: "Отвечать коротко, по-русски, простыми словами; сначала пересказ плана, потом просить OK", source: "Что поделаем сегодня?", when: "12 окт", about: ["me"] },
  { id: "m4", kind: "decision", text: "Интерфейс Mac-приложений — только SwiftUI, без WebView и React", source: "Пульт: с чего начать", when: "9 окт", about: ["dash", "island", "shelf", "lumen"] },
  { id: "m5", kind: "project", text: "Shelf: вкладку «Полка» убрали, файлы идут в Буфер строками-иконками", source: "Почему падает Shelf?", when: "сегодня", about: ["shelf", "island"] },
  { id: "m6", kind: "project", text: "kandeev.com — папин сайт; превью в ветке preview, прод — только по OK", source: "Тексты для блога", when: "13 окт", about: ["site", "papa"] },
  { id: "m7", kind: "decision", text: "HandPilot (управление жестами) пробовали и бросили — не предлагать снова", source: "HandPilot: итоги", when: "23 сен", about: ["me"] },
  { id: "m8", kind: "you", text: "Говорит голосом через FlowLocal — в тексте бывают оговорки, понимать по смыслу", source: "Остров: самолётик вместо слова", when: "11 окт", about: ["me", "flow"] },
  { id: "m9", kind: "project", text: "Lumen: v1 — память, люди, характер и боты-агенты; мессенджеры позже", source: "Lumen: замысел", when: "сегодня", about: ["lumen"] },
  { id: "m12", kind: "decision", text: "Только тёмные темы: «Люмен» и «Монохром»; светлую не делаем", source: "Lumen: замысел", when: "сейчас", about: ["lumen"] },
  { id: "m13", kind: "project", text: "Island: тень должна следовать за островом, иначе анимация проседает", source: "Island: анимация чёлки", when: "8 окт", about: ["island"] },
  { id: "m14", kind: "project", text: "FlowLocal v3.0: нейтральные цвета, яркий зелёный, капсула чёрная", source: "FlowLocal редизайн", when: "7 окт", about: ["flow"] },
  { id: "m10", kind: "people", text: "Папа — хозяин kandeev.com; на сайте без цен и кейсов с цифрами", source: "Тексты для блога", when: "13 окт", about: ["papa", "site"] },
  { id: "m11", kind: "people", text: "С папой — на «вы» в текстах для клиентов, объяснять без терминов", source: "Анкета: Папа", when: "2 окт", about: ["papa"] },
  { id: "m15", kind: "people", text: "Лёша тестирует сборки Shelf и Island на своём MacBook Air", source: "Анкета: Лёша", when: "10 окт", about: ["lesha", "shelf", "island"] },
]

// ── чаты: обычные разговоры отдельно от агентных сессий (как Chat и Code у Claude) ──

export type Chat = {
  id: string
  title: string
  when: string
  unread?: boolean
}

export type AgentSession = {
  id: string
  title: string
  project: string
  when: string
  where: "mac" | "cloud" // облако — через облачные сессии Claude Code
  state: "running" | "done" | "waiting"
}

export const chats: { group: string; items: Chat[] }[] = [
  {
    group: "Сегодня",
    items: [
      { id: "lumen", title: "Lumen: замысел", when: "сейчас" },
      { id: "plan", title: "Что поделаем сегодня?", when: "2 ч" },
    ],
  },
  {
    group: "Раньше",
    items: [
      { id: "blog", title: "Тексты для блога", when: "13 окт", unread: true },
      { id: "idea", title: "Идеи для Заметочек 1.2", when: "12 окт" },
    ],
  },
]

export const sessions: AgentSession[] = [
  { id: "shelf", title: "Почему падает Shelf?", project: "shelf", when: "12 мин", where: "mac", state: "waiting" },
  { id: "island", title: "Анимация чёлки проседает", project: "island", when: "сейчас", where: "cloud", state: "running" },
  { id: "dash", title: "Ревью Пульта перед релизом", project: "prog-dashboard", when: "вчера", where: "mac", state: "done" },
  { id: "night", title: "Ночной обход сайтов", project: "kandeev.com", when: "03:00", where: "cloud", state: "done" },
]

export const projects = ["lumen", "shelf", "island", "prog-dashboard", "flow-local", "kandeev.com", "notes"]

export const pastConversations = [
  {
    id: "shelf",
    title: "Почему падает Shelf?",
    when: "сегодня, 21:04",
    summary: "Падение в ShelfStorage.remove(at:) при двойном щелчке; добавили проверку индекса и отключение кнопки.",
    hit: "…индекс берётся из старого списка — после первого удаления он уже за краем…",
  },
  {
    id: "dash",
    title: "Ревью Пульта перед релизом",
    when: "14 окт",
    summary: "Нашли 3 замечания; договорились не переносить кнопки без просьбы.",
    hit: "…кнопку «Обновить» оставь на месте, я к ней привык…",
  },
  {
    id: "plan",
    title: "Что поделаем сегодня?",
    when: "12 окт",
    summary: "Выбрали Shelf и сайт; Рома попросил сначала короткий пересказ плана.",
    hit: "…сначала скажи коротко, что будешь делать, потом спроси…",
  },
]

// ── люди: не собеседники, а анкеты — что Lumen знает о близких и коллегах ──

export type Person = {
  id: string
  name: string
  relation: string
  work: string
  dates: string
  howToTalk: string
  interests: string
  mentions: number
}

export const initialPeople: Person[] = [
  {
    id: "papa",
    name: "Папа",
    relation: "Отец",
    work: "Ремонт квартир, хозяин сайта kandeev.com",
    dates: "День рождения — 3 марта",
    howToTalk: "На «ты» со мной, но тексты для его клиентов — на «вы», без терминов",
    interests: "Ремонт, рыбалка, старые «Жигули»",
    mentions: 6,
  },
  {
    id: "lesha",
    name: "Лёша",
    relation: "Друг",
    work: "Тестирует мои сборки на MacBook Air",
    dates: "",
    howToTalk: "Коротко, можно с шутками",
    interests: "Игры, клавиатуры",
    mentions: 3,
  },
]

// ── модели ──

export const models = [
  { id: "fable", name: "Fable 5.1", note: "самый сильный, для сложного" },
  { id: "opus", name: "Opus 5.5", note: "умный, для кода и разбора" },
  { id: "sonnet", name: "Sonnet 5.5", note: "быстрый, на каждый день" },
  { id: "haiku", name: "Haiku 5.5", note: "мгновенный и дешёвый" },
]

export const efforts = [
  { id: "low", name: "Низкий", note: "быстрые ответы на простое" },
  { id: "medium", name: "Средний", note: "обычные вопросы и правки" },
  { id: "high", name: "Высокий", note: "код и разбор — по умолчанию" },
  { id: "xhigh", name: "Сверхвысокий", note: "сложные баги, большие правки" },
  { id: "max", name: "Максимальный", note: "самое трудное, думает долго" },
  { id: "ultra", name: "Ультракод", note: "глубокая работа над кодом, дольше всего" },
]

// ── боты: агенты-субагенты под одну роль ──
// Lumen зовёт их через @id из любого чата. Всё вне роли отрезано в коде:
// у бота просто нет нужных инструментов. У каждого один постоянный разговор.

export type BotIcon = "flask" | "palette" | "code" | "pen" | "sunrise" | "shield"

export const botTools = [
  { id: "read", name: "Читать файлы" },
  { id: "write", name: "Править файлы" },
  { id: "run", name: "Запускать команды" },
  { id: "web", name: "Интернет" },
  { id: "git", name: "Git: коммит и push" },
  { id: "memory", name: "Писать в память" },
  { id: "bots", name: "Звать других ботов" },
] as const

export type ToolId = (typeof botTools)[number]["id"]

export type BotDef = {
  id: string // то, что пишут после @
  name: string
  icon: BotIcon
  hue: number // свой цвет — чтобы бот не путался с Lumen
  role: string
  instructions: string
  can: string[]
  tools: ToolId[] // всё, чего нет в списке, бот физически не может
  skills: { name: string; self?: boolean; uses: number }[]
  learned: string[]
  needs: { text: string; ok: boolean }[]
  starters: string[]
  offTopic: RegExp // в макете — чем ловим просьбы не по роли
  handoff?: string // кому передать то, что не его
  messages: number
  compactions: { when: string; from: number; summary: string }[]
}

export const initialBots: BotDef[] = [
  {
    id: "tester",
    name: "Тестировщик",
    icon: "flask",
    hue: 160,
    role: "Проверяет приложения и правки — и только",
    instructions: "Собирает проект, гоняет тесты, проходит сценарии руками в симуляторе. Пишет, что сломано, с шагами и скриншотом. Сам ничего не чинит.",
    can: ["Собрать и запустить проект", "Прогнать тесты и сценарии", "Написать отчёт: шаги, ожидал / получил"],
    tools: ["read", "run", "memory"],
    skills: [
      { name: "Сборка Swift через build.sh", uses: 41 },
      { name: "Сценарии для Island", self: true, uses: 12 },
      { name: "Проверка падений по .ips", self: true, uses: 7 },
    ],
    learned: ["Island проседает, когда тень не успевает за островом — проверять первым делом", "У Shelf двойной щелчок по полке — частый источник падений"],
    needs: [
      { text: "Доступ к папке ~/Documents/prog", ok: true },
      { text: "Xcode 27 и симулятор", ok: true },
      { text: "Доступ к TestFlight", ok: false },
    ],
    starters: ["Протестируй последний коммит в Shelf", "Пройди сценарий раскрытия острова", "Что сломалось в прошлый раз?"],
    offTopic: /напиши код|почини|исправь|сделай дизайн|задеплой|запушь|выложи|придумай текст/i,
    handoff: "coder",
    messages: 412,
    compactions: [{ when: "1–12 окт", from: 380, summary: "Нашёл 9 падений: 6 в Shelf, 3 в Island; 8 закрыты." }],
  },
  {
    id: "designer",
    name: "Дизайнер",
    icon: "palette",
    hue: 320,
    role: "Макеты, стиль и ТЗ для кодера",
    instructions: "Делает мокапы и разбирает интерфейс. Код не пишет — вместо этого готовит подробное ТЗ для @coder.",
    can: ["Мокап экрана", "Разбор интерфейса", "Подробное ТЗ для @coder"],
    tools: ["read", "web", "memory", "bots"],
    skills: [
      { name: "Стиль prog: тёмный монохром", uses: 18 },
      { name: "ТЗ для кодера", self: true, uses: 9 },
    ],
    learned: ["Кнопки не переносить без просьбы", "Только тёмные темы"],
    needs: [
      { text: "Figma — подключить в «Инструментах»", ok: false },
      { text: "Скриншоты приложений", ok: true },
    ],
    starters: ["Разбери экран памяти Lumen", "Сделай ТЗ на вкладку «Боты»"],
    offTopic: /напиши код|код\b|функци|собери|почини|запушь|задеплой/i,
    handoff: "coder",
    messages: 156,
    compactions: [],
  },
  {
    id: "coder",
    name: "Кодер prog",
    icon: "code",
    hue: 235,
    role: "Пишет и чинит код Mac-приложений",
    instructions: "Правит Swift-код в prog, собирает, коммитит. Push и выкатка — только с OK Ромы.",
    can: ["Править Swift-код", "Собрать проект", "Закоммитить"],
    tools: ["read", "write", "run", "git", "memory", "bots"],
    skills: [
      { name: "SwiftUI по правилам prog", uses: 120 },
      { name: "Энергосбережение острова", self: true, uses: 6 },
    ],
    learned: ["Только SwiftUI, без WebView", "Тень острова — CA-анимация"],
    needs: [{ text: "Доступ к папке ~/Documents/prog", ok: true }],
    starters: ["Почини падение Shelf", "Сделай по ТЗ от @designer"],
    offTopic: /напиши текст для блога|сделай дизайн|нарисуй/i,
    handoff: "designer",
    messages: 1284,
    compactions: [
      { when: "1–9 окт", from: 612, summary: "Пульт v1.0 выпущен; Island — спринговые анимации; правило: только SwiftUI." },
      { when: "10–14 окт", from: 471, summary: "Shelf: Полка → Буфер; lid-plane v0.3.3; FlowLocal v3.2." },
    ],
  },
  {
    id: "writer",
    name: "Тексты для сайта",
    icon: "pen",
    hue: 200,
    role: "Тексты для kandeev.com",
    instructions: "Пишет тексты для папиного сайта: без цен, без кейсов с цифрами, для клиентов — на «вы».",
    can: ["Статья для блога", "Описание услуги", "Правка текста"],
    tools: ["read", "web", "memory"],
    skills: [{ name: "Голос kandeev.com", self: true, uses: 14 }],
    learned: ["Без цен и цифр", "Превью — ветка preview"],
    needs: [{ text: "Доступ к Сайты/kandeev.com", ok: true }],
    starters: ["Статья про ремонт ванной", "Перепиши «О нас» короче"],
    offTopic: /код|почини|собери|запушь/i,
    handoff: "coder",
    messages: 318,
    compactions: [{ when: "сентябрь", from: 260, summary: "Тон сайта, 6 статей, правило про цены." }],
  },
  {
    id: "morning",
    name: "Утро",
    icon: "sunrise",
    hue: 85,
    role: "Каждое утро — статус проектов",
    instructions: "В 9:00 смотрит tools/status.sh и ПЛАН.md и пишет коротко, что висит и что ждёт решения.",
    can: ["Статус проектов", "Что ждёт решения"],
    tools: ["read", "run"],
    skills: [{ name: "Отчёт по prog", uses: 30 }],
    learned: ["Скрипт прав, память может врать"],
    needs: [{ text: "Расписание: каждый день 9:00", ok: true }],
    starters: ["Что висит сейчас?"],
    offTopic: /напиши|почини|сделай|собери/i,
    messages: 96,
    compactions: [],
  },
]

/// Что боты делают прямо сейчас — как панель «Агенты» в Hermes
export const runs = [
  { bot: "tester", task: "Проверяет фикс Shelf", from: "Почему падает Shelf?", step: "Шаг 3 из 5: двойной щелчок по полке", where: "mac" as const },
  { bot: "coder", task: "Чинит анимацию чёлки", from: "Анимация чёлки проседает", step: "Собирает Island", where: "cloud" as const },
]

// ── инструменты: MCP, коннекторы, навыки, API ──

export const mcpServers = [
  { id: "fs", name: "Файлы prog", note: "чтение и правка ~/Documents/prog", tools: 8, on: true, local: true },
  { id: "xcode", name: "Xcode", note: "сборка, симулятор, тесты", tools: 12, on: true, local: true },
  { id: "browser", name: "Браузер", note: "открыть страницу, скриншот, клик", tools: 9, on: true, local: true },
  { id: "tldraw", name: "tldraw", note: "доска для схем", tools: 3, on: false, local: false },
]

export const connectors = [
  { id: "github", name: "GitHub", note: "репозитории, PR, issues", on: true },
  { id: "gmail", name: "Gmail", note: "почта: читать и черновики", on: true },
  { id: "calendar", name: "Календарь", note: "события и свободное время", on: true },
  { id: "notion", name: "Notion", note: "страницы и базы", on: false },
  { id: "figma", name: "Figma", note: "макеты и компоненты", on: false },
  { id: "linear", name: "Linear", note: "задачи", on: false },
  { id: "vercel", name: "Vercel", note: "деплои kandeev.com", on: true },
  { id: "telegram", name: "Telegram", note: "писать Lumen с телефона — позже", on: false, soon: true },
]

export const skills = [
  { id: "status", name: "Статус prog", note: "tools/status.sh + ПЛАН.md → короткий отчёт", source: "мой", uses: 64, on: true },
  { id: "swift", name: "SwiftUI по правилам prog", note: "стиль, энергосбережение, без WebView", source: "мой", uses: 120, on: true },
  { id: "island", name: "Сценарии для Island", note: "раскрытие, уведомления, тень", source: "сам научился", uses: 12, on: true },
  { id: "ips", name: "Разбор падений .ips", note: "найти место и причину", source: "сам научился", uses: 7, on: true },
  { id: "pdf", name: "PDF", note: "читать и собирать PDF", source: "каталог agentskills.io", uses: 3, on: true },
  { id: "reel", name: "Монтаж рилса", note: "из клипов в вертикальное видео", source: "каталог agentskills.io", uses: 0, on: false },
]

export const apis = [
  { id: "search", name: "Поиск в интернете", note: "Brave Search", on: true },
  { id: "weather", name: "Погода", note: "Open-Meteo, без ключа", on: true },
  { id: "custom", name: "Свой API", note: "любой адрес + ключ", on: false },
]
