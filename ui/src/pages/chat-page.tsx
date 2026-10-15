import {
  ArrowUp,
  Archive,
  AtSign,
  Brain,
  Check,
  ChevronDown,
  ChevronRight,
  Eye,
  FileText,
  Folder,
  GitCommitHorizontal,
  MessageSquare,
  Mic,
  PanelRight,
  Pencil,
  RotateCcw,
  Search,
  Square,
  Undo2,
  X,
  Zap,
} from "lucide-react"
import { useEffect, useRef, useState } from "react"
import { toast } from "sonner"

import { LumenOrb } from "@/components/lumen-orb"
import { EffortPicker, ModelPicker } from "@/components/pickers"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Switch } from "@/components/ui/switch"
import { Textarea } from "@/components/ui/textarea"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { useApp } from "@/lib/app-state"
import { chatGroups, type BotDef, type Memory } from "@/lib/mock-data"
import { cn } from "@/lib/utils"

// Чат как в Claude Code: шаги сворачиваются в строку, ответ — обычным текстом.
// Своё у Люмена: под ответом видно, на какие воспоминания он опирался,
// а когда что-то запомнил — в ленте плашка «Запомнил» с «Изменить» и «Забыть».

type Msg =
  | { id: string; from: "user"; text: string }
  | {
      id: string
      from: "lumen"
      steps?: { summary: string; items: { icon: "eye" | "search" | "brain"; text: string }[] }
      body: React.ReactNode
      used?: string[]
      remembered?: string // id воспоминания
      change?: boolean
      streaming?: boolean
    }

const code = "rounded bg-foreground/[0.07] px-1 py-0.5 font-mono text-[0.8em]"

const scripts: Record<string, Msg[]> = {
  lumen: [
    { id: "u1", from: "user", text: "Напомни, на чём мы остановились с Люменом и что я просил про кнопки?" },
    {
      id: "a1",
      from: "lumen",
      steps: {
        summary: "Вспомнил 3 факта и прочитал запись lumen в ПЛАН.md",
        items: [
          { icon: "brain", text: "Нашёл в памяти: «Lumen: v1 — память…»" },
          { icon: "brain", text: "Нашёл в памяти: «Не двигать кнопки…»" },
          { icon: "eye", text: "Читает ПЛАН.md · запись ## lumen" },
        ],
      },
      body: (
        <>
          <p>
            Остановились на макете первой версии: память между разговорами, понимание, с кем я говорю, и характер ответов.
            Боты в Telegram и других мессенджерах — во второй версии.
          </p>
          <p>
            Про кнопки ты просил одно: когда я внедряю мокап или новую функцию, существующие кнопки остаются на своих местах. Двигаю
            их только по твоей просьбе.
          </p>
          <p>Дальше предлагаю собрать экран памяти и показать тебе. Делаем?</p>
        </>
      ),
      used: ["m9", "m2", "m3"],
    },
    { id: "u2", from: "user", text: "Да. И запомни: светлую тему не делаем, только тёмные." },
    {
      id: "a2",
      from: "lumen",
      body: <p>Понял. Тёмных тем будет две — «Люмен» и «Монохром»; позже добавим свои и готовые наборы. Светлой не будет.</p>,
      remembered: "m12",
    },
  ],
  shelf: [
    { id: "u1", from: "user", text: "Почему Shelf падал 9 октября? Глянь отчёт и скажи, что чинить." },
    {
      id: "a1",
      from: "lumen",
      steps: {
        summary: "Прочитал отчёт о падении и 2 файла, поискал «items[»",
        items: [
          { icon: "eye", text: "Читает Shelf-2026-10-09-235406.ips" },
          { icon: "eye", text: "Читает Sources/ShelfStorage.swift" },
          { icon: "search", text: "Ищет «items[» по проекту" },
          { icon: "eye", text: "Читает Sources/ShelfWindow.swift" },
        ],
      },
      body: (
        <>
          <p>
            Все три падения одинаковые: <code className={code}>EXC_BREAKPOINT</code> в <code className={code}>ShelfStorage.remove(at:)</code>.
            Когда файл удаляют с полки двойным щелчком, индекс берётся из старого списка — после первого удаления он уже за краем.
          </p>
          <pre className="overflow-auto rounded-xl border bg-background/60 p-3 font-mono text-xs leading-relaxed">
            <span className="text-muted-foreground">// ShelfStorage.swift:88</span>
            {"\n"}
            <span className="text-red-400/90">- let item = items[index]</span>
            {"\n"}
            <span className="text-emerald-300/90">+ guard items.indices.contains(index) else {"{ return }"}</span>
            {"\n"}
            <span className="text-emerald-300/90">+ let item = items[index]</span>
          </pre>
          <p>Это чинит падение. Заодно стоит отключать кнопку, пока идёт удаление, — двойной щелчок вообще не дойдёт.</p>
        </>
      ),
      used: ["m5", "m4"],
      change: true,
    },
  ],
  plan: [
    { id: "u1", from: "user", text: "Что поделаем сегодня?" },
    {
      id: "a1",
      from: "lumen",
      steps: { summary: "Запустил tools/status.sh и прочитал ПЛАН.md", items: [{ icon: "eye", text: "Читает ПЛАН.md" }] },
      body: (
        <>
          <p>Свежее всего Lumen и Пульт. У lid-plane 2 коммита не отправлены, у soundcore 8 файлов не закоммичено.</p>
          <p>Предлагаю: Shelf (падение) или тексты для сайта. Что берём?</p>
        </>
      ),
      used: ["m3"],
    },
  ],
  dash: [
    { id: "u1", from: "user", text: "Глянь Пульт перед релизом." },
    { id: "a1", from: "lumen", body: <p>Нашёл три мелочи. Кнопку «Обновить» оставил на месте — ты к ней привык.</p>, used: ["m2"] },
  ],
  blog: [
    { id: "u1", from: "user", text: "Напиши текст для блога про ремонт кухни." },
    { id: "a1", from: "lumen", body: <p>Набросал три абзаца — без цен и без цифр, как ты просил для сайта.</p>, used: ["m6", "m10"] },
  ],
  new: [],
  "bot:coder": [
    { id: "u1", from: "user", text: "Собери Island и глянь, не тормозит ли анимация чёлки." },
    {
      id: "a1",
      from: "lumen",
      steps: {
        summary: "Собрал Island и замерил кадры анимации",
        items: [
          { icon: "eye", text: "Запускает ./build.sh в Мак-приложения/island" },
          { icon: "search", text: "Ищет CABasicAnimation в IslandView.swift" },
        ],
      },
      body: (
        <>
          <p>Собралось без ошибок. Анимация держит 120 кадров; один раз проседает до 90, когда остров раскрывается и сразу приходит уведомление.</p>
          <p>Это та же история, что в начале октября, — тень не успевает за островом. Поправить так же, как тогда?</p>
        </>
      ),
      used: ["m4"],
    },
  ],
  "bot:site": [
    { id: "u1", from: "user", text: "Нужен короткий текст про ремонт ванной для блога." },
    { id: "a1", from: "lumen", body: <p>Набросал три абзаца без цен и цифр. Выложу в ветку preview — на прод только после твоего OK.</p>, used: ["m6", "m10"] },
  ],
  "bot:morning": [
    {
      id: "a1",
      from: "lumen",
      body: (
        <>
          <p>Доброе утро. Что изменилось за ночь:</p>
          <p>Lumen — новый макет готов, ждёт твоего взгляда. У lid-plane 2 коммита не отправлены. У soundcore 8 файлов не закоммичено уже 3 дня.</p>
          <p>Ждут решения: репозиторий для Lumen на GitHub, сайт FlowLocal.</p>
        </>
      ),
      used: ["m3"],
    },
  ],
}

