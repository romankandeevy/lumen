import {
  ArrowUp,
  AtSign,
  Brain,
  Check,
  ChevronDown,
  ChevronRight,
  Cloud,
  Eye,
  FileText,
  Folder,
  GitCommitHorizontal,
  Loader2,
  MessageSquare,
  Mic,
  Plus,
  RotateCcw,
  Search,
  Sparkles,
  Square,
  SquareTerminal,
  X,
  Zap,
} from "lucide-react"
import { useEffect, useRef, useState } from "react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Textarea } from "@/components/ui/textarea"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip"
import { cn } from "@/lib/utils"

// Мокап Lumen: чат с Claude Code, который знает проекты prog, память и Пульт.
// Слева — чаты и задачи в фоне, в центре — разговор, справа — контекст, окно и расход.

type Chat = { id: string; title: string; project: string; model: string; when: string; unread?: boolean }

const chats: { group: string; items: Chat[] }[] = [
  {
    group: "Сегодня",
    items: [
      { id: "shelf", title: "Почему падает Shelf?", project: "shelf", model: "Opus", when: "12 мин" },
      { id: "plan", title: "Что поделаем сегодня?", project: "prog", model: "Sonnet", when: "2 ч" },
      { id: "blog", title: "Тексты для блога kandeev.com", project: "kandeev.com", model: "Opus", when: "5 ч", unread: true },
    ],
  },
  {
    group: "Вчера",
    items: [
      { id: "review", title: "Ревью Пульта перед релизом", project: "prog-dashboard", model: "Opus", when: "вчера" },
      { id: "island", title: "Остров: самолётик вместо слова", project: "island", model: "Sonnet", when: "вчера" },
    ],
  },
  {
    group: "Раньше",
    items: [{ id: "notes", title: "Идеи для Заметочек 1.2", project: "notes", model: "Haiku", when: "12 окт" }],
  },
]

const background = [
  { title: "Разобрать падение Island", project: "island", state: "running", step: "Читает IslandModel.swift", when: "4 мин" },
  { title: "Ночной обход 15.10", project: "облако", state: "cloud", step: "1 замечание · сайт и SSL в порядке", when: "03:00" },
  { title: "Прочитай README Пульта", project: "prog", state: "done", step: "Готово · ничего не менял", when: "вчера" },
]

const models = [
  { id: "fable", name: "Fable 5.1", note: "самый сильный, для сложного" },
  { id: "opus", name: "Opus 5.5", note: "умный, для кода и разбора" },
  { id: "sonnet", name: "Sonnet 5.5", note: "быстрый, на каждый день" },
  { id: "haiku", name: "Haiku 5.5", note: "мгновенный и дешёвый" },
]

