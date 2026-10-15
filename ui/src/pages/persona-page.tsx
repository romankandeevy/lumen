import { AudioLines, Code2, Plus, RotateCcw, X } from "lucide-react"
import { Fragment, useState } from "react"
import { toast } from "sonner"

import { LumenOrb } from "@/components/lumen-orb"
import { GroupTitle, Page, Segmented } from "@/components/page"
import { Button } from "@/components/ui/button"
import { Switch } from "@/components/ui/switch"
import { defaultPersona, useApp, type Me, type Persona } from "@/lib/app-state"
import { cn } from "@/lib/utils"
import { RuleList } from "@/pages/people-page"

// «Характер»: как отвечает Lumen. Слева настройки по секциям, справа живое превью того же вопроса,
// внизу — итоговые инструкции (SOUL.md), которые уходят модели. Собеседник всегда Рома.

const questions = ["Что поделаем сегодня?", "Почему падает Shelf?", "Напиши коммит для правки"]

const voices: { id: Persona["voice"]; name: string; note: string }[] = [
  { id: "calm", name: "Спокойный", note: "ровный, неторопливый" },
  { id: "bright", name: "Яркий", note: "живой, с интонацией" },
  { id: "low", name: "Низкий", note: "глубокий, тихий" },
]

export function PersonaPage() {
  const app = useApp()
  const p = app.persona
  const me = app.me
  const set = (patch: Partial<Persona>) => app.setPersona((x) => ({ ...x, ...patch }))
  const [q, setQ] = useState(questions[0])
  const [showSoul, setShowSoul] = useState(false)

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
        <div className="min-w-0 space-y-9">
          <Section title="Кто он">
            <div className="grid gap-6 md:grid-cols-[160px_minmax(0,1fr)]">
              <Choice label="Имя">
                <input
                  value={p.name}
                  onChange={(e) => set({ name: e.target.value })}
                  className="h-9 w-full rounded-lg border bg-input/30 px-3 text-sm outline-none focus:border-glow/50"
                />
              </Choice>
              <Choice label="Кто он — своими словами">
                <textarea
                  value={p.about}
                  onChange={(e) => set({ about: e.target.value })}
                  rows={3}
                  className="w-full resize-none rounded-lg border bg-input/30 px-3 py-2 text-sm leading-relaxed outline-none focus:border-glow/50"
                />
              </Choice>
            </div>
          </Section>

          <Section title="Как говорит">
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
                    { id: "match", name: "Как пишешь ты" },
                  ]}
                />
              </Choice>
              <Choice label="Юмор">
                <Segmented
                  value={p.humor}
                  onChange={(v) => set({ humor: v })}
                  options={[
                    { id: "none", name: "Без шуток" },
                    { id: "light", name: "Чуть-чуть" },
                    { id: "more", name: "Почаще" },
                  ]}
                />
              </Choice>
              <Choice label="Оформление">
                <Segmented
                  value={p.format}
                  onChange={(v) => set({ format: v })}
                  options={[
                    { id: "prose", name: "Текстом" },
                    { id: "lists", name: "Списками" },
                    { id: "mixed", name: "Смешанно" },
                  ]}
                />
              </Choice>
              <Choice label="Эмодзи">
                <label className="flex h-8 items-center gap-2.5 text-sm">
                  <Switch checked={p.emoji} onCheckedChange={(v) => set({ emoji: v })} /> {p.emoji ? "Иногда можно" : "Без эмодзи"}
                </label>
              </Choice>
            </div>
            <div className="mt-6">
              <BannedWords items={p.bannedWords} onChange={(bannedWords) => set({ bannedWords })} />
            </div>
          </Section>

          <Section title="Как думает и действует">
            <div className="grid gap-x-8 gap-y-5 md:grid-cols-2">
              <Choice label="Самостоятельность" hint={{ ask: "Всё спрашивает перед делом", suggest: "Предлагает шаг и ждёт OK", act: "Делает сам, потом рассказывает" }[p.initiative]}>
                <Segmented
                  value={p.initiative}
                  onChange={(v) => set({ initiative: v })}
                  options={[
                    { id: "ask", name: "Спрашивать" },
                    { id: "suggest", name: "Предлагать" },
                    { id: "act", name: "Делать сам" },
                  ]}
                />
              </Choice>
              <Choice label="Честность" hint={p.honesty === "plain" ? "Говорит как есть, даже если неприятно" : "Смягчает, но суть не прячет"}>
                <Segmented
                  value={p.honesty}
                  onChange={(v) => set({ honesty: v })}
                  options={[
                    { id: "plain", name: "Прямо" },
                    { id: "soft", name: "Мягко" },
                  ]}
                />
              </Choice>
              <Choice label="Рассуждения" hint={{ result: "Только ответ", brief: "Ответ и пара слов почему", full: "Показывает ход мыслей" }[p.reasoning]}>
                <Segmented
                  value={p.reasoning}
                  onChange={(v) => set({ reasoning: v })}
                  options={[
                    { id: "result", name: "Только итог" },
                    { id: "brief", name: "Коротко" },
                    { id: "full", name: "Подробно" },
                  ]}
                />
              </Choice>
              <Choice label="Подсказывать о висящем">
                <label className="flex h-8 items-center gap-2.5 text-sm">
                  <Switch checked={p.nudges} onCheckedChange={(v) => set({ nudges: v })} />
                  {p.nudges ? "Напоминает о неотправленном и забытом" : "Только по делу"}
                </label>
              </Choice>
            </div>
          </Section>

          <Section title="Голос" note="Для голосового режима">
            <div className="grid gap-2 sm:grid-cols-3">
              {voices.map((v) => (
                <button
                  key={v.id}
                  onClick={() => set({ voice: v.id })}
                  aria-pressed={p.voice === v.id}
                  className={cn(
                    "flex items-center gap-3 rounded-xl border px-3 py-2.5 text-left transition-colors",
                    p.voice === v.id ? "border-glow/40 bg-glow/10" : "bg-card/40 hover:bg-card"
                  )}
                >
                  <AudioLines className={cn("size-4 shrink-0", p.voice === v.id ? "text-glow" : "text-muted-foreground")} />
                  <span className="min-w-0">
                    <span className="block text-sm">{v.name}</span>
                    <span className="block truncate text-xs text-muted-foreground">{v.note}</span>
                  </span>
                </button>
              ))}
            </div>
            <Button
              variant="ghost"
              size="sm"
              className="mt-2"
              onClick={() => toast(`Голос: ${voices.find((v) => v.id === p.voice)?.name}`, { description: `«${me.call}, привет! Я тут, если что».` })}
            >
              Послушать
            </Button>
          </Section>

          <Section title="Правила">
            <div className="grid gap-6 md:grid-cols-2">
              <RuleList title="Всегда" items={p.always} onChange={(always) => set({ always })} placeholder="Например: называть файл и строку" />
              <RuleList title="Никогда" items={p.never} onChange={(never) => set({ never })} placeholder="Например: извиняться" negative />
            </div>
          </Section>

          <div>
            <button onClick={() => setShowSoul((s) => !s)} className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground">
              <Code2 className="size-4" /> {showSoul ? "Скрыть" : "Показать"} инструкции, которые получает модель
            </button>
            {showSoul && (
              <pre className="mt-3 max-h-96 overflow-auto rounded-xl border bg-background/60 p-4 font-mono text-xs leading-relaxed whitespace-pre-wrap text-foreground/85">
                {soul(p, me)}
              </pre>
            )}
          </div>
        </div>

        {/* живое превью */}
        <div className="xl:sticky xl:top-0 xl:self-start">
          <GroupTitle aside={`говорит с: ${me.name}`}>Как он ответит</GroupTitle>
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
              <div key={JSON.stringify(p) + q} className="min-w-0 animate-in space-y-2 text-sm leading-relaxed duration-500 fade-in">
                <Answer lines={preview(p, q, me)} />
              </div>
            </div>
          </div>
          <p className="mt-3 text-xs text-muted-foreground">Превью собрано по шаблону. В приложении его напишет сама модель с этими инструкциями.</p>
        </div>
      </div>
    </Page>
  )
}

