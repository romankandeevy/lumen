import { ArrowUp, Check, FileLock2, Hand, Pause, Play, RotateCcw, ShieldCheck, Users } from "lucide-react"
import { useEffect, useRef, useState } from "react"
import { toast } from "sonner"

import { BotAvatar, botStyle } from "@/components/bot-avatar"
import { LumenOrb } from "@/components/lumen-orb"
import { Segmented } from "@/components/page"
import { PlanList, type PlanItem } from "@/components/plan-list"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import { chatWidthClass, useApp } from "@/lib/app-state"
import { groupRules, type Group, type GroupMode } from "@/lib/groups-data"
import type { BotDef } from "@/lib/mock-data"
import { cn } from "@/lib/utils"

// Группа ботов. Lumen — ведущий: даёт слово по очереди (никто не перебивает), следит,
// чтобы у файла был один хозяин, и зовёт Рому, когда нужно решение.
// Боты сначала делят роли и вместе пишут план, потом работают — параллельно, где можно.

type GMsg =
  | { id: string; kind: "lead"; text: string }
  | { id: string; kind: "bot"; bot: string; text: string; to?: string }
  | { id: string; kind: "you"; text: string }
  | { id: string; kind: "system"; icon: "lock" | "wait" | "turn" | "ok"; text: string }
  | { id: string; kind: "plan"; text: string }
  | { id: string; kind: "ask"; bot: string; text: string; options: string[]; answered?: string }

type DistOmit<T, K extends PropertyKey> = T extends unknown ? Omit<T, K> : never
type Step = { msg?: DistOmit<GMsg, "id">; plan?: PlanItem[]; speaker?: string | null; queue?: string[]; files?: Record<string, string>; wait?: boolean }

/// Сценарий группы: знакомство → роли → общий план → работа с очередью слова и замками на файлы
function script(g: Group, bots: BotDef[]): Step[] {
  const [a, b, c] = g.members
  const name = (id?: string) => bots.find((x) => x.id === id)?.name ?? id
  const base: PlanItem[] = [
    { text: "Структура и макет", state: "doing", who: a },
    { text: "Каркас проекта", state: "doing", who: b },
    { text: "ТЗ на страницы", state: "todo", who: a },
    { text: "Вёрстка страниц", state: "todo", who: b },
    ...(c ? [{ text: "Проверка: телефон, ссылки, скорость", state: "todo" as const, who: c }] : []),
    { text: "Правки по замечаниям", state: "todo", who: b },
    { text: "Выкладка — только с OK Ромы", state: "todo" },
  ]
  const mark = (done: number, doing: number[]) => base.map((p, i) => ({ ...p, state: i < done ? "done" : doing.includes(i) ? "doing" : "todo" }) as PlanItem)
  return [
    { msg: { kind: "lead", text: `Задача: ${g.goal}. В группе: ${g.members.map((m) => name(m)).join(", ")}. Сначала договоритесь о ролях — по очереди.` }, speaker: a, queue: [b, c].filter(Boolean) as string[] },
    { msg: { kind: "bot", bot: a, text: "Беру структуру и макет: главная, работы, контакты. Потом дам ТЗ кодеру." }, speaker: b, queue: [c].filter(Boolean) as string[] },
    { msg: { kind: "bot", bot: b, text: "Беру вёрстку и выкладку. Каркас начну сразу — это можно параллельно с макетом." }, speaker: c ?? null, queue: [] },
    ...(c ? [{ msg: { kind: "bot" as const, bot: c, text: "Беру проверку: телефон, ссылки, скорость. Подключусь на первой сборке." }, speaker: null, queue: [] }] : []),
    { msg: { kind: "plan", text: `План согласован (${g.members.length} из ${g.members.length})` }, plan: mark(0, [0, 1]) },
    { msg: { kind: "system", icon: "turn", text: `Параллельно: ${name(a)} и ${name(b)}.${c ? ` ${name(c)} ждёт первую сборку.` : ""}` }, speaker: b },
    { msg: { kind: "system", icon: "lock", text: `${name(b)} взял файлы app/layout.tsx и package.json — остальные их не трогают` }, files: { "app/layout.tsx": b, "package.json": b } },
    { msg: { kind: "ask", bot: a, text: "Рома, какой стиль сайта?", options: ["Тёмный минимализм", "Ярко и смело", "Решите сами"] }, speaker: a, wait: true },
    { msg: { kind: "bot", bot: a, text: "Принято. Макет готов, ТЗ на 3 страницы передал кодеру." }, plan: mark(3, [3]), speaker: b, queue: c ? [c] : [] },
    ...(c ? [{ msg: { kind: "system" as const, icon: "wait" as const, text: `${name(c)} хочет сказать — ждёт очереди, слово у ${name(b)}` } }] : []),
    { msg: { kind: "bot", bot: b, text: `Главная, работы и контакты свёрстаны, сборка готова.${c ? " Твоя очередь." : ""}`, to: c }, plan: mark(4, c ? [4] : [4]), speaker: c ?? null, queue: [], files: {} },
    ...(c
      ? [
          { msg: { kind: "bot" as const, bot: c, text: "Проверил: на телефоне меню наезжает на заголовок, остальное ок. Вернул кодеру.", to: b }, plan: mark(5, [5]), speaker: b },
          { msg: { kind: "bot" as const, bot: b, text: "Поправил меню, собрал заново. Готово к выкладке — нужен OK Ромы." }, plan: mark(6, [6]), speaker: null },
        ]
      : []),
    { msg: { kind: "ask", bot: b, text: "Выкладываем на прод?", options: ["Да, выкладывай", "Сначала покажи"] }, wait: true },
    { msg: { kind: "lead", text: "Готово. Сайт выложен, итог и ссылки — в карточке группы." }, plan: base.map((p) => ({ ...p, state: "done" })), speaker: null },
  ]
}

