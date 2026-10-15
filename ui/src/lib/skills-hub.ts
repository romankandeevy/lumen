// Каталог навыков — «все навыки в мире» в одном месте: agentskills.io, GitHub, Hugging Face.
// Заглушка макета: правдоподобные карточки; ничего не скачивается.

export type HubSkill = {
  id: string
  name: string
  author: string
  note: string
  category: string
  stars: number
  downloads: number
  sizeMb: number
  source: "agentskills.io" | "GitHub" | "Hugging Face"
  installed?: boolean // уже лежит в Lumen — качать не надо
}

export const hubCategories = ["Все", "Код", "Тесты", "Дизайн", "Тексты", "Исследования", "Данные", "Документы", "Медиа", "Работа"]

export const hub: HubSkill[] = [
  { id: "swiftui-rules", name: "SwiftUI по правилам prog", author: "roma", note: "Стиль, энергосбережение, без WebView", category: "Код", stars: 12, downloads: 40, sizeMb: 0.1, source: "GitHub", installed: true },
  { id: "status-prog", name: "Статус prog", author: "roma", note: "tools/status.sh + ПЛАН.md → короткий отчёт", category: "Работа", stars: 8, downloads: 22, sizeMb: 0.05, source: "GitHub", installed: true },
  { id: "pdf", name: "PDF", author: "anthropic", note: "Читать, заполнять и собирать PDF", category: "Документы", stars: 4820, downloads: 91200, sizeMb: 2.4, source: "agentskills.io", installed: true },
  { id: "xcode-build", name: "Сборка Xcode", author: "swift-tools", note: "xcodebuild, схемы, подпись, разбор ошибок сборки", category: "Код", stars: 1340, downloads: 18800, sizeMb: 0.6, source: "agentskills.io" },
  { id: "xctest", name: "XCTest и UI-тесты", author: "swift-tools", note: "Пишет и гоняет тесты, читает отчёты xcresult", category: "Тесты", stars: 980, downloads: 12400, sizeMb: 0.8, source: "agentskills.io" },
  { id: "simulator", name: "Сценарии в симуляторе", author: "ios-qa", note: "Тапы, жесты, скриншоты, видео сценария", category: "Тесты", stars: 640, downloads: 7100, sizeMb: 1.2, source: "GitHub" },
  { id: "crash-ips", name: "Разбор падений .ips", author: "apple-dev", note: "Символикация, место и причина падения", category: "Тесты", stars: 410, downloads: 5300, sizeMb: 0.3, source: "GitHub", installed: true },
  { id: "playwright", name: "Playwright", author: "microsoft", note: "Проверка сайтов в браузере: клики, формы, снимки", category: "Тесты", stars: 7200, downloads: 140000, sizeMb: 4.8, source: "agentskills.io" },
  { id: "a11y", name: "Доступность WCAG", author: "a11y-project", note: "Контраст, клавиатура, подписи для VoiceOver", category: "Тесты", stars: 1530, downloads: 21000, sizeMb: 0.4, source: "agentskills.io" },
  { id: "figma-read", name: "Чтение Figma", author: "figma-community", note: "Достаёт фреймы, токены, отступы из макета", category: "Дизайн", stars: 2100, downloads: 33000, sizeMb: 0.9, source: "agentskills.io" },
  { id: "design-tokens", name: "Дизайн-токены", author: "tokens-studio", note: "Цвета, шрифты и отступы в коде и в Figma", category: "Дизайн", stars: 1180, downloads: 15000, sizeMb: 0.5, source: "GitHub" },
  { id: "ui-critique", name: "Разбор интерфейса", author: "nngroup-fans", note: "Эвристики Нильсена, иерархия, отступы", category: "Дизайн", stars: 870, downloads: 9800, sizeMb: 0.2, source: "agentskills.io" },
  { id: "spec-writer", name: "ТЗ для разработчика", author: "pm-kit", note: "Экраны, состояния, тексты, края — по шаблону", category: "Дизайн", stars: 760, downloads: 8700, sizeMb: 0.1, source: "agentskills.io" },
  { id: "icons-sf", name: "SF Symbols", author: "apple-dev", note: "Подбирает и проверяет системные значки", category: "Дизайн", stars: 520, downloads: 6100, sizeMb: 0.7, source: "GitHub" },
  { id: "copy-ru", name: "Тексты по-русски", author: "glavred-like", note: "Без канцелярита и воды, проверка стоп-слов", category: "Тексты", stars: 1410, downloads: 17600, sizeMb: 0.3, source: "GitHub" },
  { id: "seo", name: "SEO для статей", author: "seo-kit", note: "Заголовки, мета-описания, ключевые слова", category: "Тексты", stars: 2300, downloads: 41000, sizeMb: 0.2, source: "agentskills.io" },
  { id: "brand-voice", name: "Голос бренда", author: "content-ops", note: "Держит тон сайта по примерам", category: "Тексты", stars: 690, downloads: 7400, sizeMb: 0.1, source: "agentskills.io" },
  { id: "translate", name: "Перевод с правкой", author: "deepl-fans", note: "Перевод и вычитка носителем", category: "Тексты", stars: 1890, downloads: 29000, sizeMb: 0.2, source: "agentskills.io" },
  { id: "deep-research", name: "Глубокое исследование", author: "anthropic", note: "Много источников, сверка, отчёт со ссылками", category: "Исследования", stars: 5400, downloads: 77000, sizeMb: 0.6, source: "agentskills.io" },
  { id: "arxiv", name: "Статьи arXiv", author: "hf-community", note: "Находит и пересказывает научные статьи", category: "Исследования", stars: 1620, downloads: 19000, sizeMb: 0.4, source: "Hugging Face" },
  { id: "competitors", name: "Разбор конкурентов", author: "pm-kit", note: "Сравнение функций и цен по сайтам", category: "Исследования", stars: 940, downloads: 11200, sizeMb: 0.2, source: "agentskills.io" },
  { id: "sqlite", name: "SQLite", author: "data-tools", note: "Схемы, запросы, миграции, FTS5", category: "Данные", stars: 1260, downloads: 16400, sizeMb: 0.5, source: "GitHub" },
  { id: "xlsx", name: "Таблицы Excel", author: "anthropic", note: "Читать, считать, собирать отчёты в xlsx", category: "Данные", stars: 3900, downloads: 68000, sizeMb: 3.1, source: "agentskills.io" },
  { id: "charts", name: "Графики", author: "dataviz-kit", note: "Понятные графики из таблиц", category: "Данные", stars: 1100, downloads: 14300, sizeMb: 1.8, source: "agentskills.io" },
  { id: "docx", name: "Word-документы", author: "anthropic", note: "Создаёт и правит docx с оформлением", category: "Документы", stars: 3300, downloads: 59000, sizeMb: 2.2, source: "agentskills.io" },
  { id: "pptx", name: "Презентации", author: "anthropic", note: "Слайды pptx по тексту или плану", category: "Документы", stars: 3100, downloads: 52000, sizeMb: 2.9, source: "agentskills.io" },
  { id: "markdown-docs", name: "README и документация", author: "docs-kit", note: "Пишет понятные README, обновляет по коду", category: "Документы", stars: 820, downloads: 9100, sizeMb: 0.1, source: "GitHub" },
  { id: "reel", name: "Монтаж рилса", author: "video-kit", note: "Из клипов — вертикальное видео с титрами", category: "Медиа", stars: 1450, downloads: 22000, sizeMb: 12.4, source: "agentskills.io", installed: true },
  { id: "whisper", name: "Расшифровка аудио", author: "hf-community", note: "Речь в текст, таймкоды, спикеры", category: "Медиа", stars: 6100, downloads: 120000, sizeMb: 145, source: "Hugging Face" },
  { id: "image-gen", name: "Картинки по описанию", author: "hf-community", note: "Обложки и иллюстрации для статей", category: "Медиа", stars: 4200, downloads: 88000, sizeMb: 6.2, source: "Hugging Face" },
  { id: "screenshots", name: "Скриншоты приложений", author: "mac-tools", note: "Снимки окон и красивые рамки", category: "Медиа", stars: 610, downloads: 7700, sizeMb: 0.9, source: "GitHub" },
  { id: "git-flow", name: "Git без боли", author: "git-kit", note: "Ветки, коммиты по правилам, разбор конфликтов", category: "Код", stars: 2700, downloads: 47000, sizeMb: 0.3, source: "agentskills.io" },
  { id: "code-review", name: "Ревью кода", author: "anthropic", note: "Баги, безопасность, лишний код", category: "Код", stars: 4600, downloads: 81000, sizeMb: 0.4, source: "agentskills.io" },
  { id: "nextjs", name: "Next.js", author: "vercel", note: "Страницы, роутинг, кэш, деплой", category: "Код", stars: 3800, downloads: 64000, sizeMb: 1.1, source: "agentskills.io" },
  { id: "swift-concurrency", name: "Swift Concurrency", author: "swift-tools", note: "async/await, акторы, без гонок", category: "Код", stars: 990, downloads: 12900, sizeMb: 0.3, source: "GitHub" },
  { id: "calendar", name: "Календарь", author: "productivity-kit", note: "Свободное время, встречи, напоминания", category: "Работа", stars: 1320, downloads: 25000, sizeMb: 0.2, source: "agentskills.io" },
  { id: "mail-drafts", name: "Черновики писем", author: "productivity-kit", note: "Ответы в твоём тоне, без отправки", category: "Работа", stars: 1700, downloads: 30000, sizeMb: 0.2, source: "agentskills.io" },
  { id: "standup", name: "Отчёт за день", author: "eng-kit", note: "Что сделано, что дальше, что мешает", category: "Работа", stars: 540, downloads: 6800, sizeMb: 0.1, source: "agentskills.io" },
  { id: "linear", name: "Задачи Linear", author: "linear", note: "Создаёт и двигает задачи", category: "Работа", stars: 880, downloads: 10400, sizeMb: 0.3, source: "agentskills.io" },
  { id: "security", name: "Проверка безопасности", author: "sec-kit", note: "Секреты в коде, зависимости, права", category: "Код", stars: 2500, downloads: 39000, sizeMb: 0.6, source: "agentskills.io" },
]

export const fmtNum = (n: number) => (n >= 1000 ? `${(n / 1000).toFixed(n >= 10000 ? 0 : 1).replace(".", ",")} тыс.` : String(n))