function Section({ title, note, children }: { title: string; note?: string; children: React.ReactNode }) {
  return (
    <section className="border-t pt-5 first:border-t-0 first:pt-0">
      <div className="mb-4 flex items-baseline gap-2">
        <h2 className="text-base font-semibold tracking-[-0.01em]">{title}</h2>
        {note && <span className="text-xs text-muted-foreground">{note}</span>}
      </div>
      {children}
    </section>
  )
}

function Choice({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="mb-2 text-xs text-muted-foreground">{label}</p>
      {children}
      {hint && <p className="mt-1.5 text-xs text-muted-foreground/80">{hint}</p>}
    </div>
  )
}

function BannedWords({ items, onChange }: { items: string[]; onChange: (v: string[]) => void }) {
  const [draft, setDraft] = useState("")
  const add = () => {
    const w = draft.trim().toLowerCase()
    if (!w || items.includes(w)) return setDraft("")
    onChange([...items, w])
    setDraft("")
  }
  return (
    <div>
      <p className="mb-2 text-xs text-muted-foreground">Запрещённые слова — он их не скажет</p>
      <div className="flex flex-wrap items-center gap-1.5">
        {items.map((w) => (
          <span key={w} className="flex items-center gap-1 rounded-full border bg-foreground/[0.04] py-0.5 pr-1 pl-2.5 text-xs">
            {w}
            <button onClick={() => onChange(items.filter((x) => x !== w))} aria-label={`Убрать «${w}»`} className="rounded-full p-0.5 text-muted-foreground hover:text-foreground">
              <X className="size-3" />
            </button>
          </span>
        ))}
        <span className="flex items-center gap-1 rounded-full border border-dashed py-0.5 pr-2.5 pl-2 text-xs focus-within:border-glow/40">
          <Plus className="size-3 text-muted-foreground" />
          <input
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && add()}
            onBlur={add}
            placeholder="добавить слово"
            className="w-28 bg-transparent outline-none placeholder:text-muted-foreground"
          />
        </span>
      </div>
    </div>
  )
}

