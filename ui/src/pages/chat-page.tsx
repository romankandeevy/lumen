import {
  ArrowUp,
  AtSign,
  AudioLines,
  Brain,
  Check,
  ChevronDown,
  ChevronRight,
  Cloud,
  Eye,
  FileText,
  Folder,
  GitCommitHorizontal,
  Globe,
  Laptop,
  Loader2,
  Lock,
  PanelRight,
  Paperclip,
  Pencil,
  Plus,
  RotateCcw,
  Search,
  Square,
  Telescope,
  Undo2,
  X,
} from "lucide-react"
import { useEffect, useRef, useState } from "react"
import { toast } from "sonner"

import { BotAvatar, botStyle } from "@/components/bot-avatar"
import { LumenOrb } from "@/components/lumen-orb"
import { NextStep, type Choice, type NextStepData } from "@/components/next-step"
import { PlanList, type PlanItem } from "@/components/plan-list"
import { EffortPicker, ModelPicker } from "@/components/pickers"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Switch } from "@/components/ui/switch"
import { Textarea } from "@/components/ui/textarea"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { chatWidthClass, useApp } from "@/lib/app-state"
import { chats, projects, sessions, type BotDef, type Memory } from "@/lib/mock-data"
import { cn } from "@/lib/utils"

// Два вида разговора, как Chat и Code у Claude:
// Чат — просто разговор (модель, «сколько думать», голос), ничего не трогает.
// Агент — работа в папке проекта: папка, файлы, шаги, правки; на Маке или в облаке Claude Code.
// В обоих можно позвать бота через @ — Lumen передаст ему задачу как субагенту.

type Step = { icon: "eye" | "search" | "brain"; text: string }

type Msg =
  | { id: string; from: "user"; text: string }
  | {
      id: string
      from: "lumen"
      steps?: { summary: string; items: Step[] }
      body: React.ReactNode
      used?: string[]
      remembered?: string
      change?: boolean
      streaming?: boolean
      running?: string
    }
  | {
      id: string
      from: "delegate"
      bot: string
      task: string
      state: "running" | "done" | "blocked"
      steps: string[]
      result?: React.ReactNode
    }

/// План работы — сбоку, в правой панели, как в Claude Code
const plans: Record<string, PlanItem[]> = {
  shelf: [
    { text: "Прочитать отчёт о падении", state: "done" },
    { text: "Найти причину в ShelfStorage", state: "done" },
    { text: "Поправить проверку индекса", state: "done" },
    { text: "Проверить фикс", state: "doing", who: "tester" },
    { text: "Закоммитить", state: "todo" },
  ],
  island: [
    { text: "Прочитать IslandView.swift", state: "done" },
    { text: "Собрать в облаке и замерить кадры", state: "doing" },
    { text: "Перенести тень в CA-анимацию", state: "todo", who: "coder" },
    { text: "Проверить при уведомлении", state: "todo", who: "tester" },
  ],
  lumen: [
    { text: "Вспомнить, на чём остановились", state: "done" },
    { text: "Записать решение про темы", state: "done" },
    { text: "Собрать экран памяти", state: "todo" },
  ],
}

/// «Что дальше» в конце хода агента — итог и одно решение за Ромой
const nextSteps: Record<string, NextStepData> = {
  shelf: {
    recap: "Падение Shelf починено: проверка индекса в ShelfStorage.swift и кнопка выключается на время удаления. @tester сейчас проверяет фикс. Ничего не закоммичено.",
    ask: "Закоммитить фикс?",
    primary: { label: "Закоммитить", reply: "Закоммить", ack: "Закоммитил: «Shelf: не падать при двойном удалении». Push — когда скажешь." },
    secondary: { label: "Сначала разница", reply: "Покажи сначала разницу", ack: "Вот разница: ShelfStorage.swift, +2 −1 — проверка индекса перед удалением. Коммитить?" },
  },
  dash: {
    recap: "Три мелочи в Пульте поправлены, кнопки остались на местах. Сборка прошла, в приложении руками не проверял.",
    ask: "Выпускать 1.1?",
    primary: { label: "Выпускай", reply: "Выпускай", ack: "Собрал релиз 1.1 и подготовил заметки. Выкладку жду от тебя — нужен твой OK на push." },
    secondary: { label: "Сначала проверю", reply: "Сначала сам проверю", ack: "Хорошо. Сборка лежит в build/, запусти и скажи, что увидел." },
  },
  night: {
    recap: "Ночной обход прошёл: сайт отвечает, SSL до марта, битую ссылку в блоге поправил в ветке preview. На прод не выкладывал.",
    ask: "Выложить правку на прод?",
    primary: { label: "Выложить", reply: "Выкладывай", ack: "Выложил на прод, ссылка в блоге теперь живая." },
  },
}

const code = "rounded bg-foreground/[0.07] px-1 py-0.5 font-mono text-[0.8em]"

