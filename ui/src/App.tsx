import {
  Bot,
  Brain,
  MessageSquare,
  Moon,
  Plug,
  Plus,
  Search,
  Settings,
  Sparkles,
  Sun,
  UserRound,
  UsersRound,
} from "lucide-react"
import { useState } from "react"
import { toast } from "sonner"

import { LumenOrb } from "@/components/lumen-orb"
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
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Toaster } from "@/components/ui/sonner"
import { TooltipProvider } from "@/components/ui/tooltip"
import { AppStateProvider, useApp, type Page } from "@/lib/app-state"
import { bots as initialBots, chatGroups, type BotDef } from "@/lib/mock-data"
import { cn } from "@/lib/utils"
import { ChatPage } from "@/pages/chat-page"
import { ConnectionsPage } from "@/pages/connections-page"
import { MemoryPage } from "@/pages/memory-page"
import { Onboarding } from "@/pages/onboarding"
import { PeoplePage } from "@/pages/people-page"
import { PersonaPage } from "@/pages/persona-page"
import { SettingsPage } from "@/pages/settings-page"

// Оболочка как в Cursor: слева узкая панель (разделы и чаты по проектам), справа — раздел.
// Свет Люмена падает на всё окно и усиливается, когда он думает.

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

const sections: {
  id: Page
  name: string
  icon: React.ComponentType<{ className?: string }>
  hint: string
}[] = [
  { id: "chat", name: "Чат", icon: MessageSquare, hint: "⌘1" },
  { id: "memory", name: "Память", icon: Brain, hint: "⌘2" },
  { id: "people", name: "Люди", icon: UsersRound, hint: "⌘3" },
  { id: "persona", name: "Характер", icon: Sparkles, hint: "⌘4" },
]