// ── превью ──

type Line = { t: "p" | "li" | "think"; text: string }

function Answer({ lines }: { lines: Line[] }) {
  // подряд идущие пункты собираем в один список
  const blocks: (Line | Line[])[] = []
  for (const l of lines) {
    const last = blocks[blocks.length - 1]
    if (l.t === "li" && Array.isArray(last)) last.push(l)
    else blocks.push(l.t === "li" ? [l] : l)
  }
  return (
    <>
      {blocks.map((b, i) =>
        Array.isArray(b) ? (
          <ul key={i} className="space-y-1">
            {b.map((l, j) => (
              <li key={j} className="flex gap-2">
                <span className="mt-[0.6em] size-1 shrink-0 rounded-full bg-glow/80" />
                <span>{l.text}</span>
              </li>
            ))}
          </ul>
        ) : b.t === "think" ? (
          <p key={i} className="border-l-2 border-glow/30 pl-2.5 text-xs leading-relaxed text-muted-foreground italic">
            {b.text}
          </p>
        ) : (
          <Fragment key={i}>
            <p>{b.text}</p>
          </Fragment>
        )
      )}
    </>
  )
}

/// Шаблонное превью ответа — чтобы было видно, что меняет каждая настройка
function preview(p: Persona, q: string, me: Me): Line[] {
  const vy = me.address === "vy"
  const name = me.call || me.name
  const e = p.emoji ? " ✨" : ""
  const banned = (w: string) => p.bannedWords.some((b) => b.toLowerCase() === w)
  const recap = p.always.some((r) => /пересказ/i.test(r))
  const out: Line[] = []
  const say = (text: string) => out.push({ t: "p", text })

  // главное — по пунктам; как его подать, решает «Оформление»
  const points: string[] = []
  let why: string
  let think = ""
  let joke: string
  let nudge = ""
  let ending: string

  if (q === questions[0]) {
    const hi = { warm: vy ? `${name}, добрый вечер!` : `${name}, привет!`, plain: "", dry: "" }[p.warmth]
    if (hi) say(hi + e)
    think = "Смотрю status.sh и ПЛАН.md: свежее всего Lumen (сегодня) и Пульт (вчера). Shelf ждёт ответа в агентной сессии 12 минут — это самое срочное."
    points.push("Lumen: доделать экран памяти")
    points.push("Shelf: разобрать падение — сессия ждёт ответа")
    if (p.length !== "short") points.push("kandeev.com: новый текст для блога")
    if (p.length === "long") points.push("Пульт: три замечания после ревью")
    why = "Shelf первым, потому что там ждут ответа."
    joke = p.humor === "more" ? "Остров, к счастью, сегодня не проседает — даже скучно." : "Остров пока ведёт себя прилично."
    nudge = "Кстати: у lid-plane два коммита так и не отправлены."
    ending = {
      ask: vy ? "С чего начнём?" : "Что берём?",
      suggest: vy ? "Предлагаю начать с Shelf. Согласны?" : "Предлагаю начать с Shelf. Ок?",
      act: "Начинаю с Shelf — если хочешь другое, останови.",
    }[p.initiative]
    if (recap && p.initiative !== "act") ending = (vy ? "Сначала коротко расскажу план, потом жду вашего OK. " : "Сначала коротко расскажу план, потом жду твоего OK. ") + ending
  } else if (q === questions[1]) {
    if (p.warmth === "warm") say((banned("безусловно") ? "Сейчас гляну." : "Безусловно, сейчас гляну.") + e)
    think = "Открыл три отчёта .ips от 9 октября — стек одинаковый, падает в ShelfStorage.remove(at:). Значит, причина одна."
    points.push(
      p.honesty === "plain"
        ? "Причина — моя же правка от 9 октября: индекс берётся из старого списка."
        : "Похоже, в прошлой правке закрался недочёт, такое бывает: индекс берётся из старого списка."
    )
    if (p.length !== "short") points.push("Чинится проверкой индекса перед удалением")
    if (p.length !== "short") points.push("Заодно стоит отключать кнопку, пока идёт удаление")
    if (p.length === "long") points.push("Все три отчёта одинаковые — других причин не видно")
    why = "Срабатывает только при двойном щелчке — поэтому не ловилось в тестах."
    joke = p.humor === "more" ? "Двойной щелчок — враг полки номер один. Второй — понедельник." : "Двойной щелчок опять за своё."
    nudge = "Ещё в Shelf восемь файлов не закоммичено — заодно разберёмся?"
    ending = { ask: vy ? "Исправить?" : "Чинить?", suggest: "Предлагаю поправить и прогнать тест. Ок?", act: "Уже правлю — пришлю, когда тест пройдёт." }[p.initiative]
  } else {
    say("Shelf: не падать при двойном удалении с полки")
    if (p.length !== "short") points.push("Проверяю индекс перед удалением")
    if (p.length !== "short") points.push("Отключаю кнопку, пока удаление идёт")
    why = "Сообщение по-русски, как в остальных коммитах Shelf."
    joke = p.humor === "more" ? "Полка больше не падает в обморок от двойного щелчка." : ""
    ending = { ask: "Закоммитить?", suggest: vy ? "Если удобно, закоммичу." : "Если ок — закоммичу.", act: "Закоммитил." + e }[p.initiative]
  }

  if (p.reasoning === "full") out.push({ t: "think", text: think })

  if (p.format === "prose") {
    if (points.length) say(points.map((x) => (x.endsWith(".") ? x : x + ".")).join(" "))
  } else if (p.format === "lists") {
    points.forEach((x) => out.push({ t: "li", text: x }))
  } else {
    if (points[0]) say(points[0] + (points[0].endsWith(".") ? "" : "."))
    points.slice(1).forEach((x) => out.push({ t: "li", text: x }))
  }

  if (p.reasoning === "brief" && why) say(why)
  if (p.humor !== "none" && joke) say(joke + (p.humor === "more" && p.emoji ? " 😄" : ""))
  if (p.nudges && nudge) say(nudge)
  if (ending) say(ending)
  return out
}