export function ChatPage({ chatId, bot }: { chatId: string; bot?: BotDef }) {
  const app = useApp()
  const [messages, setMessages] = useState<Msg[]>(scripts[chatId] ?? [])
  const [draft, setDraft] = useState("")
  const [model, setModel] = useState("opus")
  const [effort, setEffort] = useState("high")
  const [mode, setMode] = useState("agent")
  const busy = app.orb === "thinking" || app.orb === "writing"
  const scroller = useRef<HTMLDivElement>(null)
  const timers = useRef<number[]>([])

  const title = bot?.name ?? chatGroups.flatMap((g) => g.items).find((c) => c.id === chatId)?.title ?? "Новый чат"
  const project = bot?.project ?? chatGroups.flatMap((g) => g.items).find((c) => c.id === chatId)?.project ?? "prog"
  const [compactions, setCompactions] = useState(bot?.compactions ?? [])

  // при смене чата страница пересоздаётся (key в App), здесь только подсветка памяти
  useEffect(() => {
    const last = [...(scripts[chatId] ?? [])].reverse().find((m) => m.from === "lumen" && !!m.used?.length)
    app.showMemories(last && last.from === "lumen" ? (last.used ?? []) : [])
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chatId])

  useEffect(() => {
    scroller.current?.scrollTo({ top: scroller.current.scrollHeight, behavior: "smooth" })
  }, [messages])

  useEffect(() => () => timers.current.forEach(clearTimeout), [])

  const later = (fn: () => void, ms: number) => timers.current.push(window.setTimeout(fn, ms))

  /// Демо живого ответа: думает → пишет по словам → (если просили запомнить) вспышка и плашка
  function send(text = draft) {
    const t = text.trim()
    if (!t || busy) return
    setDraft("")
    const uid = `u${Date.now()}`
    const aid = `a${Date.now()}`
    setMessages((m) => [...m, { id: uid, from: "user", text: t }])
    app.setOrb("thinking")

    const wantsMemory = /запомни/i.test(t)
    const fact = t.replace(/^.*?запомни[,:]?\s*/i, "").replace(/^что\s+/i, "")
    const pinned = app.memories.filter((m) => m.pinned && m.profile === app.activeProfile)
    const who = app.profiles.find((p) => p.id === app.activeProfile)
    const reply = wantsMemory
      ? `Запомнил. Буду учитывать это в следующих разговорах — и здесь, и в других чатах.`
      : `${who?.address === "vy" ? "Хорошо, " + who.call + "." : "Понял."} Это макет — настоящий ответ придёт, когда подключим Claude. Сейчас я бы опирался на то, что знаю: ${pinned
          .slice(0, 2)
          .map((m) => m.text.charAt(0).toLowerCase() + m.text.slice(1))
          .join("; ")}.`
    const used = wantsMemory ? [] : pinned.slice(0, 2).map((m) => m.id)

    later(() => {
      app.setOrb("writing")
      const words = reply.split(" ")
      let i = 0
      setMessages((m) => [...m, { id: aid, from: "lumen", body: "", streaming: true, used }])
      const tick = () => {
        i += 2
        const done = i >= words.length
        setMessages((m) =>
          m.map((x) => (x.id === aid && x.from === "lumen" ? { ...x, body: <p>{words.slice(0, i).join(" ")}</p>, streaming: !done } : x))
        )
        if (!done) return later(tick, 70)
        app.showMemories(used)
        if (wantsMemory && fact) {
          const id = `m${Date.now()}`
          const memory: Memory = { id, text: fact.charAt(0).toUpperCase() + fact.slice(1), kind: "pref", source: title, when: "сейчас", profile: app.activeProfile }
          app.setMemories((ms) => [memory, ...ms])
          setMessages((m) => m.map((x) => (x.id === aid && x.from === "lumen" ? { ...x, remembered: id } : x)))
          app.setOrb("remember")
          later(() => app.setOrb("idle"), 1200)
        } else {
          app.setOrb("idle")
        }
      }
      later(tick, 60)
    }, 1300)
  }

  function stop() {
    timers.current.forEach(clearTimeout)
    timers.current = []
    setMessages((m) => m.map((x) => (x.from === "lumen" ? { ...x, streaming: false } : x)))
    app.setOrb("idle")
  }

  return (
    <div className={cn("relative grid h-full grid-cols-1", app.contextOpen && "xl:grid-cols-[minmax(0,1fr)_320px]")}>
      <section className="flex min-h-0 flex-col">
        <header className="flex h-14 shrink-0 items-center gap-2 border-b px-5">
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium">{title}</p>
            <p className="truncate text-xs text-muted-foreground">
              {bot
                ? `Бот: ${bot.task.charAt(0).toLowerCase() + bot.task.slice(1)}`
                : messages.length
                  ? `${messages.length} сообщений`
                  : "пока пусто"}
            </p>
          </div>
          <div className="ml-auto flex shrink-0 items-center gap-2 [&_button]:whitespace-nowrap">
            <ProfilePill />
            {bot ? (
              <span className="flex h-8 items-center gap-1.5 rounded-lg border px-2.5 text-sm text-muted-foreground" title="Проект бота задаётся при создании">
                <Folder className="size-4" /> {project}
              </span>
            ) : (
              <Button variant="outline" size="sm" className="h-8" onClick={() => toast("Выбор проекта", { description: "В приложении здесь будет список проектов prog." })}>
                <Folder /> {project} <ChevronDown className="opacity-50" />
              </Button>
            )}
            <ToggleGroup
              type="single"
              variant="outline"
              size="sm"
              value={mode}
              onValueChange={(v) => v && setMode(v)}
              className="[&_[data-state=on]]:bg-foreground [&_[data-state=on]]:text-background"
            >
              <ToggleGroupItem value="chat" title="Только отвечает и читает — ничего не меняет">
                <MessageSquare /> Чат
              </ToggleGroupItem>
              <ToggleGroupItem value="agent" title="Правит файлы и запускает сборку; push и выкатка — только с твоего OK">
                <Zap /> Агент
              </ToggleGroupItem>
            </ToggleGroup>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button variant={app.contextOpen ? "secondary" : "ghost"} size="icon-sm" onClick={() => app.setContextOpen(!app.contextOpen)}>
                  <PanelRight />
                </Button>
              </TooltipTrigger>
              <TooltipContent>Контекст: с кем говорю, память, расход</TooltipContent>
            </Tooltip>
          </div>
        </header>

        <div ref={scroller} className="min-h-0 flex-1 overflow-auto">
          {messages.length === 0 && !bot ? (
            <Empty onPick={(t) => setDraft(t)} />
          ) : (
            <div className="mx-auto flex max-w-[44rem] flex-col gap-7 px-6 py-8">
              {bot && <BotHistory bot={bot} compactions={compactions} />}
              {messages.map((m) => (m.from === "user" ? <UserMsg key={m.id}>{m.text}</UserMsg> : <LumenMsg key={m.id} msg={m} />))}
              {app.orb === "thinking" && (
                <div className="flex items-center gap-3 text-sm text-muted-foreground">
                  <LumenOrb state="thinking" size={22} />
                  <span>Вспоминает и думает…</span>
                </div>
              )}
            </div>
          )}
        </div>

        <div className="relative px-5 pt-1 pb-5">
          <div className="pointer-events-none absolute inset-x-0 -top-10 h-10 bg-gradient-to-t from-background to-transparent" />
          <div className="glow-field mx-auto max-w-[44rem] rounded-2xl border bg-card/60 p-3 backdrop-blur">
            <div className="mb-2 flex flex-wrap items-center gap-1.5">
              <Chip icon={Folder}>{project}</Chip>
              <Chip icon={FileText}>ПЛАН.md</Chip>
              <Chip icon={Brain}>память</Chip>
              <button
                onClick={() => setDraft((d) => d + "@")}
                className="flex h-6 items-center gap-1 rounded-md px-1.5 text-xs text-muted-foreground hover:text-foreground"
              >
                <AtSign className="size-3" /> добавить
              </button>
            </div>
            <Textarea
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault()
                  send()
                }
              }}
              placeholder={bot ? `Напиши боту «${bot.name}». Это всегда один и тот же разговор` : "Спроси или дай задачу. «Запомни, что…» — и Lumen запомнит"}
              className="min-h-14 resize-none border-0 bg-transparent p-0 text-sm shadow-none focus-visible:ring-0 dark:bg-transparent"
            />
            <div className="mt-2 flex items-center gap-1">
              <ModelPicker value={model} onChange={setModel} />
              <EffortPicker value={effort} onChange={setEffort} />
              <BackendBadge />
              <div className="ml-auto flex items-center gap-1">
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button variant="ghost" size="icon-sm" onClick={() => toast("Голосом", { description: "Держи правый ⌥ — FlowLocal расшифрует речь." })}>
                      <Mic />
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent>Голосом — держи правый ⌥</TooltipContent>
                </Tooltip>
                {busy ? (
                  <Button size="sm" variant="secondary" className="h-8" onClick={stop}>
                    <Square className="fill-current" /> Остановить
                  </Button>
                ) : (
                  <Button
                    size="icon-sm"
                    className="rounded-full bg-glow text-black shadow-[0_0_16px_var(--glow-soft)] hover:bg-glow/85"
                    disabled={!draft.trim()}
                    onClick={() => send()}
                    aria-label="Отправить"
                  >
                    <ArrowUp />
                  </Button>
                )}
              </div>
            </div>
          </div>
        </div>
      </section>

      {app.contextOpen && (
        <ContextPanel
          bot={bot}
          compactions={compactions.length}
          onCompact={() => {
            setCompactions((c) => [...c, { when: "сейчас", from: 42, summary: "Свежий кусок разговора пересказан; договорённости ушли в память." }])
            setMessages((m) => m.slice(-2))
            toast("Разговор сжат", { description: "42 сообщения → пересказ. Важное сохранено в память." })
          }}
        />
      )}
    </div>
  )
}

