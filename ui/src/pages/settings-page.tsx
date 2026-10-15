import { Check, Download, Eye, EyeOff, FolderOpen, KeyRound, Loader2, LogOut, Mic, RefreshCw, Sparkles, TerminalSquare } from "lucide-react"
import { useEffect, useRef, useState } from "react"
import { toast } from "sonner"

import { LumenOrb } from "@/components/lumen-orb"
import { GroupTitle, Page, Segmented } from "@/components/page"
import { Button } from "@/components/ui/button"
import { Switch } from "@/components/ui/switch"
import { useApp, type Backend, type Persona, type Theme } from "@/lib/app-state"
import { cn } from "@/lib/utils"

// Настройки: слева узкое подменю-якоря, справа секции.
// «Модели и оплата» переехали сюда из бывших «Подключений». Проверки ключа и входа — имитация.

const sections = [
  { id: "look", name: "Внешний вид" },
  { id: "models", name: "Модели и оплата" },
  { id: "voice", name: "Голос" },
  { id: "keys", name: "Горячие клавиши" },
  { id: "data", name: "Данные" },
] as const
type SectionId = (typeof sections)[number]["id"]

const shortcuts = [
  ["Найти и сделать", "⌘K"],
  ["Новый чат", "⌘N"],
  ["Чат / Память / Люди / Характер", "⌘1 – ⌘4"],
  ["Показать контекст", "⌘."],
  ["Голосом", "держать правый ⌥"],
  ["Настройки", "⌘,"],
]

