// Заглушки макета: правдоподобные данные из жизни prog. Никуда не отправляются.

export type MemoryKind = "you" | "project" | "decision" | "pref"

export type Memory = {
  id: string
  text: string
  kind: MemoryKind
  source: string // из какого разговора
  when: string
  pinned?: boolean
  profile: string // чья это память
}

export const memoryKinds: { id: MemoryKind | "all"; name: string }[] = [
  { id: "all", name: "Всё" },
  { id: "you", name: "О тебе" },
  { id: "project", name: "Проекты" },
  { id: "decision", name: "Решения" },
  { id: "pref", name: "Как тебе удобно" },
]

export const initialMemories: Memory[] = [
  { id: "m1", kind: "you", text: "Рома делает Mac-приложения на Swift и сайты; работает в ~/Documents/prog", source: "Знакомство", when: "1 окт", pinned: true, profile: "roma" },
  { id: "m2", kind: "pref", text: "Не двигать существующие кнопки, когда внедряю мокап или фичу, — только по просьбе", source: "Ревью Пульта перед релизом", when: "14 окт", pinned: true, profile: "roma" },
  { id: "m3", kind: "pref", text: "Отвечать коротко, по-русски, простыми словами; сначала пересказ плана, потом просить OK", source: "Что поделаем сегодня?", when: "12 окт", profile: "roma" },
  { id: "m4", kind: "decision", text: "Интерфейс Mac-приложений — только SwiftUI, без WebView и React", source: "Пульт: с чего начать", when: "9 окт", profile: "roma" },
  { id: "m5", kind: "project", text: "Shelf: вкладку «Полка» убрали, файлы идут в Буфер строками-иконками", source: "Почему падает Shelf?", when: "сегодня", profile: "roma" },
  { id: "m6", kind: "project", text: "kandeev.com — папин сайт; превью в ветке preview, прод — только по OK", source: "Тексты для блога kandeev.com", when: "13 окт", profile: "roma" },
  { id: "m7", kind: "decision", text: "HandPilot (управление жестами) пробовали и бросили — не предлагать снова", source: "HandPilot: итоги", when: "23 сен", profile: "roma" },
  { id: "m8", kind: "you", text: "Говорит голосом через FlowLocal — в тексте бывают оговорки, понимать по смыслу", source: "Остров: самолётик вместо слова", when: "11 окт", profile: "roma" },
  { id: "m9", kind: "project", text: "Lumen: v1 — память, «с кем говорю» и характер; боты — во второй версии", source: "Lumen: замысел", when: "сегодня", profile: "roma" },
  { id: "m12", kind: "decision", text: "Только тёмные темы: «Люмен» и «Монохром»; светлую не делаем", source: "Lumen: замысел", when: "сейчас", profile: "roma" },
  { id: "m10", kind: "pref", text: "Сайт без цен и кейсов с цифрами", source: "Тексты для блога kandeev.com", when: "13 окт", profile: "papa" },
  { id: "m11", kind: "you", text: "Пишет на «вы», любит, когда объясняют без терминов", source: "Telegram · 2 окт", when: "2 окт", profile: "papa" },
]

export type Chat = { id: string; title: string; project: string; when: string; unread?: boolean }

export const chatGroups: { project: string; items: Chat[] }[] = [
  {
    project: "lumen",
    items: [{ id: "lumen", title: "Lumen: замысел", project: "lumen", when: "сейчас" }],
  },
  {
    project: "shelf",
    items: [{ id: "shelf", title: "Почему падает Shelf?", project: "shelf", when: "12 мин" }],
  },
  {
    project: "prog",
    items: [
      { id: "plan", title: "Что поделаем сегодня?", project: "prog", when: "2 ч" },
      { id: "dash", title: "Ревью Пульта перед релизом", project: "prog-dashboard", when: "вчера" },
    ],
  },
  {
    project: "kandeev.com",
    items: [{ id: "blog", title: "Тексты для блога", project: "kandeev.com", when: "5 ч", unread: true }],
  },
]

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

export type Profile = {
  id: string
  name: string
  call: string // как обращаться
  role: string
  tone: "warm" | "plain" | "formal"
  address: "ty" | "vy"
  can: string[]
  cannot: string[]
  via: string
  memories: number
}

export const initialProfiles: Profile[] = [
  {
    id: "roma",
    name: "Рома",
    call: "Рома",
    role: "Хозяин. Разработчик, все проекты prog",
    tone: "warm",
    address: "ty",
    can: ["Менять код и файлы", "Запускать сборку", "Читать всю память"],
    cannot: ["push и выкатка без OK", "Удалять файлы без спроса"],
    via: "Этот Мак",
    memories: 9,
  },
  {
    id: "papa",
    name: "Папа",
    call: "Александр",
    role: "Владелец сайта kandeev.com",
    tone: "formal",
    address: "vy",
    can: ["Спрашивать про сайт", "Просить тексты"],
    cannot: ["Видеть проекты Ромы", "Менять код", "Знать память Ромы"],
    via: "Telegram — во второй версии",
    memories: 2,
  },
]

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

// Бот — тот же чат, но под одну задачу: у него ровно один бесконечный разговор.
// Новый чат в боте не создаётся; старое сжимается в пересказы, чтобы с ним можно было работать всегда.
export type BotDef = {
  id: string
  name: string
  task: string
  project: string
  messages: number
  compactions: { when: string; from: number; summary: string }[]
  unread?: boolean
}

export const bots: BotDef[] = [
  {
    id: "coder",
    name: "Кодер prog",
    task: "Чинит и собирает Mac-приложения из prog",
    project: "prog",
    messages: 1284,
    compactions: [
      { when: "1–9 окт", from: 612, summary: "Пульт v1.0 выпущен; Island — спринговые анимации; правило: только SwiftUI, кнопки не двигать." },
      { when: "10–14 окт", from: 471, summary: "Shelf: Полка → Буфер; lid-plane v0.3.3; FlowLocal v3.2 и новый сайт в docs/." },
    ],
  },
  {
    id: "site",
    name: "Сайт папы",
    task: "Тексты и правки для kandeev.com",
    project: "kandeev.com",
    messages: 318,
    compactions: [{ when: "сентябрь", from: 260, summary: "Без цен и кейсов с цифрами; превью — ветка preview, прод только по OK; включён Вебвизор." }],
    unread: true,
  },
  {
    id: "morning",
    name: "Утро",
    task: "Каждое утро: статус проектов и что ждёт решения",
    project: "prog",
    messages: 96,
    compactions: [],
  },
]
