import { ArrowUp, Check, ChevronDown, Clock, Folder, FolderOpen, GitBranch, Laptop, Plus, Sparkles } from "lucide-react"
import { useState } from "react"

import { LumenOrb } from "@/components/lumen-orb"
import { EffortPicker, ModelPicker } from "@/components/pickers"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Textarea } from "@/components/ui/textarea"
import { projects, sessions } from "@/lib/mock-data"
import { cn } from "@/lib/utils"

// Новая задача агента — три варианта на выбор (переключатель сверху есть только в макете).
// A — как в Claude Code: большое поле по центру, папка внутри поля, ниже недавние задачи этой папки.
// B — проекты карточками: ветка, изменённые файлы, последняя задача; поле внизу.
// C — минимум: поле по центру и три подсказки, придуманные по проекту.

export type AgentVariant = "a" | "b" | "c"

type Props = {
  variant: AgentVariant
  project: string
  setProject: (v: string) => void
  model: string
  setModel: (v: string) => void
  effort: string
  setEffort: (v: string) => void
  draft: string
  setDraft: (v: string) => void
  send: () => void
}

// что Lumen знает о папках: ветка git и сколько файлов сейчас изменено (в приложении — из git)
const folderInfo: Record<string, { branch: string; changed: number; last: string; when: string }> = {
  lumen: { branch: "main", changed: 0, last: "Агент: план сбоку и «что дальше»", when: "сегодня" },
  shelf: { branch: "main", changed: 2, last: "Почему падает Shelf?", when: "12 мин" },
  island: { branch: "notch-anim", changed: 5, last: "Анимация чёлки проседает", when: "вчера" },
  "prog-dashboard": { branch: "main", changed: 0, last: "Ревью Пульта перед релизом", when: "вчера" },
  "flow-local": { branch: "main", changed: 1, last: "Двухпоточное распознавание", when: "11 окт" },
  "kandeev.com": { branch: "preview", changed: 0, last: "Ночной обход сайтов", when: "03:00" },
  notes: { branch: "main", changed: 0, last: "PWA с экрана «Домой»", when: "9 окт" },
}

// подсказки, которые Lumen придумывает по проекту (в приложении — Haiku по истории папки)
const ideasFor: Record<string, string[]> = {
  lumen: ["Доделай граф памяти по макету", "Прогони живые тесты и разбери падения", "Подготовь релиз 1.0"],
  shelf: ["Проверь фикс двойного щелчка", "Собери и запусти Shelf", "Найди, где ещё может упасть"],
  island: ["Почини просадку анимации чёлки", "Замерь, сколько кадров теряется", "Сделай ревью ветки notch-anim"],
}
const defaultIdeas = ["Найди и почини падение", "Собери и проверь сборку", "Объясни, как устроен проект"]

export function AgentNew(p: Props) {
  if (p.variant === "b") return <VariantB {...p} />
  if (p.variant === "c") return <VariantC {...p} />
  return <VariantA {...p} />
}

// ── A: как в Claude Code ──

