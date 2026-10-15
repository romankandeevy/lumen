import { Brain, MessageSquare, Plus, Trash2, Undo2, UserRound, X } from "lucide-react"
import { useState } from "react"
import { toast } from "sonner"

import { GroupTitle, Page } from "@/components/page"
import { Button } from "@/components/ui/button"
import { useApp } from "@/lib/app-state"
import type { Person } from "@/lib/mock-data"
import { cn } from "@/lib/utils"

// «Люди»: анкеты о близких и коллегах. Lumen всегда говорит только с Ромой,
// а здесь хранит, что знает о других, — чтобы учитывать это в разговорах и текстах для них.

export function PeoplePage() {
  const app = useApp()
  const [selected, setSelected] = useState<string | null>(app.people[0]?.id ?? null)
  const p = app.people.find((x) => x.id === selected) ?? app.people[0]

  const addPerson = () => {
    const id = `p${Date.now()}`
    app.setPeople((ps) => [...ps, { id, name: "", relation: "", work: "", dates: "", howToTalk: "", interests: "", mentions: 0 }])
    setSelected(id)
  }

  const remove = (person: Person) => {
    const index = app.people.findIndex((x) => x.id === person.id)
    const rest = app.people.filter((x) => x.id !== person.id)
    app.setPeople(rest)
    setSelected(rest[Math.max(0, index - 1)]?.id ?? null)
    toast(`Анкета удалена: ${person.name || "без имени"}`, {
      description: "Факты о нём в памяти остались.",
      icon: <Undo2 className="size-4" />,
      action: {
        label: "Вернуть",
        onClick: () => {
          app.setPeople((ps) => [...ps.slice(0, index), person, ...ps.slice(index)])
          setSelected(person.id)
        },
      },
    })
  }

  return (
    <Page
      title="Люди"
      lead="Кто есть в твоей жизни. Lumen учитывает это, когда ты о них говоришь или просишь написать им."
      actions={
        <Button variant="outline" onClick={addPerson}>
          <Plus /> Добавить человека
        </Button>
      }
    >
      <div className="grid gap-6 lg:grid-cols-[240px_minmax(0,1fr)]">
        <div className="space-y-1">
          {app.people.map((x) => (
            <button
              key={x.id}
              onClick={() => setSelected(x.id)}
              className={cn(
                "flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition-colors hover:bg-foreground/5",
                x.id === p?.id && "bg-foreground/[0.07]"
              )}
            >
              <Avatar name={x.name} lit={x.id === p?.id} />
              <span className="min-w-0 flex-1">
                <span className={cn("block truncate text-sm font-medium", !x.name && "text-muted-foreground")}>{x.name || "Без имени"}</span>
                <span className="block truncate text-xs text-muted-foreground">{x.relation || "кто тебе — не указано"}</span>
              </span>
            </button>
          ))}
          {app.people.length === 0 && <p className="px-3 py-6 text-sm text-muted-foreground">Пока никого. Добавь папу, друга или коллегу.</p>}
        </div>

        {p ? (
          <Card key={p.id} person={p} onRemove={() => remove(p)} />
        ) : (
          <div className="flex flex-col items-center justify-center gap-3 rounded-2xl border border-dashed p-12 text-center">
            <UserRound className="size-6 text-muted-foreground" />
            <p className="max-w-sm text-sm text-muted-foreground">Расскажи Lumen о людях вокруг — он будет помнить, как к кому обращаться и что для них важно.</p>
            <Button onClick={addPerson}>
              <Plus /> Добавить человека
            </Button>
          </div>
        )}
      </div>
    </Page>
  )
}

