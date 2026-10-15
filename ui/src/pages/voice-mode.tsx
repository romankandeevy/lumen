import { Camera, Captions, Check, ChevronDown, Ellipsis, Laptop, MessageSquare, Mic, MicOff, MonitorUp, Smartphone, Video, X } from "lucide-react"
import { useCallback, useEffect, useRef, useState } from "react"
import { toast } from "sonner"

import { LumenOrb } from "@/components/lumen-orb"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { useApp, type Persona } from "@/lib/app-state"
import { cn } from "@/lib/utils"

// Голосовой разговор — как Advanced Voice в ChatGPT: в центре живая сфера Lumen, внизу круглые кнопки
// (камера, микрофон, экран, ещё, закончить). С камерой видео во весь экран, сфера уезжает вниз —
// Lumen видит, что ты показываешь. Пока он говорит, его можно перебить касанием сферы.

type Phase = "listening" | "thinking" | "speaking" | "muted"

const talks = {
  plain: [
    { you: "Слушай, на чём мы вчера остановились?", lumen: "На экране памяти Lumen. Граф уже как в Obsidian. Продолжим с ботов?" },
    { you: "Да, давай про группы ботов", lumen: "Хорошо. Группа сама распределит роли и напишет общий план. Собрать первую?" },
  ],
  camera: [
    { you: "Что у меня в руке?", lumen: "Клавиатура с круглыми клавишами, похоже на ретро-раскладку. Это та, что ты хотел подарить Лёше?" },
    { you: "Да. Как думаешь, ему понравится?", lumen: "Он любит клавиатуры — это есть в его анкете. Думаю, очень." },
  ],
  screen: [
    { you: "Глянь на экран, что не так с отступами?", lumen: "Справа у карточек отступ 24, слева 16. Выровнять до 20 с обеих сторон?" },
  ],
}

const cams = [
  { id: "mac", name: "Камера MacBook", note: "встроенная FaceTime HD", icon: Laptop },
  { id: "iphone", name: "iPhone Ромы", note: "Камера Continuity — по воздуху", icon: Smartphone },
]

const voices: { id: Persona["voice"]; name: string }[] = [
  { id: "calm", name: "Спокойный" },
  { id: "bright", name: "Яркий" },
  { id: "low", name: "Низкий" },
]