function Shell() {
  const app = useApp()
  const [activeChat, setActiveChat] = useState("lumen")
  const [botList, setBotList] = useState<BotDef[]>(initialBots)
  const [creatingBot, setCreatingBot] = useState(false)

  const openChat = (id: string) => {
    setActiveChat(id)
    app.go("chat")
  }

  return (
    <div
      data-lumen={app.orb}
      className="lumen-light grid h-svh grid-cols-[248px_minmax(0,1fr)] overflow-hidden"
    >
      <aside className="flex min-h-0 flex-col border-r bg-sidebar/70 backdrop-blur-sm">
        {/* знак */}
        <div className="flex items-center gap-2.5 px-4 pt-4 pb-3">
          <LumenOrb state={app.orb} size={22} />
          <span className="text-[15px] font-semibold tracking-[-0.01em]">
            Lumen
          </span>
          <span className="ml-auto rounded-md border px-1.5 py-0.5 text-[10px] text-muted-foreground">
            макет
          </span>
        </div>

        <div className="space-y-1 px-3">
          <button
            onClick={() => {
              setActiveChat("new")
              app.go("chat")
            }}
            className="flex h-8 w-full items-center gap-2 rounded-lg bg-foreground/[0.06] px-2.5 text-sm hover:bg-foreground/10"
          >
            <Plus className="size-4" /> Новый чат
            <kbd className="ml-auto text-[11px] text-muted-foreground">⌘N</kbd>
          </button>
          <button
            onClick={() => app.setPaletteOpen(true)}
            className="flex h-8 w-full items-center gap-2 rounded-lg px-2.5 text-sm text-muted-foreground hover:bg-foreground/5 hover:text-foreground"
          >
            <Search className="size-4" /> Найти и сделать
            <kbd className="ml-auto text-[11px]">⌘K</kbd>
          </button>
        </div>

        {/* боты — сверху: каждый бот это один постоянный чат под свою задачу */}
        <div className="mt-4 px-3">
          <div className="flex items-center px-2.5 pb-1">
            <p className="text-xs text-muted-foreground">Боты</p>
            <button
              onClick={() => setCreatingBot(true)}
              title="Новый бот"
              aria-label="Новый бот"
              className="ml-auto flex size-5 items-center justify-center rounded-md text-muted-foreground hover:bg-foreground/10 hover:text-foreground"
            >
              <Plus className="size-3.5" />
            </button>
          </div>
          {botList.map((b) => {
            const active = app.page === "chat" && activeChat === `bot:${b.id}`
            return (
              <button
                key={b.id}
                onClick={() => openChat(`bot:${b.id}`)}
                className={cn(
                  "relative flex w-full items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-left hover:bg-foreground/5",
                  active && "bg-foreground/[0.07]"
                )}
              >
                {active && (
                  <span className="absolute top-1.5 bottom-1.5 left-0 w-[2px] rounded-full bg-glow shadow-[0_0_10px_var(--glow)]" />
                )}
                <span
                  className={cn(
                    "flex size-6 shrink-0 items-center justify-center rounded-md bg-foreground/[0.07] text-[11px] font-medium",
                    active && "text-glow"
                  )}
                >
                  {b.name[0]}
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm">{b.name}</span>
                  <span className="block truncate text-[11px] text-muted-foreground">
                    {b.task}
                  </span>
                </span>
                {b.unread && (
                  <span className="size-1.5 shrink-0 rounded-full bg-glow shadow-[0_0_8px_var(--glow)]" />
                )}
              </button>
            )
          })}
        </div>

        <nav className="mt-3 space-y-0.5 border-t px-3 pt-3">
          {sections.map((s) => (
            <NavItem
              key={s.id}
              active={
                app.page === s.id &&
                !(s.id === "chat" && activeChat.startsWith("bot:"))
              }
              onClick={() =>
                s.id === "chat"
                  ? openChat(
                      activeChat.startsWith("bot:") ? "lumen" : activeChat
                    )
                  : app.go(s.id)
              }
              icon={s.icon}
            >
              {s.name}
              {s.id === "memory" && (
                <span className="ml-auto text-xs text-muted-foreground tabular-nums">
                  {
                    app.memories.filter((m) => m.profile === app.activeProfile)
                      .length
                  }
                </span>
              )}
            </NavItem>
          ))}
        </nav>

        <div className="mt-5 min-h-0 flex-1 overflow-auto px-3 pb-3">
          {chatGroups.map((g) => (
            <div key={g.project} className="mb-3">
              <p className="px-2.5 pb-1 text-xs text-muted-foreground">
                {g.project}
              </p>
              {g.items.map((c) => (
                <button
                  key={c.id}
                  onClick={() => openChat(c.id)}
                  className={cn(
                    "flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-left text-sm text-foreground/80 hover:bg-foreground/5 hover:text-foreground",
                    app.page === "chat" &&
                      activeChat === c.id &&
                      "bg-foreground/[0.07] text-foreground"
                  )}
                >
                  <span className="truncate">{c.title}</span>
                  {c.unread ? (
                    <span className="ml-auto size-1.5 shrink-0 rounded-full bg-glow shadow-[0_0_8px_var(--glow)]" />
                  ) : (
                    <span className="ml-auto shrink-0 text-[11px] text-muted-foreground">
                      {c.when}
                    </span>
                  )}
                </button>
              ))}
            </div>
          ))}
        </div>

        <div className="space-y-0.5 border-t px-3 py-2">
          <NavItem
            active={app.page === "connections"}
            onClick={() => app.go("connections")}
            icon={Plug}
          >
            Подключения
          </NavItem>
          <NavItem
            active={app.page === "settings"}
            onClick={() => app.go("settings")}
            icon={Settings}
          >
            Настройки
          </NavItem>
        </div>
        <ProfileSwitch />
      </aside>

      <main className="min-h-0 overflow-hidden">
        {app.page === "chat" && (
          <ChatPage
            key={activeChat}
            chatId={activeChat}
            bot={botList.find((b) => `bot:${b.id}` === activeChat)}
          />
        )}
        {app.page === "memory" && <MemoryPage openChat={openChat} />}
        {app.page === "people" && <PeoplePage />}
        {app.page === "persona" && <PersonaPage />}
        {app.page === "connections" && <ConnectionsPage />}
        {app.page === "settings" && <SettingsPage />}
      </main>

      <Palette openChat={openChat} bots={botList} />
      <NewBot
        open={creatingBot}
        onClose={() => setCreatingBot(false)}
        onCreate={(b) => {
          setBotList((l) => [...l, b])
          openChat(`bot:${b.id}`)
        }}
      />
      {!app.onboarded && <Onboarding />}
    </div>
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
      {active && (
        <span className="absolute top-1.5 bottom-1.5 left-0 w-[2px] rounded-full bg-glow shadow-[0_0_10px_var(--glow)]" />
      )}
      <Icon
        className={cn("size-4", active ? "text-glow" : "text-muted-foreground")}
      />
      {children}
    </button>
  )
}

/// Внизу панели: с кем Люмен сейчас говорит. Клик — переключить профиль.
function ProfileSwitch() {
  const app = useApp()
  const current = app.profiles.find((p) => p.id === app.activeProfile)
  const next = app.profiles.find((p) => p.id !== app.activeProfile)
  return (
    <button
      onClick={() => {
        if (!next) return
        app.setActiveProfile(next.id)
        toast(`Теперь Lumen говорит с: ${next.name}`, {
          description: "Его память и правила подставятся в следующий ответ.",
        })
      }}
      className="m-3 mt-0 flex items-center gap-2.5 rounded-xl border bg-card/40 px-2.5 py-2 text-left hover:bg-card"
      title="Переключить, с кем говорит Lumen"
    >
      <span className="flex size-7 items-center justify-center rounded-full bg-foreground/10 text-xs font-medium">
        {current?.name[0]}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm">{current?.name}</span>
        <span className="block truncate text-xs text-muted-foreground">
          говорит сейчас
        </span>
      </span>
      <UserRound className="size-4 text-muted-foreground" />
    </button>
  )
}

