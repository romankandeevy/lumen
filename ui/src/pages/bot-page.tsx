import {
  Archive,
  ArrowLeft,
  ArrowRight,
  ArrowUp,
  AtSign,
  Check,
  ChevronDown,
  CircleAlert,
  Download,
  Library,
  Lock,
  Plus,
  Search,
  Sparkles,
  Star,
  Trash2,
  X,
} from "lucide-react"
import { useEffect, useMemo, useRef, useState } from "react"
import { toast } from "sonner"

import { allIcons, botColor, BotAvatar, botStyle } from "@/components/bot-avatar"
import { Segmented } from "@/components/page"
import { PlanList, type PlanItem } from "@/components/plan-list"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Switch } from "@/components/ui/switch"
import { Textarea } from "@/components/ui/textarea"
import { chatWidthClass, useApp } from "@/lib/app-state"
import { botTools, type BotDef, type ToolId } from "@/lib/mock-data"
import { fmtNum, hub, hubCategories, type HubSkill } from "@/lib/skills-hub"
import { cn } from "@/lib/utils"

// Страница бота. Бот — агент-субагент под одну роль, со своим цветом и квадратным знаком.
// Создание: конструктор по шагам (как GPT Builder) → бот сам настраивается и скачивает навыки
// из каталога, пропуская уже скачанные → его единственный чат.

type BMsg =
  | { id: string; from: "user"; text: string }
  | { id: string; from: "bot"; text: string; working?: boolean }
  | { id: string; from: "blocked"; text: string }

const firstTalk: Record<string, BMsg[]> = {
  tester: [
    { id: "1", from: "user", text: "Протестируй последний коммит в Shelf" },
    { id: "2", from: "bot", text: "Собрал, прошёл 6 сценариев. 5 ок. Двойной щелчок по полке больше не роняет приложение. Нашёл одно: при удалении 20 файлов подряд список мигает. Шаги и снимок — в отчёте." },
  ],
  designer: [
    { id: "1", from: "user", text: "Напиши код экрана памяти" },
    { id: "2", from: "blocked", text: "Код не пишу — у меня нет инструмента правки файлов. Могу сделать подробное ТЗ для @coder: экраны, состояния, отступы, тексты." },
    { id: "3", from: "user", text: "Давай ТЗ" },
    { id: "4", from: "bot", text: "Готово: 3 экрана, 11 состояний, все тексты. Передал @coder, он уже видит ТЗ в своём чате." },
  ],
  coder: [
    { id: "1", from: "user", text: "Почини падение Shelf" },
    { id: "2", from: "bot", text: "Поправил ShelfStorage.swift: проверка индекса и отключение кнопки на время удаления. Собрал, закоммитил. Push — жду твоего OK." },
  ],
  writer: [{ id: "1", from: "bot", text: "Последнее: статья про ремонт ванной, 3 абзаца, без цен. Лежит в ветке preview." }],
  morning: [{ id: "1", from: "bot", text: "Доброе утро. Свежее: Lumen — новый макет. У lid-plane 2 коммита не отправлены. Ждут решения: репозиторий Lumen на GitHub." }],
}

/// Что бот делает прямо сейчас — показывается сбоку, как план в Claude Code
const botPlans: Record<string, PlanItem[]> = {
  tester: [
    { text: "Собрать Shelf", state: "done" },
    { text: "Удалить 20 файлов подряд", state: "done" },
    { text: "Двойной щелчок по полке", state: "doing" },
    { text: "Проверить список после удаления", state: "todo" },
    { text: "Написать отчёт: шаги и снимок", state: "todo" },
  ],
  coder: [
    { text: "Прочитать IslandView.swift", state: "done" },
    { text: "Перенести тень в CA-анимацию", state: "doing" },
    { text: "Собрать Island в облаке", state: "todo" },
    { text: "Замерить кадры при уведомлении", state: "todo" },
  ],
}

const newBot = (): BotDef => ({
  id: "",
  name: "",
  icon: "Bot",
  hue: 265,
  chroma: 0.13,
  role: "",
  instructions: "",
  can: [],
  tools: ["read", "memory"],
  skills: [],
  learned: [],
  needs: [],
  starters: [],
  offTopic: /$^/,
  messages: 0,
  compactions: [],
  hubSkills: [],
  never: [],
})

export function BotPage({ botId }: { botId: string }) {
  const app = useApp()
  const creating = botId === "new"
  const existing = app.bots.find((b) => b.id === botId)
  const [draft, setDraft] = useState<BotDef>(() => (existing ? { ...existing } : newBot()))
  const [stage, setStage] = useState<"build" | "setup" | "talk">(creating ? "build" : "talk")
  const bot = stage === "build" || stage === "setup" ? draft : (existing ?? draft)

  if (!creating && !existing) return null

  return (
    <div style={botStyle(bot.hue, bot.chroma)} className="flex h-full min-h-0 flex-col">
      <header className="relative shrink-0 overflow-hidden border-b">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(600px_160px_at_10%_0%,var(--bot-soft),transparent_70%)]" />
        <div className="relative flex items-center gap-4 px-6 py-4">
          <BotAvatar bot={bot} size={44} />
          <div className="min-w-0 flex-1">
            <p className="flex items-center gap-2 text-lg font-semibold tracking-[-0.01em]">
              {bot.name || "Новый бот"}
              {bot.id && <span className="rounded-md bg-[var(--bot-soft)] px-1.5 py-0.5 text-xs font-medium text-[var(--bot)]">@{bot.id}</span>}
            </p>
            <p className="flex items-center gap-1.5 truncate text-sm text-muted-foreground">
              <Lock className="size-3.5 shrink-0" /> Только: {bot.role ? bot.role.charAt(0).toLowerCase() + bot.role.slice(1) : "роль ещё не задана"}
            </p>
          </div>
          {!creating && stage !== "setup" && (
            <Segmented
              value={stage}
              onChange={(v) => {
                if (v === "build" && existing) setDraft({ ...existing })
                setStage(v)
              }}
              options={[
                { id: "talk", name: "Разговор" },
                { id: "build", name: "Настройка" },
              ]}
            />
          )}
        </div>
      </header>

      {stage === "talk" && existing && <Talk bot={existing} />}
      {stage === "build" && (
        <Builder
          draft={draft}
          setDraft={setDraft}
          creating={creating}
          onSave={() => {
            if (creating) {
              setStage("setup")
            } else {
              app.setBots((bs) => bs.map((b) => (b.id === draft.id ? draft : b)))
              toast("Бот сохранён")
              setStage("talk")
            }
          }}
        />
      )}
      {stage === "setup" && (
        <Setup
          bot={draft}
          onDone={() => {
            app.setBots((bs) => [
              ...bs,
              {
                ...draft,
                offTopic: /напиши код|почини|запушь|задеплой/i,
                messages: 0,
                skills: hub.filter((h) => draft.hubSkills?.includes(h.id)).map((h) => ({ name: h.name, uses: 0 })),
                learned: [`Моя роль: ${draft.role}`],
              },
            ])
            app.go("bot", draft.id)
          }}
        />
      )}
    </div>
  )
}

