import { BookOpen, ChevronRight, Eye, EyeOff, Globe, Laptop, Loader2, Plus, Search, Server, Sparkles, Wand2 } from "lucide-react"
import { useMemo, useState } from "react"
import { toast } from "sonner"

import { GroupTitle, Page, Segmented } from "@/components/page"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Switch } from "@/components/ui/switch"
import { apis as initialApis, connectors as initialConnectors, mcpServers as initialMcp, skills as initialSkills } from "@/lib/mock-data"
import { cn } from "@/lib/utils"

// Инструменты: всё, чем Lumen и боты могут пользоваться — навыки, MCP-серверы, коннекторы и API.
// Макет: подключение, проверка ключей и каталог — имитация, ничего никуда не уходит.

type TabId = "skills" | "mcp" | "connectors" | "api"
type Skill = { id: string; name: string; note: string; source: string; uses: number; on: boolean }
type McpServer = { id: string; name: string; note: string; tools: number; on: boolean; local: boolean }
type Connector = { id: string; name: string; note: string; on: boolean; soon?: boolean }
type Api = { id: string; name: string; note: string; on: boolean; key?: string }

const field = "glow-field h-9 w-full rounded-lg border bg-input/30 px-3 text-sm outline-none placeholder:text-muted-foreground"

const matches = (q: string, ...texts: string[]) => !q || texts.some((t) => t.toLowerCase().includes(q.toLowerCase()))

export function ToolsPage() {
  const [tab, setTab] = useState<TabId>("skills")
  const [query, setQuery] = useState("")
  const [skills, setSkills] = useState<Skill[]>(initialSkills)
  const [mcp, setMcp] = useState<McpServer[]>(initialMcp)
  const [connectors, setConnectors] = useState<Connector[]>(initialConnectors)
  const [apis, setApis] = useState<Api[]>(initialApis)

  const counts: Record<TabId, number> = {
    skills: skills.filter((s) => s.on).length,
    mcp: mcp.filter((s) => s.on).length,
    connectors: connectors.filter((c) => c.on).length,
    api: apis.filter((a) => a.on).length,
  }

  return (
    <Page title="Инструменты" lead="Всё, чем Lumen и боты могут пользоваться. Выключенное просто не попадает им в руки.">
      <div className="max-w-4xl">
        <div className="flex flex-wrap items-center gap-3">
          <Segmented
            value={tab}
            onChange={setTab}
            options={[
              { id: "skills", name: `Навыки · ${counts.skills}` },
              { id: "mcp", name: `MCP · ${counts.mcp}` },
              { id: "connectors", name: `Коннекторы · ${counts.connectors}` },
              { id: "api", name: `API · ${counts.api}` },
            ]}
          />
          <label className="glow-field ml-auto flex h-8 w-full items-center gap-2 rounded-lg border bg-input/30 px-3 sm:w-64">
            <Search className="size-3.5 text-muted-foreground" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Найти инструмент"
              aria-label="Поиск по инструментам"
              className="w-full bg-transparent text-sm outline-none placeholder:text-muted-foreground"
            />
          </label>
        </div>

        <div className="mt-6">
          {tab === "skills" && <SkillsTab items={skills} setItems={setSkills} query={query} />}
          {tab === "mcp" && <McpTab items={mcp} setItems={setMcp} query={query} />}
          {tab === "connectors" && <ConnectorsTab items={connectors} setItems={setConnectors} query={query} />}
          {tab === "api" && <ApiTab items={apis} setItems={setApis} query={query} />}
        </div>
      </div>
    </Page>
  )
}

function Empty({ query }: { query: string }) {
  return <p className="rounded-xl border border-dashed px-4 py-8 text-center text-sm text-muted-foreground">Ничего не нашлось по «{query}»</p>
}

function Dot({ on }: { on: boolean }) {
  return <span className={cn("size-1.5 shrink-0 rounded-full", on ? "bg-emerald-400 shadow-[0_0_8px_theme(colors.emerald.400)]" : "bg-foreground/25")} />
}

