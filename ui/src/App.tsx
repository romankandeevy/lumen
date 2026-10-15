import {
  Bot,
  Brain,
  Cloud,
  Laptop,
  Loader2,
  MessageSquare,
  Moon,
  Plus,
  Search,
  Settings,
  Sparkles,
  SquarePen,
  SquareTerminal,
  Sun,
  UsersRound,
  Wrench,
} from "lucide-react"
import { toast } from "sonner"

import { BotAvatar } from "@/components/bot-avatar"
import { LumenOrb } from "@/components/lumen-orb"
import { Page as PageFrame } from "@/components/page"
import {
  Command,
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandShortcut,
} from "@/components/ui/command"
import { Toaster } from "@/components/ui/sonner"
import { TooltipProvider } from "@/components/ui/tooltip"
import { AppStateProvider, useApp, type Page, type Tab } from "@/lib/app-state"
import { chats, runs, sessions } from "@/lib/mock-data"
import { cn } from "@/lib/utils"
import { BotPage } from "@/pages/bot-page"
import { BotsPage } from "@/pages/bots-page"
import { ChatPage } from "@/pages/chat-page"
import { GroupPage, NewGroupForm, Stack } from "@/pages/group-page"
import { MemoryPage } from "@/pages/memory-page"
import { Onboarding } from "@/pages/onboarding"
import { PeoplePage } from "@/pages/people-page"
import { PersonaPage } from "@/pages/persona-page"
import { SettingsPage } from "@/pages/settings-page"
import { ToolsPage } from "@/pages/tools-page"
import { VoiceMode } from "@/pages/voice-mode"

// Оболочка как в Claude: сверху панели три вкладки — Чат (просто разговор),
// Агент (работа в папке, на Маке или в облаке через API) и Боты (агенты под одну роль).
// Внизу панели — общее для всех: память, люди, характер, инструменты, настройки.

export function App() {
  return (
    <AppStateProvider>
      <TooltipProvider delayDuration={150}>
        <Shell />
        <Toaster position="bottom-right" />
      </TooltipProvider>
    </AppStateProvider>
  )
}

const tabs: { id: Tab; name: string; icon: React.ComponentType<{ className?: string }> }[] = [
  { id: "chat", name: "Чат", icon: MessageSquare },
  { id: "agent", name: "Агент", icon: SquareTerminal },
  { id: "bots", name: "Боты", icon: Bot },
]

const sections: { id: Page; name: string; icon: React.ComponentType<{ className?: string }> }[] = [
  { id: "memory", name: "Память", icon: Brain },
  { id: "people", name: "Люди", icon: UsersRound },
  { id: "persona", name: "Характер", icon: Sparkles },
  { id: "tools", name: "Инструменты", icon: Wrench },
]

