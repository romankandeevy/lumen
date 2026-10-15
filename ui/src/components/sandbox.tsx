import {
  ArrowLeft,
  ArrowRight,
  Box,
  Clapperboard,
  ExternalLink,
  FileText,
  Globe,
  Lock,
  Monitor,
  Pause,
  Play,
  Plus,
  RotateCw,
  Smartphone,
  SquareTerminal,
  X,
} from "lucide-react"
import { useEffect, useRef, useState } from "react"
import { toast } from "sonner"

import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"

// Песочница сбоку — как браузер в Claude Code, только своя: агент и боты показывают здесь
// всё, что сделали: сайт на localhost, любой сайт из интернета, видео, 3D-модель, файл.
// В приложении это WKWebView (браузер), AVPlayer (видео), RealityKit/QuickLook (3D и файлы).

type Kind = "preview" | "web" | "video" | "model" | "file"
type Tab = { id: string; kind: Kind; title: string; url: string }

const kindIcon: Record<Kind, React.ComponentType<{ className?: string }>> = {
  preview: SquareTerminal,
  web: Globe,
  video: Clapperboard,
  model: Box,
  file: FileText,
}

const startTabs: Tab[] = [
  { id: "t1", kind: "preview", title: "Сайт Лёши", url: "http://localhost:3000" },
  { id: "t2", kind: "web", title: "example.com", url: "https://example.com" },
  { id: "t3", kind: "video", title: "Рилс: Заметочки", url: "file:///prog/Рилсы/zametki.mp4" },
  { id: "t4", kind: "model", title: "Подставка для Мака", url: "file:///prog/stand.usdz" },
  { id: "t5", kind: "file", title: "SKILL.md", url: "file:///Lumen/skills/xctest/SKILL.md" },
]