export function ClaudePage() {
  const [tab, setTab] = useState<"chats" | "bg">("chats")
  const [active, setActive] = useState("shelf")
  const [mode, setMode] = useState("agent")
  const [model, setModel] = useState("opus")
  const [effort, setEffort] = useState("high")
  const [stepsOpen, setStepsOpen] = useState(false)
  const scroller = useRef<HTMLDivElement>(null)
  // как в живом чате: открыт на последнем сообщении
  useEffect(() => {
    scroller.current?.scrollTo({ top: scroller.current.scrollHeight })
  }, [active])

  return (
    <div className="grid h-svh grid-cols-[272px_minmax(0,1fr)_300px]">
      {/* ── чаты и фон ── */}
      <aside className="flex min-h-0 flex-col border-r">
        <div className="flex items-center gap-2 p-3">
          <ToggleGroup
            type="single"
            variant="outline"
            size="sm"
            value={tab}
            onValueChange={(v) => v && setTab(v as "chats" | "bg")}
            className="[&_[data-state=on]]:bg-foreground [&_[data-state=on]]:text-background"
          >
            <ToggleGroupItem value="chats">
              <MessageSquare /> Чаты
            </ToggleGroupItem>
            <ToggleGroupItem value="bg">
              <Loader2 className="animate-spin" /> В фоне
              <span className="ml-0.5 rounded bg-amber-400 px-1 text-[10px] font-semibold text-black">1</span>
            </ToggleGroupItem>
          </ToggleGroup>
          <Tooltip>
            <TooltipTrigger asChild>
              <Button size="icon-sm" className="ml-auto">
                <Plus />
              </Button>
            </TooltipTrigger>
            <TooltipContent>Новый чат · ⌘N</TooltipContent>
          </Tooltip>
        </div>
        <div className="px-3 pb-2">
          <div className="flex h-8 items-center gap-2 rounded-lg border bg-input/30 px-2.5 text-sm text-muted-foreground">
            <Search className="size-4" /> Найти в чатах
          </div>
        </div>
        <div className="min-h-0 flex-1 overflow-auto px-2 pb-3">
          {tab === "chats" ? (
            chats.map((g) => (
              <div key={g.group} className="mt-2">
                <p className="px-2 py-1.5 text-xs text-muted-foreground">{g.group}</p>
                {g.items.map((c) => (
                  <button
                    key={c.id}
                    onClick={() => setActive(c.id)}
                    className={cn(
                      "group flex w-full flex-col gap-0.5 rounded-lg px-2 py-2 text-left transition-colors hover:bg-muted/60",
                      active === c.id && "bg-muted"
                    )}
                  >
                    <span className="flex items-center gap-1.5 text-sm font-medium">
                      {c.unread && <span className="size-1.5 rounded-full bg-foreground" />}
                      <span className="truncate">{c.title}</span>
                    </span>
                    <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
                      <Folder className="size-3" />
                      {c.project}
                      <span>·</span>
                      {c.model}
                      <span className="ml-auto">{c.when}</span>
                    </span>
                  </button>
                ))}
              </div>
            ))
          ) : (
            <div className="mt-2 space-y-1">
              <p className="px-2 py-1.5 text-xs text-muted-foreground">
                Задачи, которые Claude делает сам — на Маке или в облаке
              </p>
              {background.map((b) => (
                <div key={b.title} className="flex gap-2.5 rounded-lg px-2 py-2.5 hover:bg-muted/60">
                  <div className="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-lg border bg-muted/40">
                    {b.state === "running" ? (
                      <Loader2 className="size-3.5 animate-spin" />
                    ) : b.state === "cloud" ? (
                      <Cloud className="size-3.5" />
                    ) : (
                      <Check className="size-3.5" />
                    )}
                  </div>
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium">{b.title}</p>
                    <p className="truncate text-xs text-muted-foreground">{b.step}</p>
                    <p className="text-xs text-muted-foreground">
                      {b.project} · {b.when}
                    </p>
                  </div>
                </div>
              ))}
              <Button variant="outline" size="sm" className="mt-2 w-full">
                <Plus /> Задача в фон
              </Button>
            </div>
          )}
        </div>
      </aside>

      {/* ── разговор ── */}
      <section className="flex min-h-0 flex-col">
        <header className="flex h-14 items-center gap-2 border-b px-4">
          <div className="min-w-0">
            <p className="truncate text-sm font-medium">Почему падает Shelf?</p>
            <p className="text-xs text-muted-foreground">18 сообщений · начат 12 мин назад</p>
          </div>
          <div className="ml-auto flex items-center gap-2">
            <Button variant="outline" size="sm" className="h-8">
              <Folder /> shelf <ChevronDown className="opacity-50" />
            </Button>
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
                <Button variant="ghost" size="icon-sm">
                  <Cloud />
                </Button>
              </TooltipTrigger>
              <TooltipContent>Отправить в фон — доделает без тебя</TooltipContent>
            </Tooltip>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button variant="ghost" size="icon-sm">
                  <SquareTerminal />
                </Button>
              </TooltipTrigger>
              <TooltipContent>Продолжить в Терминале</TooltipContent>
            </Tooltip>
          </div>
        </header>

        <div ref={scroller} className="min-h-0 flex-1 overflow-auto">
          <div className="mx-auto flex max-w-3xl flex-col gap-6 px-6 py-6">
            <UserMsg>Почему Shelf падал 9 октября? Глянь отчёт и скажи, что чинить.</UserMsg>

            <div className="flex gap-3">
              <Avatar />
              <div className="min-w-0 flex-1 space-y-3">
                <button
                  onClick={() => setStepsOpen((o) => !o)}
                  className="flex items-center gap-2 rounded-lg border bg-muted/30 px-2.5 py-1.5 text-xs text-muted-foreground hover:text-foreground"
                >
                  {stepsOpen ? <ChevronDown className="size-3.5" /> : <ChevronRight className="size-3.5" />}
                  Прочитал отчёт о падении и 2 файла · поискал «items[»
                  <span className="text-foreground/60">· 4 шага · 9 с</span>
                </button>
                {stepsOpen && (
                  <div className="space-y-1.5 border-l pl-3 text-xs text-muted-foreground">
                    <p className="flex items-center gap-2"><Eye className="size-3.5" /> Читает Shelf-2026-10-09-235406.ips</p>
                    <p className="flex items-center gap-2"><Eye className="size-3.5" /> Читает Sources/ShelfStorage.swift</p>
                    <p className="flex items-center gap-2"><Search className="size-3.5" /> Ищет «items[» по проекту</p>
                    <p className="flex items-center gap-2"><Eye className="size-3.5" /> Читает Sources/ShelfWindow.swift</p>
                  </div>
                )}
                <div className="space-y-3 text-sm leading-relaxed">
                  <p>
                    Все три падения одинаковые: <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">EXC_BREAKPOINT</code>{" "}
                    в <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">ShelfStorage.remove(at:)</code>. Когда
                    файл удаляют с полки двойным щелчком, индекс берётся из старого списка — после первого удаления он уже
                    за краем.
                  </p>
                  <pre className="overflow-auto rounded-xl border bg-background/60 p-3 font-mono text-xs leading-relaxed">
                    <span className="text-muted-foreground">// ShelfStorage.swift:88</span>
                    {"\n"}
                    <span className="text-red-400/90">- let item = items[index]</span>
                    {"\n"}
                    <span>+ guard items.indices.contains(index) else {"{ return }"}</span>
                    {"\n"}
                    <span>+ let item = items[index]</span>
                  </pre>
                  <p>Это чинит падение. Заодно стоит отключать кнопку, пока идёт удаление, — двойной щелчок вообще не дойдёт.</p>
                </div>
                <ChangeCard />
              </div>
            </div>

            <UserMsg>Давай, чини и собери.</UserMsg>

            <div className="flex gap-3">
              <Avatar />
              <div className="min-w-0 flex-1 space-y-2">
                <div className="flex items-center gap-2 text-sm">
                  <Loader2 className="size-4 animate-spin text-muted-foreground" />
                  <span className="animate-pulse">Запускает ./build.sh</span>
                  <span className="text-xs text-muted-foreground">· шаг 3 из ~5</span>
                </div>
                <div className="space-y-1 border-l pl-3 text-xs text-muted-foreground">
                  <p className="flex items-center gap-2"><Check className="size-3.5" /> Поправил ShelfStorage.swift</p>
                  <p className="flex items-center gap-2"><Check className="size-3.5" /> Отключил кнопку на время удаления</p>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* поле ввода */}
        {/* поле ввода — продолжение разговора: без черты и без рамки, только лёгкий фон;
            текст разговора над ним не обрывается, а мягко гаснет */}
        <div className="relative px-4 pt-1 pb-4">
          <div className="pointer-events-none absolute inset-x-0 -top-10 h-10 bg-gradient-to-t from-background to-transparent" />
          <div className="mx-auto max-w-3xl rounded-2xl bg-muted/40 p-3">
            <div className="mb-2 flex flex-wrap items-center gap-1.5">
              <Chip icon={Folder}>shelf</Chip>
              <Chip icon={FileText}>ПЛАН.md · запись</Chip>
              <Chip icon={Brain}>память · 3</Chip>
              <Chip icon={FileText}>crash.ips</Chip>
              <button className="flex h-6 items-center gap-1 rounded-md px-1.5 text-xs text-muted-foreground hover:text-foreground">
                <AtSign className="size-3" /> добавить
              </button>
            </div>
            <Textarea
              placeholder="Спроси про проект или дай задачу…  @ — файл или проект, / — команды"
              className="min-h-14 resize-none border-0 bg-transparent p-0 text-sm shadow-none focus-visible:ring-0 dark:bg-transparent"
            />
            <div className="mt-2 flex items-center gap-2">
              <ModelPicker value={model} onChange={setModel} />
              <EffortPicker value={effort} onChange={setEffort} />
              <span className="hidden text-xs text-muted-foreground 2xl:inline">/clear · /compact · /review</span>
              <div className="ml-auto flex items-center gap-1">
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button variant="ghost" size="icon-sm">
                      <Mic />
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent>Голосом — держи правый ⌥ (FlowLocal)</TooltipContent>
                </Tooltip>
                <Button size="sm" variant="secondary" className="h-8">
                  <Square className="fill-current" /> Остановить
                </Button>
                <Button size="icon-sm" className="rounded-full" disabled>
                  <ArrowUp />
                </Button>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ── контекст и расход ── */}
      <SidePanel />
    </div>
  )
}