export function SettingsPage() {
  const app = useApp()
  const rootRef = useRef<HTMLDivElement>(null)
  const [current, setCurrent] = useState<SectionId>("look")

  const scrollerOf = () => rootRef.current?.closest(".overflow-auto") as HTMLElement | null

  const jump = (id: SectionId, smooth = true) => {
    const el = document.getElementById(`settings-${id}`)
    const scroller = scrollerOf()
    if (!el || !scroller) return
    const top = el.getBoundingClientRect().top - scroller.getBoundingClientRect().top + scroller.scrollTop - 8
    scroller.scrollTo({ top, behavior: smooth && !app.reducedMotion ? "smooth" : "auto" })
    setCurrent(id)
  }

  // подсветка текущей секции по прокрутке
  useEffect(() => {
    const scroller = scrollerOf()
    if (!scroller) return
    const onScroll = () => {
      const base = scroller.getBoundingClientRect().top + 80
      let found: SectionId = sections[0].id
      for (const s of sections) {
        const el = document.getElementById(`settings-${s.id}`)
        if (el && el.getBoundingClientRect().top <= base) found = s.id
      }
      if (scroller.scrollTop + scroller.clientHeight >= scroller.scrollHeight - 4) found = sections[sections.length - 1].id
      setCurrent(found)
    }
    scroller.addEventListener("scroll", onScroll, { passive: true })
    return () => scroller.removeEventListener("scroll", onScroll)
  }, [])

  // открыли «Модели и оплата» снаружи (из чата, из меню)
  useEffect(() => {
    const id = app.open.id
    if (id && sections.some((s) => s.id === id)) requestAnimationFrame(() => jump(id as SectionId, false))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [app.open.id])

  return (
    <Page title="Настройки">
      <div ref={rootRef} className="flex max-w-5xl gap-10">
        <nav aria-label="Разделы настроек" className="sticky top-0 hidden w-40 shrink-0 self-start pt-1 md:block">
          <ul className="space-y-0.5">
            {sections.map((s) => (
              <li key={s.id}>
                <a
                  href={`#settings-${s.id}`}
                  onClick={(e) => {
                    e.preventDefault()
                    jump(s.id)
                  }}
                  aria-current={current === s.id ? "true" : undefined}
                  className={cn(
                    "relative block rounded-md py-1.5 pr-2 pl-3 text-sm transition-colors",
                    current === s.id ? "bg-foreground/[0.05] text-foreground" : "text-muted-foreground hover:text-foreground"
                  )}
                >
                  {current === s.id && <span className="absolute top-1.5 bottom-1.5 left-0 w-0.5 rounded-full bg-glow shadow-[0_0_8px_var(--glow-soft)]" />}
                  {s.name}
                </a>
              </li>
            ))}
          </ul>
        </nav>

        <div className="min-w-0 flex-1 space-y-12 pb-[40vh]">
          <Section id="look" title="Внешний вид">
            <GroupTitle>Тема</GroupTitle>
            <div className="grid gap-3 sm:grid-cols-3">
              <ThemeCard id="lumen" name="Люмен" note="Тёплая темнота и свет" />
              <ThemeCard id="mono" name="Монохром" note="Чёрно-белая, как Пульт" />
              <div className="flex flex-col justify-center rounded-2xl border border-dashed p-4 text-muted-foreground">
                <p className="text-sm text-foreground/70">Свои темы</p>
                <p className="mt-1 text-xs leading-relaxed">Цвет света, фон, шрифт и ещё 10 готовых тем — позже</p>
              </div>
            </div>
            <label className="mt-4 flex max-w-md items-center gap-3 text-sm">
              <Switch checked={app.reducedMotion} onCheckedChange={app.setReducedMotion} />
              Меньше движения
              <span className="text-xs text-muted-foreground">сфера не дышит, свет не мерцает</span>
            </label>
          </Section>

          <Section id="models" title="Модели и оплата" lead="Через что Lumen думает. Можно держать оба: подписку на каждый день и ключ API про запас.">
            <div className="space-y-8">
              <div>
                <GroupTitle>Через что отвечать по умолчанию</GroupTitle>
                <div className="grid gap-2 sm:grid-cols-3">
                  {(
                    [
                      ["subscription", "Подписка", "Входит в тариф Claude. Есть лимит на 5 часов и на неделю."],
                      ["api", "API", "Платишь за токены. Без лимитов по времени."],
                      ["auto", "Авто", "Подписка, а когда лимит кончился — API. Без перерывов."],
                    ] as [Backend, string, string][]
                  ).map(([id, name, note]) => (
                    <button
                      key={id}
                      onClick={() => app.setBackend(id)}
                      className={cn(
                        "rounded-xl border p-3.5 text-left transition-colors",
                        app.backend === id ? "border-glow/50 bg-glow/[0.06] shadow-[0_0_24px_-8px_var(--glow-soft)]" : "bg-card/40 hover:bg-card"
                      )}
                    >
                      <span className="flex items-center justify-between text-sm font-medium">
                        {name} {app.backend === id && <Check className="size-4 text-glow" />}
                      </span>
                      <span className="mt-1 block text-xs leading-relaxed text-muted-foreground">{note}</span>
                    </button>
                  ))}
                </div>
              </div>

              <div className="grid gap-4 lg:grid-cols-2">
                <Subscription />
                <ApiKey />
              </div>

              <div>
                <GroupTitle aside="скоро">Другие модели</GroupTitle>
                <div className="grid gap-2 sm:grid-cols-2">
                  {[
                    ["Codex", "подписка ChatGPT, как Claude Code"],
                    ["OpenAI API", "ключ OpenAI, модели GPT"],
                  ].map(([name, note]) => (
                    <div key={name} className="flex items-center gap-3 rounded-xl border border-dashed px-4 py-3 text-muted-foreground">
                      <span className="min-w-0 flex-1">
                        <span className="block text-sm text-foreground/70">{name}</span>
                        <span className="block text-xs">{note}</span>
                      </span>
                      <span className="rounded-md border px-2 py-0.5 text-[11px]">позже</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </Section>

          <Section id="voice" title="Голос" lead="Голосовой разговор с Lumen: ты говоришь, он слушает и отвечает вслух.">
            <VoiceSettings />
          </Section>

          <Section id="keys" title="Горячие клавиши">
            <div className="divide-y rounded-xl border bg-card/40">
              {shortcuts.map(([name, keys]) => (
                <div key={name} className="flex items-center px-4 py-2.5 text-sm">
                  {name}
                  <kbd className="ml-auto rounded-md border bg-background/50 px-2 py-0.5 text-xs text-muted-foreground">{keys}</kbd>
                </div>
              ))}
            </div>
          </Section>

          <Section id="data" title="Данные">
            <div className="rounded-xl border bg-card/40 p-4">
              <p className="text-sm">Всё хранится на этом Маке</p>
              <p className="mt-1 font-mono text-xs text-muted-foreground">~/Library/Application Support/Lumen</p>
              <p className="mt-1 text-xs text-muted-foreground">Память, люди, характер, история чатов. Ничего не уходит в облако, кроме самих запросов к модели.</p>
              <div className="mt-4 flex flex-wrap gap-2">
                <Button variant="outline" size="sm" onClick={() => toast("Открыто в Finder")}>
                  <FolderOpen /> Показать в Finder
                </Button>
                <Button variant="outline" size="sm" onClick={() => toast("Память выгружена", { description: "lumen-memory-2026-10-15.zip" })}>
                  <Download /> Выгрузить память
                </Button>
                <Button variant="ghost" size="sm" onClick={() => app.setOnboarded(false)}>
                  <Sparkles /> Пройти знакомство заново
                </Button>
              </div>
            </div>
          </Section>
        </div>
      </div>
    </Page>
  )
}

function Section({ id, title, lead, children }: { id: SectionId; title: string; lead?: string; children: React.ReactNode }) {
  return (
    <section id={`settings-${id}`} aria-labelledby={`settings-${id}-title`} className="scroll-mt-2">
      <h2 id={`settings-${id}-title`} className="text-lg font-semibold tracking-[-0.01em]">
        {title}
      </h2>
      {lead && <p className="mt-1 max-w-[60ch] text-sm text-muted-foreground">{lead}</p>}
      <div className="mt-4">{children}</div>
    </section>
  )
}

// ── голос ──

const voices: { id: Persona["voice"]; name: string; note: string }[] = [
  { id: "calm", name: "Спокойный", note: "ровный, негромкий" },
  { id: "bright", name: "Яркий", note: "живой, с улыбкой" },
  { id: "low", name: "Низкий", note: "глубокий, медленнее" },
]

function VoiceSettings() {
  const app = useApp()
  const [speed, setSpeed] = useState<"slow" | "normal" | "fast">("normal")
  const [readAloud, setReadAloud] = useState(false)
  return (
    <div className="space-y-7">
      <div>
        <GroupTitle>Голос Lumen</GroupTitle>
        <div className="grid gap-2 sm:grid-cols-3">
          {voices.map((v) => {
            const active = app.persona.voice === v.id
            return (
              <button
                key={v.id}
                onClick={() => app.setPersona((p) => ({ ...p, voice: v.id }))}
                className={cn(
                  "flex items-center gap-3 rounded-xl border p-3.5 text-left transition-colors",
                  active ? "border-glow/50 bg-glow/[0.06] shadow-[0_0_24px_-8px_var(--glow-soft)]" : "bg-card/40 hover:bg-card"
                )}
              >
                <LumenOrb size={22} state={active ? "writing" : "idle"} />
                <span className="min-w-0 flex-1">
                  <span className="block text-sm font-medium">{v.name}</span>
                  <span className="block text-xs text-muted-foreground">{v.note}</span>
                </span>
                {active && <Check className="size-4 text-glow" />}
              </button>
            )
          })}
        </div>
        <Button variant="ghost" size="sm" className="mt-2 text-muted-foreground" onClick={() => toast("Пример голоса", { description: "«Привет. Я рядом, говори, когда удобно.»" })}>
          Послушать пример
        </Button>
      </div>

      <div className="divide-y rounded-xl border bg-card/40">
        <div className="flex items-center gap-4 px-4 py-3">
          <span className="min-w-0 flex-1 text-sm">Скорость речи</span>
          <Segmented
            value={speed}
            onChange={setSpeed}
            options={[
              { id: "slow", name: "Медленнее" },
              { id: "normal", name: "Обычно" },
              { id: "fast", name: "Быстрее" },
            ]}
          />
        </div>
        <label className="flex items-center gap-4 px-4 py-3">
          <span className="min-w-0 flex-1">
            <span className="block text-sm">Читать ответы вслух</span>
            <span className="block text-xs text-muted-foreground">и в обычном чате, не только в голосовом разговоре</span>
          </span>
          <Switch checked={readAloud} onCheckedChange={setReadAloud} />
        </label>
        <div className="flex items-center gap-4 px-4 py-3">
          <span className="min-w-0 flex-1">
            <span className="block text-sm">Сказать голосом</span>
            <span className="block text-xs text-muted-foreground">держишь клавишу — говоришь, отпустил — текст уже в поле</span>
          </span>
          <kbd className="rounded-md border bg-background/50 px-2 py-0.5 text-xs text-muted-foreground">держать правый ⌥</kbd>
        </div>
        <div className="flex items-center gap-4 px-4 py-3">
          <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-foreground/[0.06]">
            <Mic className="size-4" />
          </span>
          <span className="min-w-0 flex-1">
            <span className="block text-sm">Распознавание речи</span>
            <span className="block text-xs text-muted-foreground">FlowLocal на этом Маке: голос не уходит в интернет</span>
          </span>
          <span className="flex items-center gap-1.5 text-xs">
            <span className="size-1.5 rounded-full bg-emerald-400 shadow-[0_0_8px_theme(colors.emerald.400)]" /> работает
          </span>
        </div>
      </div>

      <Button variant="outline" size="sm" onClick={() => app.setVoiceOpen(true)}>
        <Mic /> Попробовать голосовой разговор
      </Button>
    </div>
  )
}

// ── тема ──

/// Карточка темы — с миниатюрой окна в цветах этой темы
function ThemeCard({ id, name, note }: { id: Theme; name: string; note: string }) {
  const app = useApp()
  const active = app.theme === id
  return (
    <button
      onClick={() => app.setTheme(id)}
      className={cn(
        "rounded-2xl border p-2 text-left transition-colors",
        active ? "border-glow/50 shadow-[0_0_28px_-8px_var(--glow-soft)]" : "hover:border-foreground/20"
      )}
    >
      <div className={cn("theme-" + id, "relative h-24 overflow-hidden rounded-xl")} style={{ background: "var(--background)" }}>
        <div className="absolute inset-y-0 left-0 w-1/4 border-r" style={{ background: "var(--sidebar)", borderColor: "var(--border)" }}>
          <LumenOrb size={10} className="m-2" />
        </div>
        <div className="absolute top-4 right-4 left-[32%] space-y-1.5">
          <div className="ml-auto h-2.5 w-1/2 rounded-full" style={{ background: "var(--secondary)" }} />
          <div className="h-2 w-5/6 rounded-full" style={{ background: "var(--muted)" }} />
          <div className="h-2 w-2/3 rounded-full" style={{ background: "var(--muted)" }} />
        </div>
        <div className="absolute right-4 bottom-3 left-[32%] h-4 rounded-md border" style={{ borderColor: "var(--border)", boxShadow: "0 0 14px -2px var(--glow-soft)" }} />
      </div>
      <div className="flex items-center px-1.5 pt-2.5 pb-1">
        <span className="min-w-0 flex-1">
          <span className="block text-sm font-medium">{name}</span>
          <span className="block text-xs text-muted-foreground">{note}</span>
        </span>
        {active && <Check className="size-4 text-glow" />}
      </div>
    </button>
  )
}

// ── модели и оплата (перенесено из «Подключений») ──

function Card({ title, icon, status, children }: { title: string; icon: React.ReactNode; status: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl border bg-card/40 p-5">
      <div className="flex items-center gap-3">
        <span className="flex size-9 items-center justify-center rounded-xl bg-foreground/[0.06]">{icon}</span>
        <p className="text-sm font-medium">{title}</p>
        <span className="ml-auto">{status}</span>
      </div>
      <div className="mt-5">{children}</div>
    </div>
  )
}

function Status({ on, children }: { on: boolean; children: React.ReactNode }) {
  return (
    <span className={cn("flex items-center gap-1.5 text-xs", on ? "text-foreground" : "text-muted-foreground")}>
      <span className={cn("size-1.5 rounded-full", on ? "bg-emerald-400 shadow-[0_0_8px_theme(colors.emerald.400)]" : "bg-foreground/25")} />
      {children}
    </span>
  )
}

function Subscription() {
  const [signedIn, setSignedIn] = useState(true)
  const [busy, setBusy] = useState(false)
  const signIn = () => {
    setBusy(true)
    setTimeout(() => {
      setBusy(false)
      setSignedIn(true)
      toast("Вошёл в Claude Code", { description: "Подписка Max · вход через браузер" })
    }, 1200)
  }
  return (
    <Card title="Подписка Claude Code" icon={<TerminalSquare className="size-4" />} status={<Status on={signedIn}>{signedIn ? "подключено" : "не подключено"}</Status>}>
      {signedIn ? (
        <>
          <p className="text-sm">Тариф Max, вход через Claude Code на этом Маке</p>
          <div className="mt-4 space-y-3">
            <Meter label="5-часовое окно" value={34} note="сброс в 23:10" />
            <Meter label="Неделя" value={12} note="до понедельника" />
          </div>
          <div className="mt-5 flex gap-2">
            <Button variant="outline" size="sm" onClick={() => toast("Подписка в порядке", { description: "Лимиты обновлены." })}>
              <RefreshCw /> Проверить
            </Button>
            <Button variant="ghost" size="sm" onClick={() => setSignedIn(false)}>
              <LogOut /> Выйти
            </Button>
          </div>
        </>
      ) : (
        <>
          <p className="text-sm text-muted-foreground">Войди тем же аккаунтом, что и в Claude Code. Откроется браузер.</p>
          <Button className="mt-4" onClick={signIn} disabled={busy}>
            {busy ? <Loader2 className="animate-spin" /> : null} Войти через браузер
          </Button>
        </>
      )}
    </Card>
  )
}

function ApiKey() {
  const [key, setKey] = useState("")
  const [show, setShow] = useState(false)
  const [state, setState] = useState<"empty" | "checking" | "ok" | "bad">("ok")
  const [limit, setLimit] = useState("20")
  const check = () => {
    setState("checking")
    setTimeout(() => setState(key.startsWith("sk-ant-") || !key ? "ok" : "bad"), 1100)
  }
  return (
    <Card
      title="Anthropic API"
      icon={<KeyRound className="size-4" />}
      status={<Status on={state === "ok"}>{state === "ok" ? "ключ работает" : state === "bad" ? "ключ не подошёл" : "нет ключа"}</Status>}
    >
      <div className="flex gap-2">
        <label className="glow-field flex h-9 flex-1 items-center gap-2 rounded-lg border bg-input/30 px-3">
          <input
            type={show ? "text" : "password"}
            value={key}
            onChange={(e) => {
              setKey(e.target.value)
              setState(e.target.value ? "empty" : "ok")
            }}
            placeholder="sk-ant-…  (сохранён, ••••4f2a)"
            className="w-full bg-transparent font-mono text-xs outline-none placeholder:text-muted-foreground"
            aria-label="Ключ API"
          />
          <button onClick={() => setShow((s) => !s)} aria-label={show ? "Скрыть ключ" : "Показать ключ"} className="text-muted-foreground hover:text-foreground">
            {show ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
          </button>
        </label>
        <Button variant="outline" onClick={check} disabled={state === "checking"}>
          {state === "checking" ? <Loader2 className="animate-spin" /> : null} Проверить
        </Button>
      </div>
      {state === "bad" && <p className="mt-2 text-xs text-red-400">Ключ должен начинаться с sk-ant-. Скопируй его заново в console.anthropic.com.</p>}
      <p className="mt-2 text-xs text-muted-foreground">Ключ хранится в Связке ключей macOS и никуда не уходит, кроме Anthropic.</p>

      <div className="mt-5 flex items-end gap-6">
        <div>
          <p className="text-xs text-muted-foreground">В этом месяце</p>
          <p className="mt-0.5 text-2xl font-semibold tracking-[-0.02em] tabular-nums">$4,18</p>
        </div>
        <label className="text-xs text-muted-foreground">
          Остановиться на
          <span className="mt-1 flex h-8 items-center gap-1 rounded-lg border bg-input/30 px-2.5 text-sm text-foreground">
            $
            <input value={limit} onChange={(e) => setLimit(e.target.value.replace(/\D/g, ""))} className="w-12 bg-transparent outline-none tabular-nums" />
            в месяц
          </span>
        </label>
      </div>
    </Card>
  )
}

function Meter({ label, value, note }: { label: string; value: number; note: string }) {
  return (
    <div>
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