export function VoiceMode() {
  const app = useApp()
  const [phase, setPhase] = useState<Phase>("listening")
  const [you, setYou] = useState("")
  const [lumen, setLumen] = useState("")
  const [captions, setCaptions] = useState(true)
  const [source, setSource] = useState<"none" | "camera" | "screen">("none")
  const [streamOk, setStreamOk] = useState(false)
  const [cam, setCam] = useState("mac")
  const video = useRef<HTMLVideoElement>(null)
  const stream = useRef<MediaStream | null>(null)
  const timers = useRef<number[]>([])
  const turn = useRef(0)
  const orbWrap = useRef<HTMLDivElement>(null)
  const reduced = app.reducedMotion

  const clear = () => {
    timers.current.forEach(clearTimeout)
    timers.current = []
  }
  const later = (fn: () => void, ms: number) => timers.current.push(window.setTimeout(fn, ms))

  const close = useCallback(() => {
    clear()
    stream.current?.getTracks().forEach((t) => t.stop())
    app.setOrb("idle")
    app.setVoiceOpen(false)
  }, [app])

  /// Один круг разговора: слушает (твои слова появляются) → думает → говорит → снова слушает
  const runTurn = useCallback(() => {
    clear()
    const set = talks[source === "none" ? "plain" : source]
    const t = set[turn.current % set.length]
    turn.current++
    setPhase("listening")
    setYou("")
    setLumen("")
    const yw = t.you.split(" ")
    yw.forEach((_, i) => later(() => setYou(yw.slice(0, i + 1).join(" ")), 700 + i * 170))
    const afterYou = 700 + yw.length * 170 + 400
    later(() => setPhase("thinking"), afterYou)
    const lw = t.lumen.split(" ")
    later(() => setPhase("speaking"), afterYou + 900)
    lw.forEach((_, i) => later(() => setLumen(lw.slice(0, i + 1).join(" ")), afterYou + 900 + i * 210))
    later(() => runTurn(), afterYou + 900 + lw.length * 210 + 2200)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [source])

  useEffect(() => {
    if (phase !== "muted") runTurn()
    return clear
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [source])

  // сфера Lumen в общей панели повторяет фазу
  useEffect(() => {
    app.setOrb(phase === "speaking" ? "writing" : phase === "thinking" ? "thinking" : phase === "muted" ? "sleep" : "idle")
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phase])

  // «громкость»: сфера дышит по-разному, когда говоришь ты и когда говорит Lumen
  useEffect(() => {
    if (reduced) return
    let raf = 0
    const tick = (t: number) => {
      const el = orbWrap.current
      if (el) {
        const amp =
          phase === "speaking"
            ? 0.09 * (0.6 + 0.4 * Math.sin(t / 90)) * (0.7 + 0.3 * Math.sin(t / 37))
            : phase === "listening"
              ? 0.045 * Math.abs(Math.sin(t / 160)) * (0.6 + 0.4 * Math.sin(t / 53))
              : phase === "thinking"
                ? 0.03 * Math.sin(t / 300)
                : 0
        el.style.transform = `scale(${1 + amp})`
      }
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [phase, reduced])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && close()
    window.addEventListener("keydown", onKey)
    return () => {
      window.removeEventListener("keydown", onKey)
      clear()
      stream.current?.getTracks().forEach((t) => t.stop())
    }
  }, [close])

  async function toggleSource(kind: "camera" | "screen") {
    stream.current?.getTracks().forEach((t) => t.stop())
    stream.current = null
    setStreamOk(false)
    if (source === kind) {
      setSource("none")
      return
    }
    setSource(kind)
    try {
      const s =
        kind === "camera"
          ? await navigator.mediaDevices.getUserMedia({ video: true })
          : await navigator.mediaDevices.getDisplayMedia({ video: true })
      stream.current = s
      if (video.current) video.current.srcObject = s
      setStreamOk(true)
    } catch {
      setStreamOk(false) // нет доступа — показываем видоискатель-заглушку
    }
  }

  const interrupt = () => {
    if (phase !== "speaking") return
    clear()
    setPhase("listening")
    setLumen("")
    toast("Перебил — Lumen слушает")
    later(() => runTurn(), 900)
  }

  const toggleMic = () => {
    if (phase === "muted") {
      setPhase("listening")
      runTurn()
    } else {
      clear()
      setPhase("muted")
    }
  }

  const visual = source !== "none"
  const status = { listening: "Слушаю", thinking: "Думаю", speaking: "Говорит — коснись, чтобы перебить", muted: "Микрофон выключен" }[phase]

  return (
    <div className="absolute inset-0 z-30 flex flex-col overflow-hidden bg-background">
      {/* фон: свет или видео */}
      {!visual && <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(60%_50%_at_50%_45%,var(--glow-faint),transparent_70%)]" />}
      {visual && (
        <div className="absolute inset-3 overflow-hidden rounded-[28px] border bg-black">
          <video ref={video} autoPlay muted playsInline className={cn("size-full object-cover", source === "camera" && "-scale-x-100", !streamOk && "hidden")} />
          {!streamOk && <Viewfinder kind={source} />}
          <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-black/50 via-transparent to-black/70" />
          <div className="absolute top-4 left-4 flex items-center gap-2 rounded-full bg-black/50 px-3 py-1.5 text-xs text-white backdrop-blur">
            <span className="size-2 animate-pulse rounded-full bg-red-500" />
            {source === "camera" ? "Lumen видит камеру" : "Lumen видит экран"}
          </div>
          {source === "camera" && (
            // на Маке камеры не «передняя/задняя», а разные устройства: встроенная или iPhone (Камера Continuity)
            <Popover>
              <PopoverTrigger asChild>
                <button className="absolute top-4 right-4 flex h-9 items-center gap-2 rounded-full bg-black/50 px-3 text-xs text-white backdrop-blur hover:bg-black/70" aria-label="Выбрать камеру">
                  <Video className="size-4" /> {cams.find((c) => c.id === cam)?.name}
                  <ChevronDown className="size-3.5 opacity-60" />
                </button>
              </PopoverTrigger>
              <PopoverContent align="end" className="w-72 p-1.5">
                <p className="px-2 pt-1 pb-1.5 text-xs text-muted-foreground">Камера</p>
                {cams.map((c) => (
                  <button
                    key={c.id}
                    onClick={() => {
                      setCam(c.id)
                      toast(`Камера: ${c.name}`)
                    }}
                    className={cn("flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left hover:bg-muted/60", c.id === cam && "bg-muted")}
                  >
                    <c.icon className="size-4 text-muted-foreground" />
                    <span className="min-w-0 flex-1">
                      <span className="block text-sm">{c.name}</span>
                      <span className="block text-xs text-muted-foreground">{c.note}</span>
                    </span>
                    {c.id === cam && <Check className="size-4 text-glow" />}
                  </button>
                ))}
              </PopoverContent>
            </Popover>
          )}
        </div>
      )}

      {/* верх */}
      {!visual && (
        <div className="relative flex items-center justify-center pt-5 text-xs text-muted-foreground">
          Голос · {voices.find((v) => v.id === app.persona.voice)?.name ?? "Спокойный"}
        </div>
      )}

      {/* сфера */}
      <div className={cn("relative flex flex-1 flex-col items-center justify-center transition-all duration-500", visual && "justify-end pb-6")}>
        <button onClick={interrupt} aria-label={phase === "speaking" ? "Перебить" : "Lumen"} className="rounded-full outline-none focus-visible:ring-2 focus-visible:ring-glow/60">
          <div ref={orbWrap} className="transition-transform duration-75 will-change-transform">
            <LumenOrb size={visual ? 72 : 190} state={phase === "speaking" ? "writing" : phase === "thinking" ? "thinking" : phase === "muted" ? "sleep" : "idle"} className="transition-all duration-500" />
          </div>
        </button>
        <p className={cn("mt-10 text-sm text-muted-foreground transition-opacity", visual && "mt-4 text-white/80")}>{status}</p>

        {captions && (you || lumen) && (
          <div className={cn("mt-6 max-w-xl space-y-2 px-6 text-center", visual && "mt-3")}>
            {you && <p className={cn("text-sm text-muted-foreground", visual && "text-white/60")}>{you}</p>}
            {lumen && <p className={cn("text-lg leading-snug text-foreground", visual && "text-white")}>{lumen}</p>}
          </div>
        )}
      </div>

      {/* кнопки, как в ChatGPT */}
      <div className="relative flex items-center justify-center gap-3 pt-2 pb-8">
        <Round label={source === "camera" ? "Выключить камеру" : "Камера"} active={source === "camera"} onClick={() => toggleSource("camera")}>
          <Camera />
        </Round>
        <Round label={phase === "muted" ? "Включить микрофон" : "Выключить микрофон"} active={phase === "muted"} onClick={toggleMic}>
          {phase === "muted" ? <MicOff /> : <Mic />}
        </Round>
        <Round label={source === "screen" ? "Перестать показывать экран" : "Показать экран"} active={source === "screen"} onClick={() => toggleSource("screen")}>
          <MonitorUp />
        </Round>
        <Popover>
          <PopoverTrigger asChild>
            <button aria-label="Ещё" className="flex size-14 items-center justify-center rounded-full bg-foreground/[0.08] text-foreground backdrop-blur transition-colors hover:bg-foreground/[0.14] [&_svg]:size-5">
              <Ellipsis />
            </button>
          </PopoverTrigger>
          <PopoverContent side="top" className="w-60 p-1.5">
            <p className="px-2 pt-1 pb-1.5 text-xs text-muted-foreground">Голос</p>
            {voices.map((v) => (
              <button
                key={v.id}
                onClick={() => app.setPersona((p) => ({ ...p, voice: v.id }))}
                className={cn("flex w-full items-center rounded-lg px-2 py-1.5 text-left text-sm hover:bg-muted/60", app.persona.voice === v.id && "bg-muted")}
              >
                {v.name}
              </button>
            ))}
            <div className="my-1 h-px bg-border" />
            <button onClick={() => setCaptions((c) => !c)} className="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-sm hover:bg-muted/60">
              <Captions className="size-4" /> {captions ? "Скрыть субтитры" : "Показать субтитры"}
            </button>
            <button
              onClick={() => {
                close()
                if (app.open.page !== "thread") app.go("thread", "lumen")
              }}
              className="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-sm hover:bg-muted/60"
            >
              <MessageSquare className="size-4" /> Перейти в текст
            </button>
          </PopoverContent>
        </Popover>
        <button onClick={close} aria-label="Закончить" className="flex size-14 items-center justify-center rounded-full bg-red-500 text-white shadow-[0_0_24px_-4px_rgb(239_68_68/0.6)] transition-colors hover:bg-red-600 [&_svg]:size-6">
          <X />
        </button>
      </div>
    </div>
  )
}

function Round({ label, active, onClick, children }: { label: string; active?: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      title={label}
      aria-pressed={active}
      className={cn(
        "flex size-14 items-center justify-center rounded-full backdrop-blur transition-colors [&_svg]:size-5",
        active ? "bg-foreground text-background" : "bg-foreground/[0.08] text-foreground hover:bg-foreground/[0.14]"
      )}
    >
      {children}
    </button>
  )
}

/// Если камеры/экрана нет (или доступ не дали) — видоискатель-заглушка
function Viewfinder({ kind }: { kind: "camera" | "screen" | "none" }) {
  return (
    <div className="absolute inset-0 bg-[radial-gradient(circle_at_50%_40%,#2a2620,#0b0a09_70%)]">
      <div className="absolute inset-0 opacity-20 [background-image:linear-gradient(to_right,white_1px,transparent_1px),linear-gradient(to_bottom,white_1px,transparent_1px)] [background-size:33.33%_33.33%]" />
      {["top-8 left-8 border-t-2 border-l-2", "top-8 right-8 border-t-2 border-r-2", "bottom-8 left-8 border-b-2 border-l-2", "right-8 bottom-8 border-r-2 border-b-2"].map((c) => (
        <span key={c} className={cn("absolute size-10 rounded-sm border-white/60", c)} />
      ))}
      <p className="absolute inset-x-0 top-1/3 text-center text-sm text-white/60">
        {kind === "camera" ? "Камера недоступна в макете — в приложении здесь будет видео" : "Здесь будет твой экран"}
      </p>
    </div>
  )
}
