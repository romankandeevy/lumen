import { Brain, Check, FileText, MessageSquare, Pencil, Pin, PinOff, Plus, Search, Undo2, UserRound, X } from "lucide-react"
import { useMemo, useState } from "react"
import { toast } from "sonner"

import { GroupTitle, Page, Segmented } from "@/components/page"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Switch } from "@/components/ui/switch"
import { useApp } from "@/lib/app-state"
import { entities, memoryKinds, pastConversations, type Memory, type MemoryKind } from "@/lib/mock-data"
import { cn } from "@/lib/utils"

// «Что Lumen знает»: факты с источником (закрепить / изменить / забыть), граф связей
// и поиск по прошлым разговорам — как полнотекстовый поиск в Hermes.

type View = "facts" | "graph" | "talks"

// откуда факт → какой чат открыть; агентные сессии живут во вкладке «Агент»
const sourceChats: Record<string, string> = {
  "Lumen: замысел": "lumen",
  "Что поделаем сегодня?": "plan",
  "Тексты для блога": "blog",
  "Тексты для блога kandeev.com": "blog",
  "Идеи для Заметочек 1.2": "idea",
  "Почему падает Shelf?": "shelf",
  "Ревью Пульта перед релизом": "dash",
  "Пульт: с чего начать": "dash",
  "Island: анимация чёлки": "island",
}
const agentSessions = new Set(["shelf", "dash", "island", "night"])

function useOpenThread() {
  const app = useApp()
  return (id: string) => {
    app.setTab(agentSessions.has(id) ? "agent" : "chat")
    app.go("thread", id)
  }
}

