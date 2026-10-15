import { Check, ChevronDown, Sparkles } from "lucide-react"

import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { efforts, models } from "@/lib/mock-data"
import { cn } from "@/lib/utils"

// Выбор модели и «сколько думать» — как в Claude Code

/// Шесть столбиков, закрашены до уровня — как индикатор сигнала
export function EffortBars({ level, className }: { level: number; className?: string }) {
  return (
    <span className={cn("flex h-3.5 items-end gap-[2px]", className)}>
      {efforts.map((_, i) => (
        <span
          key={i}
          className={cn("w-[3px] rounded-full transition-colors", i <= level ? "bg-glow" : "bg-foreground/20")}
          style={{ height: `${4 + i * 2}px` }}
        />
      ))}
    </span>
  )
}

function Option({ active, onClick, icon, name, note }: { active: boolean; onClick: () => void; icon: React.ReactNode; name: string; note: string }) {
  return (
    <button
      onClick={onClick}
      className={cn("flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left hover:bg-muted/60", active && "bg-muted")}
    >
      {icon}
      <span className="min-w-0 flex-1">
        <span className="block text-sm font-medium">{name}</span>
        <span className="block text-xs text-muted-foreground">{note}</span>
      </span>
      {active && <Check className="size-4 text-glow" />}
    </button>
  )
}

export function EffortPicker({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const level = efforts.findIndex((e) => e.id === value)
  return (
    <Popover>
      <PopoverTrigger asChild>
        <button className="flex h-7 items-center whitespace-nowrap gap-2 rounded-lg px-2 text-xs hover:bg-foreground/5">
          <EffortBars level={level} />
          {efforts[level]?.name}
          <ChevronDown className="size-3 opacity-50" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" side="top" className="w-72 p-1.5">
        <p className="px-2 pt-1 pb-2 text-xs text-muted-foreground">Сколько думать</p>
        {efforts.map((e, i) => (
          <Option key={e.id} active={e.id === value} onClick={() => onChange(e.id)} icon={<EffortBars level={i} />} name={e.name} note={e.note} />
        ))}
      </PopoverContent>
    </Popover>
  )
}

export function ModelPicker({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const current = models.find((m) => m.id === value)
  return (
    <Popover>
      <PopoverTrigger asChild>
        <button className="flex h-7 items-center whitespace-nowrap gap-1.5 rounded-lg px-2 text-xs font-medium hover:bg-foreground/5">
          <Sparkles className="size-3.5 text-glow" />
          {current?.name}
          <ChevronDown className="size-3 opacity-50" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" side="top" className="w-72 p-1.5">
        <p className="px-2 pt-1 pb-2 text-xs text-muted-foreground">Модель</p>
        {models.map((m) => (
          <Option
            key={m.id}
            active={m.id === value}
            onClick={() => onChange(m.id)}
            icon={<Sparkles className="size-4 text-muted-foreground" />}
            name={m.name}
            note={m.note}
          />
        ))}
      </PopoverContent>
    </Popover>
  )
}