// ── разговор с ботом + паспорт ──

function Talk({ bot }: { bot: BotDef }) {
  const app = useApp()
  const [messages, setMessages] = useState<BMsg[]>(firstTalk[bot.id] ?? [])
  const [text, setText] = useState("")
  const [compactions, setCompactions] = useState(bot.compactions)
  const [openC, setOpenC] = useState<number | null>(null)
  const scroller = useRef<HTMLDivElement>(null)
  const timers = useRef<number[]>([])
  const handoff = app.bots.find((b) => b.id === bot.handoff)

  useEffect(() => {
    scroller.current?.scrollTo({ top: scroller.current.scrollHeight, behavior: "smooth" })
  }, [messages])
  useEffect(() => () => timers.current.forEach(clearTimeout), [])

  const send = (t = text) => {
    const v = t.trim()
    if (!v) return
    setText("")
    const id = String(Date.now())
    setMessages((m) => [...m, { id: id + "u", from: "user", text: v }])
    // просьба не по роли упирается в блокировку — у бота просто нет инструмента
    if (bot.offTopic.test(v)) {
      const reply = `Это не моя роль — ${bot.role.charAt(0).toLowerCase() + bot.role.slice(1)}.${handoff ? ` Могу подготовить задачу для @${handoff.id}.` : ""}`
      timers.current.push(window.setTimeout(() => setMessages((m) => [...m, { id: id + "b", from: "blocked", text: reply }]), 700))
      return
    }
    setMessages((m) => [...m, { id: id + "w", from: "bot", text: "", working: true }])
    timers.current.push(
      window.setTimeout(
        () => setMessages((m) => m.map((x) => (x.id === id + "w" ? { ...x, working: false, text: "Сделал по своей части. Это макет — настоящая работа начнётся, когда подключим Claude." } : x))),
        1400
      )
    )
  }

  return (
    <div className="grid min-h-0 flex-1 grid-cols-1 lg:grid-cols-[minmax(0,1fr)_340px]">
      <section className="relative flex min-h-0 flex-col bg-[radial-gradient(700px_400px_at_50%_110%,var(--bot-faint),transparent_70%)]">
        <div ref={scroller} className="min-h-0 flex-1 overflow-auto">
          <div className={cn("mx-auto flex flex-col gap-5 px-6 py-6", chatWidthClass[app.chatWidth])}>
            <div className="flex items-center gap-3">
              <span className="h-px flex-1 bg-border" />
              <span className="text-xs text-muted-foreground">
                {bot.messages ? `один чат с начала, ${bot.messages.toLocaleString("ru")} сообщений` : "чат бота начинается здесь и не заканчивается"}
              </span>
              <span className="h-px flex-1 bg-border" />
            </div>
            {compactions.map((c, i) => (
              <button key={c.when + i} onClick={() => setOpenC(openC === i ? null : i)} className="block w-full rounded-xl border border-dashed px-3.5 py-2.5 text-left hover:border-[var(--bot-soft)]">
                <span className="flex items-center gap-2 text-xs text-muted-foreground">
                  <Archive className="size-3.5" /> Сжато: {c.when}, {c.from} сообщений → пересказ
                  <ChevronDown className={cn("ml-auto size-3.5 transition-transform", openC === i && "rotate-180")} />
                </span>
                {openC === i && <span className="mt-2 block text-sm leading-relaxed text-foreground/85">{c.summary}</span>}
              </button>
            ))}
            {messages.map((m) =>
              m.from === "user" ? (
                <div key={m.id} className="flex justify-end">
                  <div className="max-w-[80%] rounded-2xl rounded-br-md bg-secondary px-4 py-2.5 text-sm">{m.text}</div>
                </div>
              ) : m.from === "bot" ? (
                <div key={m.id} className="flex gap-3">
                  <BotAvatar bot={bot} size={26} />
                  <div className="max-w-[85%] rounded-2xl rounded-tl-md border-l-2 border-[var(--bot)] bg-[var(--bot-faint)] px-4 py-2.5 text-[0.9375rem] leading-relaxed">
                    {m.working ? <span className="animate-pulse text-muted-foreground">Работает по своей роли…</span> : m.text}
                  </div>
                </div>
              ) : (
                <div key={m.id} className="flex gap-3">
                  <BotAvatar bot={bot} size={26} />
                  <div className="max-w-[85%] rounded-2xl rounded-tl-md border border-dashed px-4 py-2.5">
                    <p className="flex items-center gap-2 text-xs text-muted-foreground">
                      <Lock className="size-3.5" /> Вне роли — заблокировано в коде
                    </p>
                    <p className="mt-1.5 text-[0.9375rem] leading-relaxed">{m.text}</p>
                    {handoff && (
                      <Button size="xs" variant="outline" className="mt-2.5" onClick={() => toast(`Задача для @${handoff.id} готова`, { description: "Он увидит её в своём чате." })}>
                        <BotAvatar bot={handoff} size={14} /> Сделать задачу для @{handoff.id}
                      </Button>
                    )}
                  </div>
                </div>
              )
            )}
          </div>
        </div>

        <div className="px-5 pb-5">
          <div className={cn("mx-auto", chatWidthClass[app.chatWidth])}>
            {bot.starters.length > 0 && (
              <div className="mb-2 flex flex-wrap gap-1.5">
                {bot.starters.map((s) => (
                  <button key={s} onClick={() => send(s)} className="rounded-full border border-[var(--bot-soft)] px-3 py-1 text-xs text-foreground/80 hover:bg-[var(--bot-faint)]">
                    {s}
                  </button>
                ))}
              </div>
            )}
            <div className="rounded-2xl border border-[var(--bot-soft)] bg-card/60 p-3 backdrop-blur focus-within:shadow-[0_0_0_1px_var(--bot-soft),0_0_32px_-8px_var(--bot)]">
              <Textarea
                value={text}
                onChange={(e) => setText(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && !e.shiftKey) {
                    e.preventDefault()
                    send()
                  }
                }}
                placeholder={`Напиши ${bot.name}. Только по роли — остальное он не сделает`}
                className="min-h-10 resize-none border-0 bg-transparent p-0 text-sm shadow-none focus-visible:ring-0 dark:bg-transparent"
              />
              <div className="mt-2 flex items-center">
                <span className="text-xs text-muted-foreground">Один постоянный чат — новых не бывает</span>
                <Button size="icon-sm" className="ml-auto rounded-full bg-[var(--bot)] text-black hover:opacity-85" disabled={!text.trim()} onClick={() => send()} aria-label="Отправить">
                  <ArrowUp />
                </Button>
              </div>
            </div>
          </div>
        </div>
      </section>

      <Passport
        bot={bot}
        compactions={compactions.length}
        onCompact={() => {
          setCompactions((c) => [...c, { when: "сейчас", from: messages.length, summary: "Свежий кусок пересказан; договорённости ушли в память бота." }])
          setMessages((m) => m.slice(-1))
          toast("Чат бота сжат", { description: "Старое — в пересказ, важное — в его память." })
        }}
      />
    </div>
  )
}

