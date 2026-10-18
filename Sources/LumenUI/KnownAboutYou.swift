import AppKit
import LumenCore
import SwiftUI

// «Что обо мне уже знают» (Рома, 18.10): знакомство и «Данные» предлагают перенести в память Lumen то, что о человеке
// уже знают другие помощники: память Claude Code и Codex, их общие инструкции (CLAUDE.md, AGENTS.md) — с диска,
// а Claude и ChatGPT — запросом: копируешь его туда, их ответ (блок кода) вставляешь сюда. Перед сохранением всё видно и снимается.

/// Где на этом Маке лежит то, что знают о человеке
struct KnownSource: Identifiable, Equatable {
    enum Kind: String { case claudeMemory, claudeMD, codexMemory, codexMD }
    let kind: Kind
    var id: String { kind.rawValue }
    let title: String
    let detail: String
    let icon: String
    /// Готовые факты (память Claude Code) или текст, который разберёт модель
    var facts: [MemoryFact] = []
    var text = ""
}

/// Факт-черновик: человек видит его и решает, сохранять ли
struct FactDraft: Identifiable, Equatable {
    let id = UUID()
    var fact: MemoryFact
    var on = true
}

extension AppModel {
    /// Что нашлось на Маке. Уже перенесённая память Claude Code второй раз не предлагается
    func knownSources(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [KnownSource] {
        let fm = FileManager.default
        var out: [KnownSource] = []
        // память Claude Code: факт на файл
        let have = Set(memories.compactMap(\.key))
        var claude: [MemoryFact] = []
        let projects = home.appendingPathComponent(".claude/projects", isDirectory: true)
        for dir in (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [] {
            let mem = dir.appendingPathComponent("memory", isDirectory: true)
            for f in (try? fm.contentsOfDirectory(at: mem, includingPropertiesForKeys: nil)) ?? []
            where f.pathExtension == "md" && f.lastPathComponent != "MEMORY.md" {
                let key = "claude-memory:" + f.deletingPathExtension().lastPathComponent
                guard !have.contains(key), let text = try? String(contentsOf: f, encoding: .utf8),
                      let fact = Self.claudeMemoryFact(text, key: key) else { continue }
                claude.append(fact)
            }
        }
        if !claude.isEmpty {
            out.append(KnownSource(kind: .claudeMemory, title: "Память Claude Code", detail: Self.count(claude.count, "факт", "факта", "фактов"),
                                   icon: "square-terminal", facts: claude))
        }
        if let t = Self.text(home.appendingPathComponent(".claude/CLAUDE.md")) {
            out.append(KnownSource(kind: .claudeMD, title: "Инструкции Claude Code", detail: "~/.claude/CLAUDE.md — как тебе удобно работать",
                                   icon: "file-text", text: t))
        }
        // память Codex: база memories_1.sqlite и файлы ~/.codex/memories/*.md
        var codex = Self.sqliteColumn(home.appendingPathComponent(".codex/memories_1.sqlite"),
                                      "select raw_memory from stage1_outputs order by source_updated_at desc limit 60")
        for f in (try? fm.contentsOfDirectory(at: home.appendingPathComponent(".codex/memories", isDirectory: true), includingPropertiesForKeys: nil)) ?? []
        where f.pathExtension == "md" {
            if let t = Self.text(f) { codex.append(t) }
        }
        if !codex.isEmpty {
            out.append(KnownSource(kind: .codexMemory, title: "Память Codex", detail: Self.count(codex.count, "запись", "записи", "записей"),
                                   icon: "brain", text: codex.joined(separator: "\n\n")))
        }
        if let t = Self.text(home.appendingPathComponent(".codex/AGENTS.md")) {
            out.append(KnownSource(kind: .codexMD, title: "Инструкции Codex", detail: "~/.codex/AGENTS.md", icon: "file-text", text: t))
        }
        return out
    }

    /// Запрос для Claude или ChatGPT: выписать всё, что они знают о человеке, одним блоком кода
    nonisolated static let exportPrompt = """
        Я переношу то, что ты обо мне знаешь, в своего помощника Lumen. Выпиши всё, что помнишь обо мне из наших разговоров и своей памяти: \
        кто я и чем занимаюсь, мои проекты и в каком они состоянии, принятые решения, как мне удобно получать ответы, люди вокруг меня, \
        предпочтения, инструменты и привычки. Каждый факт — отдельной строкой «- …», коротко, в третьем лице, только то, что знаешь точно. \
        Ответь одним блоком кода, чтобы его было удобно скопировать целиком.
        """

    /// Разобрать текст (инструкции, память другого помощника, ответ Claude или ChatGPT) на факты: Haiku, без неё — по строкам «- …»
    func facts(from text: String, source: String) async -> [MemoryFact] {
        let clean = text.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        let system = """
            Выпиши из текста факты о человеке для долгой памяти его помощника. Отвечай строго JSON без markdown:
            {"facts": [{"kind": "you|project|decision|pref|people", "text": "…"}]}
            you — о самом человеке, project — его проекты, decision — принятые решения, pref — как ему удобно, people — люди вокруг.
            Каждый факт — одна короткая самодостаточная фраза в третьем лице, по-русски. Только устойчивое и полезное помощнику, без выдумок. \
            Инструкции для помощника («пиши коротко», «не пушь без спроса») — это pref. Не больше 40 фактов.
            """
        if cli != nil, let answer = await quickAsk("Текст (\(source)):\n\n\(clean.prefix(40_000))", system: system),
           let json = Self.jsonObject(in: answer), let list = json["facts"] as? [[String: Any]] {
            return list.compactMap { f in
                guard let t = (f["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
                return MemoryFact(kind: MemoryKind(rawValue: f["kind"] as? String ?? "") ?? .you, text: String(t.prefix(400)), source: source)
            }
        }
        return Self.lineFacts(clean, source: source)
    }

    /// Без модели: каждая строка «- …» или «* …» — факт о человеке
    nonisolated static func lineFacts(_ text: String, source: String) -> [MemoryFact] {
        text.split(separator: "\n").compactMap { line in
            var l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("- ") || l.hasPrefix("* ") || l.hasPrefix("• ") else { return nil }
            l = String(l.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return l.count < 3 ? nil : MemoryFact(kind: .you, text: String(l.prefix(400)), source: source)
        }
    }

    /// Сохранить отмеченные; такие же (без учёта регистра и знаков) уже есть — пропустить. Сколько сохранено
    @discardableResult
    func saveFacts(_ facts: [MemoryFact]) -> Int {
        var seen = Set(memories.map { Self.plain($0.text) })
        var added = 0
        for f in facts where seen.insert(Self.plain(f.text)).inserted {
            if (try? store.save(f)) != nil { added += 1 }
        }
        if added > 0 {
            reloadMemories()
            chat.memoryChanged()
            log("Знакомство: в память перенесено фактов — \(added)")
        }
        return added
    }

    nonisolated static func plain(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    nonisolated static func count(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let m10 = n % 10, m100 = n % 100
        let w = m10 == 1 && m100 != 11 ? one : (2...4).contains(m10) && !(12...14).contains(m100) ? few : many
        return "\(n) \(w)"
    }

    private nonisolated static func text(_ url: URL) -> String? {
        guard let t = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// Столбец из базы sqlite (только чтение); нет базы или таблицы — пусто
    nonisolated static func sqliteColumn(_ db: URL, _ sql: String) -> [String] {
        guard FileManager.default.fileExists(atPath: db.path) else { return [] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = ["-readonly", "-json", db.path, sql]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0, let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return rows.compactMap { $0.values.first as? String }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

/// Панель «Что обо мне уже знают»: источники на Маке, запрос для Claude/ChatGPT, факты на проверку и «Сохранить»
struct KnownImportPanel: View {
    @Bindable var app: AppModel
    /// В знакомстве — плотнее и без своей рамки
    var compact = false

    @Environment(\.palette) private var p
    @State private var sources: [KnownSource] = []
    @State private var picked: Set<String> = []
    @State private var drafts: [FactDraft] = []
    @State private var pasted = ""
    @State private var busy = false
    @State private var copied = false
    @State private var note: String?

    private var canCollect: Bool { !busy && (!picked.isEmpty || !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("На этом Маке").tw(13, .medium, lh: 18)
                if sources.isEmpty {
                    Text("Памяти Claude Code и Codex здесь не нашёл — можно перенести из Claude или ChatGPT ниже.")
                        .tw(12, lh: 16).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(sources) { s in
                    check(on: picked.contains(s.id), icon: s.icon, title: s.title, detail: s.detail) {
                        if picked.contains(s.id) { picked.remove(s.id) } else { picked.insert(s.id) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Из Claude или ChatGPT").tw(13, .medium, lh: 18)
                Text("Скопируй запрос и отправь его в Claude или ChatGPT — он выпишет, что знает о тебе, одним блоком. Скопируй блок и вставь сюда.")
                    .tw(12, lh: 16).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    LButton(title: copied ? "Скопировано" : "Скопировать запрос", icon: copied ? "check" : "copy", kind: .outline, small: true) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(AppModel.exportPrompt, forType: .string)
                        copied = true
                    }
                    LButton(title: "Открыть Claude", icon: "external-link", kind: .ghost, small: true) {
                        if let u = URL(string: "https://claude.ai/new") { NSWorkspace.shared.open(u) }
                    }
                    LButton(title: "Открыть ChatGPT", icon: "external-link", kind: .ghost, small: true) {
                        if let u = URL(string: "https://chatgpt.com") { NSWorkspace.shared.open(u) }
                    }
                }
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $pasted)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                    if pasted.isEmpty {
                        Text("Вставь сюда ответ — строки «- …»").tw(12, lh: 16).foregroundStyle(p.mutedFg.opacity(0.7))
                            .padding(.horizontal, 13).padding(.vertical, 8).allowsHitTesting(false)
                    }
                }
                .frame(height: compact ? 64 : 96)
                .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
                .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
            }
            HStack(spacing: 10) {
                LButton(title: busy ? "Разбираю…" : (drafts.isEmpty ? "Найти факты" : "Найти ещё"), icon: "sparkles", kind: .primary,
                        small: true, busy: busy) { collect() }
                    .disabled(!canCollect)
                if let note { Text(note).tw(12, lh: 16).foregroundStyle(p.mutedFg) }
            }
            if !drafts.isEmpty { review }
        }
        .padding(compact ? 0 : 18)
        .task {
            sources = app.knownSources()
            picked = Set(sources.map(\.id))
        }
    }

    /// Факты на проверку: снять лишнее и сохранить
    private var review: some View {
        let on = drafts.filter(\.on).count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Нашлось — сними лишнее").tw(13, .medium, lh: 18)
                Spacer()
                Button(on == drafts.count ? "Снять все" : "Отметить все") {
                    let all = on != drafts.count
                    for i in drafts.indices { drafts[i].on = all }
                }
                .buttonStyle(.plain).font(.geist(12)).foregroundStyle(p.mutedFg)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach($drafts) { $d in
                        check(on: d.on, icon: nil, title: d.fact.text, detail: d.fact.kind.name + " · " + d.fact.source) { d.on.toggle() }
                    }
                }
            }
            .frame(maxHeight: compact ? 150 : 260)
            HStack(spacing: 10) {
                LButton(title: "Сохранить в память (\(on))", icon: "brain", kind: .glow, small: true) {
                    let n = app.saveFacts(drafts.filter(\.on).map(\.fact))
                    drafts = []
                    note = n == 0 ? "Всё это Lumen уже знал" : "Lumen теперь знает ещё \(AppModel.count(n, "факт", "факта", "фактов"))"
                    sources = app.knownSources()
                    picked = picked.intersection(Set(sources.map(\.id)))
                }
                .disabled(on == 0)
            }
        }
    }

    private func check(on: Bool, icon: String?, title: String, detail: String, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 10) {
                Icon(on ? "square-check" : "square", 16).foregroundStyle(on ? p.glow : p.mutedFg).padding(.top, 1)
                if let icon { Icon(icon, 15).foregroundStyle(p.mutedFg).padding(.top, 1) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).tw(13, lh: 18).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text(detail).tw(11, lh: 15).foregroundStyle(p.mutedFg)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(on ? p.glow.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: R.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func collect() {
        busy = true
        note = nil
        let chosen = sources.filter { picked.contains($0.id) }
        let text = pasted
        Task {
            var found: [MemoryFact] = []
            for s in chosen {
                if !s.facts.isEmpty { found += s.facts } else { found += await app.facts(from: s.text, source: s.title) }
            }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                found += await app.facts(from: text, source: "Claude или ChatGPT")
            }
            // без повторов: ни с памятью, ни между собой
            var seen = Set(app.memories.map { AppModel.plain($0.text) } + drafts.map { AppModel.plain($0.fact.text) })
            let fresh = found.filter { seen.insert(AppModel.plain($0.text)).inserted }
            drafts += fresh.map { FactDraft(fact: $0) }
            busy = false
            if fresh.isEmpty { note = "Нового не нашлось — всё это Lumen уже знает" }
            pasted = ""
        }
    }
}