export function Sandbox({ onClose }: { onClose: () => void }) {
  const [tabs, setTabs] = useState(startTabs)
  const [active, setActive] = useState("t1")
  const [device, setDevice] = useState<"desktop" | "phone">("desktop")
  const tab = tabs.find((t) => t.id === active) ?? tabs[0]
  const [address, setAddress] = useState(tab?.url ?? "")
  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => setAddress(tab?.url ?? ""), [tab?.id, tab?.url])

  const go = () => {
    let url = address.trim()
    if (!url) return
    if (!/^[a-z]+:\/\//i.test(url)) url = url.includes(".") ? `https://${url}` : `https://duckduckgo.com/?q=${encodeURIComponent(url)}`
    const kind: Kind = url.startsWith("http://localhost") ? "preview" : "web"
    setTabs((ts) => ts.map((t) => (t.id === tab.id ? { ...t, url, kind, title: url.replace(/^https?:\/\//, "").split("/")[0] } : t)))
  }

  const newTab = () => {
    const id = `t${Date.now()}`
    setTabs((ts) => [...ts, { id, kind: "web", title: "Новая вкладка", url: "https://example.com" }])
    setActive(id)
  }

  const closeTab = (id: string) => {
    setTabs((ts) => {
      const next = ts.filter((t) => t.id !== id)
      if (id === active && next[0]) setActive(next[0].id)
      return next
    })
  }

  return (
    <aside className="flex min-h-0 flex-col border-l bg-sidebar">
      {/* вкладки */}
      <div className="flex items-center gap-1 border-b px-2 pt-2">
        <div className="flex min-w-0 flex-1 gap-1 overflow-x-auto">
          {tabs.map((t) => {
            const Icon = kindIcon[t.kind]
            return (
              <button
                key={t.id}
                onClick={() => setActive(t.id)}
                className={cn(
                  "group flex h-8 max-w-44 shrink-0 items-center gap-1.5 rounded-t-lg px-2.5 text-xs transition-colors",
                  t.id === active ? "bg-background text-foreground" : "text-muted-foreground hover:bg-foreground/5 hover:text-foreground"
                )}
              >
                <Icon className="size-3.5 shrink-0" />
                <span className="truncate">{t.title}</span>
                <span
                  role="button"
                  aria-label="Закрыть вкладку"
                  onClick={(e) => {
                    e.stopPropagation()
                    closeTab(t.id)
                  }}
                  className="ml-0.5 rounded p-0.5 opacity-0 group-hover:opacity-100 hover:bg-foreground/10"
                >
                  <X className="size-3" />
                </span>
              </button>
            )
          })}
        </div>
        <Button size="icon-xs" variant="ghost" onClick={newTab} aria-label="Новая вкладка">
          <Plus />
        </Button>
        <Button size="icon-xs" variant="ghost" onClick={onClose} aria-label="Закрыть песочницу" title="Закрыть песочницу">
          <X />
        </Button>
      </div>

      {/* адресная строка */}
      {tab && (
        <div className="flex items-center gap-1 border-b bg-background px-2 py-1.5">
          <Button size="icon-xs" variant="ghost" aria-label="Назад" onClick={() => toast("Назад")}>
            <ArrowLeft />
          </Button>
          <Button size="icon-xs" variant="ghost" aria-label="Вперёд" onClick={() => toast("Вперёд")}>
            <ArrowRight />
          </Button>
          <Button size="icon-xs" variant="ghost" aria-label="Обновить" onClick={() => setReloadKey((k) => k + 1)}>
            <RotateCw />
          </Button>
          <label className="mx-1 flex h-7 min-w-0 flex-1 items-center gap-1.5 rounded-lg bg-foreground/[0.06] px-2.5 text-xs">
            {tab.url.startsWith("https") ? <Lock className="size-3 text-muted-foreground" /> : <Globe className="size-3 text-muted-foreground" />}
            <input
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && go()}
              className="w-full bg-transparent outline-none"
              aria-label="Адрес"
              spellCheck={false}
            />
          </label>
          {(tab.kind === "preview" || tab.kind === "web") && (
            <div className="flex rounded-lg bg-foreground/[0.06] p-0.5">
              <button onClick={() => setDevice("desktop")} aria-label="Как на компьютере" className={cn("rounded-md p-1", device === "desktop" && "bg-background")}>
                <Monitor className="size-3.5" />
              </button>
              <button onClick={() => setDevice("phone")} aria-label="Как на телефоне" className={cn("rounded-md p-1", device === "phone" && "bg-background")}>
                <Smartphone className="size-3.5" />
              </button>
            </div>
          )}
          <Button size="icon-xs" variant="ghost" aria-label="Открыть в браузере" onClick={() => toast("Откроется в Safari")}>
            <ExternalLink />
          </Button>
        </div>
      )}

      {/* содержимое */}
      <div className="relative min-h-0 flex-1 overflow-hidden bg-[color-mix(in_oklch,var(--background)_85%,black)]">
        {!tab && <p className="p-8 text-center text-sm text-muted-foreground">Вкладок нет. Нажми +, или агент сам откроет то, что сделал.</p>}
        {tab && (
          <div key={tab.id + reloadKey} className={cn("mx-auto h-full transition-[max-width] duration-300", (tab.kind === "preview" || tab.kind === "web") && device === "phone" ? "max-w-[390px] py-4" : "max-w-full")}>
            <div className={cn("h-full overflow-hidden", device === "phone" && (tab.kind === "preview" || tab.kind === "web") && "rounded-[28px] border-4 border-foreground/15")}>
              {tab.kind === "preview" && <DemoSite phone={device === "phone"} />}
              {tab.kind === "web" && <iframe title={tab.title} src={tab.url} className="size-full bg-white" sandbox="allow-scripts allow-same-origin allow-forms allow-popups" />}
              {tab.kind === "video" && <DemoVideo />}
              {tab.kind === "model" && <DemoModel />}
              {tab.kind === "file" && <DemoFile />}
            </div>
          </div>
        )}
      </div>
      <p className="border-t px-3 py-1.5 text-[11px] text-muted-foreground">Песочница отделена от твоих файлов: сайты и код здесь не видят остальной Мак.</p>
    </aside>
  )
}

/// Превью сайта, который собрал агент (в макете — нарисованный сайт)
function DemoSite({ phone }: { phone: boolean }) {
  return (
    <div className="h-full overflow-auto bg-[#0f1115] text-white">
      <nav className="flex items-center justify-between px-6 py-4 text-sm">
        <span className="font-semibold">Лёша</span>
        {!phone && (
          <span className="flex gap-5 text-white/60">
            <span>Работы</span>
            <span>Обо мне</span>
            <span>Контакты</span>
          </span>
        )}
      </nav>
      <div className={cn("px-6", phone ? "py-10" : "py-16")}>
        <p className="text-sm text-emerald-300">Тестирую приложения и собираю клавиатуры</p>
        <h1 className={cn("mt-3 font-semibold tracking-tight", phone ? "text-3xl" : "text-5xl")}>Нахожу баги до того, как их найдут люди.</h1>
        <button className="mt-6 rounded-full bg-white px-5 py-2.5 text-sm font-medium text-black">Посмотреть работы</button>
      </div>
      <div className={cn("grid gap-3 px-6 pb-10", phone ? "grid-cols-1" : "grid-cols-3")}>
        {["Shelf", "Island", "Заметочки"].map((p, i) => (
          <div key={p} className="aspect-[4/3] rounded-2xl p-4" style={{ background: `linear-gradient(140deg, hsl(${160 + i * 50} 40% 22%), hsl(${200 + i * 40} 30% 12%))` }}>
            <p className="text-sm font-medium">{p}</p>
            <p className="text-xs text-white/50">проверено 40+ сценариев</p>
          </div>
        ))}
      </div>
    </div>
  )
}

/// Видео (в приложении — AVPlayer). В макете — анимированный кадр с управлением
function DemoVideo() {
  const [playing, setPlaying] = useState(true)
  const [t, setT] = useState(0)
  useEffect(() => {
    if (!playing) return
    const iv = window.setInterval(() => setT((x) => (x + 1) % 300), 100)
    return () => window.clearInterval(iv)
  }, [playing])
  return (
    <div className="flex h-full flex-col items-center justify-center gap-4 p-6">
      <div className="relative aspect-[9/16] h-[78%] overflow-hidden rounded-2xl border bg-black">
        <div
          className="absolute inset-0 transition-all duration-100"
          style={{ background: `radial-gradient(circle at ${30 + 40 * Math.sin(t / 15)}% ${40 + 20 * Math.cos(t / 20)}%, oklch(0.6 0.15 250), oklch(0.2 0.05 260) 70%)` }}
        />
        <p className="absolute inset-x-0 bottom-10 px-4 text-center text-lg font-semibold text-white drop-shadow">Заметки, которые пишутся сами</p>
        <button onClick={() => setPlaying((p) => !p)} className="absolute inset-0 flex items-center justify-center" aria-label={playing ? "Пауза" : "Играть"}>
          {!playing && <Play className="size-12 text-white/90" />}
        </button>
      </div>
      <div className="flex w-full max-w-sm items-center gap-3 text-xs text-muted-foreground">
        <button onClick={() => setPlaying((p) => !p)} aria-label={playing ? "Пауза" : "Играть"} className="text-foreground">
          {playing ? <Pause className="size-4" /> : <Play className="size-4" />}
        </button>
        <span className="tabular-nums">0:{String(Math.floor(t / 10)).padStart(2, "0")}</span>
        <span className="h-1 flex-1 overflow-hidden rounded-full bg-foreground/10">
          <span className="block h-full bg-glow" style={{ width: `${(t / 300) * 100}%` }} />
        </span>
        <span>0:30</span>
      </div>
    </div>
  )
}

/// 3D-модель (в приложении — RealityKit/QuickLook, USDZ). В макете — куб, который можно крутить мышью
function DemoModel() {
  const [rot, setRot] = useState({ x: -20, y: 30 })
  const drag = useRef<{ x: number; y: number } | null>(null)
  useEffect(() => {
    const move = (e: MouseEvent) => {
      if (!drag.current) return
      setRot((r) => ({ x: r.x - (e.clientY - drag.current!.y) * 0.5, y: r.y + (e.clientX - drag.current!.x) * 0.5 }))
      drag.current = { x: e.clientX, y: e.clientY }
    }
    const up = () => (drag.current = null)
    window.addEventListener("mousemove", move)
    window.addEventListener("mouseup", up)
    return () => {
      window.removeEventListener("mousemove", move)
      window.removeEventListener("mouseup", up)
    }
  }, [])
  const faces = [
    "translateZ(70px)",
    "rotateY(180deg) translateZ(70px)",
    "rotateY(90deg) translateZ(70px)",
    "rotateY(-90deg) translateZ(70px)",
    "rotateX(90deg) translateZ(70px)",
    "rotateX(-90deg) translateZ(70px)",
  ]
  return (
    <div className="flex h-full cursor-grab flex-col items-center justify-center gap-6 select-none active:cursor-grabbing" onMouseDown={(e) => (drag.current = { x: e.clientX, y: e.clientY })} style={{ perspective: 800 }}>
      <div className="relative size-[140px]" style={{ transformStyle: "preserve-3d", transform: `rotateX(${rot.x}deg) rotateY(${rot.y}deg)` }}>
        {faces.map((f, i) => (
          <div key={i} className="absolute inset-0 rounded-md border border-glow/40" style={{ transform: f, background: `color-mix(in oklch, var(--glow) ${8 + i * 4}%, transparent)` }} />
        ))}
      </div>
      <p className="text-xs text-muted-foreground">Тяни, чтобы повернуть · stand.usdz</p>
    </div>
  )
}

/// Файл (в приложении — QuickLook). В макете — навык, который сделал бот
function DemoFile() {
  return (
    <pre className="h-full overflow-auto p-5 font-mono text-xs leading-relaxed whitespace-pre-wrap text-foreground/85">{`---
name: xctest
description: Пишет и гоняет XCTest и UI-тесты, читает отчёты xcresult
---

# XCTest и UI-тесты

## Когда применять
- Нужно проверить правку в Swift-проекте
- Бот @tester получил задачу «протестируй»

## Шаги
1. xcodebuild test -scheme <схема> -resultBundlePath out.xcresult
2. Разобрать xcresult: упавшие тесты, время, снимки
3. Отчёт: что проверено, что упало, шаги повтора`}</pre>
  )
}