function Palette({
  openChat,
  bots,
}: {
  openChat: (id: string) => void
  bots: BotDef[]
}) {
  const app = useApp()
  const run = (fn: () => void) => {
    fn()
    app.setPaletteOpen(false)
  }
  return (
    <CommandDialog
      open={app.paletteOpen}
      onOpenChange={app.setPaletteOpen}
      title="Найти и сделать"
      description="Раздел, бот, чат, воспоминание или действие"
    >
      <Command>
        <CommandInput placeholder="Раздел, чат, воспоминание или действие…" />
        <CommandList>
          <CommandEmpty>Ничего не нашлось.</CommandEmpty>
          <CommandGroup heading="Разделы">
            {[
              ...sections,
              {
                id: "connections" as Page,
                name: "Подключения",
                icon: Plug,
                hint: "",
              },
              {
                id: "settings" as Page,
                name: "Настройки",
                icon: Settings,
                hint: "⌘,",
              },
            ].map((s) => (
              <CommandItem key={s.id} onSelect={() => run(() => app.go(s.id))}>
                <s.icon /> {s.name}
                {s.hint && <CommandShortcut>{s.hint}</CommandShortcut>}
              </CommandItem>
            ))}
          </CommandGroup>
          <CommandGroup heading="Боты">
            {bots.map((b) => (
              <CommandItem
                key={b.id}
                onSelect={() => run(() => openChat(`bot:${b.id}`))}
              >
                <Bot /> {b.name}
                <CommandShortcut>{b.project}</CommandShortcut>
              </CommandItem>
            ))}
          </CommandGroup>
          <CommandGroup heading="Чаты">
            {chatGroups
              .flatMap((g) => g.items)
              .map((c) => (
                <CommandItem
                  key={c.id}
                  onSelect={() => run(() => openChat(c.id))}
                >
                  <MessageSquare /> {c.title}
                  <CommandShortcut>{c.project}</CommandShortcut>
                </CommandItem>
              ))}
          </CommandGroup>
          <CommandGroup heading="Память">
            {app.memories.slice(0, 5).map((m) => (
              <CommandItem
                key={m.id}
                value={m.text}
                onSelect={() => run(() => app.go("memory"))}
              >
                <Brain /> <span className="truncate">{m.text}</span>
              </CommandItem>
            ))}
          </CommandGroup>
          <CommandGroup heading="Действия">
            <CommandItem
              onSelect={() =>
                run(() =>
                  app.setTheme(app.theme === "lumen" ? "mono" : "lumen")
                )
              }
            >
              {app.theme === "lumen" ? <Moon /> : <Sun />} Тема:{" "}
              {app.theme === "lumen" ? "Монохром" : "Люмен"}
            </CommandItem>
            <CommandItem onSelect={() => run(() => app.setOnboarded(false))}>
              <Sparkles /> Пройти знакомство заново
            </CommandItem>
          </CommandGroup>
        </CommandList>
      </Command>
    </CommandDialog>
  )
}

/// Новый бот: имя и задача. Чат у него будет один — навсегда.
function NewBot({
  open,
  onClose,
  onCreate,
}: {
  open: boolean
  onClose: () => void
  onCreate: (b: BotDef) => void
}) {
  const [name, setName] = useState("")
  const [task, setTask] = useState("")
  const [project, setProject] = useState("prog")
  const create = () => {
    if (!name.trim()) return
    onCreate({
      id: `b${Date.now()}`,
      name: name.trim(),
      task: task.trim() || "Своя задача",
      project,
      messages: 0,
      compactions: [],
    })
    setName("")
    setTask("")
    onClose()
  }
  const field =
    "h-9 w-full rounded-lg border bg-input/30 px-3 text-sm outline-none focus:border-glow/50"
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Bot className="size-4 text-glow" /> Новый бот
          </DialogTitle>
          <DialogDescription>
            Бот — это один постоянный чат под одну задачу. Новых чатов в нём не
            бывает: старое Lumen сжимает в пересказы, а важное кладёт в память.
          </DialogDescription>
        </DialogHeader>
        <input
          autoFocus
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Имя, например «Ревьюер»"
          className={field}
        />
        <textarea
          value={task}
          onChange={(e) => setTask(e.target.value)}
          placeholder="Задача: что он делает и как"
          rows={3}
          className="w-full resize-none rounded-lg border bg-input/30 px-3 py-2 text-sm outline-none focus:border-glow/50"
        />
        <select
          value={project}
          onChange={(e) => setProject(e.target.value)}
          className={field}
          aria-label="Проект"
        >
          {["prog", "lumen", "shelf", "island", "kandeev.com"].map((p) => (
            <option key={p}>{p}</option>
          ))}
        </select>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>
            Отмена
          </Button>
          <Button onClick={create} disabled={!name.trim()}>
            Создать бота
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

export default App