export function GroupPage({ groupId }: { groupId: string }) {
  const app = useApp()
  const group = app.groups.find((g) => g.id === groupId)
  const members = (group?.members ?? []).map((id) => app.bots.find((b) => b.id === id)).filter(Boolean) as BotDef[]
  const steps = group ? script(group, app.bots) : []
  const [at, setAt] = useState(0)
  const [msgs, setMsgs] = useState<GMsg[]>([])
  const [plan, setPlan] = useState<PlanItem[]>([])
  const [speaker, setSpeaker] = useState<string | null>(null)
  const [queue, setQueue] = useState<string[]>([])
  const [files, setFiles] = useState<Record<string, string>>({})
  const [paused, setPaused] = useState(false)
  const [waiting, setWaiting] = useState(false)
  const [text, setText] = useState("")
  const [mode, setMode] = useState<GroupMode>(group?.mode ?? "auto")
  const scroller = useRef<HTMLDivElement>(null)

  // следующий шаг сценария — если не на паузе и никто не ждёт ответа Ромы
  useEffect(() => {
    if (paused || waiting || at >= steps.length) return
    const t = window.setTimeout(() => {
      const s = steps[at]
      if (s.msg) setMsgs((m) => [...m, { ...(s.msg as GMsg), id: String(at) }])
      if (s.plan) setPlan(s.plan)
      if (s.speaker !== undefined) setSpeaker(s.speaker)
      if (s.queue) setQueue(s.queue)
      if (s.files) setFiles(s.files)
      if (s.wait) setWaiting(true)
      setAt((a) => a + 1)
    }, at === 0 ? 500 : 1500)
    return () => window.clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [at, paused, waiting])

  useEffect(() => {
    scroller.current?.scrollTo({ top: scroller.current.scrollHeight, behavior: "smooth" })
  }, [msgs])

  if (!group) return null

  const answer = (id: string, option: string) => {
    setMsgs((m) => m.map((x) => (x.id === id && x.kind === "ask" ? { ...x, answered: option } : x)))
    setWaiting(false)
  }

  const send = () => {
    const v = text.trim()
    if (!v) return
    setText("")
    setMsgs((m) => [...m, { id: `y${Date.now()}`, kind: "you", text: v }])
    window.setTimeout(
      () => setMsgs((m) => [...m, { id: `l${Date.now()}`, kind: "lead", text: "Принял. Дождусь, пока текущий говорящий закончит, и передам группе — без перебиваний." }]),
      700
    )
  }

  const restart = () => {
    setAt(0)
    setMsgs([])
    setPlan([])
    setSpeaker(null)
    setQueue([])
    setFiles({})
    setWaiting(false)
    setPaused(false)
  }

  const bot = (id?: string) => members.find((m) => m.id === id)
  const status = (id: string) => (speaker === id ? "говорит" : queue.includes(id) ? "ждёт очереди" : plan.some((p) => p.who === id && p.state === "doing") ? "работает" : "свободен")

  return (
    <div className="flex h-full min-h-0 flex-col">
      <header className="relative shrink-0 overflow-hidden border-b">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(600px_160px_at_10%_0%,var(--glow-faint),transparent_70%)]" />
        <div className="relative flex items-center gap-4 px-6 py-4">
          <Stack bots={members} size={36} />
          <div className="min-w-0 flex-1">
            <p className="flex items-center gap-2 text-lg font-semibold tracking-[-0.01em]">
              {group.name}
              <span className="rounded-md bg-foreground/[0.07] px-1.5 py-0.5 text-xs font-normal text-muted-foreground">группа · {members.length}</span>
            </p>
            <p className="truncate text-sm text-muted-foreground">{group.goal}</p>
          </div>
          <Segmented
            value={mode}
            onChange={(v) => {
              setMode(v)
              toast(v === "auto" ? "Боты сами решают, что можно параллельно" : v === "parallel" ? "Параллельно, где нет общих файлов" : "Строго по очереди")
            }}
            options={[
              { id: "auto", name: "Сами решают" },
              { id: "parallel", name: "Параллельно" },
              { id: "sequence", name: "По очереди" },
            ]}
          />
          <Button variant="outline" size="sm" onClick={() => setPaused((p) => !p)}>
            {paused ? <Play /> : <Pause />} {paused ? "Продолжить" : "Пауза"}
          </Button>
          <Button variant="ghost" size="icon-sm" onClick={restart} title="Начать сначала" aria-label="Начать сначала">
            <RotateCcw />
          </Button>
        </div>
      </header>

      <div className="grid min-h-0 flex-1 grid-cols-1 lg:grid-cols-[minmax(0,1fr)_340px]">
        <section className="flex min-h-0 flex-col">
          <div ref={scroller} className="min-h-0 flex-1 overflow-auto">
            <div className={cn("mx-auto flex flex-col gap-4 px-6 py-6", chatWidthClass[app.chatWidth])}>
              {msgs.map((m) => {
                if (m.kind === "lead")
                  return (
                    <div key={m.id} className="flex gap-3">
                      <LumenOrb size={24} className="mt-0.5" />
                      <div className="min-w-0">
                        <p className="text-xs text-muted-foreground">Lumen ведёт группу</p>
                        <p className="mt-0.5 text-[0.9375rem] leading-relaxed">{m.text}</p>
                      </div>
                    </div>
                  )
                if (m.kind === "you")
                  return (
                    <div key={m.id} className="flex justify-end">
                      <div className="max-w-[80%] rounded-2xl rounded-br-md bg-secondary px-4 py-2.5 text-sm">{m.text}</div>
                    </div>
                  )
                if (m.kind === "system")
                  return (
                    <p key={m.id} className="flex items-center justify-center gap-2 text-xs text-muted-foreground">
                      {m.icon === "lock" ? <FileLock2 className="size-3.5" /> : m.icon === "wait" ? <Hand className="size-3.5" /> : <Users className="size-3.5" />}
                      {m.text}
                    </p>
                  )
                if (m.kind === "plan")
                  return (
                    <div key={m.id} className="shine flex items-center gap-2.5 rounded-xl border border-glow/25 bg-glow/[0.04] px-3.5 py-2.5 text-sm">
                      <Check className="size-4 text-glow" /> {m.text} — он справа
                      <Stack bots={members} size={20} className="ml-auto" />
                    </div>
                  )
                const b = bot(m.bot)
                if (!b) return null
                const to = m.kind === "bot" ? bot(m.to) : undefined
                return (
                  <div key={m.id} style={botStyle(b.hue, b.chroma)} className="flex gap-3">
                    <BotAvatar bot={b} size={28} />
                    <div className="min-w-0 max-w-[85%]">
                      <p className="flex items-center gap-1.5 text-xs">
                        <span className="font-medium text-[var(--bot)]">{b.name}</span>
                        {to && <span className="text-muted-foreground">→ {to.name}</span>}
                        {m.kind === "ask" && <span className="text-muted-foreground">→ тебе</span>}
                      </p>
                      <div className={cn("mt-1 rounded-2xl rounded-tl-md border-l-2 border-[var(--bot)] bg-[var(--bot-faint)] px-4 py-2.5 text-[0.9375rem] leading-relaxed", m.kind === "ask" && "border border-[var(--bot-soft)]")}>
                        {m.text}
                        {m.kind === "ask" && (
                          <div className="mt-2.5 flex flex-wrap gap-1.5">
                            {m.options.map((o) =>
                              m.answered ? (
                                <span key={o} className={cn("rounded-full border px-3 py-1 text-xs", m.answered === o ? "border-[var(--bot)] text-[var(--bot)]" : "text-muted-foreground/50")}>
                                  {m.answered === o && <Check className="mr-1 inline size-3" />}
                                  {o}
                                </span>
                              ) : (
                                <button key={o} onClick={() => answer(m.id, o)} className="rounded-full border border-[var(--bot-soft)] px-3 py-1 text-xs hover:bg-[var(--bot-soft)]">
                                  {o}
                                </button>
                              )
                            )}
                          </div>
                        )}
                      </div>
                    </div>
                  </div>
                )
              })}
              {speaker && !paused && !waiting && (
                <div style={botStyle(bot(speaker)!.hue, bot(speaker)!.chroma)} className="flex items-center gap-2 pl-10 text-xs text-muted-foreground">
                  <span className="flex gap-0.5">
                    {[0, 1, 2].map((i) => (
                      <span key={i} className="size-1.5 animate-bounce rounded-full bg-[var(--bot)]" style={{ animationDelay: `${i * 120}ms` }} />
                    ))}
                  </span>
                  {bot(speaker)?.name} пишет…
                </div>
              )}
              {waiting && <p className="text-center text-xs text-glow">Группа ждёт твоего ответа</p>}
              {paused && <p className="text-center text-xs text-muted-foreground">На паузе — боты дописали фразу и ждут</p>}
            </div>
          </div>

          <div className="px-5 pb-5">
            <div className={cn("glow-field mx-auto rounded-2xl border bg-card/60 p-3 backdrop-blur", chatWidthClass[app.chatWidth])}>
              <Textarea
                value={text}
                onChange={(e) => setText(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && !e.shiftKey) {
                    e.preventDefault()
                    send()
                  }
                }}
                placeholder="Напиши группе. @ — обратиться к одному боту. Lumen передаст, когда дойдёт очередь"
                className="min-h-10 resize-none border-0 bg-transparent p-0 text-sm shadow-none focus-visible:ring-0 dark:bg-transparent"
              />
              <div className="mt-2 flex items-center">
                <span className="text-xs text-muted-foreground">Бюджет: {group.budget}</span>
                <Button size="icon-sm" className="ml-auto rounded-full bg-glow text-black hover:bg-glow/85" disabled={!text.trim()} onClick={send} aria-label="Отправить">
                  <ArrowUp />
                </Button>
              </div>
            </div>
          </div>
        </section>

        <aside className="hidden min-h-0 flex-col overflow-auto border-l bg-sidebar/50 lg:flex">
          <Side title="План" aside={plan.length ? <span className="text-[11px] text-muted-foreground">написали вместе</span> : undefined}>
            {plan.length ? <PlanList items={plan} bots={app.bots} /> : <p className="text-xs text-muted-foreground">Боты договариваются о ролях — план появится здесь.</p>}
          </Side>

          <Side title="Слово">
            {speaker ? (
              <div style={botStyle(bot(speaker)!.hue, bot(speaker)!.chroma)} className="flex items-center gap-2.5 rounded-xl border border-[var(--bot-soft)] bg-[var(--bot-faint)] px-3 py-2">
                <BotAvatar bot={bot(speaker)!} size={24} />
                <span className="text-sm">{bot(speaker)?.name}</span>
                <span className="ml-auto text-xs text-[var(--bot)]">говорит</span>
              </div>
            ) : (
              <p className="text-xs text-muted-foreground">Сейчас никто не говорит</p>
            )}
            {queue.length > 0 && (
              <p className="mt-2 flex items-center gap-1.5 text-xs text-muted-foreground">
                Очередь:
                {queue.map((q) => (
                  <BotAvatar key={q} bot={bot(q)!} size={16} />
                ))}
              </p>
            )}
          </Side>

          <Side title="Участники">
            <div className="space-y-2">
              {members.map((m) => {
                const st = status(m.id)
                const own = Object.entries(files).filter(([, who]) => who === m.id)
                return (
                  <div key={m.id} style={botStyle(m.hue, m.chroma)} className="flex items-center gap-2.5">
                    <BotAvatar bot={m} size={28} />
                    <div className="min-w-0 flex-1">
                      <p className="text-sm">{m.name}</p>
                      <p className="truncate text-[11px] text-muted-foreground">{own.length ? `держит: ${own.map(([f]) => f).join(", ")}` : `@${m.id}`}</p>
                    </div>
                    <span className={cn("text-[11px]", st === "говорит" || st === "работает" ? "text-[var(--bot)]" : "text-muted-foreground")}>{st}</span>
                  </div>
                )
              })}
            </div>
          </Side>

          <Side title="Правила группы">
            <ul className="space-y-1.5 text-xs leading-relaxed text-muted-foreground">
              {groupRules.map((r) => (
                <li key={r} className="flex gap-2">
                  <ShieldCheck className="mt-0.5 size-3.5 shrink-0 text-glow" /> {r}
                </li>
              ))}
            </ul>
          </Side>
        </aside>
      </div>
    </div>
  )
}