function Avatar() {
  return (
    <div className="flex size-7 shrink-0 items-center justify-center rounded-lg border bg-muted/40">
      <Sparkles className="size-3.5" />
    </div>
  )
}

function UserMsg({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex justify-end">
      <div className="max-w-[80%] rounded-2xl rounded-br-md bg-secondary px-4 py-2.5 text-sm">{children}</div>
    </div>
  )
}

/// Предложенная правка: файл, разница, кнопки — как ревью фоновой задачи
function ChangeCard() {
  return (
    <Card size="sm" className="gap-0 py-0">
      <div className="flex items-center gap-2 border-b px-3 py-2">
        <GitCommitHorizontal className="size-4 text-muted-foreground" />
        <span className="text-sm font-medium">Изменения</span>
        <span className="text-xs text-muted-foreground">1 файл · +2 −1</span>
        <Badge variant="outline" className="ml-auto rounded-md font-normal">
          применено
        </Badge>
      </div>
      <div className="flex items-center gap-2 px-3 py-2 font-mono text-xs">
        <span className="text-muted-foreground">M</span> Sources/ShelfStorage.swift
        <span className="ml-auto">+2</span>
        <span className="text-muted-foreground">−1</span>
      </div>
      <div className="flex items-center gap-2 border-t px-3 py-2">
        <Button size="sm" variant="ghost" className="h-7 text-xs">
          <RotateCcw /> Откатить
        </Button>
        <Button size="sm" variant="outline" className="ml-auto h-7 text-xs">
          <Eye /> Разница
        </Button>
        <Button size="sm" className="h-7 text-xs">
          <GitCommitHorizontal /> Закоммитить
        </Button>
      </div>
    </Card>
  )
}

