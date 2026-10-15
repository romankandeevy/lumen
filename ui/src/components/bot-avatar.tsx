import * as Lucide from "lucide-react"

import type { BotDef } from "@/lib/mock-data"
import { cn } from "@/lib/utils"

// Знак бота — плитка своего цвета с любой иконкой lucide. Lumen — круглая сфера, бот — плитка:
// так в ленте сразу видно, кто говорит. Цвет — оттенок (hue) и насыщенность (chroma) в oklch.

type IconComp = React.ComponentType<{ className?: string }>

/// Все иконки lucide по имени (без дублей-«…Icon» и служебных экспортов)
export const allIcons: Record<string, IconComp> = Object.fromEntries(
  Object.entries(Lucide).filter(
    ([k, v]) => /^[A-Z]/.test(k) && !k.endsWith("Icon") && !k.startsWith("Lucide") && k !== "Icon" && typeof v === "object"
  )
) as Record<string, IconComp>

export function botColor(hue: number, chroma = 0.12, l = 0.8) {
  return `oklch(${l} ${chroma} ${hue})`
}

/// CSS-переменные --bot / --bot-soft / --bot-faint с цветом бота — для акцентов на его страницах и карточках
export function botStyle(hue: number, chroma = 0.12): React.CSSProperties {
  return {
    ["--bot" as string]: `oklch(0.8 ${chroma} ${hue})`,
    ["--bot-soft" as string]: `oklch(0.8 ${chroma} ${hue} / 14%)`,
    ["--bot-faint" as string]: `oklch(0.8 ${chroma} ${hue} / 6%)`,
  }
}

export function BotAvatar({ bot, size = 28, className }: { bot: Pick<BotDef, "icon" | "hue"> & { chroma?: number }; size?: number; className?: string }) {
  const Icon = allIcons[bot.icon] ?? Lucide.Bot
  const c = bot.chroma ?? 0.12
  return (
    <span
      aria-hidden
      className={cn("relative inline-flex shrink-0 items-center justify-center overflow-hidden", className)}
      style={{
        ...botStyle(bot.hue, c),
        width: size,
        height: size,
        borderRadius: size * 0.28,
        background: `linear-gradient(140deg, oklch(0.42 ${c * 0.85} ${bot.hue}), oklch(0.24 ${c * 0.4} ${bot.hue}))`,
        boxShadow: `inset 0 1px 0 oklch(1 0 0 / 12%), 0 0 ${size * 0.6}px -${size * 0.2}px var(--bot)`,
      }}
    >
      <span className="flex text-[var(--bot)]" style={{ width: size * 0.5, height: size * 0.5 }}>
        <Icon className="size-full" />
      </span>
    </span>
  )
}