// ── навыки ──

function SourceBadge({ source }: { source: string }) {
  const self = source === "сам научился"
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-md border px-1.5 py-0.5 text-[11px] whitespace-nowrap",
        self ? "border-glow/40 bg-glow/[0.08] text-glow shadow-[0_0_14px_-4px_var(--glow-soft)]" : "text-muted-foreground"
      )}
    >
      {self && <Sparkles className="size-3" />}
      {source === "каталог agentskills.io" ? "каталог agentskills.io" : source}
    </span>
  )
}

const catalog = [
  { id: "docx", name: "Документы Word", note: "читать и править .docx" },
  { id: "xlsx", name: "Таблицы", note: "формулы, графики, выгрузка в .xlsx" },
  { id: "slides", name: "Слайды", note: "собрать презентацию из заметок" },
  { id: "scrape", name: "Выжимка страницы", note: "главное со страницы в 5 строк" },
  { id: "i18n", name: "Перевод интерфейса", note: "строки приложения на английский" },
]

function SkillsTab({ items, setItems, query }: { items: Skill[]; setItems: React.Dispatch<React.SetStateAction<Skill[]>>; query: string }) {
  const [createOpen, setCreateOpen] = useState(false)
  const [catalogOpen, setCatalogOpen] = useState(false)
  const shown = items.filter((s) => matches(query, s.name, s.note, s.source))

  return (
    <>
      <GroupTitle aside={`${items.length} навыков`}>Что Lumen умеет делать по шагам</GroupTitle>
      <div className="mb-4 flex gap-2">
        <Button size="sm" onClick={() => setCreateOpen(true)}>
          <Plus /> Создать навык
        </Button>
        <Button size="sm" variant="outline" onClick={() => setCatalogOpen(true)}>
          <BookOpen /> Каталог навыков
        </Button>
      </div>
      {shown.length === 0 ? (
        <Empty query={query} />
      ) : (
        <div className="divide-y rounded-xl border bg-card/40">
          {shown.map((s) => (
            <div key={s.id} className={cn("flex items-center gap-4 px-4 py-3 transition-opacity", !s.on && "opacity-60")}>
              <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-foreground/[0.06]">
                <Wand2 className="size-4" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="flex flex-wrap items-center gap-2">
                  <span className="text-sm font-medium">{s.name}</span>
                  <SourceBadge source={s.source} />
                </span>
                <span className="mt-0.5 block truncate text-xs text-muted-foreground">{s.note}</span>
              </span>
              <span className="hidden text-xs whitespace-nowrap text-muted-foreground tabular-nums sm:block">
                {s.uses ? `использован ${s.uses} раз` : "ещё не использован"}
              </span>
              <Switch
                checked={s.on}
                onCheckedChange={(on) => setItems((xs) => xs.map((x) => (x.id === s.id ? { ...x, on } : x)))}
                aria-label={`Навык «${s.name}»`}
              />
            </div>
          ))}
        </div>
      )}

      <CreateSkillDialog
        open={createOpen}
        onClose={() => setCreateOpen(false)}
        onCreate={(name, when) => {
          setItems((xs) => [{ id: `s${Date.now()}`, name, note: when, source: "мой", uses: 0, on: true }, ...xs])
          toast("Навык создан", { description: name })
        }}
      />
      <CatalogDialog
        open={catalogOpen}
        onClose={() => setCatalogOpen(false)}
        added={items.map((s) => s.id)}
        onAdd={(c) => {
          setItems((xs) => [...xs, { id: c.id, name: c.name, note: c.note, source: "каталог agentskills.io", uses: 0, on: true }])
          toast("Навык добавлен", { description: c.name })
        }}
      />
    </>
  )
}