const scripts: Record<string, Msg[]> = {
  lumen: [
    { id: "u1", from: "user", text: "Напомни, на чём мы остановились с Люменом и что я просил про кнопки?" },
    {
      id: "a1",
      from: "lumen",
      body: (
        <>
          <p>Остановились на макете первой версии: память между разговорами, люди, характер ответов и боты-агенты.</p>
          <p>Про кнопки ты просил одно: когда я внедряю мокап или новую функцию, существующие кнопки остаются на местах. Двигаю только по твоей просьбе.</p>
        </>
      ),
      used: ["m9", "m2", "m3"],
    },
    { id: "u2", from: "user", text: "Да. И запомни: светлую тему не делаем, только тёмные." },
    { id: "a2", from: "lumen", body: <p>Понял. Тёмных тем будет две — «Люмен» и «Монохром»; позже добавим свои. Светлой не будет.</p>, remembered: "m12" },
  ],
  plan: [
    { id: "u1", from: "user", text: "Что поделаем сегодня?" },
    {
      id: "a1",
      from: "lumen",
      body: (
        <>
          <p>Свежее всего Lumen и Пульт. У lid-plane 2 коммита не отправлены, у soundcore 8 файлов не закоммичено.</p>
          <p>Предлагаю Shelf (падение) или тексты для сайта. Что берём?</p>
        </>
      ),
      used: ["m3"],
    },
  ],
  blog: [
    { id: "u1", from: "user", text: "@writer напиши короткий текст про ремонт ванной" },
    { id: "a1", from: "lumen", body: <p>Передаю @writer — это его задача.</p> },
    {
      id: "d1",
      from: "delegate",
      bot: "writer",
      task: "Короткий текст про ремонт ванной",
      state: "done",
      steps: ["Прочитал правила сайта", "Написал 3 абзаца"],
      result: (
        <p>
          «Ванная — место, где начинается утро. Мы аккуратно снимаем старую плитку, выравниваем стены и делаем гидроизоляцию, чтобы через
          десять лет не вспоминать о ремонте…»
        </p>
      ),
    },
  ],
  idea: [
    { id: "u1", from: "user", text: "Идеи для Заметочек 1.2?" },
    { id: "a1", from: "lumen", body: <p>Три идеи: закреплённые заметки, быстрый поиск по ⌘F и экспорт в Markdown. С какой начнём?</p> },
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
        ],
      },
      body: (
        <>
          <p>
            Все три падения одинаковые: <code className={code}>EXC_BREAKPOINT</code> в <code className={code}>ShelfStorage.remove(at:)</code>.
            При двойном щелчке индекс берётся из старого списка — после первого удаления он уже за краем.
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
        </>
      ),
      used: ["m5", "m4"],
      change: true,
    },
    { id: "u2", from: "user", text: "@tester проверь фикс" },
    {
      id: "d1",
      from: "delegate",
      bot: "tester",
      task: "Проверить фикс падения Shelf",
      state: "running",
      steps: ["Собрал Shelf", "Удалил 20 файлов подряд", "Двойной щелчок по полке…"],
    },
  ],
  island: [
    { id: "u1", from: "user", text: "Анимация чёлки проседает при уведомлении. Разберись." },
    {
      id: "a1",
      from: "lumen",
      steps: { summary: "Читает IslandView.swift и собирает в облаке", items: [{ icon: "eye", text: "Читает IslandView.swift" }] },
      body: <p>Похоже на тень, которая не успевает за островом. Собираю и замеряю кадры.</p>,
      used: ["m13"],
      running: "Собирает Island в облаке Claude Code",
    },
  ],
  dash: [
    { id: "u1", from: "user", text: "Глянь Пульт перед релизом." },
    { id: "a1", from: "lumen", body: <p>Нашёл три мелочи и поправил. Кнопку «Обновить» оставил на месте — ты к ней привык.</p>, used: ["m2"], change: true },
  ],
  night: [{ id: "a1", from: "lumen", body: <p>Ночной обход: сайт отвечает, SSL до марта, одна битая ссылка в блоге — поправил в ветке preview.</p>, used: ["m6"] }],
}

