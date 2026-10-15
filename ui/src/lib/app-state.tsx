import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react"

import { initialMemories, initialProfiles, type Memory, type Profile } from "@/lib/mock-data"

// Состояние макета в одном месте: страница, тема, память, профили, характер.
// Всё живёт в памяти вкладки; запоминаются только тема и «знакомство пройдено».

export type Page = "chat" | "memory" | "people" | "persona" | "connections" | "settings"
export type Theme = "lumen" | "mono"
export type OrbState = "idle" | "thinking" | "writing" | "remember" | "sleep"
export type Backend = "subscription" | "api" | "auto"

export type Persona = {
  name: string
  about: string
  warmth: "warm" | "plain" | "dry"
  length: "short" | "medium" | "long"
  language: "ru" | "match"
  emoji: boolean
  always: string[]
  never: string[]
}

export const defaultPersona: Persona = {
  name: "Lumen",
  about: "Спокойный помощник, который помнит тебя и твои проекты. Говорит прямо, без воды, и сам предлагает следующий шаг.",
  warmth: "warm",
  length: "short",
  language: "ru",
  emoji: false,
  always: ["Сначала короткий пересказ плана, потом просить OK", "Говорить, на что опирался из памяти"],
  never: ["Двигать кнопки без просьбы", "Пушить и выкатывать без OK"],
}

type State = {
  page: Page
  go: (p: Page) => void
  theme: Theme
  setTheme: (t: Theme) => void
  reducedMotion: boolean
  setReducedMotion: (v: boolean) => void
  onboarded: boolean
  setOnboarded: (v: boolean) => void
  memories: Memory[]
  setMemories: React.Dispatch<React.SetStateAction<Memory[]>>
  profiles: Profile[]
  setProfiles: React.Dispatch<React.SetStateAction<Profile[]>>
  activeProfile: string
  setActiveProfile: (id: string) => void
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
  const [page, setPage] = useState<Page>("chat")
  const [theme, setThemeState] = useState<Theme>(() => (read("lumen-theme") === "mono" ? "mono" : "lumen"))
  const [reducedMotion, setReducedMotion] = useState(false)
  const [onboarded, setOnboardedState] = useState(() => read("lumen-onboarded") === "1")
  const [memories, setMemories] = useState(initialMemories)
  const [profiles, setProfiles] = useState(initialProfiles)
  const [activeProfile, setActiveProfile] = useState("roma")
  const [persona, setPersona] = useState(defaultPersona)
  const [orb, setOrb] = useState<OrbState>("idle")
  const [backend, setBackend] = useState<Backend>("auto")
  const [paletteOpen, setPaletteOpen] = useState(false)
  const [contextOpen, setContextOpen] = useState(() => window.innerWidth >= 1280)
  const [focusMemories, setFocusMemories] = useState<string[]>([])

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
    setContextOpen(true)
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
      page,
      go: setPage,
      theme,
      setTheme,
      reducedMotion,
      setReducedMotion,
      onboarded,
      setOnboarded,
      memories,
      setMemories,
      profiles,
      setProfiles,
      activeProfile,
      setActiveProfile,
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
    }),
    [page, theme, setTheme, reducedMotion, onboarded, setOnboarded, memories, profiles, activeProfile, persona, orb, backend, paletteOpen, contextOpen, focusMemories, showMemories]
  )

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useApp() {
  const v = useContext(Ctx)
  if (!v) throw new Error("useApp вне AppStateProvider")
  return v
}