function PSection({ title, children, aside }: { title: string; children: React.ReactNode; aside?: React.ReactNode }) {
  return (
    <section className="border-b px-5 py-4 last:border-b-0">
      <div className="mb-2.5 flex items-center justify-between">
        <p className="text-[13px] font-medium">{title}</p>
        {aside}
      </div>
      {children}
    </section>
  )
}

function Passport({ bot, compactions, onCompact }: { bot: BotDef; compactions: number; onCompact: () => void }) {
  const app = useApp()
  const blocked = botTools.filter((t) => !bot.tools.includes(t.id))
  const plan = botPlans[bot.id]
  return (
    <aside className="hidden min-h-0 flex-col overflow-auto border-l bg-sidebar/50 lg:flex">
      {plan && (
        <PSection title="План" aside={<span className="text-[11px] text-muted-foreground">работает сейчас</span>}>
          <PlanList items={plan} accent="var(--bot)" />
        </PSection>
      )}

      <PSection title="Как позвать">
        <p className="flex items-center gap-2 text-sm">
          <AtSign className="size-4 text-[var(--bot)]" /> Напиши <span className="rounded bg-[var(--bot-soft)] px-1 text-[var(--bot)]">@{bot.id}</span> в любом чате
        </p>
        <p className="mt-1.5 text-xs text-muted-foreground">Lumen передаст ему задачу и покажет результат карточкой.</p>
      </PSection>

      <PSection title="Умеет">
        <ul className="space-y-1.5 text-sm">
          {bot.can.map((c) => (
            <li key={c} className="flex items-start gap-2">
              <Check className="mt-0.5 size-4 shrink-0 text-[var(--bot)]" /> {c}
            </li>
          ))}
        </ul>
      </PSection>

      <PSection title="Отрезано в коде" aside={<span className="text-[11px] text-muted-foreground">не обойти просьбой</span>}>
        <ul className="space-y-1.5 text-sm text-muted-foreground">
          {blocked.map((t) => (
            <li key={t.id} className="flex items-center gap-2">
              <Lock className="size-3.5 shrink-0" /> {t.name}
            </li>
          ))}
          {blocked.length === 0 && <li className="text-xs">Все инструменты разрешены</li>}
        </ul>
      </PSection>

      <PSection title="Навыки">
        <div className="space-y-1.5">
          {bot.skills.map((s) => (
            <div key={s.name} className="flex items-center gap-2 text-sm">
              <Sparkles className={cn("size-3.5 shrink-0", s.self ? "text-[var(--bot)]" : "text-muted-foreground")} />
              <span className="min-w-0 flex-1 truncate">{s.name}</span>
              {s.self && <span className="rounded bg-[var(--bot-soft)] px-1.5 text-[10px] text-[var(--bot)]">сам</span>}
              <span className="text-[11px] text-muted-foreground tabular-nums">{s.uses}×</span>
            </div>
          ))}
          {bot.skills.length === 0 && <p className="text-xs text-muted-foreground">Пока нет — научится в работе.</p>}
        </div>
      </PSection>

      {bot.learned.length > 0 && (
        <PSection title="Чему научился">
          <ul className="space-y-1.5 text-sm text-foreground/85">
            {bot.learned.map((l) => (
              <li key={l} className="leading-snug">
                {l}
              </li>
            ))}
          </ul>
        </PSection>
      )}

      {bot.needs.length > 0 && (
        <PSection title="Что нужно для работы">
          <ul className="space-y-1.5 text-sm">
            {bot.needs.map((n) => (
              <li key={n.text} className="flex items-center gap-2">
                {n.ok ? <Check className="size-4 shrink-0 text-[var(--bot)]" /> : <CircleAlert className="size-4 shrink-0 text-amber-400" />}
                <span className="min-w-0 flex-1">{n.text}</span>
                {!n.ok && (
                  <button onClick={() => app.go("tools")} className="text-xs text-muted-foreground hover:text-foreground">
                    Дать
                  </button>
                )}
              </li>
            ))}
          </ul>
        </PSection>
      )}

      <PSection title="Один чат">
        <p className="text-xs leading-relaxed text-muted-foreground">Новых чатов у бота нет. У края окна старое пересказывается, договорённости уходят в его память.</p>
        <p className="mt-2 text-sm tabular-nums">Сжат {compactions} раз · занято 24% окна</p>
        <Button size="sm" variant="outline" className="mt-2.5" onClick={onCompact}>
          <Archive /> Сжать сейчас
        </Button>
      </PSection>
    </aside>
  )
}

// ── конструктор ──

const steps = [
  { id: "look", name: "Знак и имя" },
  { id: "role", name: "Роль и инструкции" },
  { id: "skills", name: "Навыки" },
  { id: "tools", name: "Инструменты и границы" },
  { id: "start", name: "Начало разговора" },
] as const
type StepId = (typeof steps)[number]["id"]

/// Готовые роли: подставляют всё сразу, дальше можно поправить
const templates: { name: string; patch: Partial<BotDef> }[] = [
  {
    name: "Тестировщик",
    patch: { icon: "FlaskConical", hue: 160, role: "Проверяет приложения и правки — и только", instructions: "Собирает проект, гоняет тесты и сценарии, пишет отчёт: шаги, ожидал / получил, снимок. Сам ничего не чинит.", can: ["Собрать и запустить проект", "Прогнать тесты и сценарии", "Написать отчёт"], tools: ["read", "run", "memory"], hubSkills: ["xcode-build", "xctest", "simulator", "crash-ips"], doneWhen: "Все сценарии пройдены, отчёт отправлен", report: "Список: что проверено, что сломано, шаги и снимок", never: ["Чинить код сам"] },
  },
  {
    name: "Дизайнер",
    patch: { icon: "Palette", hue: 320, role: "Макеты, стиль и ТЗ для кодера", instructions: "Делает мокапы и разбирает интерфейс. Код не пишет — вместо этого готовит подробное ТЗ для @coder.", can: ["Мокап экрана", "Разбор интерфейса", "ТЗ для кодера"], tools: ["read", "web", "memory", "bots"], hubSkills: ["figma-read", "ui-critique", "spec-writer", "design-tokens"], doneWhen: "Есть макет и ТЗ, кодеру всё понятно", report: "Ссылка на макет и короткий список решений", never: ["Писать код", "Двигать кнопки без просьбы"] },
  },
  {
    name: "Кодер",
    patch: { icon: "CodeXml", hue: 235, role: "Пишет и чинит код", instructions: "Правит код по ТЗ, собирает, коммитит. Push и выкатка — только с OK.", can: ["Править код", "Собрать проект", "Закоммитить"], tools: ["read", "write", "run", "git", "memory", "bots"], hubSkills: ["git-flow", "swift-concurrency", "code-review"], doneWhen: "Собирается, тесты зелёные, есть коммит", report: "Что поменял и почему, какие файлы", never: ["Пушить без OK"] },
  },
  {
    name: "Писатель",
    patch: { icon: "PenLine", hue: 200, role: "Тексты для сайта и соцсетей", instructions: "Пишет просто и по делу, без канцелярита. Держит голос бренда.", can: ["Статья", "Описание услуги", "Правка текста"], tools: ["read", "web", "memory"], hubSkills: ["copy-ru", "seo", "brand-voice"], doneWhen: "Текст вычитан, без стоп-слов", report: "Текст и 2–3 варианта заголовка", never: ["Цены и цифры без проверки"] },
  },
  {
    name: "Исследователь",
    patch: { icon: "Telescope", hue: 95, role: "Ищет и сверяет информацию", instructions: "Находит источники, сверяет их между собой, пишет короткий отчёт со ссылками.", can: ["Поиск", "Сравнение", "Отчёт со ссылками"], tools: ["web", "memory"], hubSkills: ["deep-research", "arxiv", "competitors"], doneWhen: "Ответ на вопрос со ссылками", report: "Вывод сверху, ниже доказательства и ссылки", never: ["Выдумывать источники"] },
  },
  {
    name: "Ревьюер",
    patch: { icon: "ShieldCheck", hue: 25, role: "Проверяет код перед коммитом", instructions: "Читает правки, ищет баги, риски и лишний код. Сам не правит.", can: ["Ревью правок", "Список замечаний"], tools: ["read", "memory"], hubSkills: ["code-review", "security"], doneWhen: "Все правки просмотрены", report: "Замечания по важности, с файлом и строкой", never: ["Править код"] },
  },
]