export function MemoryPage() {
  const app = useApp()
  const openThread = useOpenThread()
  const [view, setView] = useState<View>("facts")
  const [kind, setKind] = useState<MemoryKind | "all">("all")
  const [query, setQuery] = useState("")
  const [adding, setAdding] = useState(false)
  const [fileOpen, setFileOpen] = useState<null | "USER.md" | "MEMORY.md">(null)
  const [auto, setAuto] = useState(true)

  const all = app.memories
  const shown = all
    .filter((m) => kind === "all" || m.kind === kind)
    .filter((m) => !query || m.text.toLowerCase().includes(query.toLowerCase()))
    .sort((a, b) => Number(!!b.pinned) - Number(!!a.pinned))
  const talks = pastConversations.filter((t) => !query || (t.title + t.summary + t.hit).toLowerCase().includes(query.toLowerCase()))

  return (
    <Page
      title="Что Lumen знает"
      lead="Память о тебе, твоих проектах и людях вокруг. Она подставляется в каждый разговор: закреплённое — всегда, остальное — когда к месту."
      actions={
        <Button onClick={() => setAdding(true)}>
          <Plus /> Запомнить факт
        </Button>
      }
    >
      <div className="flex flex-wrap items-center gap-3">
        <Segmented
          value={view}
          onChange={setView}
          options={[
            { id: "facts", name: `Факты, ${all.length}` },
            { id: "graph", name: "Граф" },
            { id: "talks", name: "Прошлые разговоры" },
          ]}
        />
        {view !== "graph" && (
          <label className="glow-field flex h-8 min-w-56 flex-1 items-center gap-2 rounded-lg border bg-input/30 px-2.5 text-sm">
            <Search className="size-4 text-muted-foreground" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={view === "facts" ? "Найти факт" : "Найти в разговорах: слово, проект, файл"}
              className="w-full bg-transparent outline-none placeholder:text-muted-foreground"
            />
            {query && (
              <button onClick={() => setQuery("")} aria-label="Очистить">
                <X className="size-3.5 text-muted-foreground" />
              </button>
            )}
          </label>
        )}
      </div>

      {view === "graph" ? (
        <MemoryGraph memories={all} openThread={openThread} />
      ) : (
        <div className="mt-4 grid gap-8 xl:grid-cols-[minmax(0,1fr)_280px]">
          <div className="min-w-0">
            {view === "facts" ? (
              <>
                <div className="flex flex-wrap gap-1.5">
                  {memoryKinds.map((k) => (
                    <button
                      key={k.id}
                      onClick={() => setKind(k.id)}
                      className={cn(
                        "rounded-full border px-3 py-1 text-xs transition-colors",
                        kind === k.id ? "border-glow/40 bg-glow/10 text-foreground" : "text-muted-foreground hover:text-foreground"
                      )}
                    >
                      {k.name}
                    </button>
                  ))}
                </div>
                <div className="mt-4 divide-y rounded-xl border bg-card/40">
                  {shown.length === 0 && (
                    <div className="px-4 py-10 text-center text-sm text-muted-foreground">
                      {query ? "Ничего не нашлось. Попробуй другое слово или поищи в прошлых разговорах." : "Здесь пусто. Скажи в чате «запомни, что…» — и факт появится тут."}
                    </div>
                  )}
                  {shown.map((m) => (
                    <FactRow key={m.id} memory={m} openThread={openThread} />
                  ))}
                </div>
              </>
            ) : (
              <div className="space-y-2">
                {talks.map((t) => (
                  <button
                    key={t.id}
                    onClick={() => openThread(t.id)}
                    className="block w-full rounded-xl border bg-card/40 px-4 py-3 text-left transition-colors hover:border-glow/30 hover:bg-card"
                  >
                    <div className="flex items-baseline gap-2">
                      <MessageSquare className="size-3.5 shrink-0 translate-y-0.5 text-muted-foreground" />
                      <p className="text-sm font-medium">{t.title}</p>
                      <span className="ml-auto text-xs text-muted-foreground">{t.when}</span>
                    </div>
                    <p className="mt-1.5 text-sm text-foreground/80">{t.summary}</p>
                    <p className="mt-1.5 text-xs text-muted-foreground italic">{t.hit}</p>
                  </button>
                ))}
                {talks.length === 0 && <p className="py-10 text-center text-sm text-muted-foreground">В разговорах такого не было.</p>}
              </div>
            )}
          </div>

          <aside className="space-y-6">
            <div>
              <GroupTitle>Файлы памяти</GroupTitle>
              <div className="space-y-1.5">
                {(
                  [
                    ["USER.md", "кто ты и как с тобой говорить", "1,2 тыс. знаков"],
                    ["MEMORY.md", "проекты, решения, люди", "3,8 тыс. знаков"],
                  ] as const
                ).map(([name, note, size]) => (
                  <button
                    key={name}
                    onClick={() => setFileOpen(name)}
                    className="flex w-full items-center gap-3 rounded-lg border bg-card/40 px-3 py-2 text-left hover:bg-card"
                  >
                    <FileText className="size-4 text-muted-foreground" />
                    <span className="min-w-0 flex-1">
                      <span className="block font-mono text-xs">{name}</span>
                      <span className="block truncate text-xs text-muted-foreground">{note}</span>
                    </span>
                    <span className="text-[11px] text-muted-foreground">{size}</span>
                  </button>
                ))}
              </div>
            </div>

            <div>
              <GroupTitle>Как запоминать</GroupTitle>
              <div className="space-y-3 rounded-xl border bg-card/40 p-3.5">
                <label className="flex items-start gap-3">
                  <span className="min-w-0 flex-1">
                    <span className="block text-sm">Запоминать само</span>
                    <span className="block text-xs text-muted-foreground">После разговора Lumen сам сохраняет важное и показывает плашку «Запомнил»</span>
                  </span>
                  <Switch checked={auto} onCheckedChange={setAuto} />
                </label>
                {all[0] && (
                  <p className="text-xs text-muted-foreground">
                    Последнее: <span className="text-foreground">«{all[0].text}»</span>
                  </p>
                )}
              </div>
            </div>
          </aside>
        </div>
      )}

      <AddFact open={adding} onClose={() => setAdding(false)} />
      <FileDialog name={fileOpen} onClose={() => setFileOpen(null)} />
    </Page>
  )
}

// ── строка факта ──

