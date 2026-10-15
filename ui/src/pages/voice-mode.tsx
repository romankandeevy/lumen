import { Keyboard, Mic, MicOff, PhoneOff } from "lucide-react"
import { useEffect, useState } from "react"

import { LumenOrb } from "@/components/lumen-orb"
import { Button } from "@/components/ui/button"
import { useApp, type OrbState, type Persona } from "@/lib/app-state"
import { cn } from "@/lib/utils"

// Голосовой разговор поверх основной области. Макет: микрофона нет, реплики идут по кругу.
// Слушаю → твоя фраза по словам → думаю → Lumen говорит субтитрами → снова слушаю.

const voiceNames: Record<Persona["voice"], string> = { calm: "Спокойный", bright: "Яркий", low: "Низкий" }

const script: { you: string; lumen: string }[] = [
  { you: "Слушай, на чём мы вчера остановились с Люменом?", lumen: "На макете: память, люди, характер и боты уже есть. Сегодня очередь инструментов и голоса." },
  { you: "А что по Shelf, он всё ещё падает?", lumen: "Да, падает на двойном щелчке по полке. Тестер как раз проверяет фикс, через пару минут скажу." },
  { you: "Хорошо. Напомни вечером закоммитить.", lumen: "Запомнил. В восемь вечера напомню про коммит в Люмене." },
]

type Phase = "listen" | "hear" | "think" | "speak" | "pause"

const labels: Record<Phase, string> = { listen: "Слушаю…", hear: "Слушаю…", think: "Думаю…", speak: "Говорит", pause: "Говорит" }
const orbOf: Record<Phase, OrbState> = { listen: "thinking", hear: "thinking", think: "thinking", speak: "writing", pause: "writing" }

