import { Brain, Check, MessageSquare, Plus, Send, X } from "lucide-react"
import { useState } from "react"
import { toast } from "sonner"

import { GroupTitle, Page, Segmented } from "@/components/page"
import { Button } from "@/components/ui/button"
import { useApp } from "@/lib/app-state"
import type { Profile } from "@/lib/mock-data"
import { cn } from "@/lib/utils"

// «С кем говорю»: у каждого собеседника свой профиль — как обращаться, тон,
// что можно и чего нельзя, своя память. В v1 это ты; в v2 через ботов придут другие люди.

export function PeoplePage() {
  const app = useApp()
  const [selected, setSelected] = useState(app.activeProfile)
  const p = app.profiles.find((x) => x.id === selected) ?? app.profiles[0]

  const update = (patch: Partial<Profile>) => app.setProfiles((ps) => ps.map((x) => (x.id === p.id ? { ...x, ...patch } : x)))

  const addProfile = () => {
    const id = `p${Date.now()}`
    app.setProfiles((ps) => [
      ...ps,
      { id, name: "Новый человек", call: "", role: "Кто это и откуда", tone: "plain", address: "ty", can: [], cannot: ["Видеть проекты Ромы"], via: "Telegram — во второй версии", memories: 0 },
    ])
    setSelected(id)
  }

  return (
    <Page
      title="С кем говорю"
      lead="Lumen отвечает каждому по-своему: обращение, тон и доступ берутся из профиля. Память у каждого своя и не смешивается."
      actions={
        <Button variant="outline" onClick={addProfile}>
          <Plus /> Новый профиль
        </Button>
      }
    >
      <div className="grid gap-6 lg:grid-cols-[240px_minmax(0,1fr)]">
        <div className="space-y-1">
          {app.profiles.map((x) => (
            <button
              key={x.id}
              onClick={() => setSelected(x.id)}
              className={cn(
                "flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition-colors hover:bg-foreground/5",
                x.id === selected && "bg-foreground/[0.07]"
              )}
            >
              <Avatar name={x.name} lit={x.id === app.activeProfile} />
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-medium">{x.name}</span>
                <span className="block truncate text-xs text-muted-foreground">{x.id === app.activeProfile ? "говорит сейчас" : x.via}</span>
              </span>
            </button>
          ))}
        </div>

        <div className="min-w-0 rounded-2xl border bg-card/40 p-6">
          <div className="flex items-center gap-4">
            <Avatar name={p.name} lit={p.id === app.activeProfile} size="lg" />
            <div className="min-w-0 flex-1">
              <input
                value={p.name}
                onChange={(e) => update({ name: e.target.value })}
                className="w-full bg-transparent text-xl font-semibold tracking-[-0.01em] outline-none"
                aria-label="Имя"
              />
              <input
                value={p.role}
                onChange={(e) => update({ role: e.target.value })}
                className="w-full bg-transparent text-sm text-muted-foreground outline-none"
                aria-label="Кто это"
              />
            </div>
            {p.id === app.activeProfile ? (
              <span className="flex items-center gap-1.5 text-xs text-glow">
                <Check className="size-3.5" /> Lumen говорит с ним сейчас
              </span>
            ) : (
              <Button
                variant="outline"
                onClick={() => {
                  app.setActiveProfile(p.id)
                  toast(`Теперь Lumen говорит с: ${p.name}`, { description: "Открой чат и спроси что-нибудь — ответ будет по его профилю." })
                }}
              >
                <MessageSquare /> Говорить от его лица
              </Button>
            )}
          </div>

          <div className="mt-7 grid gap-6 md:grid-cols-2">
            <Field label="Как обращаться">
              <input
                value={p.call}
                onChange={(e) => update({ call: e.target.value })}
                placeholder="Имя или как он любит"
                className="h-9 w-full rounded-lg border bg-input/30 px-3 text-sm outline-none focus:border-glow/50"
              />
            </Field>
            <Field label="На «ты» или на «вы»">
              <Segmented
                value={p.address}
                onChange={(v) => update({ address: v })}
                options={[
                  { id: "ty", name: "На «ты»" },
                  { id: "vy", name: "На «вы»" },
                ]}
              />
            </Field>
            <Field label="Тон">
              <Segmented
                value={p.tone}
                onChange={(v) => update({ tone: v })}
                options={[
                  { id: "warm", name: "Тепло" },
                  { id: "plain", name: "Ровно" },
                  { id: "formal", name: "Официально" },
                ]}
              />
            </Field>
            <Field label="Как Lumen его узнаёт">
              <p className="flex h-9 items-center gap-2 text-sm text-muted-foreground">
                {p.id === "roma" ? (
                  "Это Мак Ромы — значит, Рома"
                ) : (
                  <>
                    <Send className="size-3.5" /> По аккаунту в Telegram — во второй версии
                  </>
                )}
              </p>
            </Field>
          </div>

          <div className="mt-7 grid gap-6 md:grid-cols-2">
            <RuleList title="Можно" items={p.can} onChange={(can) => update({ can })} placeholder="Например: просить тексты" />
            <RuleList title="Нельзя" items={p.cannot} onChange={(cannot) => update({ cannot })} placeholder="Например: менять код" negative />
          </div>

          <div className="mt-7 flex items-center gap-3 rounded-xl bg-foreground/[0.04] px-4 py-3">
            <Brain className="size-4 text-glow" />
            <p className="text-sm">
              Своя память: <span className="tabular-nums">{app.memories.filter((m) => m.profile === p.id).length}</span> фактов
            </p>
            <Button
              size="sm"
              variant="ghost"
              className="ml-auto"
              onClick={() => {
                app.setActiveProfile(p.id)
                app.go("memory")
              }}
            >
              Открыть
            </Button>
          </div>
        </div>
      </div>
    </Page>
  )
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
      {name[0]}
    </span>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="mb-2 text-xs text-muted-foreground">{label}</p>
      {children}
    </div>
  )
}

/// Список правил с добавлением и удалением — для «можно / нельзя» и «всегда / никогда»
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
