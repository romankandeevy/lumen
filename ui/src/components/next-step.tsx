import { X } from "lucide-react"
import { useEffect } from "react"

import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"

// Карточка «что дальше» — как в Claude Code: в конце хода агент сам пишет короткий итог
// (что сделано, что не проверено) и, если решение за Ромой, один вопрос с кнопками.
// Главная кнопка — ⌘↵, вторая — реальная альтернатива, крестик — убрать карточку.

export type NextStepData = {
  recap: string
  ask?: string
  primary?: Choice
  secondary?: Choice
}

/// Кнопка: что отправится от Ромы и что агент ответит
export type Choice = { label: string; reply: string; ack: string }

export function NextStep({ data, onAnswer, onClose }: { data: NextStepData; onAnswer: (choice: Choice) => void; onClose: () => void }) {
  // ⌘↵ — главная кнопка, если фокус не в поле с текстом
  useEffect(() => {
    if (!data.primary) return
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
        const t = e.target as HTMLElement
        if (t instanceof HTMLTextAreaElement && t.value.trim()) return
        e.preventDefault()
        onAnswer(data.primary!)
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [data, onAnswer])

  return (
    <div className="relative animate-in rounded-2xl border bg-card/70 px-5 py-4 duration-300 fade-in slide-in-from-bottom-1">
      <button onClick={onClose} aria-label="Убрать" className="absolute top-3.5 right-3.5 text-muted-foreground hover:text-foreground">
        <X className="size-4" />
      </button>
      <p className="pr-7 text-[0.9375rem] leading-relaxed text-foreground/85">{data.recap}</p>
      {data.ask && <p className="mt-3.5 text-[0.9375rem]">{data.ask}</p>}
      {(data.primary || data.secondary) && (
        <div className="mt-3.5 flex flex-wrap gap-2">
          {data.primary && (
            <Button className="h-9 rounded-xl bg-foreground pr-1.5 text-background hover:bg-foreground/90" onClick={() => onAnswer(data.primary!)}>
              {data.primary.label}
              <span className="ml-1.5 flex gap-0.5">
                <Kbd>⌘</Kbd>
                <Kbd>↵</Kbd>
              </span>
            </Button>
          )}
          {data.secondary && (
            <Button variant="secondary" className="h-9 rounded-xl" onClick={() => onAnswer(data.secondary!)}>
              {data.secondary.label}
            </Button>
          )}
        </div>
      )}
    </div>
  )
}

function Kbd({ children, className }: { children: React.ReactNode; className?: string }) {
  return <kbd className={cn("flex size-6 items-center justify-center rounded-md border border-background/20 bg-background/10 font-sans text-xs", className)}>{children}</kbd>
}
