import type { OrbState } from "@/lib/app-state"
import { cn } from "@/lib/utils"

/// Знак Люмена — светящаяся сфера. Покой: медленно дышит. Думает: дышит чаще.
/// Пишет: разгорается. Запомнил: вспышка и кольцо света. Спит: тускнеет.
export function LumenOrb({ state = "idle", size = 28, className }: { state?: OrbState; size?: number; className?: string }) {
  return (
    <span
      aria-hidden
      data-state={state}
      className={cn("orb", className)}
      style={{ width: size, height: size, ["--orb-size" as string]: `${size}px` }}
    >
      <span className="orb-halo" />
      <span className="orb-body" />
      <span className="orb-ring" />
    </span>
  )
}