function Shell() {
  const app = useApp()
  const { page, id } = app.open

  return (
    <div data-lumen={app.orb} className="lumen-light grid h-svh grid-cols-[256px_minmax(0,1fr)] overflow-hidden">
      <aside className="flex min-h-0 flex-col border-r bg-sidebar/70 backdrop-blur-sm">
        <div className="flex items-center gap-2.5 px-4 pt-4 pb-3">
          <LumenOrb state={app.orb} size={22} />
          <span className="text-[15px] font-semibold tracking-[-0.01em]">Lumen</span>
          <button
            onClick={() => app.setPaletteOpen(true)}
            className="ml-auto flex size-7 items-center justify-center rounded-lg text-muted-foreground hover:bg-foreground/5 hover:text-foreground"
            title="Найти и сделать · ⌘K"
            aria-label="Найти и сделать"
          >
            <Search className="size-4" />
          </button>
          <button
            onClick={app.newInTab}
            className="flex size-7 items-center justify-center rounded-lg text-muted-foreground hover:bg-foreground/5 hover:text-foreground"
            title={`${app.tab === "bots" ? "Новый бот" : app.tab === "agent" ? "Новая задача" : "Новый чат"} · ⌘N`}
            aria-label="Новый разговор"
          >
            <SquarePen className="size-4" />
          </button>
        </div>

        {/* три вкладки — как Chat / Code в Claude */}
        <div className="mx-3 grid grid-cols-3 gap-0.5 rounded-xl bg-foreground/[0.05] p-0.5" role="tablist">
          {tabs.map((t) => (
            <button
              key={t.id}
              role="tab"
              aria-selected={app.tab === t.id}
              onClick={() => app.setTab(t.id)}
              className={cn(
                "flex h-8 items-center justify-center gap-1.5 rounded-[10px] text-[13px] transition-colors",
                app.tab === t.id ? "bg-background text-foreground shadow-[0_0_0_1px_var(--border)]" : "text-muted-foreground hover:text-foreground"
              )}
            >
              <t.icon className={cn("size-3.5", app.tab === t.id && "text-glow")} />
              {t.name}
            </button>
          ))}
        </div>

        <div className="mt-3 min-h-0 flex-1 overflow-auto px-3 pb-3">
          {app.tab === "chat" && <ChatList />}
          {app.tab === "agent" && <AgentList />}
          {app.tab === "bots" && <BotList />}
        </div>

        <nav className="space-y-0.5 border-t px-3 py-2">
          {sections.map((s) => (
            <NavItem key={s.id} active={page === s.id} onClick={() => app.go(s.id)} icon={s.icon}>
              {s.name}
              {s.id === "memory" && <span className="ml-auto text-xs text-muted-foreground tabular-nums">{app.memories.length}</span>}
            </NavItem>
          ))}
          <NavItem active={page === "settings"} onClick={() => app.go("settings")} icon={Settings}>
            Настройки
          </NavItem>
        </nav>
        <button
          onClick={() => app.go("settings", "models")}
          className="m-3 mt-0 flex items-center gap-2.5 rounded-xl border bg-card/40 px-2.5 py-2 text-left hover:bg-card"
        >
          <span className="flex size-7 items-center justify-center rounded-full bg-foreground/10 text-xs font-medium">{app.me.name[0]}</span>
          <span className="min-w-0 flex-1">
            <span className="block truncate text-sm">{app.me.name}</span>
            <span className="block truncate text-xs text-muted-foreground">Claude Max · подписка</span>
          </span>
        </button>
      </aside>

      <main className="relative min-h-0 overflow-hidden">
        {page === "thread" && <ChatPage key={id} chatId={id ?? "new-chat"} />}
        {page === "bots" && <BotsPage />}
        {page === "bot" && id && <BotPage key={id} botId={id} />}
        {page === "group" && id === "new" && (
          <PageFrame title="Новая группа" lead="Несколько ботов на одну задачу. Сначала они договорятся о ролях и вместе напишут план, потом начнут работать.">
            <div className="max-w-3xl">
              <NewGroupForm
                onCreate={(g) => {
                  app.setGroups((gs) => [...gs, g])
                  app.go("group", g.id)
                }}
              />
            </div>
          </PageFrame>
        )}
        {page === "group" && id && id !== "new" && <GroupPage key={id} groupId={id} />}
        {page === "memory" && <MemoryPage />}
        {page === "people" && <PeoplePage />}
        {page === "persona" && <PersonaPage />}
        {page === "tools" && <ToolsPage />}
        {page === "settings" && <SettingsPage />}
        {app.voiceOpen && <VoiceMode />}
      </main>

      <Palette />
      {!app.onboarded && <Onboarding />}
    </div>
  )
}

function NewButton({ onClick, children }: { onClick: () => void; children: React.ReactNode }) {
  return (
    <button onClick={onClick} className="mb-3 flex h-8 w-full items-center gap-2 rounded-lg bg-foreground/[0.06] px-2.5 text-sm hover:bg-foreground/10">
      <Plus className="size-4" /> {children}
    </button>
  )
}

function Row({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "relative flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-left text-sm text-foreground/80 hover:bg-foreground/5 hover:text-foreground",
        active && "bg-foreground/[0.07] text-foreground"
      )}
    >
      {active && <span className="absolute top-1.5 bottom-1.5 left-0 w-[2px] rounded-full bg-glow shadow-[0_0_10px_var(--glow)]" />}
      {children}
    </button>
  )
}