function CreateSkillDialog({ open, onClose, onCreate }: { open: boolean; onClose: () => void; onCreate: (name: string, when: string) => void }) {
  const [name, setName] = useState("")
  const [when, setWhen] = useState("")
  const [steps, setSteps] = useState("")
  const submit = () => {
    onCreate(name.trim(), when.trim() || "по просьбе")
    setName("")
    setWhen("")
    setSteps("")
    onClose()
  }
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Wand2 className="size-4 text-glow" /> Новый навык
          </DialogTitle>
          <DialogDescription>Навык — это готовый порядок действий. Lumen сам поймёт, когда его взять.</DialogDescription>
        </DialogHeader>
        <label className="space-y-1.5 text-xs text-muted-foreground">
          Название
          <input autoFocus value={name} onChange={(e) => setName(e.target.value)} placeholder="Например: Релиз приложения" className={field} />
        </label>
        <label className="space-y-1.5 text-xs text-muted-foreground">
          Когда применять
          <input value={when} onChange={(e) => setWhen(e.target.value)} placeholder="Когда прошу выпустить новую версию" className={field} />
        </label>
        <label className="space-y-1.5 text-xs text-muted-foreground">
          Шаги, по одному на строку
          <textarea
            value={steps}
            onChange={(e) => setSteps(e.target.value)}
            placeholder={"Поднять версию\nСобрать и проверить\nНаписать, что нового"}
            className="glow-field min-h-24 w-full resize-none rounded-lg border bg-input/30 px-3 py-2 text-sm text-foreground outline-none placeholder:text-muted-foreground"
          />
        </label>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>
            Отмена
          </Button>
          <Button onClick={submit} disabled={!name.trim()}>
            Создать
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function CatalogDialog({
  open,
  onClose,
  added,
  onAdd,
}: {
  open: boolean
  onClose: () => void
  added: string[]
  onAdd: (c: (typeof catalog)[number]) => void
}) {
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <BookOpen className="size-4 text-glow" /> Каталог навыков
          </DialogTitle>
          <DialogDescription>Готовые навыки с agentskills.io. Добавленный сразу включается.</DialogDescription>
        </DialogHeader>
        <div className="-mx-1 max-h-80 divide-y overflow-auto">
          {catalog.map((c) => {
            const has = added.includes(c.id)
            return (
              <div key={c.id} className="flex items-center gap-3 px-1 py-2.5">
                <span className="min-w-0 flex-1">
                  <span className="block text-sm">{c.name}</span>
                  <span className="block text-xs text-muted-foreground">{c.note}</span>
                </span>
                <Button size="sm" variant={has ? "ghost" : "outline"} disabled={has} onClick={() => onAdd(c)}>
                  {has ? "Добавлен" : "Добавить"}
                </Button>
              </div>
            )
          })}
        </div>
      </DialogContent>
    </Dialog>
  )
}

// ── MCP ──

const fakeTools: Record<string, string[]> = {
  fs: ["read_file", "write_file", "edit_file", "list_dir", "search", "move", "stat", "tree"],
  xcode: ["build", "test", "run", "simulator_boot", "screenshot", "logs"],
  browser: ["open", "screenshot", "click", "type", "read_page"],
  tldraw: ["exec", "search", "export"],
}

