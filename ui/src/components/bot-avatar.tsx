import { Code2, FlaskConical, Palette, PenLine, ShieldCheck, Sunrise } from "lucide-react"

import type { BotDef, BotIcon } from "@/lib/mock-data"
import { cn } from "@/lib/utils"

// Знак бота — квадрат своего цвета. Lumen — круглая сфера, бот — плитка:
// так в ленте сразу видно, кто говорит.

export const botIcons: Record<BotIcon, React.ComponentType<{ className?: string }>> = {
  flask: FlaskConical,
  palette: Palette,
  code: Code2,
  pen: PenLine,
  sunrise: Sunrise,
  shield: ShieldCheck,
}

/// CSS-переменная --bot с цветом бота — для акцентов на его странице и карточках
export function botStyle(hue: number): React.CSSProperties {
  return {
    ["--bot" as string]: `oklch(0.8 0.12 ${hue})`,
    ["--bot-soft" as string]: `oklch(0.8 0.12 ${hue} / 14%)`,
    ["--bot-faint" as string]: `oklch(0.8 0.12 ${hue} / 6%)`,
  }
}

export function BotAvatar({ bot, size = 28, className }: { bot: Pick<BotDef, "icon" | "hue">; size?: number; className?: string }) {
  const Icon = botIcons[bot.icon]
  return (
    <span
      aria-hidden
      className={cn("relative inline-flex shrink-0 items-center justify-center overflow-hidden", className)}
      style={{
        ...botStyle(bot.hue),
        width: size,
        height: size,
        borderRadius: size * 0.28,
        background: `linear-gradient(140deg, oklch(0.42 0.1 ${bot.hue}), oklch(0.24 0.05 ${bot.hue}))`,
        boxShadow: `inset 0 1px 0 oklch(1 0 0 / 12%), 0 0 ${size * 0.6}px -${size * 0.2}px var(--bot)`,
      }}
    >
      <span className="flex text-[var(--bot)]" style={{ width: size * 0.5, height: size * 0.5 }}>
        <Icon className="size-full" />
      </span>
    </span>
  )
}
