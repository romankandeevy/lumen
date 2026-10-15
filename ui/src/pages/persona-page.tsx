import { Code2, RotateCcw } from "lucide-react"
import { useState } from "react"
import { toast } from "sonner"

import { LumenOrb } from "@/components/lumen-orb"
import { GroupTitle, Page, Segmented } from "@/components/page"
import { Button } from "@/components/ui/button"
import { Switch } from "@/components/ui/switch"
import { defaultPersona, useApp, type Persona } from "@/lib/app-state"
import { RuleList } from "@/pages/people-page"

// «Характер»: как отвечает Lumen. Слева настройки, справа живое превью того же вопроса,
// внизу — итоговые инструкции (SOUL.md), которые уходят модели.

const questions = ["Что поделаем сегодня?", "Почему падает Shelf?", "Напиши коммит для правки"]

export function PersonaPage() {
  const app = useApp()
  const p = app.persona
  const set = (patch: Partial<Persona>) => app.setPersona((x) => ({ ...x, ...patch }))
  const [q, setQ] = useState(questions[0])
  const [showSoul, setShowSoul] = useState(false)
  const who = app.profiles.find((x) => x.id === app.activeProfile)!

  return (
    <Page
      title="Характер"
      lead="Как Lumen думает вслух и отвечает. Меняй слева — справа сразу видно, как он ответит."
      actions={
        <>
          <Button variant="ghost" onClick={() => set(defaultPersona)}>
            <RotateCcw /> Сбросить
          </Button>
          <Button onClick={() => toast("Характер сохранён", { description: "Применится со следующего ответа во всех чатах." })}>Сохранить</Button>
        </>
      }
    >
      <div className="grid gap-8 xl:grid-cols-[minmax(0,1fr)_420px]">
        <div className="min-w-0 space-y-7">
          <div className="grid gap-6 md:grid-cols-[160px_minmax(0,1fr)]">
            <div>
              <p className="mb-2 text-xs text-muted-foreground">Имя</p>
              <input
                value={p.name}
                onChange={(e) => set({ name: e.target.value })}
                className="h-9 w-full rounded-lg border bg-input/30 px-3 text-sm outline-none focus:border-glow/50"
              />
            </div>
            <div>
              <p className="mb-2 text-xs text-muted-foreground">Кто он — своими словами</p>
              <textarea
                value={p.about}
                onChange={(e) => set({ about: e.target.value })}
                rows={3}
                className="w-full resize-none rounded-lg border bg-input/30 px-3 py-2 text-sm leading-relaxed outline-none focus:border-glow/50"
              />
            </div>
          </div>

          <div className="grid gap-x-8 gap-y-5 md:grid-cols-2">
            <Choice label="Тон">
              <Segmented
                value={p.warmth}
                onChange={(v) => set({ warmth: v })}
                options={[
                  { id: "warm", name: "Тёплый" },
                  { id: "plain", name: "Ровный" },
                  { id: "dry", name: "Сухой" },
                ]}
              />
            </Choice>
            <Choice label="Длина ответов">
              <Segmented
                value={p.length}
                onChange={(v) => set({ length: v })}
                options={[
                  { id: "short", name: "Коротко" },
                  { id: "medium", name: "Средне" },
                  { id: "long", name: "Подробно" },
                ]}
              />
            </Choice>
            <Choice label="Язык">
              <Segmented
                value={p.language}
                onChange={(v) => set({ language: v })}
                options={[
                  { id: "ru", name: "Всегда русский" },
                  { id: "match", name: "Как собеседник" },
                ]}
              />
            </Choice>
            <Choice label="Эмодзи">
              <label className="flex h-8 items-center gap-2.5 text-sm">
                <Switch checked={p.emoji} onCheckedChange={(v) => set({ emoji: v })} /> {p.emoji ? "Иногда можно" : "Без эмодзи"}
              </label>
            </Choice>
          </div>

          <div className="grid gap-6 md:grid-cols-2">
            <RuleList title="Всегда" items={p.always} onChange={(always) => set({ always })} placeholder="Например: называть файл и строку" />
            <RuleList title="Никогда" items={p.never} onChange={(never) => set({ never })} placeholder="Например: извиняться" negative />
          </div>

          <div>
            <button onClick={() => setShowSoul((s) => !s)} className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground">
              <Code2 className="size-4" /> {showSoul ? "Скрыть" : "Показать"} инструкции, которые получает модель
            </button>
            {showSoul && (
              <pre className="mt-3 max-h-96 overflow-auto rounded-xl border bg-background/60 p-4 font-mono text-xs leading-relaxed whitespace-pre-wrap text-foreground/85">
                {soul(p, who.call || who.name, who.address)}
              </pre>
            )}
          </div>
        </div>

        {/* живое превью */}
        <div className="xl:sticky xl:top-0 xl:self-start">
          <GroupTitle aside={`отвечает: ${who.name}`}>Как он ответит</GroupTitle>
          <div className="rounded-2xl border bg-card/50 p-4">
            <div className="flex flex-wrap gap-1.5">
              {questions.map((x) => (
                <button
                  key={x}
                  onClick={() => setQ(x)}
                  className={
                    "rounded-full border px-2.5 py-1 text-xs transition-colors " +
                    (x === q ? "border-glow/40 bg-glow/10" : "text-muted-foreground hover:text-foreground")
                  }
                >
                  {x}
                </button>
              ))}
            </div>
            <div className="mt-5 flex justify-end">
              <div className="max-w-[85%] rounded-2xl rounded-br-md bg-secondary px-3.5 py-2 text-sm">{q}</div>
            </div>
            <div className="mt-4 flex gap-3">
              <LumenOrb size={20} className="mt-0.5" />
              <div key={JSON.stringify(p) + q + who.id} className="min-w-0 animate-in space-y-2 text-sm leading-relaxed duration-500 fade-in">
                {preview(p, q, who.call || who.name, who.address, who.id === "roma").map((line, i) => (
                  <p key={i}>{line}</p>
                ))}
              </div>
            </div>
          </div>
          <p className="mt-3 text-xs text-muted-foreground">Превью собрано по шаблону. В приложении его напишет сама модель с этими инструкциями.</p>
        </div>
      </div>
    </Page>
  )
}