/// Начало единственного чата бота: старые куски разговора уже сжаты в пересказы
function BotHistory({ bot, compactions }: { bot: BotDef; compactions: BotDef["compactions"] }) {
  const [open, setOpen] = useState<number | null>(null)
  return (
    <div className="space-y-2">
      <div className="flex items-center gap-3 pb-2">
        <span className="h-px flex-1 bg-border" />
        <span className="text-xs text-muted-foreground">
          {bot.messages ? `один чат с начала, ${bot.messages.toLocaleString("ru")} сообщений` : "новый бот — его чат начинается здесь и не закончится"}
        </span>
        <span className="h-px flex-1 bg-border" />
      </div>
      {compactions.map((c, i) => (
        <button
          key={c.when + i}
          onClick={() => setOpen(open === i ? null : i)}
          className="block w-full rounded-xl border border-dashed px-3.5 py-2.5 text-left hover:border-glow/30"
        >
          <span className="flex items-center gap-2 text-xs text-muted-foreground">
            <Archive className="size-3.5" /> Сжато: {c.when}, {c.from} сообщений → пересказ
            <ChevronDown className={cn("ml-auto size-3.5 transition-transform", open === i && "rotate-180")} />
          </span>
          {open === i && <span className="mt-2 block text-sm leading-relaxed text-foreground/85">{c.summary}</span>}
        </button>
      ))}
    </div>
  )
}