function Chip({ icon: Icon, children }: { icon: React.ComponentType<{ className?: string }>; children: React.ReactNode }) {
  return (
    <span className="flex h-6 items-center gap-1 rounded-md border bg-muted/40 px-1.5 text-xs">
      <Icon className="size-3 text-muted-foreground" />
      {children}
      <X className="size-3 text-muted-foreground" />
    </span>
  )
}

function Legend({ shade, label, value }: { shade: string; label: string; value: string }) {
  return (
    <span className="flex items-center gap-1.5">
      <span className={cn("size-2 rounded-sm", shade)} />
      {label} <span className="text-foreground tabular-nums">{value}</span>
    </span>
  )
}

function Meter({ label, value, note }: { label: string; value: number; note: string }) {
  return (
    <div className="mt-2 first:mt-0">
      <div className="flex items-baseline justify-between text-xs">
        <span>{label}</span>
        <span className="tabular-nums text-muted-foreground">
          {value}% · {note}
        </span>
      </div>
      <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-muted">
        <div className={cn("h-full rounded-full", value > 80 ? "bg-amber-400" : "bg-foreground")} style={{ width: `${value}%` }} />
      </div>
    </div>
  )
}

// ── выбор модели и «сколько думать» — как в Claude Code ──

const efforts = [
  { id: "low", name: "Низкий", note: "быстрые ответы на простое" },
  { id: "medium", name: "Средний", note: "обычные вопросы и правки" },
  { id: "high", name: "Высокий", note: "код и разбор — по умолчанию" },
  { id: "xhigh", name: "Сверхвысокий", note: "сложные баги, большие правки" },
  { id: "max", name: "Максимальный", note: "самое трудное, думает долго" },
  { id: "ultra", name: "Ультракод", note: "глубокая работа над кодом, дольше всего" },
]

