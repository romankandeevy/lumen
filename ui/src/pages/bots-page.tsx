import { AtSign, Cloud, Laptop, Loader2, Lock, Plus } from "lucide-react"
import { toast } from "sonner"

import { BotAvatar, botStyle } from "@/components/bot-avatar"
import { GroupTitle, Page } from "@/components/page"
import { Button } from "@/components/ui/button"
import { useApp } from "@/lib/app-state"
import { botTools, runs, sessions } from "@/lib/mock-data"

// «Все боты»: что сейчас работает (как панель «Агенты» в Hermes) и каталог карточками (как GPTs).

export function BotsPage() {
  const app = useApp()
  return (
    <Page
      title="Боты"
      lead="Агенты под одну роль. Позови любого в чате через @ — Lumen передаст ему задачу. Всё, что вне роли, у бота отрезано в коде."
      actions={
        <Button onClick={() => app.go("bot", "new")}>
          <Plus /> Создать бота
        </Button>
      }
    >
      <div className="space-y-9">
        <div>
          <GroupTitle aside={`${runs.length} сейчас`}>Работают</GroupTitle>
          <div className="space-y-2">
            {runs.map((r) => {
              const bot = app.bots.find((b) => b.id === r.bot)!
              const session = sessions.find((s) => s.title === r.from)
              return (
                <button
                  key={r.bot}
                  style={botStyle(bot.hue)}
                  onClick={() => {
                    if (!session) return
                    app.setTab("agent")
                    app.go("thread", session.id)
                  }}
                  className="flex w-full items-center gap-3.5 rounded-xl border border-[var(--bot-soft)] bg-[var(--bot-faint)] px-4 py-3 text-left transition-colors hover:bg-[var(--bot-soft)]"
                >
                  <BotAvatar bot={bot} size={34} />
                  <span className="min-w-0 flex-1">
                    <span className="block text-sm">
                      <span className="font-medium">{bot.name}</span> <span className="text-muted-foreground">— {r.task}</span>
                    </span>
                    <span className="block truncate text-xs text-muted-foreground">
                      позвал Lumen из «{r.from}» · {r.step}
                    </span>
                  </span>
                  <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
                    {r.where === "cloud" ? <Cloud className="size-3.5" /> : <Laptop className="size-3.5" />}
                    <Loader2 className="size-4 animate-spin text-[var(--bot)]" />
                  </span>
                </button>
              )
            })}
          </div>
        </div>

        <div>
          <GroupTitle aside={`${app.bots.length} ботов`}>Все</GroupTitle>
          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4">
            {app.bots.map((b) => {
              const blocked = botTools.length - b.tools.length
              return (
                <div
                  key={b.id}
                  style={botStyle(b.hue)}
                  className="group relative flex flex-col overflow-hidden rounded-2xl border bg-card/40 p-4 transition-colors hover:border-[var(--bot-soft)]"
                >
                  <div className="pointer-events-none absolute -top-16 -right-16 size-40 rounded-full bg-[var(--bot-faint)] blur-2xl transition-opacity group-hover:opacity-100" />
                  <div className="flex items-start gap-3">
                    <BotAvatar bot={b} size={44} />
                    <div className="min-w-0">
                      <p className="font-medium">{b.name}</p>
                      <p className="text-xs text-[var(--bot)]">@{b.id}</p>
                    </div>
                  </div>
                  <p className="mt-3 text-sm text-foreground/80">{b.role}</p>
                  <div className="mt-3 flex flex-wrap gap-1.5 text-[11px] text-muted-foreground">
                    <span className="rounded-md bg-foreground/[0.06] px-1.5 py-0.5">{b.skills.length} навыка</span>
                    {blocked > 0 && (
                      <span className="flex items-center gap-1 rounded-md bg-foreground/[0.06] px-1.5 py-0.5">
                        <Lock className="size-3" /> {blocked} запрещено
                      </span>
                    )}
                    <span className="rounded-md bg-foreground/[0.06] px-1.5 py-0.5">{b.messages.toLocaleString("ru")} сообщений</span>
                  </div>
                  <div className="mt-4 flex gap-2 pt-1">
                    <Button size="sm" variant="outline" className="flex-1" onClick={() => app.go("bot", b.id)}>
                      Открыть
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => {
                        navigator.clipboard?.writeText(`@${b.id} `).catch(() => {})
                        toast(`@${b.id} скопирован`, { description: "Вставь в любом чате — Lumen передаст задачу боту." })
                      }}
                    >
                      <AtSign /> Позвать
                    </Button>
                  </div>
                </div>
              )
            })}
            <button
              onClick={() => app.go("bot", "new")}
              className="flex min-h-48 flex-col items-center justify-center gap-2 rounded-2xl border border-dashed text-muted-foreground transition-colors hover:border-glow/40 hover:text-foreground"
            >
              <Plus className="size-5" />
              <span className="text-sm">Создать бота</span>
              <span className="max-w-[24ch] text-center text-xs">Роль, разрешённые инструменты и навыки</span>
            </button>
          </div>
        </div>
      </div>
    </Page>
  )
}