function Empty({ onPick }: { onPick: (t: string) => void }) {
  const app = useApp()
  const who = app.profiles.find((p) => p.id === app.activeProfile)
  const ideas =
    who?.id === "roma"
      ? ["Продолжим Lumen: экран памяти", "Проверь, не падает ли Shelf", "Что поделаем сегодня?", "Запомни, что я встаю в 9"]
      : ["Что нового на сайте?", "Напишите текст для блога", "Запомни, что я люблю короткие тексты"]
  return (
    <div className="mx-auto flex h-full max-w-[44rem] flex-col items-center justify-center px-6 text-center">
      <LumenOrb state={app.orb} size={72} />
      <h2 className="mt-8 text-2xl font-semibold tracking-[-0.02em]">
        {who?.address === "vy" ? `Здравствуйте, ${who.call}.` : `Привет, ${who?.call}.`} Что делаем?
      </h2>
      <p className="mt-2 text-sm text-muted-foreground">
        Помню {facts(app.memories.filter((m) => m.profile === app.activeProfile).length)} о {who?.address === "vy" ? "вас" : "тебе и проектах"}.
      </p>
      <div className="mt-6 flex flex-wrap justify-center gap-2">
        {ideas.map((i) => (
          <button key={i} onClick={() => onPick(i)} className="rounded-full border bg-card/50 px-3.5 py-1.5 text-sm hover:border-glow/40 hover:bg-card">
            {i}
          </button>
        ))}
      </div>
    </div>
  )
}