function SourceLink({ source, openThread }: { source: string; openThread: (id: string) => void }) {
  const id = sourceChats[source]
  if (!id) return <span>из «{source}»</span>
  return (
    <button onClick={() => openThread(id)} className="hover:text-glow">
      из «{source}»
    </button>
  )
}

function FactRow({ memory: m, openThread }: { memory: Memory; openThread: (id: string) => void }) {
  const app = useApp()
  const [editing, setEditing] = useState(false)
  const [text, setText] = useState(m.text)
  const kindName = memoryKinds.find((k) => k.id === m.kind)?.name
  const about = m.about.map((id) => entities.find((e) => e.id === id)?.name ?? app.people.find((p) => p.id === id)?.name).filter(Boolean)

  const save = () => {
    app.setMemories((ms) => ms.map((x) => (x.id === m.id ? { ...x, text } : x)))
    setEditing(false)
    toast("Факт изменён")
  }
  const forget = () => {
    app.setMemories((ms) => ms.filter((x) => x.id !== m.id))
    toast("Забыл", {
      description: m.text,
      action: { label: "Вернуть", onClick: () => app.setMemories((ms) => [m, ...ms]) },
      icon: <Undo2 className="size-4" />,
    })
  }

  return (
    <div className="group flex items-start gap-3 px-4 py-3">
      <span className={cn("mt-1.5 size-1.5 shrink-0 rounded-full", m.pinned ? "bg-glow shadow-[0_0_8px_var(--glow)]" : "bg-foreground/25")} />
      <div className="min-w-0 flex-1">
        {editing ? (
          <input
            autoFocus
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") save()
              if (e.key === "Escape") setEditing(false)
            }}
            className="w-full rounded-md border bg-background/60 px-2 py-1 text-sm outline-none focus:border-glow/50"
          />
        ) : (
          <p className="text-sm leading-relaxed">{m.text}</p>
        )}
        <p className="mt-1 flex flex-wrap items-center gap-x-2 text-xs text-muted-foreground">
          <span>{kindName}</span>
          {about.length > 0 && (
            <>
              <span className="text-foreground/20">/</span>
              <span>про {about.join(", ")}</span>
            </>
          )}
          <span className="text-foreground/20">/</span>
          <SourceLink source={m.source} openThread={openThread} />
          <span className="text-foreground/20">/</span>
          <span>{m.when}</span>
        </p>
      </div>
      <div className={cn("flex shrink-0 items-center gap-0.5 transition-opacity", !editing && "opacity-40 group-hover:opacity-100 focus-within:opacity-100")}>
        {editing ? (
          <Button size="xs" onClick={save}>
            <Check /> Сохранить
          </Button>
        ) : (
          <>
            <IconBtn
              label={m.pinned ? "Открепить" : "Закрепить: всегда в разговоре"}
              onClick={() => app.setMemories((ms) => ms.map((x) => (x.id === m.id ? { ...x, pinned: !x.pinned } : x)))}
            >
              {m.pinned ? <PinOff /> : <Pin />}
            </IconBtn>
            <IconBtn label="Изменить" onClick={() => setEditing(true)}>
              <Pencil />
            </IconBtn>
            <IconBtn label="Забыть" onClick={forget}>
              <X />
            </IconBtn>
          </>
        )}
      </div>
    </div>
  )
}

function IconBtn({ label, onClick, children }: { label: string; onClick: () => void; children: React.ReactNode }) {
  return (
    <Button size="icon-sm" variant="ghost" onClick={onClick} title={label} aria-label={label}>
      {children}
    </Button>
  )
}

// ── граф ──

const W = 800
const H = 520
const CX = W / 2
const CY = H / 2
const PERSON = "oklch(0.8 0.1 200)"

type GNode = { id: string; x: number; y: number; kind: "me" | "project" | "person" | "fact"; name: string; angle: number; memory?: Memory; tint: string }
type GEdge = { a: string; b: string; kind: "spoke" | "own" | "cross"; tint: string }

