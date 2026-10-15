// Группы ботов: несколько ботов получают одну задачу, сами делят роли, пишут общий план
// и работают — параллельно, где можно, и по очереди, где нельзя. Lumen ведёт группу:
// раздаёт слово, следит за файлами, зовёт человека, когда нужно решение.

export type GroupMode = "auto" | "parallel" | "sequence"

export type Group = {
  id: string
  name: string
  goal: string
  members: string[] // id ботов
  mode: GroupMode
  budget: string
  live?: boolean
}

export const initialGroups: Group[] = [
  {
    id: "site",
    name: "Сайт для Лёши",
    goal: "Нужен полноценный сайт-портфолио для Лёши: главная, работы, контакты",
    members: ["designer", "coder", "tester"],
    mode: "auto",
    budget: "$3 и 2 часа",
    live: true,
  },
  {
    id: "release",
    name: "Релиз Shelf",
    goal: "Довести Shelf до релиза 1.0",
    members: ["coder", "tester"],
    mode: "sequence",
    budget: "$5 и 1 день",
  },
]

export const groupRules = [
  "Говорит один: слово передаётся по очереди, остальные ждут",
  "У файла один хозяин — другие не правят, пока он не отдал",
  "Спор дольше двух кругов — решает Рома",
  "Push и выкатка — только с OK Ромы",
]