function facts(n: number) {
  const tail = n % 10 === 1 && n % 100 !== 11 ? "факт" : [2, 3, 4].includes(n % 10) && ![12, 13, 14].includes(n % 100) ? "факта" : "фактов"
  return `${n} ${tail}`
}

function UserMsg({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex justify-end">
      <div className="max-w-[80%] rounded-2xl rounded-br-md bg-secondary px-4 py-2.5 text-sm leading-relaxed">{children}</div>
    </div>
  )
}

const stepIcon = { eye: Eye, search: Search, brain: Brain }

function LumenMsg({ msg }: { msg: Extract<Msg, { from: "lumen" }> }) {
  const app = useApp()
  const [open, setOpen] = useState(false)
  return (
    <div className="flex gap-3.5">
      <LumenOrb state={msg.streaming ? "writing" : "idle"} size={22} className="mt-0.5" />
      <div className="min-w-0 flex-1 space-y-3">
        {msg.steps && (
          <>
            <button
              onClick={() => setOpen((o) => !o)}
              className="flex items-center gap-2 rounded-lg px-0 py-0.5 text-xs text-muted-foreground hover:text-foreground"
            >
              {open ? <ChevronDown className="size-3.5" /> : <ChevronRight className="size-3.5" />}
              {msg.steps.summary}
              <span className="text-foreground/40">{msg.steps.items.length} шага</span>
            </button>
            {open && (
              <div className="space-y-1.5 border-l pl-3 text-xs text-muted-foreground">
                {msg.steps.items.map((s) => {
                  const I = stepIcon[s.icon]
                  return (
                    <p key={s.text} className="flex items-center gap-2">
                      <I className="size-3.5" /> {s.text}
                    </p>
                  )
                })}
              </div>
            )}
          </>
        )}
        <div className={cn("space-y-3 text-[0.9375rem] leading-[1.65]", msg.streaming && "[&>p:last-child]:caret")}>{msg.body}</div>
        {msg.change && <ChangeCard />}
        {msg.remembered && <Remembered id={msg.remembered} />}
        {!msg.streaming && msg.used && msg.used.length > 0 && (
          <button
            onClick={() => app.showMemories(msg.used!)}
            className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-glow"
          >
            <Brain className="size-3.5" />
            Опирался на {msg.used.length} {msg.used.length === 1 ? "воспоминание" : msg.used.length < 5 ? "воспоминания" : "воспоминаний"}
          </button>
        )}
      </div>
    </div>
  )
}