function layout(memories: Memory[]) {
  const known = new Set(entities.map((e) => e.id))
  const ring = [...entities.filter((e) => e.kind === "project"), ...entities.filter((e) => e.kind === "person")]
  const nodes = new Map<string, GNode>()
  const edges: GEdge[] = []

  const me = entities.find((e) => e.kind === "me")!
  nodes.set(me.id, { id: me.id, x: CX, y: CY, kind: "me", name: me.name, angle: 0, tint: "var(--glow)" })

  ring.forEach((e, i) => {
    const angle = -Math.PI / 2 + (i * 2 * Math.PI) / ring.length
    const tint = e.kind === "person" ? PERSON : "var(--glow)"
    nodes.set(e.id, { id: e.id, x: CX + Math.cos(angle) * 300, y: CY + Math.sin(angle) * 188, kind: e.kind, name: e.name, angle, tint })
    edges.push({ a: me.id, b: e.id, kind: "spoke", tint })
  })

  // факты группой вокруг своей первой сущности
  const groups = new Map<string, Memory[]>()
  for (const m of memories) {
    const home = m.about.find((id) => known.has(id)) ?? me.id
    groups.set(home, [...(groups.get(home) ?? []), m])
  }
  for (const [home, list] of groups) {
    const h = nodes.get(home)!
    list.forEach((m, k) => {
      let x: number
      let y: number
      if (h.kind === "me") {
        const a = -Math.PI / 3 + (k * 2 * Math.PI) / list.length
        x = CX + Math.cos(a) * 58
        y = CY + Math.sin(a) * 58
      } else {
        // веером внутрь кольца — подписи сущностей остаются снаружи
        const a = h.angle + Math.PI + (k - (list.length - 1) / 2) * 0.62
        x = h.x + Math.cos(a) * 44
        y = h.y + Math.sin(a) * 44
      }
      const tint = m.kind === "people" ? PERSON : "var(--glow)"
      nodes.set(m.id, { id: m.id, x, y, kind: "fact", name: m.text, angle: 0, memory: m, tint })
      edges.push({ a: home, b: m.id, kind: "own", tint: h.tint })
      for (const other of m.about) {
        if (other !== home && known.has(other)) edges.push({ a: m.id, b: other, kind: "cross", tint })
      }
    })
  }
  return { nodes: [...nodes.values()], byId: nodes, edges }
}