function Card({ person: p, onRemove }: { person: Person; onRemove: () => void }) {
  const app = useApp()
  const [draft, setDraft] = useState("")
  const update = (patch: Partial<Person>) => app.setPeople((ps) => ps.map((x) => (x.id === p.id ? { ...x, ...patch } : x)))
  const facts = app.memories.filter((m) => m.kind === "people" && m.about.includes(p.id))

  const addFact = () => {
    const text = draft.trim()
    if (!text) return
    app.setMemories((ms) => [{ id: `m${Date.now()}`, text, kind: "people", source: `Анкета: ${p.name || "без имени"}`, when: "сейчас", about: [p.id] }, ...ms])
    app.setOrb("remember")
    setTimeout(() => app.setOrb("idle"), 1200)
    toast("Запомнил", { description: text })
    setDraft("")
  }

  return (
    <div className="min-w-0 rounded-2xl border bg-card/40 p-6">
      <div className="flex items-center gap-4">
        <Avatar name={p.name} lit size="lg" />
        <div className="min-w-0 flex-1">
          <input
            autoFocus={!p.name}
            value={p.name}
            onChange={(e) => update({ name: e.target.value })}
            placeholder="Имя"
            className="w-full bg-transparent text-xl font-semibold tracking-[-0.01em] outline-none placeholder:text-muted-foreground/60"
            aria-label="Имя"
          />
          <input
            value={p.relation}
            onChange={(e) => update({ relation: e.target.value })}
            placeholder="Кто тебе: отец, друг, коллега"
            className="w-full bg-transparent text-sm text-muted-foreground outline-none placeholder:text-muted-foreground/60"
            aria-label="Кто тебе"
          />
        </div>
        <Button variant="ghost" size="sm" onClick={onRemove} className="text-muted-foreground">
          <Trash2 /> Удалить
        </Button>
      </div>

      <div className="mt-7 grid gap-5 md:grid-cols-2">
        <Field label="Чем занимается" value={p.work} onChange={(work) => update({ work })} placeholder="Работа, учёба, чем живёт" />
        <Field label="Важные даты" value={p.dates} onChange={(dates) => update({ dates })} placeholder="Например: день рождения — 3 марта" />
        <Field label="Как с ним общаться" value={p.howToTalk} onChange={(howToTalk) => update({ howToTalk })} placeholder="На «ты» или «вы», можно ли шутить, без терминов" multiline />
        <Field label="Интересы" value={p.interests} onChange={(interests) => update({ interests })} placeholder="Что любит, чем увлекается" multiline />
      </div>

      <div className="mt-8">
        <GroupTitle aside={facts.length || undefined}>Что Lumen знает о нём</GroupTitle>
        <div className="space-y-1">
          {facts.map((m) => (
            <div key={m.id} className="group flex items-start gap-3 rounded-lg bg-foreground/[0.04] px-3 py-2">
              <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-[oklch(0.8_0.1_200)]" />
              <div className="min-w-0 flex-1">
                <p className="text-sm leading-snug">{m.text}</p>
                <p className="mt-0.5 text-xs text-muted-foreground">
                  из «{m.source}» · {m.when}
                </p>
              </div>
              <Button
                size="xs"
                variant="ghost"
                className="opacity-40 group-hover:opacity-100 focus-visible:opacity-100"
                onClick={() => {
                  app.setMemories((ms) => ms.filter((x) => x.id !== m.id))
                  toast("Забыл", {
                    description: m.text,
                    icon: <Undo2 className="size-4" />,
                    action: { label: "Вернуть", onClick: () => app.setMemories((ms) => [m, ...ms]) },
                  })
                }}
              >
                <X /> Забыть
              </Button>
            </div>
          ))}
          {facts.length === 0 && <p className="px-1 py-2 text-sm text-muted-foreground">Пока ничего. Добавь факт ниже или упомяни человека в чате.</p>}
          <div className="flex items-center gap-2 rounded-lg border border-dashed px-3 py-1 focus-within:border-glow/40">
            <Plus className="size-3.5 text-muted-foreground" />
            <input
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && addFact()}
              placeholder="Добавить факт: например, не любит звонки после девяти"
              className="h-8 w-full bg-transparent text-sm outline-none placeholder:text-muted-foreground"
            />
            {draft.trim() && (
              <Button size="xs" onClick={addFact}>
                Запомнить
              </Button>
            )}
          </div>
        </div>
      </div>

      <div className="mt-7 flex items-center gap-3 rounded-xl bg-foreground/[0.04] px-4 py-3">
        <MessageSquare className="size-4 text-muted-foreground" />
        <p className="text-sm">
          {p.mentions > 0 ? (
            <>
              Упоминался в <span className="tabular-nums">{p.mentions}</span> {chatsWord(p.mentions)}
            </>
          ) : (
            "Ещё не упоминался в чатах"
          )}
        </p>
        <Button size="sm" variant="ghost" className="ml-auto" onClick={() => app.go("memory")}>
          <Brain /> Вся память
        </Button>
      </div>
    </div>
  )
}

