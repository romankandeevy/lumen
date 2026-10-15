import { ArrowLeft, Check, KeyRound, TerminalSquare } from "lucide-react"
import { useState } from "react"

import { LumenOrb } from "@/components/lumen-orb"
import { Segmented } from "@/components/page"
import { Button } from "@/components/ui/button"
import { useApp, type Backend, type Theme } from "@/lib/app-state"
import { cn } from "@/lib/utils"

// Знакомство при первом запуске: имя и обращение → модель → тема.
// Ответы сразу кладутся в профиль и память — Lumen с первого чата знает, с кем говорит.

const steps = ["Знакомство", "Модель", "Тема"]

export function Onboarding() {
  const app = useApp()
  const me = app.profiles.find((p) => p.id === "roma")!
  const [step, setStep] = useState(-1) // -1 — приветствие
  const [name, setName] = useState(me.call)
  const [address, setAddress] = useState(me.address)
  const [backend, setBackend] = useState<Backend>(app.backend)

  const finish = () => {
    app.setProfiles((ps) => ps.map((p) => (p.id === "roma" ? { ...p, call: name || p.call, address } : p)))
    app.setBackend(backend)
    app.setActiveProfile("roma")
    app.setOnboarded(true)
    app.setOrb("remember")
    setTimeout(() => app.setOrb("idle"), 1200)
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-background/80 backdrop-blur-xl">
      <div className="lumen-light relative w-full max-w-lg overflow-hidden rounded-3xl border bg-card/80 p-10 shadow-2xl">
        {step === -1 ? (
          <div className="flex flex-col items-center text-center">
            <LumenOrb size={96} state="thinking" />
            <h1 className="mt-10 text-3xl font-semibold tracking-[-0.03em]">Привет. Я Lumen.</h1>
            <p className="mt-3 max-w-[38ch] text-sm leading-relaxed text-muted-foreground">
              Я помню тебя и твои проекты между разговорами, понимаю, с кем говорю, и отвечаю так, как ты настроишь.
              Давай познакомимся — это минута.
            </p>
            <Button size="lg" className="mt-8 bg-glow text-black hover:bg-glow/85" onClick={() => setStep(0)}>
              Познакомиться
            </Button>
            <button onClick={() => app.setOnboarded(true)} className="mt-3 text-xs text-muted-foreground hover:text-foreground">
              Пропустить
            </button>
          </div>
        ) : (
          <>
            <div className="flex items-center gap-3">
              <LumenOrb size={22} />
              <ol className="flex flex-1 items-center gap-1.5" aria-label="Шаги">
                {steps.map((s, i) => (
                  <li key={s} className={cn("h-1 flex-1 rounded-full", i <= step ? "bg-glow shadow-[0_0_8px_var(--glow-soft)]" : "bg-foreground/10")} aria-current={i === step ? "step" : undefined} />
                ))}
              </ol>
              <span className="text-xs text-muted-foreground tabular-nums">
                {step + 1} из {steps.length}
              </span>
            </div>

            <div className="mt-8 min-h-64">
              {step === 0 && (
                <>
                  <h2 className="text-xl font-semibold tracking-[-0.02em]">Как к тебе обращаться?</h2>
                  <p className="mt-1.5 text-sm text-muted-foreground">Запомню это первым фактом о тебе.</p>
                  <input
                    autoFocus
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    onKeyDown={(e) => e.key === "Enter" && name && setStep(1)}
                    placeholder="Имя"
                    className="mt-6 h-11 w-full rounded-xl border bg-input/30 px-4 text-base outline-none focus:border-glow/50"
                  />
                  <div className="mt-4">
                    <Segmented
                      value={address}
                      onChange={setAddress}
                      options={[
                        { id: "ty", name: "Можно на «ты»" },
                        { id: "vy", name: "Лучше на «вы»" },
                      ]}
                    />
                  </div>
                </>
              )}
              {step === 1 && (
                <>
                  <h2 className="text-xl font-semibold tracking-[-0.02em]">Через что мне думать?</h2>
                  <p className="mt-1.5 text-sm text-muted-foreground">Можно поменять потом в «Подключениях».</p>
                  <div className="mt-6 space-y-2">
                    <Option active={backend === "subscription" || backend === "auto"} onClick={() => setBackend("auto")} icon={<TerminalSquare className="size-4" />} title="Подписка Claude Code" note="Нашёл Claude Code на этом Маке — вход уже есть" />
                    <Option active={backend === "api"} onClick={() => setBackend("api")} icon={<KeyRound className="size-4" />} title="Ключ Anthropic API" note="Вставишь ключ на следующем экране" />
                  </div>
                </>
              )}
              {step === 2 && (
                <>
                  <h2 className="text-xl font-semibold tracking-[-0.02em]">Как мне выглядеть?</h2>
                  <p className="mt-1.5 text-sm text-muted-foreground">Обе тёмные. Свои темы появятся позже.</p>
                  <div className="mt-6 grid grid-cols-2 gap-3">
                    {(
                      [
                        ["lumen", "Люмен", "тёплый свет"],
                        ["mono", "Монохром", "как Пульт"],
                      ] as [Theme, string, string][]
                    ).map(([id, n, note]) => (
                      <button
                        key={id}
                        onClick={() => app.setTheme(id)}
                        className={cn("theme-" + id, "rounded-2xl border p-4 text-left", app.theme === id && "border-glow/60 shadow-[0_0_28px_-8px_var(--glow-soft)]")}
                        style={{ background: "var(--background)", color: "var(--foreground)" }}
                      >
                        <LumenOrb size={28} />
                        <p className="mt-6 text-sm font-medium">{n}</p>
                        <p className="text-xs" style={{ color: "var(--muted-foreground)" }}>
                          {note}
                        </p>
                      </button>
                    ))}
                  </div>
                </>
              )}
            </div>

            <div className="mt-6 flex items-center">
              <Button variant="ghost" onClick={() => setStep((s) => s - 1)}>
                <ArrowLeft /> Назад
              </Button>
              {step < steps.length - 1 ? (
                <Button className="ml-auto" disabled={step === 0 && !name.trim()} onClick={() => setStep((s) => s + 1)}>
                  Дальше
                </Button>
              ) : (
                <Button className="ml-auto bg-glow text-black hover:bg-glow/85" onClick={finish}>
                  <Check /> Начать
                </Button>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  )
}

function Option({ active, onClick, icon, title, note }: { active: boolean; onClick: () => void; icon: React.ReactNode; title: string; note: string }) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "flex w-full items-center gap-3 rounded-xl border p-3.5 text-left transition-colors",
        active ? "border-glow/50 bg-glow/[0.06]" : "hover:bg-foreground/5"
      )}
    >
      <span className="flex size-9 items-center justify-center rounded-lg bg-foreground/[0.06]">{icon}</span>
      <span className="min-w-0 flex-1">
        <span className="block text-sm font-medium">{title}</span>
        <span className="block text-xs text-muted-foreground">{note}</span>
      </span>
      {active && <Check className="size-4 text-glow" />}
    </button>
  )
}