function MemoryGraph({ memories, openThread }: { memories: Memory[]; openThread: (id: string) => void }) {
  const app = useApp()
  const { nodes, byId, edges } = useMemo(() => layout(memories), [memories])
  const [hover, setHover] = useState<string | null>(null)
  const [selected, setSelected] = useState<string | null>("me")

  const focus = hover ?? selected
  const near = useMemo(() => {
    if (!focus) return null
    const s = new Set([focus])
    for (const e of edges) {
      if (e.a === focus) s.add(e.b)
      if (e.b === focus) s.add(e.a)
    }
    return s
  }, [focus, edges])

  const pick = (n: GNode) => setSelected(n.kind === "fact" ? (n.memory!.about.find((id) => byId.has(id)) ?? "me") : n.id)
  const hoveredFact = hover ? byId.get(hover)?.memory : undefined

  const entity = selected ? byId.get(selected) : undefined
  const entityFacts = selected ? memories.filter((m) => m.about.includes(selected) || (selected === "me" && !m.about.some((id) => byId.has(id)))) : []
  const isPerson = entity?.kind === "person"

  return (
    <div className="mt-4 grid gap-6 xl:grid-cols-[minmax(0,1fr)_300px]">
      <div className="relative min-w-0 overflow-hidden rounded-2xl border bg-card/30">
        <style>{`
          @keyframes lm-graph-breathe { 0%, 100% { opacity: .55; transform: scale(1); } 50% { opacity: 1; transform: scale(1.18); } }
          .lm-graph-breathe { transform-box: fill-box; transform-origin: center; animation: lm-graph-breathe 4.5s ease-in-out infinite; }
          @media (prefers-reduced-motion: reduce) { .lm-graph-breathe { animation: none; } }
          .lm-graph * { transition: opacity .25s ease, stroke-opacity .25s ease; }
        `}</style>
        <svg viewBox={`0 0 ${W} ${H}`} className="lm-graph block h-auto w-full" role="img" aria-label="Граф памяти: ты в центре, вокруг проекты и люди, точки — факты">
          <defs>
            <radialGradient id="lm-core-halo">
              <stop offset="0%" stopColor="var(--glow)" stopOpacity="0.55" />
              <stop offset="60%" stopColor="var(--glow)" stopOpacity="0.08" />
              <stop offset="100%" stopColor="var(--glow)" stopOpacity="0" />
            </radialGradient>
            <radialGradient id="lm-core-body" cx="38%" cy="34%">
              <stop offset="0%" stopColor="var(--glow-core)" />
              <stop offset="70%" stopColor="var(--glow)" />
            </radialGradient>
          </defs>

          {/* рёбра */}
          {edges.map((e, i) => {
            const a = byId.get(e.a)!
            const b = byId.get(e.b)!
            const lit = focus && (e.a === focus || e.b === focus)
            const base = e.kind === "spoke" ? 0.16 : e.kind === "own" ? 0.22 : 0.13
            return (
              <line
                key={i}
                x1={a.x}
                y1={a.y}
                x2={b.x}
                y2={b.y}
                stroke={e.tint}
                strokeWidth={e.kind === "spoke" ? 1 : 0.8}
                strokeDasharray={e.kind === "cross" ? "3 4" : undefined}
                strokeOpacity={focus ? (lit ? 0.75 : 0.04) : base}
              />
            )
          })}

          {/* узлы */}
          {nodes.map((n) => {
            const dim = near && !near.has(n.id)
            const isSel = selected === n.id
            const common = {
              role: "button",
              tabIndex: 0,
              style: { cursor: "pointer", opacity: dim ? 0.2 : 1 },
              onMouseEnter: () => setHover(n.id),
              onMouseLeave: () => setHover(null),
              onFocus: () => setHover(n.id),
              onBlur: () => setHover(null),
              onClick: () => pick(n),
              onKeyDown: (e: React.KeyboardEvent) => (e.key === "Enter" || e.key === " ") && pick(n),
            }
            if (n.kind === "fact")
              return (
                <g key={n.id} {...common} aria-label={n.name}>
                  <circle cx={n.x} cy={n.y} r={9} fill="transparent" />
                  <circle cx={n.x} cy={n.y} r={n.memory?.pinned ? 5 : 4} fill={n.tint} fillOpacity={hover === n.id ? 1 : 0.85} style={{ filter: "drop-shadow(0 0 4px var(--glow-soft))" }} />
                  {n.memory?.pinned && <circle cx={n.x} cy={n.y} r={8.5} fill="none" stroke={n.tint} strokeOpacity={0.4} />}
                </g>
              )
            if (n.kind === "me")
              return (
                <g key={n.id} {...common} aria-label={n.name}>
                  <circle className="lm-graph-breathe" cx={n.x} cy={n.y} r={46} fill="url(#lm-core-halo)" />
                  <circle cx={n.x} cy={n.y} r={15} fill="url(#lm-core-body)" />
                  {isSel && <circle cx={n.x} cy={n.y} r={21} fill="none" stroke="var(--glow)" strokeOpacity={0.5} />}
                  <text x={n.x} y={n.y + 36} textAnchor="middle" fontSize={13} fontWeight={600} fill="var(--foreground)">
                    {n.name}
                  </text>
                </g>
              )
            const cos = Math.cos(n.angle)
            const sin = Math.sin(n.angle)
            const anchor = cos > 0.35 ? "start" : cos < -0.35 ? "end" : "middle"
            const lx = n.x + cos * 16
            const ly = n.y + sin * 16 + (Math.abs(cos) <= 0.35 ? (sin > 0 ? 10 : -2) : 4)
            const count = memories.filter((m) => m.about.includes(n.id)).length
            return (
              <g key={n.id} {...common} aria-label={`${n.name}: ${count} фактов`}>
                <circle cx={n.x} cy={n.y} r={16} fill={n.tint} fillOpacity={hover === n.id || isSel ? 0.16 : 0.06} />
                <circle cx={n.x} cy={n.y} r={n.kind === "person" ? 6 : 7} fill="var(--card)" stroke={n.tint} strokeWidth={1.5} />
                {isSel && <circle cx={n.x} cy={n.y} r={11} fill="none" stroke={n.tint} strokeOpacity={0.6} />}
                <text x={lx} y={ly} textAnchor={anchor} fontSize={12.5} fontWeight={500} fill="var(--foreground)" paintOrder="stroke" stroke="var(--background)" strokeWidth={3}>
                  {n.name}
                </text>
              </g>
            )
          })}
        </svg>

        <div className="pointer-events-none absolute inset-x-0 bottom-0 flex min-h-10 items-end justify-between gap-4 bg-gradient-to-t from-background/80 to-transparent px-4 pt-6 pb-3 text-xs">
          <span className="min-w-0 truncate text-foreground/85">{hoveredFact ? hoveredFact.text : "Наведи на точку — увидишь факт. Нажми на узел — справа его карточка."}</span>
          <span className="flex shrink-0 items-center gap-3 text-muted-foreground">
            <Legend color="var(--glow)" label="проекты" />
            <Legend color={PERSON} label="люди" />
          </span>
        </div>
      </div>

      <aside className="min-w-0">
        {entity ? (
          <div className="rounded-2xl border bg-card/40 p-4">
            <div className="flex items-center gap-3">
              <span
                className="flex size-9 shrink-0 items-center justify-center rounded-full text-sm font-medium"
                style={{ background: `color-mix(in oklch, ${entity.tint} 16%, transparent)`, boxShadow: `0 0 0 1px color-mix(in oklch, ${entity.tint} 45%, transparent)` }}
              >
                {entity.kind === "me" ? <Brain className="size-4 text-glow" /> : entity.name[0]}
              </span>
              <div className="min-w-0">
                <p className="truncate text-base font-semibold">{entity.name}</p>
                <p className="text-xs text-muted-foreground">
                  {{ me: "это ты", project: "проект", person: "человек", fact: "" }[entity.kind]} · {plural(entityFacts.length, "факт", "факта", "фактов")}
                </p>
              </div>
            </div>
            <div className="mt-4 space-y-2">
              {entityFacts.map((m) => (
                <div
                  key={m.id}
                  onMouseEnter={() => setHover(m.id)}
                  onMouseLeave={() => setHover(null)}
                  className={cn("rounded-lg bg-foreground/[0.04] px-3 py-2 transition-colors", hover === m.id && "bg-glow/10")}
                >
                  <p className="text-sm leading-snug">{m.text}</p>
                  <p className="mt-1 flex flex-wrap gap-x-2 text-xs text-muted-foreground">
                    <SourceLink source={m.source} openThread={openThread} />
                    <span className="text-foreground/20">/</span>
                    <span>{m.when}</span>
                  </p>
                </div>
              ))}
              {entityFacts.length === 0 && <p className="py-4 text-center text-sm text-muted-foreground">Пока ничего не знаю.</p>}
            </div>
            {isPerson && (
              <Button variant="outline" size="sm" className="mt-4 w-full" onClick={() => app.go("people")}>
                <UserRound /> Открыть анкету
              </Button>
            )}
          </div>
        ) : (
          <p className="rounded-2xl border border-dashed p-6 text-center text-sm text-muted-foreground">Нажми на узел, чтобы увидеть, что Lumen о нём знает.</p>
        )}
      </aside>
    </div>
  )
}

