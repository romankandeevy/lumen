import { cn } from "@/lib/utils"

/// Каркас страницы-раздела: заголовок, пояснение, справа действия, ниже прокручиваемое содержимое
export function Page({
  title,
  lead,
  actions,
  children,
  className,
}: {
  title: string
  lead?: React.ReactNode
  actions?: React.ReactNode
  children: React.ReactNode
  className?: string
}) {
  return (
    <section className="flex min-h-0 flex-col">
      <header className="flex items-end gap-4 px-8 pt-8 pb-5">
        <div className="min-w-0">
          <h1 className="text-[1.65rem] leading-tight font-semibold tracking-[-0.02em]">{title}</h1>
          {lead && <p className="mt-1.5 max-w-[60ch] text-sm text-muted-foreground">{lead}</p>}
        </div>
        {actions && <div className="ml-auto flex shrink-0 items-center gap-2">{actions}</div>}
      </header>
      <div className={cn("min-h-0 flex-1 overflow-auto px-8 pb-10", className)}>{children}</div>
    </section>
  )
}

/// Подпись группы внутри страницы — обычным регистром, без капса
export function GroupTitle({ children, aside }: { children: React.ReactNode; aside?: React.ReactNode }) {
  return (
    <div className="mb-2.5 flex items-baseline justify-between">
      <h2 className="text-sm font-medium">{children}</h2>
      {aside && <span className="text-xs text-muted-foreground">{aside}</span>}
    </div>
  )
}

/// Сегменты-переключатель (тон, длина и т.п.)
export function Segmented<T extends string>({
  value,
  onChange,
  options,
  className,
}: {
  value: T
  onChange: (v: T) => void
  options: { id: T; name: string }[]
  className?: string
}) {
  return (
    <div className={cn("inline-flex rounded-lg bg-muted/50 p-0.5", className)} role="radiogroup">
      {options.map((o) => (
        <button
          key={o.id}
          role="radio"
          aria-checked={o.id === value}
          onClick={() => onChange(o.id)}
          className={cn(
            "h-7 rounded-md px-3 text-xs transition-colors",
            o.id === value ? "bg-background text-foreground shadow-[0_0_0_1px_var(--border)]" : "text-muted-foreground hover:text-foreground"
          )}
        >
          {o.name}
        </button>
      ))}
    </div>
  )
}