/// Вкладка «Чат»: просто разговоры, без папок
function ChatList() {
  const app = useApp()
  return (
    <>
      <NewButton onClick={() => app.go("thread", "new-chat")}>Новый чат</NewButton>
      {chats.map((g) => (
        <div key={g.group} className="mb-3">
          <p className="px-2.5 pb-1 text-xs text-muted-foreground">{g.group}</p>
          {g.items.map((c) => (
            <Row key={c.id} active={app.open.page === "thread" && app.open.id === c.id} onClick={() => app.go("thread", c.id)}>
              <span className="truncate">{c.title}</span>
              {c.unread ? (
                <span className="ml-auto size-1.5 shrink-0 rounded-full bg-glow shadow-[0_0_8px_var(--glow)]" />
              ) : (
                <span className="ml-auto shrink-0 text-[11px] text-muted-foreground">{c.when}</span>
              )}
            </Row>
          ))}
        </div>
      ))}
    </>
  )
}

/// Вкладка «Агент»: сессии в папках проектов; облачко — если идёт в облаке через API
function AgentList() {
  const app = useApp()
  return (
    <>
      <NewButton onClick={() => app.go("thread", "new-agent")}>Новая задача</NewButton>
      <p className="px-2.5 pb-1 text-xs text-muted-foreground">Сессии</p>
      {sessions.map((s) => (
        <Row key={s.id} active={app.open.page === "thread" && app.open.id === s.id} onClick={() => app.go("thread", s.id)}>
          <span className="flex size-5 shrink-0 items-center justify-center self-start pt-0.5 text-muted-foreground" title={s.where === "cloud" ? "В облаке через API" : "На этом Маке"}>
            {s.state === "running" ? <Loader2 className="size-3.5 animate-spin text-glow" /> : s.where === "cloud" ? <Cloud className="size-3.5" /> : <Laptop className="size-3.5" />}
          </span>
          <span className="min-w-0 flex-1">
            <span className="block truncate">{s.title}</span>
            <span className="flex items-center gap-1 text-[11px] text-muted-foreground">
              {s.project}
              {s.where === "cloud" && (
                <>
                  <span className="text-foreground/20">·</span>
                  <Cloud className="size-3" /> облако
                </>
              )}
              {s.state === "waiting" && <span className="ml-1 text-glow">ждёт тебя</span>}
            </span>
          </span>
          <span className="shrink-0 self-start text-[11px] text-muted-foreground">{s.when}</span>
        </Row>
      ))}
    </>
  )
}

/// Вкладка «Боты»: все боты столбиком, как чаты
function BotList() {
  const app = useApp()
  return (
    <>
      <NewButton onClick={() => app.go("bot", "new")}>Создать бота</NewButton>
      <Row active={app.open.page === "bots"} onClick={() => app.go("bots")}>
        <Bot className="size-4 text-muted-foreground" /> Все боты
        <span className="ml-auto text-[11px] text-muted-foreground">{runs.length} работают</span>
      </Row>
      {/* группы — несколько ботов на одну задачу */}
      <div className="mt-3 flex items-center px-2.5 pb-1">
        <p className="text-xs text-muted-foreground">Группы</p>
        <button onClick={() => app.go("group", "new")} title="Новая группа" aria-label="Новая группа" className="ml-auto flex size-5 items-center justify-center rounded-md text-muted-foreground hover:bg-foreground/10 hover:text-foreground">
          <Plus className="size-3.5" />
        </button>
      </div>
      {app.groups.map((g) => (
        <Row key={g.id} active={app.open.page === "group" && app.open.id === g.id} onClick={() => app.go("group", g.id)}>
          <Stack bots={g.members.map((m) => app.bots.find((b) => b.id === m)!).filter(Boolean)} size={20} />
          <span className="min-w-0 flex-1 truncate">{g.name}</span>
          {g.live && <Loader2 className="size-3.5 shrink-0 animate-spin text-glow" />}
        </Row>
      ))}
      <p className="mt-3 px-2.5 pb-1 text-xs text-muted-foreground">Боты</p>
      <div className="space-y-0.5">
        {app.bots.map((b) => {
          const running = runs.some((r) => r.bot === b.id)
          return (
            <Row key={b.id} active={app.open.page === "bot" && app.open.id === b.id} onClick={() => app.go("bot", b.id)}>
              <BotAvatar bot={b} size={28} />
              <span className="min-w-0 flex-1">
                <span className="block truncate">{b.name}</span>
                <span className="block truncate text-[11px] text-muted-foreground">@{b.id}</span>
              </span>
              {running && <Loader2 className="size-3.5 shrink-0 animate-spin" style={{ color: `oklch(0.8 0.12 ${b.hue})` }} />}
            </Row>
          )
        })}
      </div>
    </>
  )
}

