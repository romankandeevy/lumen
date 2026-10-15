import { Check, Eye, EyeOff, KeyRound, Loader2, LogOut, RefreshCw, TerminalSquare } from "lucide-react"
import { useState } from "react"
import { toast } from "sonner"

import { GroupTitle, Page } from "@/components/page"
import { Button } from "@/components/ui/button"
import { useApp, type Backend } from "@/lib/app-state"
import { cn } from "@/lib/utils"

// Подключения: подписка Claude Code и ключ Anthropic API. Codex и OpenAI — позже.
// В макете ничего никуда не отправляется: проверки ключа и входа — имитация.

export function ConnectionsPage() {
  const app = useApp()
  return (
    <Page title="Подключения" lead="Через что Lumen думает. Можно держать оба: подписку на каждый день и ключ API про запас.">
      <div className="max-w-4xl space-y-8">
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
    </Page>
  )
}

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
