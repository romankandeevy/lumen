import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react"

import { initialBots, initialMemories, initialPeople, type BotDef, type Memory, type Person } from "@/lib/mock-data"

// Состояние макета в одном месте: вкладка, открытое, тема, память, люди, боты, характер.
// Всё живёт в памяти вкладки; запоминаются только тема и «знакомство пройдено».

export type Tab = "chat" | "agent" | "bots"
export type Page = "thread" | "bots" | "bot" | "memory" | "people" | "persona" | "tools" | "settings"
export type Theme = "lumen" | "mono"
export type OrbState = "idle" | "thinking" | "writing" | "remember" | "sleep"
export type Backend = "subscription" | "api" | "auto"

export type Me = { name: string; call: string; address: "ty" | "vy" }

export type Persona = {
  name: string
  about: string
  warmth: "warm" | "plain" | "dry"
  length: "short" | "medium" | "long"
  language: "ru" | "match"
  emoji: boolean
  humor: "none" | "light" | "more"
  initiative: "ask" | "suggest" | "act"
  honesty: "plain" | "soft"
  reasoning: "result" | "brief" | "full"
  format: "prose" | "lists" | "mixed"
  nudges: boolean
  always: string[]
  never: string[]
  bannedWords: string[]
  voice: "calm" | "bright" | "low"
}

export const defaultPersona: Persona = {
  name: "Lumen",
  about: "Спокойный помощник, который помнит тебя и твои проекты. Говорит прямо, без воды, и сам предлагает следующий шаг.",
  warmth: "warm",
  length: "short",
  language: "ru",
  emoji: false,
  humor: "light",
  initiative: "suggest",
  honesty: "plain",
  reasoning: "brief",
  format: "prose",
  nudges: true,
  always: ["Сначала короткий пересказ плана, потом просить OK", "Говорить, на что опирался из памяти"],
  never: ["Двигать кнопки без просьбы", "Пушить и выкатывать без OK"],
  bannedWords: ["безусловно", "отличный вопрос"],
  voice: "calm",
}

/// Что сейчас открыто в основной области
export type Open = { page: Page; id?: string }

type State = {
  tab: Tab
  setTab: (t: Tab) => void
  open: Open
  go: (page: Page, id?: string) => void
  theme: Theme
  setTheme: (t: Theme) => void
  reducedMotion: boolean
  setReducedMotion: (v: boolean) => void
  onboarded: boolean
  setOnboarded: (v: boolean) => void
  me: Me
  setMe: React.Dispatch<React.SetStateAction<Me>>
  memories: Memory[]
  setMemories: React.Dispatch<React.SetStateAction<Memory[]>>
  people: Person[]
  setPeople: React.Dispatch<React.SetStateAction<Person[]>>
  bots: BotDef[]
  setBots: React.Dispatch<React.SetStateAction<BotDef[]>>
  persona: Persona
  setPersona: React.Dispatch<React.SetStateAction<Persona>>
  orb: OrbState
  setOrb: (s: OrbState) => void
  backend: Backend
  setBackend: (b: Backend) => void
  paletteOpen: boolean
  setPaletteOpen: (v: boolean) => void
  contextOpen: boolean
  setContextOpen: (v: boolean) => void
  focusMemories: string[]
  showMemories: (ids: string[]) => void
  voiceOpen: boolean
  setVoiceOpen: (v: boolean) => void
}

const Ctx = createContext<State | null>(null)

function read(key: string) {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}
function write(key: string, value: string) {
  try {
    localStorage.setItem(key, value)
  } catch {
    /* приватное окно — просто не запоминаем */
  }
}

export function AppStateProvider({ children }: { children: React.ReactNode }) {
  const [tab, setTabState] = useState<Tab>("chat")
  const [open, setOpen] = useState<Open>({ page: "thread", id: "lumen" })
  const [theme, setThemeState] = useState<Theme>(() => (read("lumen-theme") === "mono" ? "mono" : "lumen"))
  const [reducedMotion, setReducedMotion] = useState(false)
  const [onboarded, setOnboardedState] = useState(() => read("lumen-onboarded") === "1")
  const [me, setMe] = useState<Me>({ name: "Рома", call: "Рома", address: "ty" })
  const [memories, setMemories] = useState(initialMemories)
  const [people, setPeople] = useState(initialPeople)
  const [bots, setBots] = useState(initialBots)
  const [persona, setPersona] = useState(defaultPersona)
  const [orb, setOrb] = useState<OrbState>("idle")
  const [backend, setBackend] = useState<Backend>("auto")
  const [paletteOpen, setPaletteOpen] = useState(false)
  const [contextOpen, setContextOpen] = useState(() => window.innerWidth >= 1280)
  const [focusMemories, setFocusMemories] = useState<string[]>([])
  const [voiceOpen, setVoiceOpen] = useState(false)

  const setTheme = useCallback((t: Theme) => {
    write("lumen-theme", t)
    setThemeState(t)
  }, [])
  const setOnboarded = useCallback((v: boolean) => {
    write("lumen-onboarded", v ? "1" : "0")
    setOnboardedState(v)
  }, [])
  const showMemories = useCallback((ids: string[]) => {
    setFocusMemories(ids)
    if (ids.length) setContextOpen(window.innerWidth >= 1280)
  }, [])
  const go = useCallback((page: Page, id?: string) => setOpen({ page, id }), [])
  // вкладка сверху панели: при переключении открываем её главное
  const setTab = useCallback((t: Tab) => {
    setTabState(t)
    if (t === "chat") setOpen({ page: "thread", id: "lumen" })
    if (t === "agent") setOpen({ page: "thread", id: "shelf" })
    if (t === "bots") setOpen({ page: "bots" })
  }, [])

  useEffect(() => {
    const root = document.documentElement
    root.classList.add("dark")
    root.classList.toggle("theme-lumen", theme === "lumen")
    root.classList.toggle("theme-mono", theme === "mono")
    root.dataset.motion = reducedMotion ? "reduced" : "full"
  }, [theme, reducedMotion])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault()
        setPaletteOpen((o) => !o)
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [])

  const value = useMemo<State>(
    () => ({
      tab,
      setTab,
      open,
      go,
      theme,
      setTheme,
      reducedMotion,
      setReducedMotion,
      onboarded,
      setOnboarded,
      me,
      setMe,
      memories,
      setMemories,
      people,
      setPeople,
      bots,
      setBots,
      persona,
      setPersona,
      orb,
      setOrb,
      backend,
      setBackend,
      paletteOpen,
      setPaletteOpen,
      contextOpen,
      setContextOpen,
      focusMemories,
      showMemories,
      voiceOpen,
      setVoiceOpen,
    }),
    [tab, setTab, open, go, theme, setTheme, reducedMotion, onboarded, setOnboarded, me, memories, people, bots, persona, orb, backend, paletteOpen, contextOpen, focusMemories, showMemories, voiceOpen]
  )

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useApp() {
  const v = useContext(Ctx)
  if (!v) throw new Error("useApp вне AppStateProvider")
  return v
}