/// Итоговые инструкции — то, что Lumen отправит модели как характер (аналог SOUL.md в Hermes)
function soul(p: Persona, me: Me) {
  return `# ${p.name} — характер

${p.about}

## С кем ты говоришь
- Всегда с ${me.name}. Обращайся «${me.call || me.name}», на «${me.address === "ty" ? "ты" : "вы"}».
- О других людях знаешь из анкет; пишешь им только по просьбе ${me.name}.

## Как говорить
- Тон: ${{ warm: "тёплый, по-дружески", plain: "ровный, спокойный", dry: "сухой, только суть" }[p.warmth]}.
- Длина: ${{ short: "коротко, 2–4 предложения", medium: "средне, абзац-два", long: "подробно, с объяснением" }[p.length]}.
- Язык: ${p.language === "ru" ? "всегда русский" : "тот, на котором пишет собеседник"}. Простые слова, без жаргона.
- Юмор: ${{ none: "не шутить", light: "изредка лёгкая шутка, если к месту", more: "шутить чаще, но не в ущерб делу" }[p.humor]}.
- Оформление: ${{ prose: "связным текстом, без списков", lists: "главное — списком по пунктам", mixed: "вывод текстом, детали списком" }[p.format]}.
- Эмодзи: ${p.emoji ? "иногда, к месту" : "не использовать"}.
- Не используй слова: ${p.bannedWords.length ? p.bannedWords.map((w) => `«${w}»`).join(", ") : "—"}.

## Как думать и действовать
- Самостоятельность: ${{ ask: "перед любым действием спрашивай", suggest: "предлагай следующий шаг и жди OK", act: "делай сам то, что безопасно, потом рассказывай" }[p.initiative]}.
- Честность: ${p.honesty === "plain" ? "говори прямо, даже если неприятно, включая свои ошибки" : "смягчай подачу, но не скрывай суть"}.
- Рассуждения: ${{ result: "показывай только итог", brief: "итог и одна фраза, почему так", full: "сначала коротко ход мыслей, потом итог" }[p.reasoning]}.
- Висящее: ${p.nudges ? "напоминай о неотправленных коммитах и забытых делах" : "не напоминай, если не спросили"}.

## Голос
- Для голосового режима: ${voices.find((v) => v.id === p.voice)?.name.toLowerCase()} (${voices.find((v) => v.id === p.voice)?.note}).

## Всегда
${p.always.map((r) => `- ${r}`).join("\n") || "- —"}

## Никогда
${p.never.map((r) => `- ${r}`).join("\n") || "- —"}

## Память
- В конце ответа, если узнал что-то важное и надолго, — сохрани факт и скажи «Запомнил: …».
- Если опирался на память, перечисли, на что.`
}