function Builder({ draft, setDraft, creating, onSave }: { draft: BotDef; setDraft: React.Dispatch<React.SetStateAction<BotDef>>; creating: boolean; onSave: () => void }) {
  const app = useApp()
  const [step, setStep] = useState<StepId>("look")
  const [hubOpen, setHubOpen] = useState(false)
  const set = (p: Partial<BotDef>) => setDraft((d) => ({ ...d, ...p }))
  const idTaken = creating && app.bots.some((b) => b.id === draft.id)
  const okLook = !!draft.name.trim() && /^[a-z0-9-]+$/.test(draft.id) && !idTaken
  const okRole = !!draft.role.trim()
  const valid = okLook && okRole
  const idx = steps.findIndex((s) => s.id === step)
  const field = "h-10 w-full rounded-xl border bg-input/30 px-3.5 text-sm outline-none transition-colors focus:border-[var(--bot)]"
  const area = "w-full resize-none rounded-xl border bg-input/30 px-3.5 py-2.5 text-sm leading-relaxed outline-none transition-colors focus:border-[var(--bot)]"
  const chosen = hub.filter((h) => draft.hubSkills?.includes(h.id))

  return (
    <div className="grid min-h-0 flex-1 grid-cols-1 lg:grid-cols-[220px_minmax(0,1fr)_380px]">
      {/* шаги */}
      <nav className="hidden border-r px-3 py-6 lg:block" aria-label="Шаги">
        <ol className="space-y-1">
          {steps.map((s, i) => {
            const done = i < idx || (!creating && i !== idx)
            return (
              <li key={s.id}>
                <button
                  onClick={() => setStep(s.id)}
                  className={cn(
                    "flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left text-sm transition-colors",
                    s.id === step ? "bg-[var(--bot-faint)] text-foreground" : "text-muted-foreground hover:bg-foreground/5 hover:text-foreground"
                  )}
                >
                  <span
                    className={cn(
                      "flex size-6 shrink-0 items-center justify-center rounded-full border text-xs tabular-nums",
                      s.id === step ? "border-[var(--bot)] text-[var(--bot)]" : done ? "border-transparent bg-foreground/10" : ""
                    )}
                  >
                    {done && s.id !== step ? <Check className="size-3.5" /> : i + 1}
                  </span>
                  {s.name}
                </button>
              </li>
            )
          })}
        </ol>
        <div className="mt-8 px-3">
          <p className="mb-2 text-xs text-muted-foreground">Начать с готовой роли</p>
          <div className="flex flex-wrap gap-1.5">
            {templates.map((t) => (
              <button
                key={t.name}
                onClick={() => {
                  set({ ...t.patch, name: draft.name || t.name, id: draft.id || "" })
                  toast(`Роль «${t.name}» подставлена`, { description: "Всё можно поправить." })
                }}
                className="rounded-full border px-2.5 py-1 text-xs hover:border-[var(--bot)] hover:text-foreground"
              >
                {t.name}
              </button>
            ))}
          </div>
        </div>
      </nav>

      {/* форма шага */}
      <div className="flex min-h-0 flex-col">
        <div className="min-h-0 flex-1 overflow-auto px-8 py-7">
          <div className="max-w-2xl">
            <p className="text-xs text-muted-foreground tabular-nums">
              Шаг {idx + 1} из {steps.length}
            </p>
            <h2 className="mt-1 text-xl font-semibold tracking-[-0.02em]">{steps[idx].name}</h2>

            {step === "look" && (
              <div className="mt-6 space-y-6">
                <div className="flex items-center gap-5">
                  <BotAvatar bot={draft} size={88} />
                  <div className="space-y-2">
                    <IconPicker value={draft.icon} hue={draft.hue} chroma={draft.chroma} onChange={(icon) => set({ icon })} />
                    <ColorPicker hue={draft.hue} chroma={draft.chroma ?? 0.12} onChange={(hue, chroma) => set({ hue, chroma })} />
                  </div>
                </div>
                <Field label="Имя">
                  <input autoFocus value={draft.name} onChange={(e) => set({ name: e.target.value })} placeholder="Например, Тестировщик" className={field} />
                </Field>
                <Field label="Как звать в чате" hint={idTaken ? "такой @ уже есть" : "латиница, цифры и дефис"}>
                  <label className={cn(field, "flex items-center gap-1.5")}>
                    <AtSign className="size-4 text-[var(--bot)]" />
                    <input
                      value={draft.id}
                      disabled={!creating}
                      onChange={(e) => set({ id: e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, "") })}
                      placeholder="tester"
                      className="w-full bg-transparent outline-none"
                    />
                  </label>
                </Field>
              </div>
            )}

            {step === "role" && (
              <div className="mt-6 space-y-6">
                <Field label="Роль одной строкой" hint="всё вне роли бот отклонит">
                  <input value={draft.role} onChange={(e) => set({ role: e.target.value })} placeholder="Проверяет приложения и правки — и только" className={field} />
                </Field>
                <Field label="Инструкции" hint="как работает, по каким правилам">
                  <textarea value={draft.instructions} onChange={(e) => set({ instructions: e.target.value })} rows={8} placeholder="Опиши, как бот работает: с чего начинает, что проверяет, как решает спорное…" className={area} />
                </Field>
                <div className="grid gap-5 md:grid-cols-2">
                  <Field label="Что считать готовым">
                    <textarea value={draft.doneWhen ?? ""} onChange={(e) => set({ doneWhen: e.target.value })} rows={3} placeholder="Все сценарии пройдены, отчёт отправлен" className={area} />
                  </Field>
                  <Field label="Как отчитываться">
                    <textarea value={draft.report ?? ""} onChange={(e) => set({ report: e.target.value })} rows={3} placeholder="Коротко: что сделано, что сломано, что дальше" className={area} />
                  </Field>
                </div>
                <Field label="Умеет">
                  <Items items={draft.can} onChange={(can) => set({ can })} placeholder="Например: прогнать тесты" />
                </Field>
              </div>
            )}

            {step === "skills" && (
              <div className="mt-6 space-y-6">
                <p className="text-sm text-muted-foreground">
                  Навыки — готовые умения из каталога: agentskills.io, GitHub, Hugging Face. После создания бот скачает их сам; то, что уже есть в Lumen, качать не будет.
                </p>
                <div className="flex flex-wrap gap-2">
                  {chosen.map((s) => (
                    <span key={s.id} className="flex h-8 items-center gap-2 rounded-full border border-[var(--bot-soft)] bg-[var(--bot-faint)] pr-1.5 pl-3 text-sm">
                      <Sparkles className="size-3.5 text-[var(--bot)]" /> {s.name}
                      {s.installed && <span className="text-[11px] text-muted-foreground">уже есть</span>}
                      <button onClick={() => set({ hubSkills: draft.hubSkills?.filter((x) => x !== s.id) })} aria-label="Убрать" className="rounded-full p-1 text-muted-foreground hover:bg-foreground/10 hover:text-foreground">
                        <X className="size-3" />
                      </button>
                    </span>
                  ))}
                  <Button variant="outline" className="h-8 rounded-full" onClick={() => setHubOpen(true)}>
                    <Library /> Каталог навыков
                  </Button>
                </div>
                <div>
                  <p className="mb-2 text-xs text-muted-foreground">Подходят к роли</p>
                  <div className="grid gap-2 sm:grid-cols-2">
                    {hub
                      .filter((h) => !draft.hubSkills?.includes(h.id))
                      .slice(3, 9)
                      .map((h) => (
                        <SkillCard key={h.id} skill={h} added={false} onAdd={() => set({ hubSkills: [...(draft.hubSkills ?? []), h.id] })} compact />
                      ))}
                  </div>
                </div>
              </div>
            )}

            {step === "tools" && (
              <div className="mt-6 space-y-6">
                <p className="text-sm text-muted-foreground">Выключенное отрезано в коде: у бота просто нет этого инструмента, и никакая просьба его не вернёт.</p>
                <div className="divide-y overflow-hidden rounded-2xl border bg-card/40">
                  {botTools.map((t) => {
                    const on = draft.tools.includes(t.id)
                    return (
                      <label key={t.id} className="flex cursor-pointer items-center gap-3 px-4 py-3 text-sm hover:bg-foreground/[0.03]">
                        <span className={cn("flex size-7 items-center justify-center rounded-lg", on ? "bg-[var(--bot-soft)] text-[var(--bot)]" : "bg-foreground/5 text-muted-foreground")}>
                          {on ? <Check className="size-4" /> : <Lock className="size-3.5" />}
                        </span>
                        <span className={cn("flex-1", !on && "text-muted-foreground")}>{t.name}</span>
                        <Switch checked={on} onCheckedChange={(v) => set({ tools: v ? [...draft.tools, t.id as ToolId] : draft.tools.filter((x) => x !== t.id) })} />
                      </label>
                    )
                  })}
                </div>
                <Field label="Чего никогда не делать">
                  <Items items={draft.never ?? []} onChange={(never) => set({ never })} placeholder="Например: пушить без OK" />
                </Field>
              </div>
            )}

            {step === "start" && (
              <div className="mt-6 space-y-6">
                <Field label="Подсказки над полем ввода" hint="с чего начать разговор">
                  <Items items={draft.starters} onChange={(starters) => set({ starters })} placeholder="Например: протестируй последний коммит" />
                </Field>
                <div className="rounded-2xl border border-[var(--bot-soft)] bg-[var(--bot-faint)] p-4 text-sm">
                  <p className="font-medium">Что будет после «{creating ? "Создать" : "Сохранить"}»</p>
                  <p className="mt-1.5 leading-relaxed text-muted-foreground">
                    Бот заведёт себе рабочую папку, запишет роль и инструкции, скачает {chosen.filter((c) => !c.installed).length} навыка (ещё {chosen.filter((c) => c.installed).length} уже есть) и проверит доступы. Потом его можно звать через @{draft.id || "id"}.
                  </p>
                </div>
              </div>
            )}
          </div>
        </div>

        <div className="flex items-center gap-2 border-t px-8 py-3.5">
          <Button variant="ghost" disabled={idx === 0} onClick={() => setStep(steps[idx - 1].id)}>
            <ArrowLeft /> Назад
          </Button>
          {!creating && (
            <Button
              variant="ghost"
              className="text-muted-foreground"
              onClick={() => {
                app.setBots((bs) => bs.filter((b) => b.id !== draft.id))
                app.go("bots")
                toast(`Бот @${draft.id} удалён`)
              }}
            >
              <Trash2 /> Удалить
            </Button>
          )}
          <span className="ml-auto text-xs text-muted-foreground">{!okLook ? "Нужны имя и @" : !okRole ? "Нужна роль" : ""}</span>
          {idx < steps.length - 1 && creating ? (
            <Button className="bg-[var(--bot)] text-black hover:opacity-85" disabled={idx === 0 && !okLook} onClick={() => setStep(steps[idx + 1].id)}>
              Дальше <ArrowRight />
            </Button>
          ) : (
            <Button className="bg-[var(--bot)] text-black hover:opacity-85" disabled={!valid} onClick={onSave}>
              <Check /> {creating ? "Создать бота" : "Сохранить"}
            </Button>
          )}
        </div>
      </div>

      {/* живое превью */}
      <aside className="hidden min-h-0 overflow-auto border-l bg-sidebar/50 px-6 py-7 lg:block">
        <p className="mb-3 text-[13px] font-medium">Превью</p>
        <div className="relative overflow-hidden rounded-2xl border border-[var(--bot-soft)] bg-[var(--bot-faint)] p-5">
          <div className="pointer-events-none absolute -top-20 -right-20 size-52 rounded-full bg-[var(--bot-soft)] blur-3xl" />
          <div className="relative flex items-center gap-3">
            <BotAvatar bot={draft} size={48} />
            <div className="min-w-0">
              <p className="truncate font-medium">{draft.name || "Новый бот"}</p>
              <p className="text-xs text-[var(--bot)]">@{draft.id || "id"}</p>
            </div>
          </div>
          <p className="relative mt-3 text-sm text-foreground/80">{draft.role || "Роль появится здесь"}</p>
          {chosen.length > 0 && (
            <p className="relative mt-3 flex flex-wrap gap-1 text-[11px] text-muted-foreground">
              {chosen.slice(0, 4).map((c) => (
                <span key={c.id} className="rounded-md bg-foreground/[0.06] px-1.5 py-0.5">
                  {c.name}
                </span>
              ))}
              {chosen.length > 4 && <span className="px-1 py-0.5">+{chosen.length - 4}</span>}
            </p>
          )}
        </div>

        <p className="mt-6 mb-2 text-xs text-muted-foreground">Как ответит</p>
        <div className="space-y-3">
          {draft.starters[0] && (
            <div className="flex justify-end">
              <div className="max-w-[85%] rounded-2xl rounded-br-md bg-secondary px-3 py-2 text-sm">{draft.starters[0]}</div>
            </div>
          )}
          <div className="flex gap-2.5">
            <BotAvatar bot={draft} size={24} />
            <div className="rounded-2xl rounded-tl-md border-l-2 border-[var(--bot)] bg-[var(--bot-faint)] px-3 py-2 text-sm leading-relaxed">
              {draft.report ? `Готово. ${draft.report}.` : "Сделал по своей части — вот отчёт."}
            </div>
          </div>
          <div className="flex justify-end">
            <div className="max-w-[85%] rounded-2xl rounded-br-md bg-secondary px-3 py-2 text-sm">Сделай что-нибудь не по роли</div>
          </div>
          <div className="flex gap-2.5">
            <BotAvatar bot={draft} size={24} />
            <div className="rounded-2xl rounded-tl-md border border-dashed px-3 py-2 text-sm">
              <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
                <Lock className="size-3" /> Вне роли — заблокировано в коде
              </p>
              <p className="mt-1">Это не моя роль{draft.role ? ` — ${draft.role.charAt(0).toLowerCase() + draft.role.slice(1)}` : ""}.</p>
            </div>
          </div>
        </div>
      </aside>

      <SkillHub open={hubOpen} onClose={() => setHubOpen(false)} chosen={draft.hubSkills ?? []} onToggle={(id) => set({ hubSkills: draft.hubSkills?.includes(id) ? draft.hubSkills.filter((x) => x !== id) : [...(draft.hubSkills ?? []), id] })} />
    </div>
  )
}

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="mb-2 text-xs text-muted-foreground">
        {label}
        {hint && <span className="text-foreground/30"> — {hint}</span>}
      </p>
      {children}
    </div>
  )
}

