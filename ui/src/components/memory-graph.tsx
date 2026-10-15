import { forceCenter, forceCollide, forceLink, forceManyBody, forceSimulation, forceX, forceY, type Simulation, type SimulationLinkDatum, type SimulationNodeDatum } from "d3-force"
import { Crosshair, Minus, Plus, Search, Tags, X } from "lucide-react"
import { useEffect, useMemo, useRef, useState } from "react"

import { Button } from "@/components/ui/button"
import { useApp } from "@/lib/app-state"
import { entities, type Memory } from "@/lib/mock-data"
import { cn } from "@/lib/utils"

// Граф памяти — как Graph View в Obsidian: узлы раскладывает физика (d3-force),
// размер узла — по числу связей, наведение подсвечивает соседей, колесо — зум,
// фон тянется, узлы перетаскиваются, двойной клик — «локальный граф» вокруг узла.

type Group = "me" | "project" | "person" | "fact" | "decision"
type GNode = SimulationNodeDatum & { id: string; name: string; group: Group; r: number; memory?: Memory; degree: number }
type GLink = SimulationLinkDatum<GNode> & { kind: "core" | "own" | "cross" }

const groupNames: { id: Exclude<Group, "me">; name: string }[] = [
  { id: "project", name: "Проекты" },
  { id: "person", name: "Люди" },
  { id: "fact", name: "Факты" },
  { id: "decision", name: "Решения" },
]

function cssVar(name: string) {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim() || "#e8c070"
}

function build(memories: Memory[]) {
  const nodes: GNode[] = entities.map((e) => ({
    id: e.id,
    name: e.name,
    group: e.kind === "me" ? "me" : e.kind === "person" ? "person" : "project",
    r: 0,
    degree: 0,
  }))
  const byId = new Map(nodes.map((n) => [n.id, n]))
  const links: GLink[] = []
  nodes.filter((n) => n.group !== "me").forEach((n) => links.push({ source: "me", target: n.id, kind: "core" }))
  memories.forEach((m) => {
    const about = m.about.filter((a) => byId.has(a))
    if (!about.length) return
    nodes.push({ id: m.id, name: m.text, group: m.kind === "decision" || m.kind === "pref" ? "decision" : "fact", r: 0, memory: m, degree: 0 })
    links.push({ source: about[0], target: m.id, kind: "own" })
    about.slice(1).forEach((a) => links.push({ source: m.id, target: a, kind: "cross" }))
  })
  const deg = new Map<string, number>()
  links.forEach((l) => {
    deg.set(l.source as string, (deg.get(l.source as string) ?? 0) + 1)
    deg.set(l.target as string, (deg.get(l.target as string) ?? 0) + 1)
  })
  nodes.forEach((n) => {
    n.degree = deg.get(n.id) ?? 0
    n.r = n.group === "me" ? 15 : n.group === "fact" || n.group === "decision" ? 3.5 + Math.min(n.degree, 4) * 0.6 : 6 + Math.min(n.degree, 10) * 0.7
  })
  return { nodes, links }
}