export function VoiceMode() {
  const app = useApp()
  const [turn, setTurn] = useState(0)
  const [phase, setPhase] = useState<Phase>("listen")
  const [words, setWords] = useState(0)
  const [muted, setMuted] = useState(false)

  const line = script[turn % script.length]
  const youWords = line.you.split(" ")
  const lumenWords = line.lumen.split(" ")

  // один таймер на шаг: каждый шаг сам чистит свой таймер
  useEffect(() => {
    if (muted && (phase === "listen" || phase === "hear")) return
    let delay = 0
    let next: () => void
    if (phase === "listen") {
      delay = 1400
      next = () => {
        setWords(0)
        setPhase("hear")
      }
    } else if (phase === "hear") {
      if (words < youWords.length) {
        delay = 230
        next = () => setWords((w) => w + 1)
      } else {
        delay = 600
        next = () => setPhase("think")
      }
    } else if (phase === "think") {
      delay = 1300
      next = () => {
        setWords(0)
        setPhase("speak")
      }
    } else if (phase === "speak") {
      if (words < lumenWords.length) {
        delay = 280
        next = () => setWords((w) => w + 1)
      } else {
        delay = 1800
        next = () => setPhase("pause")
      }
    } else {
      delay = 300
      next = () => {
        setTurn((t) => t + 1)
        setWords(0)
        setPhase("listen")
      }
    }
    const t = window.setTimeout(next, delay)
    return () => window.clearTimeout(t)
  }, [phase, words, muted, youWords.length, lumenWords.length])

  // Esc закрывает
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault()
        app.setVoiceOpen(false)
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [app])

  const listening = phase === "listen" || phase === "hear"
  const speaking = phase === "speak" || phase === "pause"
  const status = muted && listening ? "Микрофон выключен" : labels[phase]
  const orb: OrbState = muted && listening ? "sleep" : orbOf[phase]
  const bars = muted && listening ? "off" : speaking ? "speak" : listening ? "listen" : "think"

  const toText = () => {
    app.setVoiceOpen(false)
    if (app.open.page !== "thread") app.go("thread", "lumen")
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Голосовой разговор с Lumen"
      className="absolute inset-0 z-30 flex flex-col items-center bg-background/80 backdrop-blur-2xl"
    >
      <style>{barsCss}</style>
      <div aria-hidden className="pointer-events-none absolute inset-0 bg-[radial-gradient(520px_360px_at_50%_42%,var(--glow-faint),transparent_70%)]" />

      <header className="relative flex w-full items-center justify-center gap-2 pt-6 text-xs text-muted-foreground">
        <span className="size-1.5 rounded-full bg-glow shadow-[0_0_8px_var(--glow-soft)]" />
        Голосовой разговор · голос «{voiceNames[app.persona.voice]}»
      </header>

      <div className="relative flex min-h-0 w-full max-w-2xl flex-1 flex-col items-center justify-center px-8">
        <LumenOrb size={160} state={orb} />

        <div aria-hidden className={cn("vm-bars mt-10", `vm-${bars}`, app.reducedMotion && "vm-still")}>
          {Array.from({ length: 11 }, (_, i) => (
            <span key={i} style={{ animationDelay: `${(i * 137) % 700}ms` }} />
          ))}
        </div>

        <p className="mt-6 text-sm text-muted-foreground" aria-live="polite">
          {status}
        </p>

        <div className="mt-6 min-h-28 w-full text-center" aria-live="polite">
          {phase === "hear" || phase === "think" ? (
            <p className="text-base leading-relaxed text-foreground/70">
              {youWords.slice(0, phase === "think" ? youWords.length : words).join(" ")}
            </p>
          ) : speaking ? (
            <p className="text-xl leading-relaxed font-medium tracking-[-0.01em] text-balance">
              {lumenWords.slice(0, words).map((w, i) => (
                <span key={i} className={cn(!app.reducedMotion && "vm-word")}>
                  {w}{" "}
                </span>
              ))}
            </p>
          ) : null}
        </div>
      </div>

      <footer className="relative flex items-center gap-3 pb-10">
        <Button
          variant="outline"
          size="lg"
          onClick={() => setMuted((m) => !m)}
          aria-pressed={muted}
          className={cn("rounded-full px-4", muted && "border-glow/50 text-glow")}
        >
          {muted ? <MicOff /> : <Mic />}
          {muted ? "Включить микрофон" : "Выключить микрофон"}
        </Button>
        <Button variant="outline" size="lg" className="rounded-full px-4" onClick={toText}>
          <Keyboard /> Перейти в текст
        </Button>
        <Button size="lg" className="h-11 rounded-full bg-red-500/90 px-6 text-white hover:bg-red-500" onClick={() => app.setVoiceOpen(false)}>
          <PhoneOff /> Закончить
        </Button>
      </footer>
      <p className="relative -mt-6 pb-4 text-[11px] text-muted-foreground/70">Esc, чтобы закончить</p>
    </div>
  )
}

const barsCss = `
.vm-bars { display: flex; align-items: center; gap: 5px; height: 40px; }
.vm-bars > span {
  width: 4px; height: 100%; border-radius: 999px; background: var(--glow);
  box-shadow: 0 0 10px var(--glow-soft); transform-origin: center;
  transform: scaleY(0.12); transition: transform .4s ease, opacity .4s ease;
  animation: vm-bar 0.9s ease-in-out infinite alternate;
}
.vm-listen > span { animation-duration: 0.75s; opacity: 0.85; }
.vm-speak > span { animation-duration: 0.5s; }
.vm-think > span { animation: vm-think 1.4s ease-in-out infinite; opacity: 0.6; }
.vm-off > span, .vm-still > span { animation: none; transform: scaleY(0.12); opacity: 0.35; }
.vm-still.vm-speak > span, .vm-still.vm-listen > span { transform: scaleY(0.4); opacity: 0.7; }
@keyframes vm-bar { 0% { transform: scaleY(0.15); } 50% { transform: scaleY(0.9); } 100% { transform: scaleY(0.35); } }
@keyframes vm-think { 0%, 100% { transform: scaleY(0.12); } 50% { transform: scaleY(0.3); } }
.vm-word { display: inline-block; animation: vm-word .35s ease-out both; white-space: pre; }
@keyframes vm-word { from { opacity: 0; filter: blur(4px); transform: translateY(3px); } to { opacity: 1; filter: none; transform: none; } }
@media (prefers-reduced-motion: reduce) {
  .vm-bars > span, .vm-word { animation: none !important; }
  .vm-bars > span { transform: scaleY(0.4); }
}
`