/// Плашка «Запомнил»: что именно, и сразу можно изменить или забыть
function Remembered({ id }: { id: string }) {
  const app = useApp()
  const memory = app.memories.find((m) => m.id === id)
  const [editing, setEditing] = useState(false)
  const [text, setText] = useState(memory?.text ?? "")
  const [forgotten, setForgotten] = useState<Memory | null>(null)

  if (!memory && forgotten) {
    return (
      <div className="flex items-center gap-2 rounded-xl border border-dashed px-3 py-2 text-xs text-muted-foreground">
        <X className="size-3.5" /> Забыл: <span className="line-through">{forgotten.text}</span>
        <button
          onClick={() => {
            app.setMemories((ms) => [forgotten, ...ms])
            setForgotten(null)
          }}
          className="ml-auto flex items-center gap-1 text-foreground hover:text-glow"
        >
          <Undo2 className="size-3.5" /> Вернуть
        </button>
      </div>
    )
  }
  if (!memory) return null

  return (
    <div className="shine flex items-start gap-3 rounded-xl border border-glow/25 bg-glow/[0.04] px-3 py-2.5">
      <Brain className="mt-0.5 size-4 shrink-0 text-glow" />
      <div className="min-w-0 flex-1">
        <p className="text-xs text-muted-foreground">Запомнил</p>
        {editing ? (
          <input
            autoFocus
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                app.setMemories((ms) => ms.map((m) => (m.id === id ? { ...m, text } : m)))
                setEditing(false)
              }
              if (e.key === "Escape") setEditing(false)
            }}
            className="mt-0.5 w-full rounded-md border bg-background/60 px-2 py-1 text-sm outline-none focus:border-glow/50"
          />
        ) : (
          <p className="mt-0.5 text-sm">{memory.text}</p>
        )}
      </div>
      <div className="flex shrink-0 items-center gap-1">
        {editing ? (
          <Button
            size="xs"
            onClick={() => {
              app.setMemories((ms) => ms.map((m) => (m.id === id ? { ...m, text } : m)))
              setEditing(false)
            }}
          >
            <Check /> Сохранить
          </Button>
        ) : (
          <Button size="xs" variant="ghost" onClick={() => setEditing(true)}>
            <Pencil /> Изменить
          </Button>
        )}
        <Button
          size="xs"
          variant="ghost"
          onClick={() => {
            setForgotten(memory)
            app.setMemories((ms) => ms.filter((m) => m.id !== id))
          }}
        >
          <X /> Забыть
        </Button>
      </div>
    </div>
  )
}

function ChangeCard() {
  const [state, setState] = useState<"applied" | "committed" | "reverted">("applied")
  return (
    <Card size="sm" className="gap-0 py-0">
      <div className="flex items-center gap-2 border-b px-3 py-2">
        <GitCommitHorizontal className="size-4 text-muted-foreground" />
        <span className="text-sm font-medium">Изменения</span>
        <span className="text-xs text-muted-foreground">1 файл, +2 −1</span>
        <Badge variant="outline" className="ml-auto rounded-md font-normal">
          {state === "applied" ? "применено" : state === "committed" ? "закоммичено" : "откачено"}
        </Badge>
      </div>
      <div className="flex items-center gap-2 px-3 py-2 font-mono text-xs">
        <span className="text-muted-foreground">M</span> Sources/ShelfStorage.swift
        <span className="ml-auto text-emerald-300/90">+2</span>
        <span className="text-red-400/90">−1</span>
      </div>
      <div className="flex items-center gap-2 border-t px-3 py-2">
        <Button size="sm" variant="ghost" className="h-7 text-xs" disabled={state !== "applied"} onClick={() => setState("reverted")}>
          <RotateCcw /> Откатить
        </Button>
        <Button size="sm" variant="outline" className="ml-auto h-7 text-xs" onClick={() => toast("Разница", { description: "Откроется сравнение файла до и после." })}>
          <Eye /> Разница
        </Button>
        <Button size="sm" className="h-7 text-xs" disabled={state !== "applied"} onClick={() => setState("committed")}>
          <GitCommitHorizontal /> Закоммитить
        </Button>
      </div>
    </Card>
  )
}

function Chip({ icon: Icon, children }: { icon: React.ComponentType<{ className?: string }>; children: React.ReactNode }) {
  const [gone, setGone] = useState(false)
  if (gone) return null
  return (
    <span className="flex h-6 items-center gap-1 rounded-md border bg-muted/40 px-1.5 text-xs">
      <Icon className="size-3 text-muted-foreground" />
      {children}
      <button onClick={() => setGone(true)} aria-label="Убрать из контекста" className="text-muted-foreground hover:text-foreground">
        <X className="size-3" />
      </button>
    </span>
  )
}

/// Через что идёт ответ: подписка, API или «сам решит»
function BackendBadge() {
  const app = useApp()
  const names = { subscription: "подписка", api: "API", auto: "авто" }
  return (
    <Popover>
      <PopoverTrigger asChild>
        <button className="flex h-7 items-center gap-1 rounded-lg px-2 text-xs whitespace-nowrap text-muted-foreground hover:bg-foreground/5 hover:text-foreground">
          через {names[app.backend]} <ChevronDown className="size-3 opacity-50" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" side="top" className="w-72 p-1.5">
        <p className="px-2 pt-1 pb-2 text-xs text-muted-foreground">Через что отвечать</p>
        {(
          [
            ["subscription", "Подписка Claude Code", "входит в тариф, есть лимит на 5 часов"],
            ["api", "Anthropic API", "по ключу, оплата за токены"],
            ["auto", "Авто", "подписка, а у лимита — API"],
          ] as const
        ).map(([id, name, note]) => (
          <button
            key={id}
            onClick={() => app.setBackend(id)}
            className={cn("flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left hover:bg-muted/60", app.backend === id && "bg-muted")}
          >
            <span className="min-w-0 flex-1">
              <span className="block text-sm font-medium">{name}</span>
              <span className="block text-xs text-muted-foreground">{note}</span>
            </span>
            {app.backend === id && <Check className="size-4 text-glow" />}
          </button>
        ))}
        <button onClick={() => app.go("connections")} className="mt-1 w-full rounded-lg px-2 py-1.5 text-left text-xs text-muted-foreground hover:text-foreground">
          Настроить подключения
        </button>
      </PopoverContent>
    </Popover>
  )
}