export function ChatPage({ chatId }: { chatId: string }) {
  const app = useApp()
  const agent = chatId === "new-agent" || sessions.some((s) => s.id === chatId)
  const session = sessions.find((s) => s.id === chatId)
  const [messages, setMessages] = useState<Msg[]>(scripts[chatId] ?? [])
  const [draft, setDraft] = useState("")
  const [model, setModel] = useState(agent ? "opus" : "sonnet")
  const [effort, setEffort] = useState(agent ? "high" : "medium")
  const [project, setProject] = useState(session?.project ?? "lumen")
  const [where, setWhere] = useState<"mac" | "cloud">(session?.where ?? "mac")
  const [tools, setTools] = useState({ web: false, research: false, memory: true })
  const [plan, setPlan] = useState<PlanItem[]>(plans[chatId] ?? [])
  const [next, setNext] = useState<NextStepData | null>(agent ? (nextSteps[chatId] ?? null) : null)
  const busy = app.orb === "thinking" || app.orb === "writing"
  const scroller = useRef<HTMLDivElement>(null)
  const timers = useRef<number[]>([])

  const title = session?.title ?? chats.flatMap((g) => g.items).find((c) => c.id === chatId)?.title ?? (agent ? "Новая задача" : "Новый чат")

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

  function patch(id: string, fn: (m: Msg) => Msg) {
    setMessages((ms) => ms.map((m) => (m.id === id ? fn(m) : m)))
  }

  /// Ответ Lumen по словам: думает → пишет → потом after()
  function stream(text: string, after?: (aid: string) => void, used: string[] = []) {
    const aid = `a${Date.now()}`
    app.setOrb("writing")
    const words = text.split(" ")
    let i = 0
    setMessages((m) => [...m, { id: aid, from: "lumen", body: "", streaming: true, used }])
    const tick = () => {
      i += 2
      const done = i >= words.length
      patch(aid, (x) => ({ ...x, body: <p>{words.slice(0, i).join(" ")}</p>, streaming: !done }) as Msg)
      if (!done) return later(tick, 60)
      app.setOrb("idle")
      app.showMemories(used)
      after?.(aid)
    }
    later(tick, 60)
  }

  /// Позвали бота: Lumen передаёт задачу, бот работает в своей роли — или упирается в блокировку
  function delegate(bot: BotDef, task: string) {
    const did = `d${Date.now()}`
    const blocked = bot.offTopic.test(task)
    stream(blocked ? `Передаю @${bot.id}.` : `Передаю @${bot.id} — это его задача.`, () => {
      setMessages((m) => [...m, { id: did, from: "delegate", bot: bot.id, task, state: "running", steps: [] }])
      if (blocked) {
        later(() => patch(did, (x) => ({ ...x, state: "blocked", steps: ["Сверил задачу со своей ролью"] }) as Msg), 900)
        return
      }
      const plan = bot.can.slice(0, 2)
      plan.forEach((s, i) => later(() => patch(did, (x) => (x.from === "delegate" ? { ...x, steps: [...x.steps, s] } : x)), 700 * (i + 1)))
      later(
        () => patch(did, (x) => (x.from === "delegate" ? { ...x, state: "done", result: <p>Готово. Подробности — в моём чате.</p> } : x)),
        700 * (plan.length + 1)
      )
    })
  }

  function send(text = draft) {
    const t = text.trim()
    if (!t || busy) return
    setDraft("")
    setNext(null)
    setMessages((m) => [...m, { id: `u${Date.now()}`, from: "user", text: t }])
    app.setOrb("thinking")

    const mention = t.match(/@([a-z0-9-]+)/i)?.[1]
    const bot = app.bots.find((b) => b.id === mention)
    if (bot) {
      later(() => delegate(bot, t.replace(/@\S+\s*/, "")), 900)
      return
    }

    if (agent && !plan.length) {
      setPlan([
        { text: "Понять задачу и прочитать проект", state: "doing" },
        { text: "Сделать правки", state: "todo" },
        { text: "Собрать и проверить", state: "todo" },
      ])
      later(() => setPlan((p) => p.map((x, i) => ({ ...x, state: i === 0 ? "done" : i === 1 ? "doing" : x.state }))), 2400)
    }

    const wantsMemory = /запомни/i.test(t)
    const fact = t.replace(/^.*?запомни[,:]?\s*/i, "").replace(/^что\s+/i, "")
    const pinned = app.memories.filter((m) => m.pinned)
    const reply = wantsMemory
      ? "Запомнил. Буду учитывать это в следующих разговорах — и здесь, и в других чатах."
      : agent
        ? `Понял. Работаю в папке ${project}${where === "cloud" ? " в облаке Claude Code" : ""}. Это макет — настоящая работа начнётся, когда подключим Claude.`
        : "Понял. Это макет — настоящий ответ придёт, когда подключим Claude. Сейчас я бы опирался на то, что знаю о тебе."
    const used = wantsMemory || !tools.memory ? [] : pinned.slice(0, 2).map((m) => m.id)

    later(
      () =>
        stream(
          reply,
          wantsMemory && fact
            ? (aid) => {
                const id = `m${Date.now()}`
                const memory: Memory = { id, text: fact.charAt(0).toUpperCase() + fact.slice(1), kind: "pref", source: title, when: "сейчас", about: ["me"] }
                app.setMemories((ms) => [memory, ...ms])
                patch(aid, (x) => (x.from === "lumen" ? { ...x, remembered: id } : x))
                app.setOrb("remember")
                later(() => app.setOrb("idle"), 1200)
              }
            : agent
              ? () =>
                  setNext({
                    recap: `Сделал первую часть в папке ${project}: прочитал проект и наметил правки. Собрать и проверить в приложении ещё не успел.`,
                    ask: "Продолжать?",
                    primary: { label: "Продолжай", reply: "Продолжай", ack: "Продолжаю: правлю файлы, потом соберу и проверю." },
                    secondary: { label: "Покажи план", reply: "Покажи, что будешь делать", ack: "План справа: понять задачу, сделать правки, собрать и проверить. Начинаю со второго пункта?" },
                  })
              : undefined,
          used
        ),
      1200
    )
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
        <header className="flex h-14 shrink-0 items-center gap-3 border-b px-5">
          <span className={cn("flex size-7 shrink-0 items-center justify-center rounded-lg", agent && "bg-foreground/[0.07]")} title={agent ? "Агент" : "Чат"}>
            {agent ? <Folder className="size-4 text-glow" /> : <LumenOrb size={18} state={app.orb} />}
          </span>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium">{title}</p>
            <p className="flex items-center gap-1.5 truncate text-xs text-muted-foreground">
              {agent ? (
                <>
                  Агент в папке {project}
                  <span className="text-foreground/20">·</span>
                  {where === "cloud" ? (
                    <>
                      <Cloud className="size-3" /> в облаке Claude Code
                    </>
                  ) : (
                    <>
                      <Laptop className="size-3" /> на этом Маке
                    </>
                  )}
                </>
              ) : (
                "Чат — просто разговор, Lumen ничего не трогает"
              )}
            </p>
          </div>
          <Tooltip>
            <TooltipTrigger asChild>
              <Button variant={app.contextOpen ? "secondary" : "ghost"} size="icon-sm" onClick={() => app.setContextOpen(!app.contextOpen)}>
                <PanelRight />
              </Button>
            </TooltipTrigger>
            <TooltipContent>Контекст: память, характер, расход</TooltipContent>
          </Tooltip>
        </header>

        <div ref={scroller} className="min-h-0 flex-1 overflow-auto">
          {messages.length === 0 ? (
            agent ? (
              <AgentEmpty project={project} setProject={setProject} where={where} setWhere={setWhere} onPick={setDraft} />
            ) : (
              <ChatEmpty onPick={setDraft} />
            )
          ) : (
            <div className={cn("mx-auto flex flex-col gap-7 px-6 py-8 transition-[max-width] duration-300", chatWidthClass[app.chatWidth])}>
              {messages.map((m) =>
                m.from === "user" ? <UserMsg key={m.id} text={m.text} /> : m.from === "lumen" ? <LumenMsg key={m.id} msg={m} agent={agent} /> : <Delegation key={m.id} msg={m} />
              )}
              {next && !busy && (
                <NextStep
                  data={next}
                  onClose={() => setNext(null)}
                  onAnswer={(c: Choice) => {
                    setNext(null)
                    setMessages((m) => [...m, { id: `u${Date.now()}`, from: "user", text: c.reply }])
                    app.setOrb("thinking")
                    later(() => stream(c.ack), 800)
                  }}
                />
              )}
              {app.orb === "thinking" && (
                <div className="flex items-center gap-3 text-sm text-muted-foreground">
                  <LumenOrb state="thinking" size={22} />
                  <span>{tools.memory ? "Вспоминает и думает…" : "Думает…"}</span>
                </div>
              )}
            </div>
          )}
        </div>

        <Composer
          agent={agent}
          draft={draft}
          setDraft={setDraft}
          send={send}
          stop={stop}
          busy={busy}
          model={model}
          setModel={setModel}
          effort={effort}
          setEffort={setEffort}
          project={project}
          setProject={setProject}
          where={where}
          setWhere={setWhere}
          tools={tools}
          setTools={setTools}
        />
      </section>

      {app.contextOpen && <ContextPanel agent={agent} project={project} where={where} plan={plan} />}
    </div>
  )
}