function chatsWord(n: number) {
  const d = n % 10
  const h = n % 100
  return d === 1 && h !== 11 ? "чате" : "чатах"
}

function Avatar({ name, lit, size = "md" }: { name: string; lit?: boolean; size?: "md" | "lg" }) {
  return (
    <span
      className={cn(
        "flex shrink-0 items-center justify-center rounded-full bg-foreground/10 font-medium",
        size === "lg" ? "size-14 text-xl" : "size-8 text-sm",
        lit && "ring-1 ring-glow/60 shadow-[0_0_18px_var(--glow-soft)]"
      )}
    >
      {name ? name[0] : <UserRound className={size === "lg" ? "size-6" : "size-4"} />}
    </span>
  )
}

function Field({
  label,
  value,
  onChange,
  placeholder,
  multiline,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  placeholder: string
  multiline?: boolean
}) {
  const cls = "w-full rounded-lg border bg-input/30 px-3 text-sm outline-none placeholder:text-muted-foreground/70 focus:border-glow/50"
  return (
    <label className="block">
      <span className="mb-2 block text-xs text-muted-foreground">{label}</span>
      {multiline ? (
        <textarea value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} rows={2} className={cn(cls, "resize-none py-2 leading-relaxed")} />
      ) : (
        <input value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} className={cn(cls, "h-9")} />
      )}
    </label>
  )
}

/// Список правил с добавлением и удалением — для «всегда / никогда» в характере
export function RuleList({
  title,
  items,
  onChange,
  placeholder,
  negative,
}: {
  title: string
  items: string[]
  onChange: (v: string[]) => void
  placeholder: string
  negative?: boolean
}) {
  const [draft, setDraft] = useState("")
  const add = () => {
    if (!draft.trim()) return
    onChange([...items, draft.trim()])
    setDraft("")
  }
  return (
    <div>
      <GroupTitle aside={items.length || undefined}>{title}</GroupTitle>
      <div className="space-y-1">
        {items.map((it, i) => (
          <div key={it + i} className="group flex items-center gap-2 rounded-lg bg-foreground/[0.04] px-3 py-1.5 text-sm">
            <span className={cn("size-1.5 shrink-0 rounded-full", negative ? "bg-foreground/30" : "bg-glow")} />
            <span className="min-w-0 flex-1">{it}</span>
            <button
              onClick={() => onChange(items.filter((_, j) => j !== i))}
              aria-label="Убрать"
              className="text-muted-foreground opacity-0 group-hover:opacity-100 hover:text-foreground focus:opacity-100"
            >
              <X className="size-3.5" />
            </button>
          </div>
        ))}
        <div className="flex items-center gap-2 rounded-lg border border-dashed px-3 py-1 focus-within:border-glow/40">
          <Plus className="size-3.5 text-muted-foreground" />
          <input
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && add()}
            placeholder={placeholder}
            className="h-7 w-full bg-transparent text-sm outline-none placeholder:text-muted-foreground"
          />
        </div>
      </div>
    </div>
  )
}