function Choice({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="mb-2 text-xs text-muted-foreground">{label}</p>
      {children}
    </div>
  )
}

/// Шаблонное превью ответа — чтобы было видно, что меняет каждая настройка
function preview(p: Persona, q: string, name: string, address: "ty" | "vy", owner: boolean): string[] {
  const vy = address === "vy"
  const hi = { warm: vy ? `${name}, добрый вечер!` : `${name}, привет!`, plain: "", dry: "" }[p.warmth]
  const e = p.emoji ? " ✨" : ""
  const recap = p.always.some((r) => /пересказ/i.test(r))
  const lines: string[] = []

  // чужому собеседнику — только его темы: проекты Ромы закрыты правилом «нельзя» из профиля
  if (!owner) {
    if (hi) lines.push(hi + e)
    if (q === questions[0]) {
      lines.push("На сайте всё работает. Могу подготовить новый текст для блога.")
      if (p.length !== "short") lines.push("Без цен и цифр — как вы просили.")
      lines.push("Начнём?")
    } else lines.push(vy ? "Это проект Ромы — о нём рассказать не могу. Спросите его самого." : "Это проект Ромы — о нём рассказать не могу.")
    return lines
  }

  if (q === questions[0]) {
    if (hi) lines.push(hi + e)
    lines.push("Свежее всего Lumen и Пульт. Могу продолжить экран памяти или разобрать падение Shelf.")
    if (p.length !== "short") lines.push("У lid-plane два коммита не отправлены, у soundcore восемь файлов не закоммичено — это стоит не забыть.")
    if (p.length === "long") lines.push("Если брать Lumen: соберу экран памяти, покажу скриншот и только потом подключу настоящую модель.")
    if (recap) lines.push(vy ? "План: сначала коротко расскажу, что сделаю, потом жду вашего OK." : "Сначала коротко расскажу план, потом жду твоего OK.")
    lines.push(p.warmth === "dry" ? "Что берём?" : vy ? "Что выберете?" : "Что берём?")
  } else if (q === questions[1]) {
    if (p.warmth === "warm") lines.push((vy ? "Сейчас посмотрю." : "Сейчас гляну.") + e)
    lines.push("Падает в ShelfStorage.remove(at:): при двойном щелчке индекс берётся из старого списка.")
    if (p.length !== "short") lines.push("Чинится проверкой индекса; заодно стоит отключать кнопку на время удаления.")
    if (p.length === "long") lines.push("Все три отчёта от 9 октября одинаковые, так что причина одна.")
    lines.push(vy ? "Исправить?" : "Чинить?")
  } else {
    lines.push("Shelf: не падать при двойном удалении с полки")
    if (p.length !== "short") lines.push("Проверяю индекс перед удалением и отключаю кнопку, пока удаление идёт.")
    if (p.warmth === "warm" && p.length === "long") lines.push((vy ? "Если удобно, закоммичу сам." : "Если ок — закоммичу сам.") + e)
  }
  return lines
}

/// Итоговые инструкции — то, что Lumen отправит модели как характер (аналог SOUL.md в Hermes)
function soul(p: Persona, name: string, address: "ty" | "vy") {
  return `# ${p.name} — характер

${p.about}

## Как говорить
- Тон: ${{ warm: "тёплый, по-дружески", plain: "ровный, спокойный", dry: "сухой, только суть" }[p.warmth]}.
- Длина: ${{ short: "коротко, 2–4 предложения", medium: "средне, абзац-два", long: "подробно, с объяснением" }[p.length]}.
- Язык: ${p.language === "ru" ? "всегда русский" : "язык собеседника"}. Простые слова, без жаргона.
- Эмодзи: ${p.emoji ? "иногда, к месту" : "не использовать"}.

## С кем ты говоришь
- Собеседник: ${name}, на «${address === "ty" ? "ты" : "вы"}».
- Его профиль и память подставлены ниже; чужую память не упоминай.

## Всегда
${p.always.map((r) => `- ${r}`).join("\n") || "- —"}

## Никогда
${p.never.map((r) => `- ${r}`).join("\n") || "- —"}

## Память
- В конце ответа, если узнал что-то важное и надолго, — сохрани факт и скажи «Запомнил: …».
- Если опирался на память, перечисли, на что.`
}