/// Шесть столбиков, закрашены до уровня — как индикатор сигнала
function EffortBars({ level, className }: { level: number; className?: string }) {
  return (
    <span className={cn("flex h-3.5 items-end gap-[2px]", className)}>
      {efforts.map((_, i) => (
        <span
          key={i}
          className={cn("w-[3px] rounded-full transition-colors", i <= level ? "bg-foreground" : "bg-foreground/20")}
          style={{ height: `${4 + i * 2}px` }}
        />
      ))}
    </span>
  )
}

function EffortPicker({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const level = efforts.findIndex((e) => e.id === value)
  return (
    <Popover>
      <PopoverTrigger asChild>
        <button className="flex h-7 items-center gap-2 rounded-lg px-2 text-xs hover:bg-foreground/5">
          <EffortBars level={level} />
          {efforts[level]?.name}
          <ChevronDown className="size-3 opacity-50" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" side="top" className="w-72 p-1.5">
        <p className="px-2 pt-1 pb-2 text-xs text-muted-foreground">Сколько думать</p>
        {efforts.map((e, i) => (
          <button
            key={e.id}
            onClick={() => onChange(e.id)}
            className={cn(
              "flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left hover:bg-muted/60",
              e.id === value && "bg-muted"
            )}
          >
            <EffortBars level={i} />
            <span className="min-w-0 flex-1">
              <span className="block text-sm font-medium">{e.name}</span>
              <span className="block text-xs text-muted-foreground">{e.note}</span>
            </span>
            {e.id === value && <Check className="size-4" />}
          </button>
        ))}
      </PopoverContent>
    </Popover>
  )
}

function ModelPicker({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const current = models.find((m) => m.id === value)
  return (
    <Popover>
      <PopoverTrigger asChild>
        <button className="flex h-7 items-center gap-1.5 rounded-lg px-2 text-xs font-medium hover:bg-foreground/5">
          <Sparkles className="size-3.5" />
          {current?.name}
          <ChevronDown className="size-3 opacity-50" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" side="top" className="w-72 p-1.5">
        <p className="px-2 pt-1 pb-2 text-xs text-muted-foreground">Модель</p>
        {models.map((m) => (
          <button
            key={m.id}
            onClick={() => onChange(m.id)}
            className={cn(
              "flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left hover:bg-muted/60",
              m.id === value && "bg-muted"
            )}
          >
            <Sparkles className="size-4 text-muted-foreground" />
            <span className="min-w-0 flex-1">
              <span className="block text-sm font-medium">{m.name}</span>
              <span className="block text-xs text-muted-foreground">{m.note}</span>
            </span>
            {m.id === value && <Check className="size-4" />}
          </button>
        ))}
      </PopoverContent>
    </Popover>
  )
}

// ── правая панель: одна спокойная колонка без карточек ──

const contextItems = [
  { icon: Folder, title: "shelf", sub: "main · чисто · v0.1" },
  { icon: FileText, title: "CLAUDE.md проекта", sub: "правила сборки и кода" },
  { icon: FileText, title: "ПЛАН.md", sub: "запись shelf · 1 пункт «Ждёт»" },
  { icon: Brain, title: "Память", sub: "3 факта: Полка → Буфер, только Swift…" },
  { icon: FileText, title: "crash.ips", sub: "отчёт о падении · 9 окт" },
]

function SideSection({ title, action, children }: { title: string; action?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="px-4 py-4">
      <div className="mb-3 flex items-center justify-between">
        <p className="text-xs font-medium tracking-wide text-muted-foreground uppercase">{title}</p>
        {action}
      </div>
      {children}
    </section>
  )
}

/// Кольцо заполнения окна контекста
function ContextRing({ used, total }: { used: number; total: number }) {
  const r = 30
  const c = 2 * Math.PI * r
  const parts = [
    { v: 12, cls: "stroke-foreground" },
    { v: 21, cls: "stroke-foreground/60" },
    { v: 14, cls: "stroke-foreground/30" },
  ]
  let offset = 0
  return (
    <svg viewBox="0 0 76 76" className="size-[76px] -rotate-90">
      <circle cx="38" cy="38" r={r} fill="none" strokeWidth="7" className="stroke-muted" />
      {parts.map((p, i) => {
        const len = (p.v / total) * c
        const el = (
          <circle
            key={i}
            cx="38"
            cy="38"
            r={r}
            fill="none"
            strokeWidth="7"
            strokeDasharray={`${len} ${c - len}`}
            strokeDashoffset={-offset}
            className={p.cls}
          />
        )
        offset += len
        return el
      })}
      <text x="38" y="38" className="rotate-90 fill-foreground text-[13px] font-semibold" style={{ transformOrigin: "38px 38px" }} textAnchor="middle" dominantBaseline="central">
        {Math.round((used / total) * 100)}%
      </text>
    </svg>
  )
}

function SidePanel() {
  return (
    <aside className="flex min-h-0 flex-col overflow-auto border-l bg-sidebar/40">
      <SideSection
        title="Контекст"
        action={
          <button className="flex size-6 items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground">
            <Plus className="size-3.5" />
          </button>
        }
      >
        <div className="space-y-0.5">
          {contextItems.map((c) => (
            <div key={c.title} className="group flex items-center gap-2.5 rounded-lg px-2 py-1.5 hover:bg-muted/50">
              <c.icon className="size-4 shrink-0 text-muted-foreground" />
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm">{c.title}</p>
                <p className="truncate text-xs text-muted-foreground">{c.sub}</p>
              </div>
              <X className="size-3.5 text-muted-foreground opacity-0 group-hover:opacity-100" />
            </div>
          ))}
        </div>
      </SideSection>

      <SideSection title="Окно контекста">
        <div className="flex items-center gap-4">
          <ContextRing used={47} total={200} />
          <div className="space-y-1 text-xs">
            <p className="text-sm font-medium tabular-nums">47 тыс. из 200 тыс.</p>
            <Legend shade="bg-foreground" label="правила" value="12k" />
            <Legend shade="bg-foreground/60" label="файлы" value="21k" />
            <Legend shade="bg-foreground/30" label="разговор" value="14k" />
          </div>
        </div>
        <button className="mt-3 flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground">
          <RotateCcw className="size-3.5" /> Сжать разговор
        </button>
      </SideSection>

      <SideSection title="Расход">
        <div className="space-y-3">
          <Meter label="5-часовое окно" value={34} note="сброс в 23:10" />
          <Meter label="Неделя" value={12} note="до понедельника" />
        </div>
        <p className="mt-3 text-xs text-muted-foreground">
          Этот чат <span className="text-foreground tabular-nums">~ $0,42</span> · 18 сообщений
        </p>
      </SideSection>

      <SideSection title="Быстро">
        <div className="flex flex-wrap gap-1.5">
          {["Что поделаем сегодня?", "Проверь сборку", "Найди баги в коммите", "Обнови ПЛАН.md"].map((q) => (
            <button key={q} className="rounded-full bg-muted/60 px-3 py-1.5 text-xs hover:bg-muted">
              {q}
            </button>
          ))}
        </div>
      </SideSection>
    </aside>
  )
}