function ProfilePill() {
  const app = useApp()
  const current = app.profiles.find((p) => p.id === app.activeProfile)
  return (
    <Popover>
      <PopoverTrigger asChild>
        <button className="flex h-8 items-center gap-2 rounded-lg border bg-input/30 pr-2 pl-1 text-sm hover:bg-input/50">
          <span className="flex size-6 items-center justify-center rounded-md bg-foreground/10 text-xs">{current?.name[0]}</span>
          {current?.name}
          <ChevronDown className="size-3.5 opacity-50" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-72 p-1.5">
        <p className="px-2 pt-1 pb-2 text-xs text-muted-foreground">С кем говорит Lumen</p>
        {app.profiles.map((p) => (
          <button
            key={p.id}
            onClick={() => app.setActiveProfile(p.id)}
            className={cn("flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left hover:bg-muted/60", p.id === app.activeProfile && "bg-muted")}
          >
            <span className="flex size-7 items-center justify-center rounded-full bg-foreground/10 text-xs">{p.name[0]}</span>
            <span className="min-w-0 flex-1">
              <span className="block text-sm font-medium">{p.name}</span>
              <span className="block truncate text-xs text-muted-foreground">{p.role}</span>
            </span>
            {p.id === app.activeProfile && <Check className="size-4 text-glow" />}
          </button>
        ))}
        <button onClick={() => app.go("people")} className="mt-1 w-full rounded-lg px-2 py-1.5 text-left text-xs text-muted-foreground hover:text-foreground">
          Все профили
        </button>
      </PopoverContent>
    </Popover>
  )
}

// ── правая панель: одна спокойная колонка ──

function Side({ title, action, children }: { title: string; action?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="border-b px-4 py-4 last:border-b-0">
      <div className="mb-3 flex items-center justify-between">
        <p className="text-[13px] font-medium text-foreground/90">{title}</p>
        {action}
      </div>
      {children}
    </section>
  )
}

function SideLink({ onClick, children }: { onClick: () => void; children: React.ReactNode }) {
  return (
    <button onClick={onClick} className="text-xs text-muted-foreground hover:text-glow">
      {children}
    </button>
  )
}