function Items({ items, onChange, placeholder }: { items: string[]; onChange: (v: string[]) => void; placeholder: string }) {
  const [v, setV] = useState("")
  const add = () => {
    if (!v.trim()) return
    onChange([...items, v.trim()])
    setV("")
  }
  return (
    <div className="space-y-1">
      {items.map((it, i) => (
        <div key={it + i} className="group flex items-center gap-2.5 rounded-xl bg-foreground/[0.04] px-3.5 py-2 text-sm">
          <span className="size-1.5 rounded-full bg-[var(--bot)]" />
          <span className="flex-1">{it}</span>
          <button onClick={() => onChange(items.filter((_, j) => j !== i))} aria-label="Убрать" className="text-muted-foreground opacity-0 group-hover:opacity-100 focus:opacity-100">
            <X className="size-3.5" />
          </button>
        </div>
      ))}
      <div className="flex items-center gap-2 rounded-xl border border-dashed px-3.5 py-1 focus-within:border-[var(--bot)]">
        <Plus className="size-3.5 text-muted-foreground" />
        <input value={v} onChange={(e) => setV(e.target.value)} onKeyDown={(e) => e.key === "Enter" && add()} placeholder={placeholder} className="h-8 w-full bg-transparent text-sm outline-none placeholder:text-muted-foreground" />
      </div>
    </div>
  )
}