function VariantA(p: Props) {
  const recent = sessions.filter((s) => s.project === p.project).slice(0, 3)
  const info = folderInfo[p.project]
  return (
    <div className="flex h-full flex-col items-center justify-center px-6 pb-16">
      <div className="w-full max-w-[44rem]">
        <div className="mb-6 flex items-center gap-3">
          <LumenOrb size={28} />
          <h2 className="text-2xl font-semibold tracking-[-0.02em]">
            Что сделаем в <span className="text-glow">{p.project}</span>?
          </h2>
        </div>
        <BigComposer {...p} />
        {info && (
          <p className="mt-3 flex items-center gap-3 px-1 text-xs text-muted-foreground">
            <span className="flex items-center gap-1">
              <GitBranch className="size-3.5" /> {info.branch}
            </span>
            {info.changed > 0 ? <span className="text-glow">{info.changed} изменённых файла не закоммичены</span> : <span>всё закоммичено</span>}
            <span className="ml-auto flex items-center gap-1">
              <Laptop className="size-3.5" /> этот Мак · push только с твоего OK
            </span>
          </p>
        )}
        {recent.length > 0 && (
          <div className="mt-10">
            <p className="mb-2 px-1 text-xs text-muted-foreground">Недавно в этой папке</p>
            <div className="divide-y rounded-xl border bg-card/40">
              {recent.map((s) => (
                <button key={s.id} className="flex w-full items-center gap-3 px-4 py-2.5 text-left text-sm hover:bg-foreground/[0.03]">
                  <Clock className="size-3.5 text-muted-foreground" />
                  <span className="min-w-0 flex-1 truncate">{s.title}</span>
                  {s.state === "waiting" && <span className="text-xs text-glow">ждёт тебя</span>}
                  <span className="text-xs text-muted-foreground">{s.when}</span>
                </button>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

// ── B: проекты карточками ──

function VariantB(p: Props) {
  return (
    <div className="mx-auto flex h-full max-w-[52rem] flex-col justify-center px-6">
      <h2 className="text-2xl font-semibold tracking-[-0.02em]">Над чем работаем?</h2>
      <p className="mt-1.5 text-sm text-muted-foreground">Выбери проект — агент откроет его папку. Push и выкатка — только с твоего OK.</p>
      <div className="mt-6 grid grid-cols-2 gap-3 lg:grid-cols-3">
        {projects.slice(0, 5).map((x) => {
          const info = folderInfo[x]
          const active = x === p.project
          return (
            <button
              key={x}
              onClick={() => p.setProject(x)}
              className={cn(
                "rounded-2xl border p-4 text-left transition-colors",
                active ? "border-glow/50 bg-glow/[0.05] shadow-[0_0_28px_-10px_var(--glow-soft)]" : "bg-card/40 hover:bg-card"
              )}
            >
              <div className="flex items-center gap-2">
                <Folder className={cn("size-4", active ? "text-glow" : "text-muted-foreground")} />
                <span className="truncate text-sm font-medium">{x}</span>
                {active && <Check className="ml-auto size-4 text-glow" />}
              </div>
              {info && (
                <>
                  <p className="mt-3 truncate text-xs text-foreground/80">{info.last}</p>
                  <p className="mt-1.5 flex items-center gap-2 text-[11px] text-muted-foreground">
                    <span className="flex items-center gap-1">
                      <GitBranch className="size-3" /> {info.branch}
                    </span>
                    {info.changed > 0 && <span className="text-glow">±{info.changed}</span>}
                    <span className="ml-auto">{info.when}</span>
                  </p>
                </>
              )}
            </button>
          )
        })}
        <button className="flex items-center justify-center gap-2 rounded-2xl border border-dashed p-4 text-sm text-muted-foreground hover:text-foreground">
          <Plus className="size-4" /> Другая папка…
        </button>
      </div>
    </div>
  )
}

// ── C: минимум ──

function VariantC(p: Props) {
  const ideas = ideasFor[p.project] ?? defaultIdeas
  return (
    <div className="flex h-full flex-col items-center justify-center px-6 pb-16">
      <div className="w-full max-w-[40rem]">
        <BigComposer {...p} placeholder={`Что сделать в ${p.project}?`} />
        <div className="mt-4 flex flex-wrap justify-center gap-2">
          {ideas.map((i) => (
            <button
              key={i}
              onClick={() => p.setDraft(i)}
              className="flex items-center gap-1.5 rounded-full border bg-card/50 px-3.5 py-1.5 text-sm hover:border-glow/40 hover:bg-card"
            >
              <Sparkles className="size-3.5 text-glow" /> {i}
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}

// ── общее: большое поле с папкой, моделью и «сколько думать» внутри ──

function BigComposer(p: Props & { placeholder?: string }) {
  return (
    <div className="rounded-2xl border bg-card/60 p-4">
      <Textarea
        autoFocus
        value={p.draft}
        onChange={(e) => p.setDraft(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter" && !e.shiftKey) {
            e.preventDefault()
            p.send()
          }
        }}
        placeholder={p.placeholder ?? "Опиши задачу: что сделать, починить или проверить"}
        className="min-h-24 resize-none border-0 bg-transparent p-0 text-[0.9375rem] shadow-none focus-visible:ring-0 dark:bg-transparent"
      />
      <div className="mt-3 flex items-center gap-1">
        <FolderChip project={p.project} setProject={p.setProject} />
        <div className="ml-auto flex items-center gap-0.5">
          <ModelPicker value={p.model} onChange={p.setModel} />
          <EffortPicker value={p.effort} onChange={p.setEffort} />
          <button
            onClick={p.send}
            aria-label="Начать"
            className="ml-1 flex size-8 items-center justify-center rounded-full bg-glow text-black shadow-[0_0_16px_var(--glow-soft)] hover:bg-glow/85"
          >
            <ArrowUp className="size-4" />
          </button>
        </div>
      </div>
    </div>
  )
}

function FolderChip({ project, setProject }: { project: string; setProject: (v: string) => void }) {
  const [open, setOpen] = useState(false)
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button className="flex h-8 items-center gap-1.5 rounded-lg border bg-background/40 px-2.5 text-sm hover:bg-foreground/5">
          <FolderOpen className="size-4 text-glow" /> {project}
          <ChevronDown className="size-3.5 opacity-50" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" side="bottom" className="w-64 p-1.5">
        <p className="px-2 pt-1 pb-2 text-xs text-muted-foreground">Папка проекта</p>
        {projects.map((x) => (
          <button
            key={x}
            onClick={() => (setProject(x), setOpen(false))}
            className={cn("flex w-full items-center gap-2.5 rounded-lg px-2 py-1.5 text-left text-sm hover:bg-muted/60", x === project && "bg-muted")}
          >
            <Folder className="size-4 text-muted-foreground" /> {x}
            {x === project && <Check className="ml-auto size-4 text-glow" />}
          </button>
        ))}
      </PopoverContent>
    </Popover>
  )
}

/// Переключатель вариантов — только в макете
export function VariantSwitch({ value, onChange }: { value: AgentVariant; onChange: (v: AgentVariant) => void }) {
  return (
    <div className="absolute top-16 left-1/2 z-10 flex -translate-x-1/2 items-center gap-1 rounded-full border bg-popover/90 p-1 text-xs shadow-lg backdrop-blur">
      <span className="px-2 text-muted-foreground">Вариант</span>
      {(
        [
          ["a", "A · как Claude Code"],
          ["b", "B · карточки"],
          ["c", "C · минимум"],
        ] as [AgentVariant, string][]
      ).map(([id, name]) => (
        <button
          key={id}
          onClick={() => onChange(id)}
          className={cn("rounded-full px-3 py-1 whitespace-nowrap", value === id ? "bg-glow text-black" : "text-muted-foreground hover:text-foreground")}
        >
          {name}
        </button>
      ))}
    </div>
  )
}