function ContextPanel({ bot, compactions, onCompact }: { bot?: BotDef; compactions: number; onCompact: () => void }) {
  const app = useApp()
  const [autoCompact, setAutoCompact] = useState(true)
  const who = app.profiles.find((p) => p.id === app.activeProfile)!
  const used = app.focusMemories.map((id) => app.memories.find((m) => m.id === id)).filter(Boolean) as Memory[]
  const tone = { warm: "тепло", plain: "ровно", formal: "официально" }[who.tone]
  const persona = app.persona
  return (
    // на узком окне панель выезжает поверх чата, на широком стоит колонкой
    <aside className="absolute inset-y-0 right-0 z-20 flex w-80 min-h-0 flex-col overflow-auto border-l bg-sidebar shadow-2xl xl:static xl:w-auto xl:bg-sidebar/50 xl:shadow-none">
      {bot && (
        <Side title="Один чат">
          <p className="text-xs leading-relaxed text-muted-foreground">
            У бота нет новых чатов. Когда разговор подходит к краю окна, Lumen пересказывает старое, а договорённости кладёт в память.
          </p>
          <p className="mt-3 text-sm tabular-nums">
            Сжат {compactions} {compactions === 1 ? "раз" : compactions > 1 && compactions < 5 ? "раза" : "раз"}, сейчас занято 24% окна
          </p>
          <label className="mt-3 flex items-center gap-2.5 text-xs">
            <Switch checked={autoCompact} onCheckedChange={setAutoCompact} /> Сжимать само на 80% окна
          </label>
          <Button size="sm" variant="outline" className="mt-3" onClick={onCompact}>
            <Archive /> Сжать сейчас
          </Button>
        </Side>
      )}
      <Side title="С кем говорю" action={<SideLink onClick={() => app.go("people")}>Профиль</SideLink>}>
        <div className="flex items-center gap-3">
          <span className="flex size-9 items-center justify-center rounded-full bg-foreground/10 text-sm font-medium">{who.name[0]}</span>
          <div className="min-w-0">
            <p className="text-sm font-medium">{who.name}</p>
            <p className="truncate text-xs text-muted-foreground">{who.role}</p>
          </div>
        </div>
        <div className="mt-3 flex flex-wrap gap-1.5 text-xs">
          <Tag>на «{who.address === "ty" ? "ты" : "вы"}»</Tag>
          <Tag>{tone}</Tag>
          <Tag>{who.via}</Tag>
        </div>
      </Side>

      <Side title="Память в этом ответе" action={<SideLink onClick={() => app.go("memory")}>Вся память</SideLink>}>
        {used.length === 0 ? (
          <p className="text-xs text-muted-foreground">В последнем ответе Lumen не опирался на память.</p>
        ) : (
          <div className="space-y-2">
            {used.map((m) => (
              <div key={m.id} className="shine rounded-lg border border-glow/15 bg-glow/[0.03] px-2.5 py-2">
                <p className="text-[13px] leading-snug">{m.text}</p>
                <p className="mt-1 text-[11px] text-muted-foreground">из «{m.source}», {m.when}</p>
              </div>
            ))}
          </div>
        )}
      </Side>

      <Side title="Характер" action={<SideLink onClick={() => app.go("persona")}>Изменить</SideLink>}>
        <p className="text-xs leading-relaxed text-muted-foreground">{persona.about}</p>
        <div className="mt-2.5 flex flex-wrap gap-1.5 text-xs">
          <Tag>{{ warm: "тёплый", plain: "ровный", dry: "сухой" }[persona.warmth]}</Tag>
          <Tag>{{ short: "коротко", medium: "средне", long: "подробно" }[persona.length]}</Tag>
          <Tag>{persona.language === "ru" ? "по-русски" : "на языке собеседника"}</Tag>
        </div>
      </Side>

      <Side title="Окно контекста">
        <div className="flex items-center gap-4">
          <ContextRing />
          <div className="space-y-1 text-xs">
            <p className="text-sm font-medium tabular-nums">47 тыс. из 200 тыс.</p>
            <Legend shade="bg-glow" label="характер и правила" value="6k" />
            <Legend shade="bg-glow/60" label="память" value="9k" />
            <Legend shade="bg-foreground/30" label="разговор и файлы" value="32k" />
          </div>
        </div>
        <button
          onClick={() => toast("Разговор сжат", { description: "Старые сообщения пересказаны, важное сохранено в память." })}
          className="mt-3 flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground"
        >
          <RotateCcw className="size-3.5" /> Сжать разговор
        </button>
      </Side>

      <Side title="Расход" action={<SideLink onClick={() => app.go("connections")}>Подключения</SideLink>}>
        <Meter label="Подписка, 5 часов" value={34} note="сброс в 23:10" />
        <Meter label="Подписка, неделя" value={12} note="до понедельника" />
        <p className="mt-3 text-xs text-muted-foreground">
          API в этом месяце <span className="text-foreground tabular-nums">$4,18</span> из $20
        </p>
      </Side>
    </aside>
  )
}

function Tag({ children }: { children: React.ReactNode }) {
  return <span className="rounded-md bg-foreground/[0.06] px-2 py-0.5 text-muted-foreground">{children}</span>
}

function Legend({ shade, label, value }: { shade: string; label: string; value: string }) {
  return (
    <span className="flex items-center gap-1.5 text-muted-foreground">
      <span className={cn("size-2 rounded-sm", shade)} />
      {label} <span className="text-foreground tabular-nums">{value}</span>
    </span>
  )
}

function Meter({ label, value, note }: { label: string; value: number; note: string }) {
  return (
    <div className="mt-2.5 first:mt-0">
      <div className="flex items-baseline justify-between text-xs">
        <span>{label}</span>
        <span className="text-muted-foreground tabular-nums">
          {value}%, {note}
        </span>
      </div>
      <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-muted">
        <div className="h-full rounded-full bg-glow shadow-[0_0_8px_var(--glow-soft)]" style={{ width: `${value}%` }} />
      </div>
    </div>
  )
}

function ContextRing() {
  const total = 200
  const r = 30
  const c = 2 * Math.PI * r
  const parts = [
    { v: 6, cls: "stroke-glow" },
    { v: 9, cls: "stroke-glow/60" },
    { v: 32, cls: "stroke-foreground/30" },
  ]
  let offset = 0
  return (
    <svg viewBox="0 0 76 76" className="size-[76px] -rotate-90">
      <circle cx="38" cy="38" r={r} fill="none" strokeWidth="7" className="stroke-muted" />
      {parts.map((p, i) => {
        const len = (p.v / total) * c
        const el = (
          <circle key={i} cx="38" cy="38" r={r} fill="none" strokeWidth="7" strokeDasharray={`${len} ${c - len}`} strokeDashoffset={-offset} className={p.cls} />
        )
        offset += len
        return el
      })}
      <text
        x="38"
        y="38"
        className="rotate-90 fill-foreground text-[13px] font-semibold"
        style={{ transformOrigin: "38px 38px" }}
        textAnchor="middle"
        dominantBaseline="central"
      >
        24%
      </text>
    </svg>
  )
}