// ── знак: любая иконка lucide и любой цвет ──

const iconGroups: Record<string, string[]> = {
  Работа: ["Briefcase", "Calendar", "ClipboardList", "Inbox", "Mail", "Clock", "Target", "ListChecks", "Kanban", "Presentation", "Timer", "Sunrise", "Coffee", "Rocket", "Flag", "Trophy"],
  Код: ["Code", "CodeXml", "Terminal", "Bug", "GitBranch", "GitPullRequest", "Braces", "Cpu", "Database", "Server", "Cloud", "Boxes", "Blocks", "Wrench", "Cog", "Binary"],
  Дизайн: ["Palette", "Brush", "PenTool", "Shapes", "Layers", "Frame", "Pipette", "SwatchBook", "Image", "Crop", "WandSparkles", "Sparkles", "Component", "LayoutGrid", "Type", "Figma"],
  Тексты: ["PenLine", "Feather", "BookOpen", "Notebook", "FileText", "Quote", "Languages", "Newspaper", "NotebookPen", "Highlighter", "Pilcrow", "MessageSquareText", "ScrollText", "Library", "Bookmark", "Captions"],
  Наука: ["FlaskConical", "Microscope", "Atom", "Dna", "Telescope", "Brain", "Calculator", "Sigma", "ChartLine", "ChartPie", "Orbit", "TestTube", "Beaker", "Radar", "Satellite", "Lightbulb"],
  Жизнь: ["House", "Hammer", "Paintbrush", "Sofa", "Lamp", "Utensils", "ShoppingCart", "Car", "Plane", "Fish", "Leaf", "Dumbbell", "Heart", "Music", "Gamepad2", "Camera"],
  Люди: ["User", "Users", "UserCheck", "Smile", "Baby", "HandHeart", "Handshake", "MessagesSquare", "Megaphone", "Headphones", "Mic", "Phone", "GraduationCap", "School", "Crown", "Ghost"],
  Разное: ["Bot", "Shield", "ShieldCheck", "Lock", "Key", "Zap", "Flame", "Star", "Moon", "Sun", "Globe", "Compass", "Map", "Anchor", "Gem", "Puzzle"],
}