function NavItem({
  active,
  onClick,
  icon: Icon,
  children,
}: {
  active: boolean
  onClick: () => void
  icon: React.ComponentType<{ className?: string }>
  children: React.ReactNode
}) {
  return (
    <button
      onClick={onClick}
      aria-current={active ? "page" : undefined}
      className={cn(
        "relative flex h-8 w-full items-center gap-2.5 rounded-lg px-2.5 text-sm text-foreground/75 transition-colors hover:bg-foreground/5 hover:text-foreground",
        active && "bg-foreground/[0.07] text-foreground"
      )}
    >
      {active && <span className="absolute top-1.5 bottom-1.5 left-0 w-[2px] rounded-full bg-glow shadow-[0_0_10px_var(--glow)]" />}
      <Icon className={cn("size-4", active ? "text-glow" : "text-muted-foreground")} />
      {children}
    </button>
  )
}

function Palette() {
  const app = useApp()
  const run = (fn: () => void) => {
    fn()
    app.setPaletteOpen(false)
  }
  const openIn = (tab: Tab, page: Page, id?: string) => {
    app.setTab(tab)
    app.go(page, id)
  }
  return (
    <CommandDialog open={app.paletteOpen} onOpenChange={app.setPaletteOpen} title="Найти и сделать" description="Чат, сессия, бот, воспоминание или действие">
      <Command>
        <CommandInput placeholder="Чат, сессия, бот, воспоминание или действие…" />
        <CommandList>
          <CommandEmpty>Ничего не нашлось.</CommandEmpty>
          <CommandGroup heading="Начать">
            <CommandItem onSelect={() => run(() => openIn("chat", "thread", "new-chat"))}>
              <MessageSquare /> Новый чат
            </CommandItem>
            <CommandItem onSelect={() => run(() => openIn("agent", "thread", "new-agent"))}>
              <SquareTerminal /> Новая задача агенту
            </CommandItem>
            <CommandItem onSelect={() => run(() => app.setVoiceOpen(true))}>
              <Sparkles /> Поговорить голосом
            </CommandItem>
          </CommandGroup>
          <CommandGroup heading="Боты">
            {app.bots.map((b) => (
              <CommandItem key={b.id} value={`${b.name} @${b.id}`} onSelect={() => run(() => openIn("bots", "bot", b.id))}>
                <BotAvatar bot={b} size={18} /> {b.name}
                <CommandShortcut>@{b.id}</CommandShortcut>
              </CommandItem>
            ))}
          </CommandGroup>
          <CommandGroup heading="Чаты и сессии">
            {chats
              .flatMap((g) => g.items)
              .map((c) => (
                <CommandItem key={c.id} value={c.title} onSelect={() => run(() => openIn("chat", "thread", c.id))}>
                  <MessageSquare /> {c.title}
                </CommandItem>
              ))}
            {sessions.map((s) => (
              <CommandItem key={s.id} value={s.title} onSelect={() => run(() => openIn("agent", "thread", s.id))}>
                <SquareTerminal /> {s.title}
                <CommandShortcut>{s.project}</CommandShortcut>
              </CommandItem>
            ))}
          </CommandGroup>
          <CommandGroup heading="Разделы">
            {[...sections, { id: "settings" as Page, name: "Настройки", icon: Settings }].map((s) => (
              <CommandItem key={s.id} onSelect={() => run(() => app.go(s.id))}>
                <s.icon /> {s.name}
              </CommandItem>
            ))}
          </CommandGroup>
          <CommandGroup heading="Действия">
            <CommandItem onSelect={() => run(() => app.setTheme(app.theme === "lumen" ? "mono" : "lumen"))}>
              {app.theme === "lumen" ? <Moon /> : <Sun />} Тема: {app.theme === "lumen" ? "Монохром" : "Люмен"}
            </CommandItem>
            <CommandItem onSelect={() => run(() => (app.setOnboarded(false), toast("Знакомство заново")))}>
              <Sparkles /> Пройти знакомство заново
            </CommandItem>
          </CommandGroup>
        </CommandList>
      </Command>
    </CommandDialog>
  )
}

export default App