export function MemoryGraph({ memories, openThread }: { memories: Memory[]; openThread: (id: string) => void }) {
  const app = useApp()
  const wrap = useRef<HTMLDivElement>(null)
  const canvas = useRef<HTMLCanvasElement>(null)
  const sim = useRef<Simulation<GNode, GLink> | null>(null)
  const view = useRef({ x: 0, y: 0, k: 1 })
  const hoverRef = useRef<string | null>(null)
  const [hover, setHover] = useState<string | null>(null)
  const [selected, setSelected] = useState<string | null>("me")
  const [local, setLocal] = useState<string | null>(null)
  const [hidden, setHidden] = useState<Set<Group>>(new Set())
  const [labels, setLabels] = useState(false)
  const [q, setQ] = useState("")
  const draw = useRef<() => void>(() => {})

  const reduced = app.reducedMotion || (typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches)

  // данные: весь граф или окрестность узла (локальный граф)
  const data = useMemo(() => {
    const full = build(memories)
    let keep = new Set(full.nodes.filter((n) => !hidden.has(n.group)).map((n) => n.id))
    if (local) {
      const near = new Set([local])
      for (let hop = 0; hop < 2; hop++)
        full.links.forEach((l) => {
          const s = l.source as string
          const t = l.target as string
          if (near.has(s)) near.add(t)
          else if (near.has(t)) near.add(s)
        })
      keep = new Set([...keep].filter((id) => near.has(id)))
    }
    keep.add("me")
    return {
      nodes: full.nodes.filter((n) => keep.has(n.id)),
      links: full.links.filter((l) => keep.has(l.source as string) && keep.has(l.target as string)),
    }
  }, [memories, hidden, local])

  const neighbors = useMemo(() => {
    const m = new Map<string, Set<string>>()
    data.links.forEach((l) => {
      const s = typeof l.source === "object" ? (l.source as GNode).id : (l.source as string)
      const t = typeof l.target === "object" ? (l.target as GNode).id : (l.target as string)
      if (!m.has(s)) m.set(s, new Set())
      if (!m.has(t)) m.set(t, new Set())
      m.get(s)!.add(t)
      m.get(t)!.add(s)
    })
    return m
  }, [data])

  // физика
  useEffect(() => {
    const nodes = data.nodes.map((n) => ({ ...n }))
    const links = data.links.map((l) => ({ ...l }))
    const s = forceSimulation<GNode>(nodes)
      .force(
        "link",
        forceLink<GNode, GLink>(links)
          .id((d) => d.id)
          .distance((l) => (l.kind === "core" ? 170 : l.kind === "own" ? ((l.source as GNode).id === "me" ? 95 : 52) : 130))
          .strength((l) => (l.kind === "cross" ? 0.05 : l.kind === "core" ? 0.35 : 0.9))
      )
      .force("charge", forceManyBody<GNode>().strength((d) => (d.group === "fact" || d.group === "decision" ? -90 : d.group === "me" ? -700 : -280)))
      .force("collide", forceCollide<GNode>().radius((d) => d.r + (d.group === "fact" || d.group === "decision" ? 12 : 8)))
      .force("center", forceCenter(0, 0))
      .force("x", forceX(0).strength(0.03))
      .force("y", forceY(0).strength(0.04))
    const me = nodes.find((n) => n.id === "me")
    if (me) {
      me.fx = 0
      me.fy = 0
    }
    if (reduced) {
      s.stop()
      for (let i = 0; i < 300; i++) s.tick()
    } else {
      s.alpha(1).alphaDecay(0.025)
    }
    s.on("tick", () => draw.current())
    sim.current = s
    draw.current()
    return () => {
      s.stop()
    }
  }, [data, reduced])

  // рисование
  useEffect(() => {
    const c = canvas.current!
    const ctx = c.getContext("2d")!
    const glow = cssVar("--glow")
    const fg = cssVar("--foreground")
    const bg = cssVar("--background")
    const person = "oklch(0.8 0.1 200)"
    const color = (g: Group) => (g === "person" ? person : g === "fact" ? fg : glow)

    draw.current = () => {
      const s = sim.current
      if (!s) return
      const dpr = window.devicePixelRatio || 1
      const w = c.clientWidth
      const h = c.clientHeight
      if (c.width !== w * dpr) {
        c.width = w * dpr
        c.height = h * dpr
      }
      const { x, y, k } = view.current
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
      ctx.clearRect(0, 0, w, h)
      ctx.translate(w / 2 + x, h / 2 + y)
      ctx.scale(k, k)

      const focus = hoverRef.current ?? null
      const near = focus ? neighbors.get(focus) : undefined
      const lit = (id: string) => !focus || id === focus || !!near?.has(id)
      const nodes = s.nodes()
      const links = (s.force("link") as ReturnType<typeof forceLink<GNode, GLink>>).links()

      // рёбра
      links.forEach((l) => {
        const a = l.source as GNode
        const b = l.target as GNode
        const on = focus ? (a.id === focus || b.id === focus) : true
        ctx.beginPath()
        ctx.moveTo(a.x!, a.y!)
        ctx.lineTo(b.x!, b.y!)
        ctx.strokeStyle = l.kind === "cross" ? person : glow
        ctx.globalAlpha = focus ? (on ? 0.7 : 0.04) : l.kind === "core" ? 0.28 : l.kind === "own" ? 0.22 : 0.12
        ctx.lineWidth = (on && focus ? 1.4 : 1) / Math.sqrt(k)
        if (l.kind === "cross") ctx.setLineDash([3 / k, 4 / k])
        ctx.stroke()
        ctx.setLineDash([])
      })

      // узлы
      nodes.forEach((n) => {
        const on = lit(n.id)
        ctx.globalAlpha = on ? 1 : 0.12
        if (n.group === "me") {
          const g = ctx.createRadialGradient(n.x!, n.y!, 0, n.x!, n.y!, n.r * 3.2)
          g.addColorStop(0, glow)
          g.addColorStop(1, "transparent")
          ctx.globalAlpha = on ? 0.35 : 0.08
          ctx.fillStyle = g
          ctx.beginPath()
          ctx.arc(n.x!, n.y!, n.r * 3.2, 0, Math.PI * 2)
          ctx.fill()
          ctx.globalAlpha = on ? 1 : 0.2
        }
        ctx.beginPath()
        ctx.arc(n.x!, n.y!, n.r, 0, Math.PI * 2)
        if (n.group === "fact" || n.group === "decision") {
          ctx.fillStyle = color(n.group)
          ctx.globalAlpha *= n.group === "fact" ? 0.55 : 0.85
          ctx.fill()
          if (n.memory?.pinned) {
            ctx.beginPath()
            ctx.arc(n.x!, n.y!, n.r + 3, 0, Math.PI * 2)
            ctx.strokeStyle = glow
            ctx.lineWidth = 1 / k
            ctx.stroke()
          }
        } else {
          ctx.fillStyle = n.group === "me" ? glow : bg
          ctx.fill()
          ctx.lineWidth = n.group === "me" ? 0 : 2
          ctx.strokeStyle = color(n.group)
          if (n.group !== "me") ctx.stroke()
        }
        if (n.id === selected) {
          ctx.globalAlpha = 0.9
          ctx.beginPath()
          ctx.arc(n.x!, n.y!, n.r + 6, 0, Math.PI * 2)
          ctx.strokeStyle = fg
          ctx.lineWidth = 1.2 / k
          ctx.stroke()
        }
      })

      // подписи: у сущностей всегда, у фактов — при приближении, наведении или «подписи всегда»
      ctx.textAlign = "center"
      ctx.textBaseline = "top"
      nodes.forEach((n) => {
        const isFact = n.group === "fact" || n.group === "decision"
        const show = !isFact || labels || k > 2.2 || n.id === focus
        if (!show) return
        const on = lit(n.id)
        const size = (isFact ? 10.5 : n.group === "me" ? 13.5 : 12.5) / Math.max(k, 0.8)
        ctx.font = `${isFact ? 400 : 500} ${size}px "Geist Variable", system-ui, sans-serif`
        const text = isFact && n.name.length > 34 ? n.name.slice(0, 33) + "…" : n.name
        ctx.globalAlpha = on ? (isFact ? 0.75 : 0.95) : 0.1
        ctx.lineWidth = 3 / k
        ctx.strokeStyle = bg
        ctx.strokeText(text, n.x!, n.y! + n.r + 5 / k)
        ctx.fillStyle = fg
        ctx.fillText(text, n.x!, n.y! + n.r + 5 / k)
      })
      ctx.globalAlpha = 1
    }
    draw.current()
    const ro = new ResizeObserver(() => draw.current())
    ro.observe(c)
    return () => ro.disconnect()
  }, [neighbors, selected, labels, app.theme])

  // мышь: зум колесом, перетаскивание фона и узлов, наведение, клик, двойной клик
  useEffect(() => {
    const c = canvas.current!
    let drag: { node?: GNode; sx: number; sy: number; vx: number; vy: number; moved: boolean } | null = null
    const toWorld = (e: { clientX: number; clientY: number }) => {
      const r = c.getBoundingClientRect()
      const { x, y, k } = view.current
      return { wx: (e.clientX - r.left - r.width / 2 - x) / k, wy: (e.clientY - r.top - r.height / 2 - y) / k }
    }
    const pick = (e: MouseEvent) => {
      const { wx, wy } = toWorld(e)
      let best: GNode | undefined
      let bd = Infinity
      sim.current?.nodes().forEach((n) => {
        const d = Math.hypot(n.x! - wx, n.y! - wy)
        if (d < n.r + 6 / view.current.k && d < bd) {
          bd = d
          best = n
        }
      })
      return best
    }
    const onWheel = (e: WheelEvent) => {
      e.preventDefault()
      const r = c.getBoundingClientRect()
      const v = view.current
      const k = Math.min(4, Math.max(0.35, v.k * Math.exp(-e.deltaY * 0.0015)))
      const mx = e.clientX - r.left - r.width / 2
      const my = e.clientY - r.top - r.height / 2
      v.x = mx - ((mx - v.x) * k) / v.k
      v.y = my - ((my - v.y) * k) / v.k
      v.k = k
      draw.current()
    }
    const onDown = (e: MouseEvent) => {
      const node = pick(e)
      drag = { node, sx: e.clientX, sy: e.clientY, vx: view.current.x, vy: view.current.y, moved: false }
      if (node && node.id !== "me") {
        sim.current?.alphaTarget(0.25).restart()
        node.fx = node.x
        node.fy = node.y
      }
    }
    const onMove = (e: MouseEvent) => {
      if (drag) {
        if (Math.hypot(e.clientX - drag.sx, e.clientY - drag.sy) > 3) drag.moved = true
        if (drag.node && drag.node.id !== "me") {
          const { wx, wy } = toWorld(e)
          drag.node.fx = wx
          drag.node.fy = wy
          if (reduced) draw.current()
        } else if (!drag.node) {
          view.current.x = drag.vx + e.clientX - drag.sx
          view.current.y = drag.vy + e.clientY - drag.sy
          draw.current()
        }
        return
      }
      const n = pick(e)
      const id = n?.id ?? null
      if (id !== hoverRef.current) {
        hoverRef.current = id
        setHover(id)
        c.style.cursor = n ? "pointer" : "grab"
        draw.current()
      }
    }
    const onUp = (e: MouseEvent) => {
      if (!drag) return
      if (drag.node && drag.node.id !== "me") {
        sim.current?.alphaTarget(0)
        drag.node.fx = null
        drag.node.fy = null
      }
      if (!drag.moved) {
        const n = pick(e)
        setSelected(n ? n.id : null)
      }
      drag = null
    }
    const onDbl = (e: MouseEvent) => {
      const n = pick(e)
      if (n) {
        setLocal(n.id)
        setSelected(n.id)
        view.current = { x: 0, y: 0, k: 1.3 }
      }
    }
    const onLeave = () => {
      hoverRef.current = null
      setHover(null)
      draw.current()
    }
    c.addEventListener("wheel", onWheel, { passive: false })
    c.addEventListener("mousedown", onDown)
    window.addEventListener("mousemove", onMove)
    window.addEventListener("mouseup", onUp)
    c.addEventListener("dblclick", onDbl)
    c.addEventListener("mouseleave", onLeave)
    return () => {
      c.removeEventListener("wheel", onWheel)
      c.removeEventListener("mousedown", onDown)
      window.removeEventListener("mousemove", onMove)
      window.removeEventListener("mouseup", onUp)
      c.removeEventListener("dblclick", onDbl)
      c.removeEventListener("mouseleave", onLeave)
    }
  }, [reduced])

  const zoom = (f: number) => {
    view.current.k = Math.min(4, Math.max(0.35, view.current.k * f))
    draw.current()
  }
  const center = (id?: string) => {
    const n = id ? sim.current?.nodes().find((x) => x.id === id) : undefined
    const k = id ? Math.max(view.current.k, 1.4) : 1
    view.current = { x: n ? -n.x! * k : 0, y: n ? -n.y! * k : 0, k }
    draw.current()
  }
  const find = (text: string) => {
    setQ(text)
    const s = text.trim().toLowerCase()
    if (!s) return
    const n = sim.current?.nodes().find((x) => x.name.toLowerCase().includes(s))
    if (n) {
      setSelected(n.id)
      center(n.id)
    }
  }

  const sel = selected ? data.nodes.find((n) => n.id === selected) : undefined
  const selFacts = sel
    ? sel.memory
      ? [sel.memory]
      : memories.filter((m) => m.about.includes(sel.id))
    : []
  const entityName = (id: string) => entities.find((e) => e.id === id)?.name ?? id

  return (
    <div
      ref={wrap}
      className="relative mt-4 h-[calc(100svh-210px)] min-h-[480px] overflow-hidden rounded-2xl border"
      style={{
        backgroundColor: "color-mix(in oklch, var(--background) 92%, black)",
        backgroundImage: "radial-gradient(circle at center, color-mix(in oklch, var(--foreground) 9%, transparent) 1px, transparent 1px)",
        backgroundSize: "22px 22px",
      }}
    >
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_center,transparent_40%,var(--background)_100%)]" />
      <canvas ref={canvas} className="absolute inset-0 size-full cursor-grab active:cursor-grabbing" aria-label="Граф памяти" />

      {/* панель управления */}
      <div className="absolute top-3 left-3 w-64 space-y-2 rounded-xl border bg-popover/85 p-2.5 shadow-xl backdrop-blur">
        <label className="flex h-8 items-center gap-2 rounded-lg bg-input/40 px-2.5">
          <Search className="size-3.5 text-muted-foreground" />
          <input value={q} onChange={(e) => find(e.target.value)} placeholder="Найти узел" className="w-full bg-transparent text-sm outline-none" />
        </label>
        <div className="flex flex-wrap gap-1">
          {groupNames.map((g) => {
            const off = hidden.has(g.id)
            return (
              <button
                key={g.id}
                onClick={() =>
                  setHidden((h) => {
                    const n = new Set(h)
                    if (n.has(g.id)) n.delete(g.id)
                    else n.add(g.id)
                    return n
                  })
                }
                className={cn("flex items-center gap-1.5 rounded-full border px-2 py-0.5 text-xs transition-colors", off ? "text-muted-foreground/60 line-through" : "text-foreground/85")}
              >
                <span className="size-2 rounded-full" style={{ background: g.id === "person" ? "oklch(0.8 0.1 200)" : g.id === "fact" ? "var(--foreground)" : "var(--glow)", opacity: off ? 0.3 : g.id === "fact" ? 0.55 : 1 }} />
                {g.name}
              </button>
            )
          })}
        </div>
        <div className="flex items-center gap-1">
          <Button size="icon-xs" variant="ghost" onClick={() => zoom(1 / 1.25)} aria-label="Отдалить">
            <Minus />
          </Button>
          <Button size="icon-xs" variant="ghost" onClick={() => zoom(1.25)} aria-label="Приблизить">
            <Plus />
          </Button>
          <Button size="icon-xs" variant="ghost" onClick={() => center()} aria-label="По центру" title="По центру">
            <Crosshair />
          </Button>
          <Button size="xs" variant={labels ? "secondary" : "ghost"} className="ml-auto" onClick={() => setLabels((l) => !l)}>
            <Tags /> Подписи
          </Button>
        </div>
      </div>

      {local && (
        <div className="absolute top-3 left-1/2 flex -translate-x-1/2 items-center gap-2 rounded-full border bg-popover/90 py-1 pr-1 pl-3 text-xs shadow-lg backdrop-blur">
          Локальный граф: {data.nodes.find((n) => n.id === local)?.name.slice(0, 30)}
          <Button size="xs" variant="secondary" className="rounded-full" onClick={() => (setLocal(null), (view.current = { x: 0, y: 0, k: 1 }))}>
            Весь граф
          </Button>
        </div>
      )}

      {/* подсказка про наведённый факт */}
      {hover && !sel?.memory && data.nodes.find((n) => n.id === hover)?.memory && (
        <div className="pointer-events-none absolute bottom-3 left-3 max-w-md rounded-lg border bg-popover/90 px-3 py-2 text-xs shadow-lg backdrop-blur">
          {data.nodes.find((n) => n.id === hover)?.name}
        </div>
      )}
      <p className="pointer-events-none absolute right-3 bottom-3 text-[11px] text-muted-foreground">
        Колесо — зум · тяни фон или узел · двойной клик — окрестность
      </p>

      {/* карточка выбранного */}
      {sel && (
        <aside className="absolute top-3 right-3 bottom-10 flex w-80 flex-col overflow-hidden rounded-xl border bg-popover/90 shadow-xl backdrop-blur">
          <div className="flex items-start gap-3 border-b p-3.5">
            <span
              className="mt-0.5 size-3 shrink-0 rounded-full"
              style={{ background: sel.group === "person" ? "oklch(0.8 0.1 200)" : "var(--glow)", boxShadow: "0 0 10px var(--glow-soft)" }}
            />
            <div className="min-w-0 flex-1">
              <p className="text-sm leading-snug font-medium">{sel.memory ? "Факт" : sel.name}</p>
              <p className="text-xs text-muted-foreground">
                {sel.group === "me" ? "это ты" : sel.group === "person" ? "человек" : sel.group === "project" ? "проект" : sel.group === "decision" ? "решение" : "факт"} ·{" "}
                {neighbors.get(sel.id)?.size ?? 0} связей
              </p>
            </div>
            <button onClick={() => setSelected(null)} aria-label="Закрыть" className="text-muted-foreground hover:text-foreground">
              <X className="size-4" />
            </button>
          </div>
          <div className="min-h-0 flex-1 space-y-2 overflow-auto p-3">
            {selFacts.map((m) => (
              <div key={m.id} className="rounded-lg border bg-card/50 px-3 py-2">
                <p className="text-[13px] leading-snug">{m.text}</p>
                <p className="mt-1 text-[11px] text-muted-foreground">
                  <button onClick={() => openThread(m.source)} className="hover:text-glow">
                    из «{m.source}»
                  </button>{" "}
                  · {m.when}
                  {m.about.length > 1 && <> · про {m.about.map(entityName).join(", ")}</>}
                </p>
              </div>
            ))}
            {selFacts.length === 0 && <p className="py-6 text-center text-xs text-muted-foreground">Фактов пока нет</p>}
          </div>
          <div className="flex gap-2 border-t p-2.5">
            <Button size="sm" variant="ghost" onClick={() => (setLocal(sel.id), (view.current = { x: 0, y: 0, k: 1.3 }))}>
              Окрестность
            </Button>
            {sel.group === "person" && (
              <Button size="sm" variant="outline" className="ml-auto" onClick={() => app.go("people")}>
                Открыть анкету
              </Button>
            )}
          </div>
        </aside>
      )}
    </div>
  )
}