// ── поле ввода ──

type Tools = { web: boolean; research: boolean; memory: boolean }

type ComposerProps = {
  agent: boolean
  draft: string
  setDraft: (v: string) => void
  send: () => void
  stop: () => void
  busy: boolean
  model: string
  setModel: (v: string) => void
  effort: string
  setEffort: (v: string) => void
  project: string
  setProject: (v: string) => void
  where: "mac" | "cloud"
  setWhere: (v: "mac" | "cloud") => void
  tools: Tools
  setTools: React.Dispatch<React.SetStateAction<Tools>>
}

function Composer(p: ComposerProps) {
  const app = useApp()
  const [files, setFiles] = useState(p.agent ? ["ПЛАН.md", "crash.ips"] : [])
  const mention = p.draft.match(/(?:^|\s)@([a-z0-9-]*)$/i)
  const q = mention?.[1].toLowerCase() ?? ""
  const matches = mention ? app.bots.filter((b) => b.id.startsWith(q) || b.name.toLowerCase().includes(q)) : []
  const insertBot = (id: string) => p.setDraft(p.draft.replace(/@([a-z0-9-]*)$/i, `@${id} `))
  const glowBtn = "ml-1 rounded-full bg-glow text-black shadow-[0_0_16px_var(--glow-soft)] hover:bg-glow/85"

  return (
    <div className="relative px-5 pt-1 pb-5">
      <div className="pointer-events-none absolute inset-x-0 -top-10 h-10 bg-gradient-to-t from-background to-transparent" />
      <div className={cn("relative mx-auto transition-[max-width] duration-300", chatWidthClass[app.chatWidth])}>
        {/* @ — список ботов над полем */}
        {mention && matches.length > 0 && (
          <div className="absolute inset-x-0 bottom-full mb-2 overflow-hidden rounded-xl border bg-popover p-1.5 shadow-2xl">
            <p className="px-2 pt-1 pb-1.5 text-xs text-muted-foreground">Позвать бота — Lumen передаст ему задачу</p>
            {matches.map((b) => (
              <button key={b.id} onClick={() => insertBot(b.id)} className="flex w-full items-center gap-3 rounded-lg px-2 py-1.5 text-left hover:bg-muted/60">
                <BotAvatar bot={b} size={26} />
                <span className="min-w-0 flex-1">
                  <span className="block text-sm">
                    {b.name} <span className="text-muted-foreground">@{b.id}</span>
                  </span>
                  <span className="block truncate text-xs text-muted-foreground">{b.role}</span>
                </span>
              </button>
            ))}
          </div>
        )}

        <div className={cn("glow-field rounded-2xl border bg-card/60 p-3 backdrop-blur", p.agent && "border-glow/15")}>
          {p.agent && files.length > 0 && (
            <div className="mb-2 flex flex-wrap items-center gap-1.5">
              {files.map((f) => (
                <span key={f} className="flex h-6 items-center gap-1 rounded-md border bg-muted/40 px-1.5 text-xs">
                  <FileText className="size-3 text-muted-foreground" />
                  {f}
                  <button onClick={() => setFiles((fs) => fs.filter((x) => x !== f))} aria-label="Убрать файл" className="text-muted-foreground hover:text-foreground">
                    <X className="size-3" />
                  </button>
                </span>
              ))}
            </div>
          )}
          <Textarea
            value={p.draft}
            onChange={(e) => p.setDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault()
                if (mention && matches[0]) return insertBot(matches[0].id)
                p.send()
              }
            }}
            placeholder={p.agent ? "Что сделать в проекте? @ — позвать бота" : "Просто напиши или поговори голосом. @ — позвать бота"}
            className="min-h-12 resize-none border-0 bg-transparent p-0 text-sm shadow-none focus-visible:ring-0 dark:bg-transparent"
          />
          <div className="mt-2 flex flex-wrap items-center gap-1">
            <PlusMenu
              tools={p.tools}
              setTools={p.setTools}
              onAttach={() => (p.agent ? setFiles((f) => [...f, "Снимок экрана.png"]) : toast("Файл прикреплён"))}
              onBot={() => p.setDraft(p.draft + (p.draft === "" || p.draft.endsWith(" ") ? "@" : " @"))}
            />
            {p.agent && <FolderPicker project={p.project} setProject={p.setProject} />}
            {p.agent && <WherePicker where={p.where} setWhere={p.setWhere} />}
            {p.tools.web && (
              <ToolPill icon={Globe} onOff={() => p.setTools((t) => ({ ...t, web: false }))}>
                Интернет
              </ToolPill>
            )}
            {p.tools.research && (
              <ToolPill icon={Telescope} onOff={() => p.setTools((t) => ({ ...t, research: false }))}>
                Исследование
              </ToolPill>
            )}
            {!p.tools.memory && (
              <ToolPill icon={Brain} onOff={() => p.setTools((t) => ({ ...t, memory: true }))}>
                Без памяти
              </ToolPill>
            )}
            <div className="ml-auto flex items-center gap-0.5">
              <ModelPicker value={p.model} onChange={p.setModel} />
              <EffortPicker value={p.effort} onChange={p.setEffort} />
              {p.busy ? (
                <Button size="sm" variant="secondary" className="ml-1 h-8" onClick={p.stop}>
                  <Square className="fill-current" /> Стоп
                </Button>
              ) : p.draft.trim() ? (
                <Button size="icon-sm" className={glowBtn} onClick={() => p.send()} aria-label="Отправить">
                  <ArrowUp />
                </Button>
              ) : (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button size="icon-sm" className={glowBtn} onClick={() => app.setVoiceOpen(true)} aria-label="Поговорить голосом">
                      <AudioLines />
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent>Поговорить голосом</TooltipContent>
                </Tooltip>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

function ToolPill({ icon: Icon, children, onOff }: { icon: React.ComponentType<{ className?: string }>; children: React.ReactNode; onOff: () => void }) {
  return (
    <button onClick={onOff} className="group flex h-7 items-center gap-1 rounded-lg bg-glow/10 px-2 text-xs whitespace-nowrap text-glow hover:bg-glow/15" title="Выключить">
      <Icon className="size-3.5" /> {children}
      <X className="size-3 opacity-50 group-hover:opacity-100" />
    </button>
  )
}

/// «+» в поле: интернет, исследование, память, файл, бот
function PlusMenu({ tools, setTools, onAttach, onBot }: { tools: Tools; setTools: React.Dispatch<React.SetStateAction<Tools>>; onAttach: () => void; onBot: () => void }) {
  const row = "flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left text-sm hover:bg-muted/60"
  const toggle = (k: keyof Tools, icon: React.ReactNode, name: string, note: string) => (
    <label className={row}>
      {icon}
      <span className="min-w-0 flex-1">
        <span className="block">{name}</span>
        <span className="block text-xs text-muted-foreground">{note}</span>
      </span>
      <Switch checked={tools[k]} onCheckedChange={(v) => setTools((t) => ({ ...t, [k]: v }))} />
    </label>
  )
  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button variant="ghost" size="icon-sm" aria-label="Добавить" className="rounded-full">
          <Plus />
        </Button>
      </PopoverTrigger>
      <PopoverContent align="start" side="top" className="w-80 p-1.5">
        {toggle("web", <Globe className="size-4 text-muted-foreground" />, "Поиск в интернете", "найдёт свежее и даст ссылки")}
        {toggle("research", <Telescope className="size-4 text-muted-foreground" />, "Глубокое исследование", "много источников, отчёт; дольше")}
        {toggle("memory", <Brain className="size-4 text-muted-foreground" />, "Память", "опираться на то, что знает о тебе")}
        <div className="my-1 h-px bg-border" />
        <button onClick={onAttach} className={row}>
          <Paperclip className="size-4 text-muted-foreground" /> Прикрепить файл или снимок
        </button>
        <button onClick={onBot} className={row}>
          <AtSign className="size-4 text-muted-foreground" /> Позвать бота
        </button>
      </PopoverContent>
    </Popover>
  )
}

function FolderPicker({ project, setProject }: { project: string; setProject: (v: string) => void }) {
  return (
    <Popover>
      <PopoverTrigger asChild>
        <button className="flex h-7 items-center gap-1.5 rounded-lg px-2 text-xs whitespace-nowrap hover:bg-foreground/5">
          <Folder className="size-3.5 text-glow" /> {project}
          <ChevronDown className="size-3 opacity-50" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" side="top" className="w-64 p-1.5">
        <p className="px-2 pt-1 pb-2 text-xs text-muted-foreground">Папка проекта</p>
        {projects.map((x) => (
          <button key={x} onClick={() => setProject(x)} className={cn("flex w-full items-center gap-2.5 rounded-lg px-2 py-1.5 text-left text-sm hover:bg-muted/60", x === project && "bg-muted")}>
            <Folder className="size-4 text-muted-foreground" /> {x}
            {x === project && <Check className="ml-auto size-4 text-glow" />}
          </button>
        ))}
        <button onClick={() => toast("Выбор папки", { description: "Откроется окно Finder." })} className="mt-1 w-full rounded-lg px-2 py-1.5 text-left text-xs text-muted-foreground hover:text-foreground">
          Другая папка…
        </button>
      </PopoverContent>
    </Popover>
  )
}

function WherePicker({ where, setWhere }: { where: "mac" | "cloud"; setWhere: (v: "mac" | "cloud") => void }) {
  const opts = [
    { id: "mac" as const, icon: Laptop, name: "Этот Мак", note: "работает здесь, видит все файлы" },
    { id: "cloud" as const, icon: Cloud, name: "Облако Claude", note: "облачная сессия Claude Code; Мак можно закрыть" },
  ]
  const cur = opts.find((o) => o.id === where)!
  return (
    <Popover>
      <PopoverTrigger asChild>
        <button className="flex h-7 items-center gap-1.5 rounded-lg px-2 text-xs whitespace-nowrap text-muted-foreground hover:bg-foreground/5 hover:text-foreground">
          <cur.icon className="size-3.5" /> {cur.name}
          <ChevronDown className="size-3 opacity-50" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" side="top" className="w-80 p-1.5">
        <p className="px-2 pt-1 pb-2 text-xs text-muted-foreground">Где работает агент</p>
        {opts.map((o) => (
          <button key={o.id} onClick={() => setWhere(o.id)} className={cn("flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left hover:bg-muted/60", o.id === where && "bg-muted")}>
            <o.icon className="size-4 text-muted-foreground" />
            <span className="min-w-0 flex-1">
              <span className="block text-sm">{o.name}</span>
              <span className="block text-xs text-muted-foreground">{o.note}</span>
            </span>
            {o.id === where && <Check className="size-4 text-glow" />}
          </button>
        ))}
      </PopoverContent>
    </Popover>
  )
}

// ── пустые экраны ──

function ChatEmpty({ onPick }: { onPick: (t: string) => void }) {
  const app = useApp()
  const ideas = ["Как прошёл день?", "Объясни, как работает память Lumen", "Запомни, что я встаю в 9", "@designer разбери экран памяти"]
  return (
    <div className="mx-auto flex h-full max-w-[44rem] flex-col items-center justify-center px-6 text-center">
      <LumenOrb state={app.orb} size={72} />
      <h2 className="mt-8 text-2xl font-semibold tracking-[-0.02em]">Привет, {app.me.call}. О чём поговорим?</h2>
      <p className="mt-2 text-sm text-muted-foreground">Помню {facts(app.memories.length)} о тебе, проектах и людях.</p>
      <Button className="mt-6 h-10 rounded-full bg-glow px-5 text-black shadow-[0_0_24px_var(--glow-soft)] hover:bg-glow/85" onClick={() => app.setVoiceOpen(true)}>
        <AudioLines /> Поговорить голосом
      </Button>
      <div className="mt-5 flex flex-wrap justify-center gap-2">
        {ideas.map((i) => (
          <button key={i} onClick={() => onPick(i)} className="rounded-full border bg-card/50 px-3.5 py-1.5 text-sm hover:border-glow/40 hover:bg-card">
            {i}
          </button>
        ))}
      </div>
    </div>
  )
}

function AgentEmpty({
  project,
  setProject,
  where,
  setWhere,
  onPick,
}: {
  project: string
  setProject: (v: string) => void
  where: "mac" | "cloud"
  setWhere: (v: "mac" | "cloud") => void
  onPick: (t: string) => void
}) {
  return (
    <div className="mx-auto flex h-full max-w-[44rem] flex-col justify-center px-6">
      <h2 className="text-2xl font-semibold tracking-[-0.02em]">Что сделать?</h2>
      <p className="mt-1.5 text-sm text-muted-foreground">Агент работает в папке проекта: читает, правит, собирает. Push и выкатка — только с твоего OK.</p>
      <p className="mt-6 mb-2 text-xs text-muted-foreground">Папка</p>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        {projects.map((x) => (
          <button
            key={x}
            onClick={() => setProject(x)}
            className={cn("flex items-center gap-2 rounded-xl border px-3 py-2.5 text-left text-sm transition-colors", x === project ? "border-glow/50 bg-glow/[0.06]" : "bg-card/40 hover:bg-card")}
          >
            <Folder className={cn("size-4 shrink-0", x === project ? "text-glow" : "text-muted-foreground")} />
            <span className="truncate">{x}</span>
          </button>
        ))}
      </div>
      <p className="mt-5 mb-2 text-xs text-muted-foreground">Где</p>
      <div className="flex gap-2">
        {(
          [
            ["mac", Laptop, "Этот Мак"],
            ["cloud", Cloud, "Облако Claude"],
          ] as const
        ).map(([id, Icon, name]) => (
          <button
            key={id}
            onClick={() => setWhere(id)}
            className={cn("flex items-center gap-2 rounded-xl border px-3 py-2 text-sm", where === id ? "border-glow/50 bg-glow/[0.06]" : "bg-card/40 hover:bg-card")}
          >
            <Icon className="size-4" /> {name}
          </button>
        ))}
      </div>
      <div className="mt-6 flex flex-wrap gap-2">
        {["Найди и почини падение", "Собери и проверь сборку", "Обнови ПЛАН.md", "@tester прогони сценарии"].map((i) => (
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

// ── сообщения ──

function UserMsg({ text }: { text: string }) {
  const app = useApp()
  // @бот в тексте — плашкой его цвета
  const parts = text.split(/(@[a-z0-9-]+)/i)
  return (
    <div className="flex justify-end">
      <div className="max-w-[80%] rounded-2xl rounded-br-md bg-secondary px-4 py-2.5 text-sm leading-relaxed">
        {parts.map((p, i) => {
          const bot = p.startsWith("@") ? app.bots.find((b) => b.id === p.slice(1)) : undefined
          return bot ? (
            <span key={i} style={botStyle(bot.hue)} className="rounded-md bg-[var(--bot-soft)] px-1 py-0.5 font-medium text-[var(--bot)]">
              {p}
            </span>
          ) : (
            <span key={i}>{p}</span>
          )
        })}
      </div>
    </div>
  )
}

const stepIcon = { eye: Eye, search: Search, brain: Brain }

function LumenMsg({ msg, agent }: { msg: Extract<Msg, { from: "lumen" }>; agent: boolean }) {
  const app = useApp()
  const [open, setOpen] = useState(false)
  return (
    <div className="flex gap-3.5">
      <LumenOrb state={msg.streaming ? "writing" : "idle"} size={22} className="mt-0.5" />
      <div className="min-w-0 flex-1 space-y-3">
        {agent && msg.steps && (
          <>
            <button onClick={() => setOpen((o) => !o)} className="flex items-center gap-2 py-0.5 text-xs text-muted-foreground hover:text-foreground">
              {open ? <ChevronDown className="size-3.5" /> : <ChevronRight className="size-3.5" />}
              {msg.steps.summary}
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
        {msg.running && (
          <p className="flex items-center gap-2 text-xs text-muted-foreground">
            <Loader2 className="size-3.5 animate-spin text-glow" /> {msg.running}
            <Cloud className="size-3.5" />
          </p>
        )}
        {msg.change && <ChangeCard />}
        {msg.remembered && <Remembered id={msg.remembered} />}
        {!msg.streaming && msg.used && msg.used.length > 0 && (
          <button onClick={() => app.showMemories(msg.used!)} className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-glow">
            <Brain className="size-3.5" />
            Опирался на {msg.used.length} {msg.used.length === 1 ? "воспоминание" : msg.used.length < 5 ? "воспоминания" : "воспоминаний"}
          </button>
        )}
      </div>
    </div>
  )
}

/// Карточка субагента: Lumen передал задачу боту; цвет и знак — бота
function Delegation({ msg }: { msg: Extract<Msg, { from: "delegate" }> }) {
  const app = useApp()
  const bot = app.bots.find((b) => b.id === msg.bot)
  const handoff = app.bots.find((b) => b.id === bot?.handoff)
  if (!bot) return null
  return (
    <div style={botStyle(bot.hue)} className="ml-9 overflow-hidden rounded-2xl border border-[var(--bot-soft)] bg-[var(--bot-faint)]">
      <div className="flex items-center gap-2.5 border-b border-[var(--bot-soft)] px-3.5 py-2.5">
        <LumenOrb size={14} />
        <span className="text-xs text-muted-foreground">Lumen →</span>
        <BotAvatar bot={bot} size={22} />
        <button
          onClick={() => {
            app.setTab("bots")
            app.go("bot", bot.id)
          }}
          className="text-sm font-medium hover:text-[var(--bot)]"
        >
          {bot.name}
        </button>
        <span className="text-xs text-muted-foreground">@{bot.id}</span>
        <span className="ml-auto flex items-center gap-1.5 text-xs">
          {msg.state === "running" && (
            <>
              <Loader2 className="size-3.5 animate-spin text-[var(--bot)]" /> работает
            </>
          )}
          {msg.state === "done" && (
            <>
              <Check className="size-3.5 text-[var(--bot)]" /> готово
            </>
          )}
          {msg.state === "blocked" && (
            <>
              <Lock className="size-3.5" /> не его роль
            </>
          )}
        </span>
      </div>
      <div className="space-y-2.5 px-3.5 py-3 text-sm">
        <p className="text-xs text-muted-foreground">Задача: {msg.task}</p>
        {msg.steps.map((s) => (
          <p key={s} className="flex items-center gap-2 text-xs text-foreground/80">
            <Check className="size-3.5 text-[var(--bot)]" /> {s}
          </p>
        ))}
        {msg.state === "blocked" && (
          <div className="rounded-xl border border-dashed px-3 py-2.5">
            <p className="flex items-center gap-2 text-sm">
              <Lock className="size-4" /> {bot.name} этого не делает
            </p>
            <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
              Его роль: {bot.role.toLowerCase()}. Нужных инструментов у него нет — это ограничение в коде, обойти его просьбой нельзя.
            </p>
            {handoff && (
              <Button size="xs" variant="outline" className="mt-2.5" onClick={() => toast(`Передано @${handoff.id}`, { description: msg.task })}>
                <BotAvatar bot={handoff} size={14} /> Передать @{handoff.id}
              </Button>
            )}
          </div>
        )}
        {msg.result && <div className="leading-relaxed">{msg.result}</div>}
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
  const save = () => {
    app.setMemories((ms) => ms.map((m) => (m.id === id ? { ...m, text } : m)))
    setEditing(false)
  }

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
              if (e.key === "Enter") save()
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
          <Button size="xs" onClick={save}>
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

// ── правая панель ──

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

function ContextPanel({ agent, project, where, plan }: { agent: boolean; project: string; where: "mac" | "cloud"; plan: PlanItem[] }) {
  const app = useApp()
  const used = app.focusMemories.map((id) => app.memories.find((m) => m.id === id)).filter(Boolean) as Memory[]
  const persona = app.persona
  return (
    <aside className="absolute inset-y-0 right-0 z-20 flex min-h-0 w-80 flex-col overflow-auto border-l bg-sidebar shadow-2xl xl:static xl:w-auto xl:bg-sidebar/50 xl:shadow-none">
      {plan.length > 0 && (
        <Side title="План">
          <PlanList items={plan} bots={app.bots} />
        </Side>
      )}
      {agent && (
        <Side title="Сессия">
          <div className="space-y-2 text-sm">
            <p className="flex items-center gap-2">
              <Folder className="size-4 shrink-0 text-glow" /> <span className="truncate">~/Documents/prog/{project}</span>
            </p>
            <p className="flex items-center gap-2 text-muted-foreground">
              {where === "cloud" ? <Cloud className="size-4 shrink-0" /> : <Laptop className="size-4 shrink-0" />}
              {where === "cloud" ? "Облако Claude Code — Мак можно закрыть" : "Этот Мак"}
            </p>
            <p className="flex items-center gap-2 text-muted-foreground">
              <Lock className="size-4 shrink-0" /> push и выкатка — только с твоего OK
            </p>
          </div>
        </Side>
      )}

      <Side title="Память в этом ответе" action={<SideLink onClick={() => app.go("memory")}>Вся память</SideLink>}>
        {used.length === 0 ? (
          <p className="text-xs text-muted-foreground">В последнем ответе Lumen не опирался на память.</p>
        ) : (
          <div className="space-y-2">
            {used.map((m) => (
              <div key={m.id} className="shine rounded-lg border border-glow/15 bg-glow/[0.03] px-2.5 py-2">
                <p className="text-[13px] leading-snug">{m.text}</p>
                <p className="mt-1 text-[11px] text-muted-foreground">
                  из «{m.source}», {m.when}
                </p>
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

      <Side title="Расход" action={<SideLink onClick={() => app.go("settings", "models")}>Модели и оплата</SideLink>}>
        <Meter label="Подписка, 5 часов" value={34} note="сброс в 23:10" />
        <Meter label="Подписка, неделя" value={12} note="до понедельника" />
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

export function Meter({ label, value, note }: { label: string; value: number; note: string }) {
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
        const el = <circle key={i} cx="38" cy="38" r={r} fill="none" strokeWidth="7" strokeDasharray={`${len} ${c - len}`} strokeDashoffset={-offset} className={p.cls} />
        offset += len
        return el
      })}
      <text x="38" y="38" className="rotate-90 fill-foreground text-[13px] font-semibold" style={{ transformOrigin: "38px 38px" }} textAnchor="middle" dominantBaseline="central">
        24%
      </text>
    </svg>
  )
}
