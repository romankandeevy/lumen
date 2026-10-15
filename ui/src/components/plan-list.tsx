import { Check } from "lucide-react"

import { BotAvatar } from "@/components/bot-avatar"
import type { BotDef } from "@/lib/mock-data"
import { cn } from "@/lib/utils"

// План работы — как список задач в Claude Code: сделано — галочка, сейчас — крутится, дальше — пунктир.
// Показывается сбоку, в правой панели чата, агента, бота и группы. В группе у пункта есть исполнитель.

export type PlanItem = { text: string; state: "done" | "doing" | "todo"; who?: string }

export function PlanList({ items, bots, accent = "var(--glow)" }: { items: PlanItem[]; bots?: BotDef[]; accent?: string }) {
  const done = items.filter((i) => i.state === "done").length
  return (
    <div>
      <div className="mb-3 flex items-center gap-2">
        <div className="h-1 flex-1 overflow-hidden rounded-full bg-foreground/10">
          <div className="h-full rounded-full transition-[width] duration-500" style={{ width: `${(done / Math.max(items.length, 1)) * 100}%`, background: accent }} />
        </div>
        <span className="text-[11px] text-muted-foreground tabular-nums">
          {done} из {items.length}
        </span>
      </div>
      <ol className="space-y-2.5">
        {items.map((it, i) => {
          const bot = it.who ? bots?.find((b) => b.id === it.who) : undefined
          return (
            <li key={i} className="flex items-start gap-2.5">
              <Mark state={it.state} accent={accent} />
              <span
                className={cn(
                  "min-w-0 flex-1 text-[13px] leading-snug",
                  it.state === "done" && "text-muted-foreground",
                  it.state === "doing" && "font-medium text-foreground",
                  it.state === "todo" && "text-foreground/75"
                )}
              >
                {it.text}
              </span>
              {bot && <BotAvatar bot={bot} size={18} className="mt-px" />}
            </li>
          )
        })}
      </ol>
    </div>
  )
}

function Mark({ state, accent }: { state: PlanItem["state"]; accent: string }) {
  if (state === "done")
    return (
      <span className="mt-px flex size-[17px] shrink-0 items-center justify-center rounded-full bg-foreground/70">
        <Check className="size-3 text-background" strokeWidth={3} />
      </span>
    )
  if (state === "doing")
    return (
      <span
        className="mt-px size-[17px] shrink-0 animate-spin rounded-full border-2 border-foreground/15"
        style={{ borderTopColor: accent, animationDuration: "1.1s" }}
        aria-label="выполняется"
      />
    )
  return <span className="mt-px size-[17px] shrink-0 rounded-full border-[1.5px] border-dashed border-foreground/35" aria-label="впереди" />
}