function McpTab({ items, setItems, query }: { items: McpServer[]; setItems: React.Dispatch<React.SetStateAction<McpServer[]>>; query: string }) {
  const [openId, setOpenId] = useState<string | null>(null)
  const [addOpen, setAddOpen] = useState(false)
  const shown = items.filter((s) => matches(query, s.name, s.note))

  return (
    <>
      <GroupTitle aside="серверы с инструментами по протоколу MCP">Серверы</GroupTitle>
      <div className="mb-4">
        <Button size="sm" onClick={() => setAddOpen(true)}>
          <Plus /> Добавить сервер
        </Button>
      </div>
      {shown.length === 0 ? (
        <Empty query={query} />
      ) : (
        <div className="divide-y rounded-xl border bg-card/40">
          {shown.map((s) => {
            const expanded = openId === s.id
            const tools = fakeTools[s.id] ?? Array.from({ length: s.tools }, (_, i) => `tool_${i + 1}`)
            return (
              <div key={s.id}>
                <div className="flex items-center gap-3 px-4 py-3">
                  <button
                    onClick={() => setOpenId(expanded ? null : s.id)}
                    aria-expanded={expanded}
                    className="flex min-w-0 flex-1 items-center gap-3 text-left"
                  >
                    <ChevronRight className={cn("size-4 shrink-0 text-muted-foreground transition-transform", expanded && "rotate-90")} />
                    <Dot on={s.on} />
                    <span className="min-w-0 flex-1">
                      <span className="block text-sm font-medium">{s.name}</span>
                      <span className="block truncate text-xs text-muted-foreground">{s.note}</span>
                    </span>
                    <span className="hidden items-center gap-1 text-xs text-muted-foreground sm:flex">
                      {s.local ? <Laptop className="size-3.5" /> : <Globe className="size-3.5" />}
                      {s.local ? "на этом Маке" : "удалённый"}
                    </span>
                    <span className="w-24 text-right text-xs text-muted-foreground tabular-nums">{s.tools} инструментов</span>
                  </button>
                  <Switch
                    checked={s.on}
                    onCheckedChange={(on) => setItems((xs) => xs.map((x) => (x.id === s.id ? { ...x, on } : x)))}
                    aria-label={`Сервер «${s.name}»`}
                  />
                </div>
                {expanded && (
                  <div className="flex flex-wrap gap-1.5 px-4 pb-3.5 pl-[3.25rem]">
                    {tools.map((t) => (
                      <span key={t} className="rounded-md border bg-background/40 px-2 py-0.5 font-mono text-[11px] text-muted-foreground">
                        {t}
                      </span>
                    ))}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}
      <AddServerDialog
        open={addOpen}
        onClose={() => setAddOpen(false)}
        onAdd={(s) => {
          setItems((xs) => [...xs, s])
          toast("Сервер добавлен", { description: `${s.name} · ${s.tools} инструментов` })
        }}
      />
    </>
  )
}

function AddServerDialog({ open, onClose, onAdd }: { open: boolean; onClose: () => void; onAdd: (s: McpServer) => void }) {
  const [name, setName] = useState("")
  const [target, setTarget] = useState("")
  const [env, setEnv] = useState("")
  const remote = /^https?:\/\//.test(target.trim())
  const submit = () => {
    onAdd({ id: `m${Date.now()}`, name: name.trim(), note: target.trim(), tools: 4, on: true, local: !remote })
    setName("")
    setTarget("")
    setEnv("")
    onClose()
  }
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Server className="size-4 text-glow" /> Новый MCP-сервер
          </DialogTitle>
          <DialogDescription>Команда запустит сервер на этом Маке, адрес подключит удалённый.</DialogDescription>
        </DialogHeader>
        <label className="space-y-1.5 text-xs text-muted-foreground">
          Название
          <input autoFocus value={name} onChange={(e) => setName(e.target.value)} placeholder="Например: Postgres" className={field} />
        </label>
        <label className="space-y-1.5 text-xs text-muted-foreground">
          Команда или адрес
          <input value={target} onChange={(e) => setTarget(e.target.value)} placeholder="npx -y @server/postgres  или  https://…" className={cn(field, "font-mono text-xs")} />
          {target.trim() && <span className="block">{remote ? "удалённый сервер" : "запустится на этом Маке"}</span>}
        </label>
        <label className="space-y-1.5 text-xs text-muted-foreground">
          Переменные окружения, по одной на строку
          <textarea
            value={env}
            onChange={(e) => setEnv(e.target.value)}
            placeholder="DATABASE_URL=…"
            className="glow-field min-h-16 w-full resize-none rounded-lg border bg-input/30 px-3 py-2 font-mono text-xs text-foreground outline-none placeholder:text-muted-foreground"
          />
        </label>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>
            Отмена
          </Button>
          <Button onClick={submit} disabled={!name.trim() || !target.trim()}>
            Добавить
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// ── коннекторы ──

function ConnectorsTab({ items, setItems, query }: { items: Connector[]; setItems: React.Dispatch<React.SetStateAction<Connector[]>>; query: string }) {
  const [busy, setBusy] = useState<string | null>(null)
  const shown = items.filter((c) => matches(query, c.name, c.note))

  const toggle = (c: Connector) => {
    if (c.on) {
      setItems((xs) => xs.map((x) => (x.id === c.id ? { ...x, on: false } : x)))
      toast("Отключено", { description: c.name })
      return
    }
    setBusy(c.id)
    setTimeout(() => {
      setBusy(null)
      setItems((xs) => xs.map((x) => (x.id === c.id ? { ...x, on: true } : x)))
      toast(`${c.name} подключён`, { description: "Вход через браузер прошёл" })
    }, 1300)
  }

  return (
    <>
      <GroupTitle aside="вход через браузер, ключи хранятся в Связке ключей">Сервисы</GroupTitle>
      {shown.length === 0 ? (
        <Empty query={query} />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {shown.map((c) => (
            <div
              key={c.id}
              className={cn(
                "flex flex-col rounded-2xl border p-4 transition-colors",
                c.on ? "bg-card/60" : "bg-card/30",
                c.soon && "border-dashed"
              )}
            >
              <div className="flex items-center gap-3">
                <span
                  className={cn(
                    "flex size-9 items-center justify-center rounded-xl text-sm font-semibold",
                    c.on ? "bg-glow/[0.12] text-glow shadow-[0_0_18px_-6px_var(--glow-soft)]" : "bg-foreground/[0.06] text-foreground/70"
                  )}
                >
                  {c.name[0]}
                </span>
                <span className="min-w-0 flex-1 text-sm font-medium">{c.name}</span>
                {c.soon ? (
                  <span className="rounded-md border px-2 py-0.5 text-[11px] text-muted-foreground">позже</span>
                ) : (
                  c.on && <Dot on />
                )}
              </div>
              <p className="mt-3 flex-1 text-xs leading-relaxed text-muted-foreground">{c.note}</p>
              <Button
                size="sm"
                variant={c.on ? "ghost" : "outline"}
                className="mt-4 self-start"
                disabled={c.soon || busy === c.id}
                onClick={() => toggle(c)}
              >
                {busy === c.id && <Loader2 className="animate-spin" />}
                {c.soon ? "Скоро" : busy === c.id ? "Подключаю…" : c.on ? "Отключить" : "Подключить"}
              </Button>
            </div>
          ))}
        </div>
      )}
    </>
  )
}

// ── API ──

function ApiTab({ items, setItems, query }: { items: Api[]; setItems: React.Dispatch<React.SetStateAction<Api[]>>; query: string }) {
  const [addOpen, setAddOpen] = useState(false)
  const shown = items.filter((a) => matches(query, a.name, a.note))
  return (
    <>
      <GroupTitle aside="ключи хранятся в Связке ключей macOS">Внешние API</GroupTitle>
      <div className="mb-4">
        <Button size="sm" onClick={() => setAddOpen(true)}>
          <Plus /> Добавить API
        </Button>
      </div>
      {shown.length === 0 ? (
        <Empty query={query} />
      ) : (
        <div className="divide-y rounded-xl border bg-card/40">
          {shown.map((a) => (
            <ApiRow key={a.id} api={a} onToggle={(on) => setItems((xs) => xs.map((x) => (x.id === a.id ? { ...x, on } : x)))} />
          ))}
        </div>
      )}
      <AddApiDialog
        open={addOpen}
        onClose={() => setAddOpen(false)}
        onAdd={(a) => {
          setItems((xs) => [...xs, a])
          toast("API добавлен", { description: a.name })
        }}
      />
    </>
  )
}

function ApiRow({ api, onToggle }: { api: Api; onToggle: (on: boolean) => void }) {
  const noKey = api.note.includes("без ключа")
  const [key, setKey] = useState(api.key ?? "")
  const [show, setShow] = useState(false)
  const [state, setState] = useState<"idle" | "checking" | "ok" | "bad">(api.on && !noKey ? "ok" : "idle")
  const check = () => {
    setState("checking")
    setTimeout(() => {
      const ok = noKey || key.trim().length >= 8 || (!key && api.on)
      setState(ok ? "ok" : "bad")
      toast(ok ? "Работает" : "Не подошло", { description: ok ? `${api.name} отвечает` : "Проверь ключ и попробуй ещё раз" })
    }, 1000)
  }
  return (
    <div className={cn("flex flex-wrap items-center gap-3 px-4 py-3 sm:flex-nowrap", !api.on && "opacity-70")}>
      <Dot on={api.on && state !== "bad"} />
      <span className="min-w-0 sm:w-48">
        <span className="block text-sm font-medium">{api.name}</span>
        <span className="block truncate text-xs text-muted-foreground">{api.note}</span>
      </span>
      {noKey ? (
        <span className="flex-1 text-xs text-muted-foreground">ключ не нужен</span>
      ) : (
        <label className="glow-field flex h-8 min-w-0 flex-1 items-center gap-2 rounded-lg border bg-input/30 px-2.5">
          <input
            type={show ? "text" : "password"}
            value={key}
            onChange={(e) => {
              setKey(e.target.value)
              setState("idle")
            }}
            placeholder={api.on ? "сохранён, ••••9c1e" : "ключ"}
            aria-label={`Ключ для «${api.name}»`}
            className="w-full bg-transparent font-mono text-xs outline-none placeholder:text-muted-foreground"
          />
          <button onClick={() => setShow((s) => !s)} aria-label={show ? "Скрыть ключ" : "Показать ключ"} className="text-muted-foreground hover:text-foreground">
            {show ? <EyeOff className="size-3.5" /> : <Eye className="size-3.5" />}
          </button>
        </label>
      )}
      <Button size="sm" variant="outline" onClick={check} disabled={state === "checking"}>
        {state === "checking" && <Loader2 className="animate-spin" />} Проверить
      </Button>
      <Switch checked={api.on} onCheckedChange={onToggle} aria-label={`API «${api.name}»`} />
    </div>
  )
}

function AddApiDialog({ open, onClose, onAdd }: { open: boolean; onClose: () => void; onAdd: (a: Api) => void }) {
  const [name, setName] = useState("")
  const [url, setUrl] = useState("")
  const [key, setKey] = useState("")
  const host = useMemo(() => {
    try {
      return new URL(url).host
    } catch {
      return url
    }
  }, [url])
  const submit = () => {
    onAdd({ id: `a${Date.now()}`, name: name.trim(), note: host || "свой адрес", on: true, key })
    setName("")
    setUrl("")
    setKey("")
    onClose()
  }
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Globe className="size-4 text-glow" /> Новый API
          </DialogTitle>
          <DialogDescription>Lumen сможет обращаться к нему, когда это нужно для ответа.</DialogDescription>
        </DialogHeader>
        <label className="space-y-1.5 text-xs text-muted-foreground">
          Название
          <input autoFocus value={name} onChange={(e) => setName(e.target.value)} placeholder="Например: Курсы валют" className={field} />
        </label>
        <label className="space-y-1.5 text-xs text-muted-foreground">
          Адрес
          <input value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://api.example.com" className={cn(field, "font-mono text-xs")} />
        </label>
        <label className="space-y-1.5 text-xs text-muted-foreground">
          Ключ, если нужен
          <input type="password" value={key} onChange={(e) => setKey(e.target.value)} placeholder="••••••••" className={cn(field, "font-mono text-xs")} />
        </label>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>
            Отмена
          </Button>
          <Button onClick={submit} disabled={!name.trim()}>
            Добавить
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
