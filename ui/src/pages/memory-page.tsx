import { Brain, Check, FileText, MessageSquare, Pencil, Pin, PinOff, Plus, Search, Undo2, X } from "lucide-react"
import { useState } from "react"
import { toast } from "sonner"

import { MemoryGraph } from "@/components/memory-graph"
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
        <MemoryGraph memories={all} openThread={(source) => sourceChats[source] && openThread(sourceChats[source])} />
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
