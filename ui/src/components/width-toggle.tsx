import { Check } from "lucide-react"

import { useApp, type ChatWidth } from "@/lib/app-state"
import { cn } from "@/lib/utils"

// Ширина переписки — в «Настройках → Внешний вид». Общая для чата, агента и ботов.
// Карточка показывает миниатюру окна: колонка переписки той ширины, что получится.

const widths: { id: ChatWidth; name: string; note: string; col: number }[] = [
  { id: "normal", name: "Обычно", note: "удобно читать", col: 46 },
  { id: "wide", name: "Шире", note: "для кода и таблиц", col: 66 },
  { id: "full", name: "Ещё шире", note: "почти весь экран", col: 90 },
]

export function WidthSetting() {
  const app = useApp()
  return (
    <div className="grid gap-3 sm:grid-cols-3" role="radiogroup" aria-label="Ширина переписки">
      {widths.map((w) => {
        const active = app.chatWidth === w.id
        return (
          <button
            key={w.id}
            role="radio"
            aria-checked={active}
            onClick={() => app.setChatWidth(w.id)}
            className={cn(
              "rounded-2xl border p-2 text-left transition-colors",
              active ? "border-glow/50 shadow-[0_0_28px_-8px_var(--glow-soft)]" : "hover:border-foreground/20"
            )}
          >
            {/* миниатюра окна */}
            <div className="relative h-24 overflow-hidden rounded-xl bg-background">
              <div className="absolute inset-y-0 left-0 w-[18%] border-r bg-sidebar" />
              <div className="absolute inset-y-0 right-0 left-[18%] flex justify-center">
                <div className="flex flex-col gap-1.5 pt-3 transition-[width] duration-300" style={{ width: `${w.col}%` }}>
                  <div className="ml-auto h-2 w-1/2 rounded-full bg-secondary" />
                  <div className="h-1.5 w-full rounded-full bg-foreground/15" />
                  <div className="h-1.5 w-5/6 rounded-full bg-foreground/15" />
                  <div className="h-1.5 w-2/3 rounded-full bg-foreground/15" />
                  <div className={cn("mt-auto mb-2.5 h-4 w-full rounded-md border", active && "border-glow/40 shadow-[0_0_12px_-2px_var(--glow-soft)]")} />
                </div>
              </div>
            </div>
            <div className="flex items-center px-1.5 pt-2.5 pb-1">
              <span className="min-w-0 flex-1">
                <span className="block text-sm font-medium">{w.name}</span>
                <span className="block text-xs text-muted-foreground">{w.note}</span>
              </span>
              {active && <Check className="size-4 text-glow" />}
            </div>
          </button>
        )
      })}
    </div>
  )
}
