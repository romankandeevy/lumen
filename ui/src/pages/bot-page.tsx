import { Archive, ArrowUp, AtSign, Check, ChevronDown, CircleAlert, Lock, Plus, Sparkles, Trash2, X } from "lucide-react"
import { useEffect, useRef, useState } from "react"
import { toast } from "sonner"

import { BotAvatar, botIcons, botStyle } from "@/components/bot-avatar"
import { Segmented } from "@/components/page"
import { Button } from "@/components/ui/button"
import { Switch } from "@/components/ui/switch"
import { Textarea } from "@/components/ui/textarea"
import { useApp } from "@/lib/app-state"
import { botTools, type BotDef, type BotIcon, type ToolId } from "@/lib/mock-data"
import { cn } from "@/lib/utils"

// Страница бота. Бот — агент-субагент под одну роль, со своим цветом и квадратным знаком,
// чтобы его не путали с Lumen. Слева — его единственный чат (старое сжато в пересказы),
// справа — паспорт: что умеет, что отрезано в коде, навыки, чему научился, что ему нужно.
// Вкладка «Настройка» — конструктор, как GPT Builder: форма и живое превью.

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

const newBot = (): BotDef => ({
  id: "",
  name: "",
  icon: "shield",
  hue: 280,
  role: "",
  instructions: "",
  can: [],
  tools: ["read"],
  skills: [],
  learned: [],
  needs: [],
  starters: [],
  offTopic: /$^/,
  messages: 0,
  compactions: [],
})

