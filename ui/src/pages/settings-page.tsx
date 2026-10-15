import { Check, FolderOpen, Download, Sparkles } from "lucide-react"
import { toast } from "sonner"

import { LumenOrb } from "@/components/lumen-orb"
import { GroupTitle, Page } from "@/components/page"
import { Button } from "@/components/ui/button"
import { Switch } from "@/components/ui/switch"
import { useApp, type Theme } from "@/lib/app-state"
import { cn } from "@/lib/utils"

const shortcuts = [
  ["Найти и сделать", "⌘K"],
  ["Новый чат", "⌘N"],
  ["Чат / Память / Люди / Характер", "⌘1 – ⌘4"],
  ["Показать контекст", "⌘."],
  ["Голосом", "держать правый ⌥"],
  ["Настройки", "⌘,"],
]

export function SettingsPage() {
  const app = useApp()
  return (
    <Page title="Настройки">
      <div className="max-w-4xl space-y-9">
        <div>
          <GroupTitle>Тема</GroupTitle>
          <div className="grid gap-3 sm:grid-cols-3">
            <ThemeCard id="lumen" name="Люмен" note="Тёплая темнота и свет" />
            <ThemeCard id="mono" name="Монохром" note="Чёрно-белая, как Пульт" />
            <div className="flex flex-col justify-center rounded-2xl border border-dashed p-4 text-muted-foreground">
              <p className="text-sm text-foreground/70">Свои темы</p>
              <p className="mt-1 text-xs leading-relaxed">Цвет света, фон, шрифт и ещё 10 готовых тем — позже</p>
            </div>
          </div>
          <label className="mt-4 flex max-w-md items-center gap-3 text-sm">
            <Switch checked={app.reducedMotion} onCheckedChange={app.setReducedMotion} />
            Меньше движения
            <span className="text-xs text-muted-foreground">сфера не дышит, свет не мерцает</span>
          </label>
        </div>

        <div>
          <GroupTitle>Горячие клавиши</GroupTitle>
          <div className="divide-y rounded-xl border bg-card/40">
            {shortcuts.map(([name, keys]) => (
              <div key={name} className="flex items-center px-4 py-2.5 text-sm">
                {name}
                <kbd className="ml-auto rounded-md border bg-background/50 px-2 py-0.5 text-xs text-muted-foreground">{keys}</kbd>
              </div>
            ))}
          </div>
        </div>

        <div>
          <GroupTitle>Данные</GroupTitle>
          <div className="rounded-xl border bg-card/40 p-4">
            <p className="text-sm">Всё хранится на этом Маке</p>
            <p className="mt-1 font-mono text-xs text-muted-foreground">~/Library/Application Support/Lumen</p>
            <p className="mt-1 text-xs text-muted-foreground">Память, профили, характер, история чатов. Ничего не уходит в облако, кроме самих запросов к модели.</p>
            <div className="mt-4 flex flex-wrap gap-2">
              <Button variant="outline" size="sm" onClick={() => toast("Открыто в Finder")}>
                <FolderOpen /> Показать в Finder
              </Button>
              <Button variant="outline" size="sm" onClick={() => toast("Память выгружена", { description: "lumen-memory-2026-10-15.zip" })}>
                <Download /> Выгрузить память
              </Button>
              <Button variant="ghost" size="sm" onClick={() => app.setOnboarded(false)}>
                <Sparkles /> Пройти знакомство заново
              </Button>
            </div>
          </div>
        </div>
      </div>
    </Page>
  )
}

/// Карточка темы — с миниатюрой окна в цветах этой темы
function ThemeCard({ id, name, note }: { id: Theme; name: string; note: string }) {
  const app = useApp()
  const active = app.theme === id
  return (
    <button
      onClick={() => app.setTheme(id)}
      className={cn(
        "rounded-2xl border p-2 text-left transition-colors",
        active ? "border-glow/50 shadow-[0_0_28px_-8px_var(--glow-soft)]" : "hover:border-foreground/20"
      )}
    >
      <div className={cn("theme-" + id, "relative h-24 overflow-hidden rounded-xl")} style={{ background: "var(--background)" }}>
        <div className="absolute inset-y-0 left-0 w-1/4 border-r" style={{ background: "var(--sidebar)", borderColor: "var(--border)" }}>
          <LumenOrb size={10} className="m-2" />
        </div>
        <div className="absolute top-4 right-4 left-[32%] space-y-1.5">
          <div className="ml-auto h-2.5 w-1/2 rounded-full" style={{ background: "var(--secondary)" }} />
          <div className="h-2 w-5/6 rounded-full" style={{ background: "var(--muted)" }} />
          <div className="h-2 w-2/3 rounded-full" style={{ background: "var(--muted)" }} />
        </div>
        <div className="absolute right-4 bottom-3 left-[32%] h-4 rounded-md border" style={{ borderColor: "var(--border)", boxShadow: "0 0 14px -2px var(--glow-soft)" }} />
      </div>
      <div className="flex items-center px-1.5 pt-2.5 pb-1">
        <span className="min-w-0 flex-1">
          <span className="block text-sm font-medium">{name}</span>
          <span className="block text-xs text-muted-foreground">{note}</span>
        </span>
        {active && <Check className="size-4 text-glow" />}
      </div>
    </button>
  )
}