function IconPicker({ value, hue, chroma, onChange }: { value: string; hue: number; chroma?: number; onChange: (v: string) => void }) {
  const [q, setQ] = useState("")
  const [group, setGroup] = useState("Работа")
  const names = useMemo(() => {
    if (q.trim()) {
      const s = q.trim().toLowerCase()
      return Object.keys(allIcons)
        .filter((n) => n.toLowerCase().includes(s))
        .slice(0, 160)
    }
    return iconGroups[group].filter((n) => allIcons[n])
  }, [q, group])
  const total = Object.keys(allIcons).length
  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button variant="outline" size="sm">
          Сменить значок
        </Button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-[400px] p-0">
        <div className="border-b p-2.5">
          <label className="flex h-9 items-center gap-2 rounded-lg bg-input/40 px-2.5">
            <Search className="size-4 text-muted-foreground" />
            <input autoFocus value={q} onChange={(e) => setQ(e.target.value)} placeholder={`Поиск среди ${total} значков (по-английски)`} className="w-full bg-transparent text-sm outline-none" />
          </label>
          {!q && (
            <div className="mt-2 flex flex-wrap gap-1">
              {Object.keys(iconGroups).map((g) => (
                <button key={g} onClick={() => setGroup(g)} className={cn("rounded-full px-2.5 py-0.5 text-xs", g === group ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground")}>
                  {g}
                </button>
              ))}
            </div>
          )}
        </div>
        <div className="grid max-h-64 grid-cols-8 gap-1 overflow-auto p-2.5">
          {names.map((n) => {
            const I = allIcons[n]
            return (
              <button
                key={n}
                onClick={() => onChange(n)}
                title={n}
                className={cn("flex aspect-square items-center justify-center rounded-lg hover:bg-foreground/10", n === value && "ring-2 ring-[var(--bot)]")}
                style={n === value ? { color: botColor(hue, chroma) } : undefined}
              >
                <I className="size-[18px]" />
              </button>
            )
          })}
          {names.length === 0 && <p className="col-span-8 py-6 text-center text-xs text-muted-foreground">Ничего не нашлось</p>}
        </div>
      </PopoverContent>
    </Popover>
  )
}

const swatches = [25, 45, 70, 95, 130, 160, 185, 205, 235, 265, 290, 320]

function ColorPicker({ hue, chroma, onChange }: { hue: number; chroma: number; onChange: (hue: number, chroma: number) => void }) {
  return (
    <div>
      <div className="flex flex-wrap items-center gap-1.5">
        {swatches.map((h) => (
          <button
            key={h}
            onClick={() => onChange(h, 0.13)}
            aria-label={`Цвет ${h}`}
            className={cn("size-6 rounded-full ring-offset-2 ring-offset-background transition-transform hover:scale-110", hue === h && chroma > 0.01 && "ring-2 ring-foreground/70")}
            style={{ background: botColor(h, 0.14, 0.72) }}
          />
        ))}
        <button onClick={() => onChange(hue, 0)} aria-label="Серый" className={cn("size-6 rounded-full ring-offset-2 ring-offset-background", chroma < 0.01 && "ring-2 ring-foreground/70")} style={{ background: botColor(0, 0, 0.72) }} />
        <Popover>
          <PopoverTrigger asChild>
            <button aria-label="Свой цвет" className="size-6 rounded-full ring-offset-2 ring-offset-background" style={{ background: "conic-gradient(from 0deg, oklch(0.75 0.14 0), oklch(0.75 0.14 90), oklch(0.75 0.14 180), oklch(0.75 0.14 270), oklch(0.75 0.14 360))" }} />
          </PopoverTrigger>
          <PopoverContent align="start" className="w-72 space-y-4">
            <p className="text-sm font-medium">Свой цвет</p>
            <div className="h-10 rounded-xl" style={{ background: botColor(hue, chroma, 0.72) }} />
            <label className="block text-xs text-muted-foreground">
              Оттенок
              <input
                type="range"
                min={0}
                max={360}
                value={hue}
                onChange={(e) => onChange(Number(e.target.value), chroma)}
                className="mt-1.5 h-2 w-full cursor-pointer appearance-none rounded-full"
                style={{ background: "linear-gradient(90deg, oklch(0.72 0.14 0), oklch(0.72 0.14 60), oklch(0.72 0.14 120), oklch(0.72 0.14 180), oklch(0.72 0.14 240), oklch(0.72 0.14 300), oklch(0.72 0.14 360))" }}
              />
            </label>
            <label className="block text-xs text-muted-foreground">
              Насыщенность
              <input
                type="range"
                min={0}
                max={20}
                value={Math.round(chroma * 100)}
                onChange={(e) => onChange(hue, Number(e.target.value) / 100)}
                className="mt-1.5 h-2 w-full cursor-pointer appearance-none rounded-full"
                style={{ background: `linear-gradient(90deg, ${botColor(hue, 0, 0.72)}, ${botColor(hue, 0.2, 0.72)})` }}
              />
            </label>
          </PopoverContent>
        </Popover>
      </div>
    </div>
  )
}

// ── каталог навыков ──

function SkillCard({ skill, added, onAdd, compact }: { skill: HubSkill; added: boolean; onAdd: () => void; compact?: boolean }) {
  return (
    <div className={cn("flex flex-col rounded-xl border bg-card/40 p-3.5 transition-colors", added && "border-[var(--bot-soft)] bg-[var(--bot-faint)]")}>
      <div className="flex items-start gap-2">
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium">{skill.name}</p>
          <p className="truncate text-[11px] text-muted-foreground">
            {skill.author} · {skill.source}
          </p>
        </div>
        {skill.installed && <span className="shrink-0 rounded-md bg-foreground/[0.07] px-1.5 py-0.5 text-[10px] text-muted-foreground">уже в Lumen</span>}
      </div>
      <p className={cn("mt-1.5 text-xs leading-relaxed text-foreground/75", compact && "line-clamp-1")}>{skill.note}</p>
      <div className="mt-auto flex items-center gap-3 pt-3 text-[11px] whitespace-nowrap text-muted-foreground">
        <span className="flex items-center gap-1">
          <Star className="size-3" /> {fmtNum(skill.stars)}
        </span>
        <span className="flex items-center gap-1">
          <Download className="size-3" /> {fmtNum(skill.downloads)}
        </span>
        {!compact && <span>{skill.sizeMb < 1 ? `${Math.round(skill.sizeMb * 1000)} КБ` : `${skill.sizeMb.toLocaleString("ru")} МБ`}</span>}
        <Button size="xs" variant={added ? "secondary" : "outline"} className="ml-auto" onClick={onAdd}>
          {added ? (
            <>
              <Check /> Добавлен
            </>
          ) : (
            <>
              <Plus /> Добавить
            </>
          )}
        </Button>
      </div>
    </div>
  )
}

function SkillHub({ open, onClose, chosen, onToggle }: { open: boolean; onClose: () => void; chosen: string[]; onToggle: (id: string) => void }) {
  const [q, setQ] = useState("")
  const [cat, setCat] = useState("Все")
  const [sort, setSort] = useState<"stars" | "downloads">("stars")
  const list = hub
    .filter((h) => cat === "Все" || h.category === cat)
    .filter((h) => !q || (h.name + h.note + h.author).toLowerCase().includes(q.toLowerCase()))
    .sort((a, b) => b[sort] - a[sort])
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="flex max-h-[85vh] flex-col gap-0 p-0 sm:max-w-4xl">
        <DialogHeader className="border-b p-5 pb-4">
          <DialogTitle className="flex items-center gap-2">
            <Library className="size-4 text-[var(--bot)]" /> Каталог навыков
          </DialogTitle>
          <DialogDescription>Навыки из agentskills.io, GitHub и Hugging Face. Выбранные бот скачает сам после создания.</DialogDescription>
          <div className="mt-3 flex flex-wrap items-center gap-2">
            <label className="flex h-9 min-w-60 flex-1 items-center gap-2 rounded-lg border bg-input/30 px-2.5">
              <Search className="size-4 text-muted-foreground" />
              <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Найти навык" className="w-full bg-transparent text-sm outline-none" />
            </label>
            <Segmented
              value={sort}
              onChange={setSort}
              options={[
                { id: "stars", name: "Популярные" },
                { id: "downloads", name: "Скачивают" },
              ]}
            />
          </div>
          <div className="mt-2 flex flex-wrap gap-1">
            {hubCategories.map((c) => (
              <button key={c} onClick={() => setCat(c)} className={cn("rounded-full px-2.5 py-1 text-xs", c === cat ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground")}>
                {c}
              </button>
            ))}
          </div>
        </DialogHeader>
        <div className="grid min-h-0 flex-1 gap-2.5 overflow-auto p-5 sm:grid-cols-2 lg:grid-cols-3">
          {list.map((h) => (
            <SkillCard key={h.id} skill={h} added={chosen.includes(h.id)} onAdd={() => onToggle(h.id)} />
          ))}
          {list.length === 0 && <p className="col-span-full py-10 text-center text-sm text-muted-foreground">Ничего не нашлось</p>}
        </div>
        <div className="flex items-center border-t px-5 py-3 text-sm">
          <span className="text-muted-foreground">Выбрано: {chosen.length}</span>
          <Button className="ml-auto bg-[var(--bot)] text-black hover:opacity-85" onClick={onClose}>
            Готово
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// ── бот настраивается сам ──

type SetupStep = { text: string; sub?: string; sizeMb?: number; skip?: boolean }

function Setup({ bot, onDone }: { bot: BotDef; onDone: () => void }) {
  const skills = hub.filter((h) => bot.hubSkills?.includes(h.id))
  const allowed = bot.tools.length
  const plan: SetupStep[] = [
    { text: "Создаю рабочую папку", sub: `~/Library/Application Support/Lumen/bots/${bot.id}` },
    { text: "Записываю роль и инструкции", sub: "BOT.md — кто я, что считаю готовым, как отчитываюсь" },
    ...skills.map((s) => (s.installed ? { text: `Навык «${s.name}»`, sub: "Уже есть в Lumen — пропускаю", skip: true } : { text: `Скачиваю навык «${s.name}»`, sub: `${s.source} · ${s.author}`, sizeMb: Math.max(s.sizeMb, 0.2) })),
    { text: "Выдаю инструменты", sub: `${allowed} разрешено, ${botTools.length - allowed} отрезано в коде` },
    { text: "Проверяю, что всё на месте", sub: "навыки читаются, доступы работают" },
    { text: "Запоминаю роль", sub: "первая запись в память бота" },
  ]
  const [at, setAt] = useState(0)
  const [progress, setProgress] = useState(0)

  useEffect(() => {
    if (at >= plan.length) return
    const s = plan[at]
    if (s.sizeMb) {
      // имитация скачивания: полоска заполняется, быстрее для маленьких
      const iv = window.setInterval(() => {
        setProgress((p) => {
          const next = p + Math.max(4, 60 / Math.max(s.sizeMb!, 0.5))
          if (next >= 100) {
            window.clearInterval(iv)
            window.setTimeout(() => {
              setProgress(0)
              setAt((a) => a + 1)
            }, 180)
            return 100
          }
          return next
        })
      }, 90)
      return () => window.clearInterval(iv)
    }
    const t = window.setTimeout(() => setAt((a) => a + 1), s.skip ? 450 : 750)
    return () => window.clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [at])

  const finished = at >= plan.length
  const downloads = skills.filter((s) => !s.installed)

  return (
    <div className="relative min-h-0 flex-1 overflow-auto bg-[radial-gradient(800px_500px_at_50%_0%,var(--bot-faint),transparent_70%)]">
      <div className="mx-auto max-w-xl px-6 py-12">
        <div className="flex flex-col items-center text-center">
          <div className="relative">
            <div className={cn("absolute -inset-6 rounded-[40px] bg-[var(--bot-soft)] blur-2xl", !finished && "animate-pulse")} />
            <BotAvatar bot={bot} size={96} className="relative" />
          </div>
          <h2 className="mt-7 text-2xl font-semibold tracking-[-0.02em]">{finished ? `${bot.name} готов` : `${bot.name} настраивается`}</h2>
          <p className="mt-1.5 text-sm text-muted-foreground">
            {finished
              ? `Зови его в любом чате через @${bot.id}.`
              : `Скачивает ${downloads.length} ${downloads.length === 1 ? "навык" : "навыка"}, ${skills.length - downloads.length} уже есть.`}
          </p>
        </div>

        <ol className="mt-9 space-y-1 rounded-2xl border bg-card/50 p-2">
          {plan.map((s, i) => {
            const state = i < at ? "done" : i === at ? "doing" : "todo"
            return (
              <li key={i} className={cn("rounded-xl px-3 py-2.5 transition-colors", state === "doing" && "bg-[var(--bot-faint)]")}>
                <div className="flex items-start gap-3">
                  <span className="mt-0.5">
                    {state === "done" ? (
                      <span className={cn("flex size-[18px] items-center justify-center rounded-full", s.skip ? "bg-foreground/25" : "bg-[var(--bot)]")}>
                        <Check className="size-3 text-black" strokeWidth={3} />
                      </span>
                    ) : state === "doing" ? (
                      <span className="block size-[18px] animate-spin rounded-full border-2 border-foreground/15" style={{ borderTopColor: "var(--bot)" }} />
                    ) : (
                      <span className="block size-[18px] rounded-full border-[1.5px] border-dashed border-foreground/30" />
                    )}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className={cn("block text-sm", state === "todo" && "text-muted-foreground", s.skip && state === "done" && "text-muted-foreground")}>{s.text}</span>
                    {s.sub && <span className="block truncate text-xs text-muted-foreground">{s.sub}</span>}
                    {s.sizeMb && state === "doing" && (
                      <span className="mt-2 flex items-center gap-2">
                        <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-foreground/10">
                          <span className="block h-full rounded-full bg-[var(--bot)] transition-[width] duration-100" style={{ width: `${progress}%` }} />
                        </span>
                        <span className="text-[11px] text-muted-foreground tabular-nums">
                          {((s.sizeMb * progress) / 100).toFixed(1).replace(".", ",")} из {s.sizeMb.toFixed(1).replace(".", ",")} МБ
                        </span>
                      </span>
                    )}
                  </span>
                </div>
              </li>
            )
          })}
        </ol>

        {finished && (
          <div className="mt-6 flex justify-center gap-2">
            <Button className="bg-[var(--bot)] text-black hover:opacity-85" onClick={onDone}>
              Открыть чат бота <ArrowRight />
            </Button>
          </div>
        )}
      </div>
    </div>
  )
}