export function BotPage({ botId }: { botId: string }) {
  const app = useApp()
  const creating = botId === "new"
  const existing = app.bots.find((b) => b.id === botId)
  const [draft, setDraft] = useState<BotDef>(() => existing ?? newBot())
  const [tab, setTab] = useState<"talk" | "setup">(creating ? "setup" : "talk")
  const bot = creating ? draft : (existing ?? draft)

  if (!creating && !existing) return null

  return (
    <div style={botStyle(bot.hue)} className="flex h-full min-h-0 flex-col">
      {/* шапка в цвете бота */}
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
          {!creating && (
            <Segmented
              value={tab}
              onChange={setTab}
              options={[
                { id: "talk", name: "Разговор" },
                { id: "setup", name: "Настройка" },
              ]}
            />
          )}
        </div>
      </header>

      {tab === "talk" && existing ? <Talk bot={existing} /> : <Builder draft={draft} setDraft={setDraft} creating={creating} onDone={() => setTab("talk")} />}
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
      timers.current.push(
        window.setTimeout(
          () =>
            setMessages((m) => [
              ...m,
              {
                id: id + "b",
                from: "blocked",
                text: `Это не моя роль — ${bot.role.charAt(0).toLowerCase() + bot.role.slice(1)}.${handoff ? ` Могу подготовить задачу для @${handoff.id}.` : ""}`,
              },
            ]),
          700
        )
      )
      return
    }
    setMessages((m) => [...m, { id: id + "w", from: "bot", text: "", working: true }])
    timers.current.push(
      window.setTimeout(
        () =>
          setMessages((m) =>
            m.map((x) => (x.id === id + "w" ? { ...x, working: false, text: "Сделал по своей части. Это макет — настоящая работа начнётся, когда подключим Claude." } : x))
          ),
        1400
      )
    )
  }

  return (
    <div className="grid min-h-0 flex-1 grid-cols-1 lg:grid-cols-[minmax(0,1fr)_340px]">
      <section className="relative flex min-h-0 flex-col bg-[radial-gradient(700px_400px_at_50%_110%,var(--bot-faint),transparent_70%)]">
        <div ref={scroller} className="min-h-0 flex-1 overflow-auto">
          <div className="mx-auto flex max-w-[42rem] flex-col gap-5 px-6 py-6">
            <div className="flex items-center gap-3">
              <span className="h-px flex-1 bg-border" />
              <span className="text-xs text-muted-foreground">
                {bot.messages ? `один чат с начала, ${bot.messages.toLocaleString("ru")} сообщений` : "чат бота начинается здесь и не заканчивается"}
              </span>
              <span className="h-px flex-1 bg-border" />
            </div>
            {compactions.map((c, i) => (
              <button
                key={c.when + i}
                onClick={() => setOpenC(openC === i ? null : i)}
                className="block w-full rounded-xl border border-dashed px-3.5 py-2.5 text-left hover:border-[var(--bot-soft)]"
              >
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
          <div className="mx-auto max-w-[42rem]">
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
  return (
    <aside className="hidden min-h-0 flex-col overflow-auto border-l bg-sidebar/50 lg:flex">
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
        </div>
      </PSection>

      <PSection title="Чему научился">
        <ul className="space-y-1.5 text-sm text-foreground/85">
          {bot.learned.map((l) => (
            <li key={l} className="leading-snug">
              {l}
            </li>
          ))}
        </ul>
      </PSection>

      <PSection title="Что нужно для работы">
        <ul className="space-y-1.5 text-sm">
          {bot.needs.map((n) => (
            <li key={n.text} className="flex items-center gap-2">
              {n.ok ? <Check className="size-4 shrink-0 text-[var(--bot)]" /> : <CircleAlert className="size-4 shrink-0 text-amber-400" />}
              <span className={cn("min-w-0 flex-1", !n.ok && "text-foreground")}>{n.text}</span>
              {!n.ok && (
                <button onClick={() => app.go("tools")} className="text-xs text-muted-foreground hover:text-foreground">
                  Дать
                </button>
              )}
            </li>
          ))}
        </ul>
      </PSection>

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

const hues = [160, 235, 320, 200, 85, 280, 25]

function Builder({ draft, setDraft, creating, onDone }: { draft: BotDef; setDraft: React.Dispatch<React.SetStateAction<BotDef>>; creating: boolean; onDone: () => void }) {
  const app = useApp()
  const set = (p: Partial<BotDef>) => setDraft((d) => ({ ...d, ...p }))
  const idTaken = creating && app.bots.some((b) => b.id === draft.id)
  const valid = draft.name.trim() && /^[a-z0-9-]+$/.test(draft.id) && !idTaken && draft.role.trim()
  const field = "h-9 w-full rounded-lg border bg-input/30 px-3 text-sm outline-none focus:border-[var(--bot)]"

  const save = () => {
    if (!valid) return
    if (creating) {
      app.setBots((bs) => [...bs, { ...draft, offTopic: /напиши код|почини|запушь|задеплой/i }])
      toast(`Бот @${draft.id} создан`, { description: "Зови его в любом чате через @." })
      app.go("bot", draft.id)
    } else {
      app.setBots((bs) => bs.map((b) => (b.id === draft.id ? draft : b)))
      toast("Бот сохранён")
      onDone()
    }
  }

  return (
    <div className="grid min-h-0 flex-1 grid-cols-1 overflow-auto lg:grid-cols-[minmax(0,1fr)_360px] lg:overflow-hidden">
      <div className="min-h-0 space-y-7 overflow-auto px-6 py-6">
        <Block title="Знак">
          <div className="flex flex-wrap items-center gap-4">
            <div className="flex gap-1.5">
              {(Object.keys(botIcons) as BotIcon[]).map((ic) => (
                <button key={ic} onClick={() => set({ icon: ic })} className={cn("rounded-lg p-0.5 ring-offset-2 ring-offset-background", draft.icon === ic && "ring-2 ring-[var(--bot)]")} aria-label={ic}>
                  <BotAvatar bot={{ icon: ic, hue: draft.hue }} size={32} />
                </button>
              ))}
            </div>
            <div className="flex gap-1.5">
              {hues.map((h) => (
                <button
                  key={h}
                  onClick={() => set({ hue: h })}
                  aria-label={`Цвет ${h}`}
                  className={cn("size-6 rounded-full ring-offset-2 ring-offset-background", draft.hue === h && "ring-2 ring-foreground/60")}
                  style={{ background: `oklch(0.75 0.13 ${h})` }}
                />
              ))}
            </div>
          </div>
        </Block>

        <div className="grid gap-4 md:grid-cols-2">
          <Block title="Имя">
            <input value={draft.name} onChange={(e) => set({ name: e.target.value })} placeholder="Например, Тестировщик" className={field} />
          </Block>
          <Block title="Как звать в чате" hint={idTaken ? "Такой @ уже есть" : "латиница, цифры и дефис"}>
            <label className={cn(field, "flex items-center gap-1")}>
              <AtSign className="size-4 text-muted-foreground" />
              <input value={draft.id} disabled={!creating} onChange={(e) => set({ id: e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, "") })} placeholder="tester" className="w-full bg-transparent outline-none" />
            </label>
          </Block>
        </div>

        <Block title="Роль одной строкой" hint="Всё, что вне роли, бот вежливо отклонит">
          <input value={draft.role} onChange={(e) => set({ role: e.target.value })} placeholder="Проверяет приложения и правки — и только" className={field} />
        </Block>

        <Block title="Инструкции">
          <Textarea value={draft.instructions} onChange={(e) => set({ instructions: e.target.value })} rows={4} placeholder="Как работает, по каким правилам, каким должен быть результат" className="resize-none bg-input/30 text-sm" />
        </Block>

        <Block title="Умеет">
          <Items items={draft.can} onChange={(can) => set({ can })} placeholder="Например: прогнать тесты" />
        </Block>

        <Block title="Инструменты" hint="Выключенное отрезано в коде: у бота просто нет этого инструмента, и просьба его не вернёт">
          <div className="divide-y rounded-xl border bg-card/40">
            {botTools.map((t) => {
              const on = draft.tools.includes(t.id)
              return (
                <label key={t.id} className="flex items-center gap-3 px-3.5 py-2.5 text-sm">
                  {on ? <Check className="size-4 text-[var(--bot)]" /> : <Lock className="size-4 text-muted-foreground" />}
                  <span className={cn("flex-1", !on && "text-muted-foreground")}>{t.name}</span>
                  <Switch
                    checked={on}
                    onCheckedChange={(v) => set({ tools: v ? [...draft.tools, t.id as ToolId] : draft.tools.filter((x) => x !== t.id) })}
                  />
                </label>
              )
            })}
          </div>
        </Block>

        <Block title="С чего начать разговор">
          <Items items={draft.starters} onChange={(starters) => set({ starters })} placeholder="Подсказка над полем ввода" />
        </Block>

        <div className="flex items-center gap-2 pb-4">
          <Button onClick={save} disabled={!valid} className="bg-[var(--bot)] text-black hover:opacity-85">
            <Check /> {creating ? "Создать бота" : "Сохранить"}
          </Button>
          {!creating && (
            <Button
              variant="ghost"
              onClick={() => {
                app.setBots((bs) => bs.filter((b) => b.id !== draft.id))
                app.go("bots")
                toast(`Бот @${draft.id} удалён`)
              }}
            >
              <Trash2 /> Удалить
            </Button>
          )}
        </div>
      </div>

      {/* превью — как бот будет выглядеть в списке и в чате */}
      <aside className="border-l bg-sidebar/50 px-5 py-6 lg:overflow-auto">
        <p className="mb-3 text-[13px] font-medium">Превью</p>
        <div className="rounded-2xl border border-[var(--bot-soft)] bg-[var(--bot-faint)] p-4">
          <div className="flex items-center gap-3">
            <BotAvatar bot={draft} size={40} />
            <div className="min-w-0">
              <p className="truncate font-medium">{draft.name || "Новый бот"}</p>
              <p className="text-xs text-[var(--bot)]">@{draft.id || "id"}</p>
            </div>
          </div>
          <p className="mt-3 text-sm text-foreground/80">{draft.role || "Роль появится здесь"}</p>
          {draft.starters.length > 0 && (
            <div className="mt-3 flex flex-wrap gap-1.5">
              {draft.starters.map((s) => (
                <span key={s} className="rounded-full border border-[var(--bot-soft)] px-2.5 py-0.5 text-xs">
                  {s}
                </span>
              ))}
            </div>
          )}
        </div>
        <p className="mt-5 mb-2 text-xs text-muted-foreground">Если попросить не по роли</p>
        <div className="flex gap-2.5">
          <BotAvatar bot={draft} size={24} />
          <div className="rounded-2xl rounded-tl-md border border-dashed px-3 py-2 text-sm">
            <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <Lock className="size-3" /> Вне роли — заблокировано в коде
            </p>
            <p className="mt-1">Это не моя роль{draft.role ? ` — ${draft.role.charAt(0).toLowerCase() + draft.role.slice(1)}` : ""}.</p>
          </div>
        </div>
      </aside>
    </div>
  )
}

function Block({ title, hint, children }: { title: string; hint?: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="mb-2 text-xs text-muted-foreground">
        {title}
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
        <div key={it + i} className="group flex items-center gap-2 rounded-lg bg-foreground/[0.04] px-3 py-1.5 text-sm">
          <span className="size-1.5 rounded-full bg-[var(--bot)]" />
          <span className="flex-1">{it}</span>
          <button onClick={() => onChange(items.filter((_, j) => j !== i))} aria-label="Убрать" className="text-muted-foreground opacity-0 group-hover:opacity-100 focus:opacity-100">
            <X className="size-3.5" />
          </button>
        </div>
      ))}
      <div className="flex items-center gap-2 rounded-lg border border-dashed px-3 py-1 focus-within:border-[var(--bot)]">
        <Plus className="size-3.5 text-muted-foreground" />
        <input value={v} onChange={(e) => setV(e.target.value)} onKeyDown={(e) => e.key === "Enter" && add()} placeholder={placeholder} className="h-7 w-full bg-transparent text-sm outline-none placeholder:text-muted-foreground" />
      </div>
    </div>
  )
}