function Legend({ color, label }: { color: string; label: string }) {
  return (
    <span className="flex items-center gap-1.5">
      <span className="size-1.5 rounded-full" style={{ background: color }} />
      {label}
    </span>
  )
}

function plural(n: number, one: string, few: string, many: string) {
  const d = n % 10
  const h = n % 100
  const w = d === 1 && h !== 11 ? one : d >= 2 && d <= 4 && (h < 12 || h > 14) ? few : many
  return `${n} ${w}`
}

// ── диалоги ──

function AddFact({ open, onClose }: { open: boolean; onClose: () => void }) {
  const app = useApp()
  const [text, setText] = useState("")
  const [kind, setKind] = useState<MemoryKind>("you")
  const [about, setAbout] = useState<string[]>(["me"])
  const [pinned, setPinned] = useState(false)
  const add = () => {
    if (!text.trim()) return
    app.setMemories((ms) => [
      { id: `m${Date.now()}`, text: text.trim(), kind, source: "Добавлено вручную", when: "сейчас", pinned, about: about.length ? about : ["me"] },
      ...ms,
    ])
    app.setOrb("remember")
    setTimeout(() => app.setOrb("idle"), 1200)
    toast("Запомнил", { description: text.trim() })
    setText("")
    setAbout(["me"])
    onClose()
  }
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Brain className="size-4 text-glow" /> Запомнить факт
          </DialogTitle>
          <DialogDescription>Одна мысль — один факт. Lumen будет учитывать его в разговорах.</DialogDescription>
        </DialogHeader>
        <textarea
          autoFocus
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Например: по пятницам релизов не делаем"
          className="min-h-20 w-full resize-none rounded-lg border bg-input/30 px-3 py-2 text-sm outline-none focus:border-glow/50"
        />
        <div className="flex flex-wrap items-center gap-3">
          <Segmented value={kind} onChange={setKind} options={memoryKinds.filter((k) => k.id !== "all") as { id: MemoryKind; name: string }[]} />
          <label className="flex items-center gap-2 text-sm">
            <Switch checked={pinned} onCheckedChange={setPinned} /> Закрепить
          </label>
        </div>
        <div>
          <p className="mb-2 text-xs text-muted-foreground">Про что этот факт</p>
          <div className="flex flex-wrap gap-1.5">
            {entities.map((e) => {
              const on = about.includes(e.id)
              return (
                <button
                  key={e.id}
                  onClick={() => setAbout((a) => (on ? a.filter((x) => x !== e.id) : [...a, e.id]))}
                  className={cn(
                    "rounded-full border px-2.5 py-0.5 text-xs transition-colors",
                    on ? "border-glow/40 bg-glow/10 text-foreground" : "text-muted-foreground hover:text-foreground"
                  )}
                >
                  {e.name}
                </button>
              )
            })}
          </div>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>
            Отмена
          </Button>
          <Button onClick={add} disabled={!text.trim()}>
            Запомнить
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function FileDialog({ name, onClose }: { name: null | "USER.md" | "MEMORY.md"; onClose: () => void }) {
  const app = useApp()
  const lines =
    name === "USER.md"
      ? app.memories.filter((m) => m.kind === "you" || m.kind === "pref")
      : app.memories.filter((m) => m.kind === "project" || m.kind === "decision" || m.kind === "people")
  return (
    <Dialog open={!!name} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-xl">
        <DialogHeader>
          <DialogTitle className="font-mono text-sm">~/Library/Application Support/Lumen/{name}</DialogTitle>
          <DialogDescription>Этот файл Lumen читает в начале каждого разговора. Его можно править и руками.</DialogDescription>
        </DialogHeader>
        <pre className="max-h-80 overflow-auto rounded-lg border bg-background/60 p-3 font-mono text-xs leading-relaxed whitespace-pre-wrap">
          {`# ${name === "USER.md" ? "Кто ты" : "Проекты, решения и люди"}\n\n` + lines.map((m) => `- ${m.text}`).join("\n")}
        </pre>
        <DialogFooter>
          <Button variant="outline" onClick={() => toast("Открыто в редакторе", { description: name ?? "" })}>
            Открыть в редакторе
          </Button>
          <Button onClick={onClose}>Готово</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