function Side({ title, aside, children }: { title: string; aside?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="border-b px-5 py-4 last:border-b-0">
      <div className="mb-3 flex items-center justify-between">
        <p className="text-[13px] font-medium">{title}</p>
        {aside}
      </div>
      {children}
    </section>
  )
}

/// Знаки участников внахлёст
export function Stack({ bots, size = 24, className }: { bots: BotDef[]; size?: number; className?: string }) {
  return (
    <span className={cn("flex shrink-0", className)}>
      {bots.map((b, i) => (
        <span key={b.id} className="rounded-[30%] ring-2 ring-background" style={{ marginLeft: i ? -size * 0.32 : 0, zIndex: bots.length - i }}>
          <BotAvatar bot={b} size={size} />
        </span>
      ))}
    </span>
  )
}

/// Создание группы: имя, задача, кто в ней, как работать
export function NewGroupForm({ onCreate }: { onCreate: (g: Group) => void }) {
  const app = useApp()
  const [name, setName] = useState("")
  const [goal, setGoal] = useState("")
  const [members, setMembers] = useState<string[]>([])
  const [mode, setMode] = useState<GroupMode>("auto")
  const ok = name.trim() && goal.trim() && members.length >= 2
  return (
    <div className="space-y-5">
      <input autoFocus value={name} onChange={(e) => setName(e.target.value)} placeholder="Название, например «Сайт для Лёши»" className="h-10 w-full rounded-xl border bg-input/30 px-3.5 text-sm outline-none focus:border-glow/50" />
      <textarea value={goal} onChange={(e) => setGoal(e.target.value)} rows={3} placeholder="Общая задача: что нужно получить в итоге" className="w-full resize-none rounded-xl border bg-input/30 px-3.5 py-2.5 text-sm outline-none focus:border-glow/50" />
      <div>
        <p className="mb-2 text-xs text-muted-foreground">Кто в группе — минимум два бота</p>
        <div className="grid gap-2 sm:grid-cols-2">
          {app.bots.map((b) => {
            const on = members.includes(b.id)
            return (
              <button
                key={b.id}
                style={botStyle(b.hue, b.chroma)}
                onClick={() => setMembers((m) => (on ? m.filter((x) => x !== b.id) : [...m, b.id]))}
                className={cn("flex items-center gap-3 rounded-xl border px-3 py-2.5 text-left transition-colors", on ? "border-[var(--bot)] bg-[var(--bot-faint)]" : "hover:bg-foreground/5")}
              >
                <BotAvatar bot={b} size={28} />
                <span className="min-w-0 flex-1">
                  <span className="block text-sm">{b.name}</span>
                  <span className="block truncate text-xs text-muted-foreground">{b.role}</span>
                </span>
                {on && <Check className="size-4 text-[var(--bot)]" />}
              </button>
            )
          })}
        </div>
      </div>
      <div className="flex items-center gap-3">
        <Segmented
          value={mode}
          onChange={setMode}
          options={[
            { id: "auto", name: "Сами решают" },
            { id: "parallel", name: "Параллельно" },
            { id: "sequence", name: "По очереди" },
          ]}
        />
        <Button className="ml-auto bg-glow text-black hover:bg-glow/85" disabled={!ok} onClick={() => onCreate({ id: `g${Date.now()}`, name: name.trim(), goal: goal.trim(), members, mode, budget: "$3 и 2 часа", live: true })}>
          <Users /> Собрать группу
        </Button>
      </div>
    </div>
  )
}
