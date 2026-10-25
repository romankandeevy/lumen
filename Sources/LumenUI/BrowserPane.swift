import AppKit
import LumenCore
import LumenProviders
import SwiftUI
import WebKit

/// Встроенный браузер сбоку окна: адресная строка, назад/вперёд, страница. Агенты работают здесь же —
/// сверху видно, кто и что делает. Входы в аккаунты остаются после перезапуска.
extension AppModel {
    /// Запустить сокет браузера для lumen-mcp (один раз за запуск)
    func startBrowser() {
        guard browserServer == nil else { return }
        // проверочный запуск (LUMEN_SELFSHOT) — второй экземпляр: сокет браузера не трогает, иначе уведёт его у настоящего Lumen
        guard ProcessInfo.processInfo.environment["LUMEN_SELFSHOT"] == nil else { return }
        let server = BrowserServer(path: paths.browserSocket.path) { [weak self] tool, args, who, conv in
            nonisolated(unsafe) let a = args
            guard let self else { return .init(text: "Lumen закрывается.", error: true) }
            return await self.browserCall(tool, a, who: who, conv: conv)
        }
        do {
            try server.start()
            browserServer = server
        } catch {
            log("Браузер: сокет не открылся — \(error.localizedDescription)")
        }
    }

    /// Действие агента: браузер, а снимки экрана и show_in_chat — ещё и в чат, под идущий ответ
    func browserCall(_ tool: String, _ args: [String: Any], who: String, conv: String) async -> BrowserTools.Reply {
        if tool == "make_file" {
            // файл вложением: в хранилище Lumen, не в проект — человек откроет сбоку и скачает, если нужен
            let raw = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (raw as NSString).lastPathComponent.isEmpty ? "файл.md" : (raw as NSString).lastPathComponent
            let content = args["content"] as? String ?? ""
            guard content.utf8.count <= 5_000_000 else { return .init(text: "Файл больше 5 МБ — так не выдаю.", error: true) }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-make-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let tmp = dir.appendingPathComponent(name)
            // .docx и .xlsx собираем сами из текста (Documents.swift): Word и Excel их открывают как настоящие
            let written: Bool
            if let doc = Documents.data(forName: name, content: content) {
                written = (try? doc.write(to: tmp, options: .atomic)) != nil
            } else {
                written = (try? content.write(to: tmp, atomically: true, encoding: .utf8)) != nil
            }
            guard written, var a = importAttachment(tmp) else { return .init(text: "Файл не получился.", error: true) }
            a.name = name
            guard controllers.contains(where: { $0.addShot(conv, a) }) else { return .init(text: "Сейчас нет идущего ответа, куда положить файл.", error: true) }
            return .init(text: "Файл «\(name)» (\(a.sizeText)) лежит под ответом: человек может открыть его сбоку и скачать. В проект он не записан.")
        }
        if tool == "show_in_chat" {
            let path = ((args["path"] as? String ?? "") as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { return .init(text: "Нет такого файла: \(path)", error: true) }
            let url = URL(fileURLWithPath: path)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            // большое (видео, архив) не копируем — вложение ссылается на сам файл
            let big = size > 50_000_000
            guard let a = big
                ? Attachment(name: url.lastPathComponent, kind: .file, mime: UTTypeMime.mime(url.pathExtension), path: path, size: size)
                : importAttachment(url) else { return .init(text: "Файл не прочитался: \(path)", error: true) }
            guard controllers.contains(where: { $0.addShot(conv, a) }) else { return .init(text: "Сейчас нет идущего ответа, куда положить файл.", error: true) }
            return .init(text: "Показано в чате под ответом: \(a.name).")
        }
        let r = await browser.handle(tool: tool, args: args, who: who)
        if let png = r.image, let image = NSImage(data: png) {
            let name = "Снимок — \(browser.title.isEmpty ? (URL(string: browser.url)?.host ?? "страница") : browser.title).png"
            if var a = importImage(image, name: name) {
                a.snapshot = true
                _ = controllers.contains { $0.addShot(conv, a) }
            }
        }
        return r
    }

    /// Открыть вложение для просмотра в браузере сбоку: картинки, PDF, HTML — как есть; Markdown — оформленным; код и текст — моноширинным
    func preview(_ a: Attachment) {
        var kind = FileKind.of(a.url)
        // вид по типу вложения: расширение у копии может быть любым, а «текст» мы уже определили при добавлении
        if a.kind == .image { kind = .image } else if a.kind == .pdf { kind = .pdf }
        if kind == .other {
            // незнакомое расширение: читается как текст — текстом, иначе в программе по умолчанию
            if (try? String(contentsOf: a.url, encoding: .utf8)) != nil { kind = .text } else { NSWorkspace.shared.open(a.url); return }
        }
        if kind == .web {
            browser.open(a.url)
            browserOpen = true
        } else {
            openFile(a.url, name: a.name, kind: kind)
        }
    }

    /// Файл в панели сбоку со своим превью (FileViewers.swift)
    func openFile(_ url: URL, name: String? = nil, kind: FileKind? = nil) {
        browser.openFile(url, name: name, kind: kind)
        browserOpen = true
    }

    /// «В чат» у открытого файла: он прикрепляется к разговору, поле ввода забирает его (как «Прикрепить» в Артефактах)
    func attachToChat(_ url: URL) {
        guard let a = importAttachment(url), !attachInbox.contains(where: { $0.path == a.path }) else { return }
        attachInbox.append(a)
    }

    /// Фрагмент картинки, показанный курсором, — вложением
    func attachImage(_ image: NSImage, name: String) {
        if let a = importImage(image, name: name) { attachInbox.append(a) }
    }

    /// Выделенный текст — цитатой в поле ввода: «Из «файл»:» и строки с «>»
    func quoteToChat(_ text: String, from name: String) {
        let quoted = text.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
        draftInbox += "Из «\(name)»:\n\(quoted)\n\n"
    }

    /// «Скачать»: копия в «Загрузки» под своим именем и показать её в Finder
    func download(_ a: Attachment) { downloadFile(a.url, name: a.name) }

    func downloadFile(_ source: URL, name: String) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var dest = dir.appendingPathComponent(name)
        var i = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)")
            i += 1
        }
        guard (try? FileManager.default.copyItem(at: source, to: dest)) != nil else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dest])
    }

    /// Сохранить ссылку (звёздочка или «Добавить ссылку»); тот же адрес второй раз не добавляется
    func saveLink(title: String, url: String) {
        guard !savedLinks.contains(where: { $0.url == url }) else { return }
        savedLinks.append(SavedLink(title: title, url: url))
        persistLinks()
    }

    func removeLink(url: String) {
        savedLinks.removeAll { $0.url == url }
        persistLinks()
    }

    private func persistLinks() {
        do { try store.set("browser.links", savedLinks) } catch { log("Ссылки браузера не сохранились: \(error.localizedDescription)") }
    }

    func toggleBrowser() {
        browserOpen.toggle()
    }

    /// Ссылка из переписки — в браузер сбоку. Занятая страница не теряется: ссылка идёт в новую вкладку,
    /// на пустой вкладке — в неё. Почта и прочие схемы — в системной программе, как раньше
    /// Ссылка из переписки: туда, где выбрано в настройках; `alternate` (⌘-клик) — в другое место
    func openLink(_ u: URL, alternate: Bool = false) {
        let side = (prefs.linkTarget == .side) != alternate
        if side { openInBrowser(u) } else { NSWorkspace.shared.open(u) }
    }

    /// Браузер Мака по умолчанию — подпись в настройках («Мой браузер — Google Chrome»)
    static var defaultBrowserName: String? {
        guard let probe = URL(string: "https://example.com"), let app = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return nil }
        return FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    func openInBrowser(_ u: URL) {
        guard ["http", "https", "file"].contains(u.scheme?.lowercased() ?? "") else { NSWorkspace.shared.open(u); return }
        // файл с локального диска (не страница) — со своим превью, без адресной строки
        if u.isFileURL, !u.hasDirectoryPath, FileKind.of(u) != .web, FileKind.of(u) != .other {
            openFile(u)
            return
        }
        browser.ensureWebTab()
        browserOpen = true
        if !browser.blankPage { browser.newTab(configuration: nil) }
        browser.open(u)
    }

    /// Показать браузер сбоку (⌘T и ⌘L открывают его, даже если он был спрятан)
    func showBrowser() {
        browserOpen = true
    }
}

/// Ссылка, которую человек сохранил в браузере. Адрес — он же и ключ.
struct SavedLink: Codable, Identifiable, Hashable {
    var id: String { url }
    var title: String
    let url: String

    /// Адрес без «https://» и последнего «/» — для строки в списке
    var short: String {
        var s = url
        for scheme in ["https://", "http://"] where s.hasPrefix(scheme) { s.removeFirst(scheme.count) }
        return s.hasSuffix("/") ? String(s.dropLast()) : s
    }
}

struct BrowserPane: View {
    @Bindable var app: AppModel
    @Bindable var browser: BrowserModel

    @Environment(\.palette) private var p
    @Environment(\.windowWidth) private var windowWidth
    @State private var address = ""
    @State private var serversOpen = false
    /// «Показать все» на пустой вкладке: по умолчанию первые четыре сервера
    @State private var serversAll = false
    /// Курсор над адресом: тогда показываем полную ссылку
    @State private var hoverAddress = false
    /// Форма «Добавить ссылку» на пустой вкладке
    @State private var adding = false
    @State private var newTitle = ""
    @State private var newURL = ""
    @FocusState private var editing: Bool

    private var blank: Bool { browser.url.isEmpty || browser.url == "about:blank" }

    var body: some View {
        VStack(spacing: 0) {
            // сверху адрес на одном уровне с крестиком, под ним вкладки (Рома, 18.10). У файла адреса нет: вкладки, под ними шапка файла
            if browser.active.file == nil { toolbar }
            tabBar
            p.border.frame(height: 1)
            if let file = browser.active.file {
                FileTabView(app: app, file: file)
                    .id(file.url)
            } else {
            ZStack {
                if let size = browser.viewport.size {
                    // телефон или планшет: страница своей ширины по центру
                    ScrollView([.vertical, .horizontal]) {
                        WebViewHost(view: browser.webView)
                            .frame(width: size.width, height: size.height)
                            .clipShape(RoundedRectangle(cornerRadius: R.xl))
                            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
                            .padding(16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(p.secondary.opacity(0.4))
                } else {
                    WebViewHost(view: browser.webView)
                }
                if blank { empty }
            }
            // что сейчас делает Lumen — таблеткой над страницей сверху, а не полосой, от которой всё прыгает вниз
            .overlay(alignment: .top) {
                if let a = browser.activity {
                    HStack(spacing: 8) {
                        LiveDot(color: p.glow, size: 6)
                        Text(a).tw(12.5, .medium, lh: 16).lineLimit(1)
                    }
                    .foregroundStyle(p.foreground)
                    .padding(.horizontal, 14).frame(height: 30)
                    .background(p.popover, in: Capsule())
                    .overlay(Capsule().strokeBorder(p.border))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                    .padding(.top, 14)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            }
        }
        .frame(width: CGFloat(max(360, min(app.browserWidth, Double(windowWidth) * 0.6))))
        // отдельный блок, как вкладка в Claude: скруглённая карточка с отступами от краёв окна
        .background(p.background, in: RoundedRectangle(cornerRadius: R.xl))
        .clipShape(RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
        .overlay(alignment: .leading) {
            ResizeHandle(side: .leading, width: $app.browserWidth, minWidth: 360) {}
                .offset(x: -4)
        }
        .padding(.vertical, 8).padding(.trailing, 8)
        .animation(.easeOut(duration: 0.2), value: browser.activity)
        .onChange(of: browser.url) { _, u in if !editing { address = u == "about:blank" ? "" : u } }
        .onChange(of: browser.viewport) { _, v in
            if let w = v.size?.width, app.browserWidth < Double(w) + 40 { app.browserWidth = Double(w) + 40 }
        }
        .onAppear { address = blank ? "" : browser.url }
        .onChange(of: browser.focusAddress) { _, _ in editing = true }
        // вышли из правки — в строке снова то, что открыто (а не недописанное)
        .onChange(of: editing) { _, on in if !on { address = blank ? "" : browser.url } }
        // запущенные localhost — раз в 5 секунд, пока панель открыта
        .task {
            while !Task.isCancelled {
                await browser.refreshServers()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Верхняя строка: назад, вперёд, обновить, адрес (со звёздочкой внутри), серверы, вид, «открыть в моём браузере», закрыть
    private var toolbar: some View {
        HStack(spacing: 2) {
            BrowserTool(icon: "arrow-left", help: "Назад", enabled: browser.canGoBack) { browser.webView.goBack() }
            BrowserTool(icon: "arrow-right", help: "Вперёд", enabled: browser.canGoForward) { browser.webView.goForward() }
            BrowserTool(icon: browser.loading ? "x" : "rotate-ccw", help: browser.loading ? "Остановить" : "Обновить") {
                if browser.loading { browser.webView.stopLoading() } else { browser.webView.reload() }
            }
            addressField.padding(.horizontal, 4)
            serversButton
            BrowserTool(icon: "laptop", help: viewportHelp, active: browser.viewport != .desktop) {
                let next: BrowserModel.Viewport = browser.viewport == .desktop ? .mobile : (browser.viewport == .mobile ? .tablet : .desktop)
                browser.setViewport(next)
            }
            BrowserTool(icon: "external-link", help: "Открыть в моём браузере", enabled: !blank) {
                if let u = URL(string: browser.url), !blank { NSWorkspace.shared.open(u) }
            }
            p.border.frame(width: 1, height: 16).padding(.horizontal, 4)
            BrowserTool(icon: "x", help: "Закрыть браузер · ⇧⌘B") { app.browserOpen = false }
        }
        .padding(.horizontal, 8).frame(height: 44)
    }

    /// Адрес: хост крупно, путь приглушённо; наведёшь — полный адрес; клик — правка. Звёздочка — внутри справа
    private var addressField: some View {
        HStack(spacing: 6) {
            Icon(browser.url.hasPrefix("https") ? "lock" : "globe", 11).foregroundStyle(p.mutedFg)
            ZStack(alignment: .leading) {
                TextField("", text: $address, prompt: Text("Введите URL").foregroundStyle(p.mutedFg.opacity(0.7)))
                    .textFieldStyle(.plain).font(.geist(12.5)).focused($editing)
                    .opacity(editing ? 1 : 0).allowsHitTesting(editing)
                    .onSubmit {
                        if let u = BrowserModel.address(address) { browser.open(u) }
                        editing = false
                    }
                    .onExitCommand { editing = false }
                if !editing { addressLabel.font(.geist(12.5)).lineLimit(1).truncationMode(.middle).allowsHitTesting(false) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { editing = true }
            .onHover { hoverAddress = $0 }
            if browser.loading { LiveDot(color: p.glow, size: 5) }
            if !blank && !editing {
                // звёздочка: страница в «Мои ссылки» на пустой вкладке (и обратно)
                let saved = app.savedLinks.contains { $0.url == browser.url }
                Button {
                    if saved {
                        app.removeLink(url: browser.url)
                    } else {
                        app.saveLink(title: browser.title.isEmpty ? (URL(string: browser.url)?.host ?? browser.url) : browser.title, url: browser.url)
                    }
                } label: {
                    Image(systemName: saved ? "star.fill" : "star").font(.system(size: 11))
                        .foregroundStyle(saved ? p.glow : p.mutedFg).frame(width: 18, height: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(saved ? "Убрать из сохранённых" : "Сохранить ссылку")
            }
        }
        .padding(.leading, 10).padding(.trailing, 6).frame(height: 28)
        .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.md))
        .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(editing ? p.glow.opacity(0.35) : p.border))
    }

    /// Адрес в строке, когда он не редактируется: ссылка — хост крупно и путь приглушённо, без «https://» и «www.»;
    /// файл — имя крупно и папка приглушённо. Курсор над строкой — полный адрес
    @ViewBuilder private var addressLabel: some View {
        if blank {
            Text("Введите URL").foregroundStyle(p.mutedFg.opacity(0.7))
        } else if hoverAddress {
            Text(Self.fullAddress(browser.url)).foregroundStyle(p.foreground)
        } else {
            let parts = Self.addressParts(browser.url)
            (Text(parts.head).foregroundStyle(p.foreground) + Text(parts.tail).foregroundStyle(p.mutedFg))
        }
    }

    static func addressParts(_ s: String) -> (head: String, tail: String) {
        guard let u = URL(string: s) else { return (s, "") }
        if u.isFileURL {
            let folder = (u.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
            return (u.lastPathComponent, folder == "/" ? "" : "  " + folder)
        }
        guard let host = u.host else { return (s, "") }
        var head = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if let port = u.port { head += ":\(port)" }
        var tail = u.path
        if let q = u.query { tail += "?" + q }
        return (head, tail == "/" ? "" : tail)
    }

    static func fullAddress(_ s: String) -> String {
        guard let u = URL(string: s), u.isFileURL else { return s }
        return (u.path as NSString).abbreviatingWithTildeInPath
    }

    private var viewportHelp: String {
        switch browser.viewport {
        case .desktop: "Вид: компьютер — нажми, чтобы посмотреть как на телефоне"
        case .mobile: "Вид: телефон — дальше планшет"
        case .tablet: "Вид: планшет — дальше компьютер"
        }
    }

    /// «Серверы»: что сейчас запущено на localhost — открыть одним нажатием
    private var serversButton: some View {
        Button { serversOpen.toggle() } label: {
            HStack(spacing: 4) {
                Icon("square-terminal", 13)
                if !browser.servers.isEmpty {
                    Text("\(browser.servers.count)").tw(12, .medium, lh: 16)
                }
            }
            .foregroundStyle(browser.servers.isEmpty ? p.mutedFg : p.glow)
            .padding(.horizontal, 5).frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(browser.servers.isEmpty ? "Запущенных localhost нет" : "Запущено на localhost: \(browser.servers.count)")
        .popover(isPresented: $serversOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Запущено на этом Маке").tw(12, .medium, lh: 16).foregroundStyle(p.mutedFg).padding(.horizontal, 8).padding(.bottom, 4)
                if browser.servers.isEmpty {
                    Text("Локальных серверов сейчас нет").tw(13, lh: 18).foregroundStyle(p.mutedFg).padding(8)
                }
                ForEach(browser.servers) { s in serverRow(s) { serversOpen = false } }
            }
            .padding(8)
            .frame(width: 320)
            .background(p.popover)
            .environment(\.palette, p)
        }
    }

    private func serverRow(_ s: LocalServers.Server, then: @escaping () -> Void = {}) -> some View {
        Button {
            browser.open(s.url)
            then()
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text("localhost:\(String(s.port))").tw(13, .medium, lh: 18)
                    Text([s.title.flatMap { $0.isEmpty ? nil : $0 }, s.process].compactMap { $0 }.joined(separator: " · "))
                        .tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(p.foreground)
    }

    /// Вкладки под адресом: у каждой крестик (виден у открытой и под курсором), «+» сразу за ними.
    /// Последнюю вкладку закрыл — браузер прячется, в следующий раз откроется пустая
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(browser.tabs) { t in
                    BrowserTabChip(title: t.file?.name ?? (t.title.isEmpty ? (URL(string: t.url)?.host ?? "Новая вкладка") : t.title),
                                   on: t.id == browser.activeID,
                                   select: { browser.select(t.id) },
                                   close: { closeTab(t.id) })
                }
                BrowserTool(icon: "plus", help: "Новая вкладка · ⌘T") { browser.newTab(configuration: nil) }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 34)
    }

    private func closeTab(_ id: Int) {
        let last = browser.tabs.count == 1
        browser.close(id)
        if last { app.browserOpen = false }
    }

    /// Новая вкладка, как в браузере Claude: запущенные на Маке серверы, свои ссылки и подсказка внизу
    private var empty: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                if !browser.servers.isEmpty { serversCard }
                linksCard
            }
            .frame(width: 360)
            Spacer(minLength: 0)
            Text("Запустите сервер для предпросмотра приложения или введите URL вверху. Звёздочка сохраняет страницу сюда.")
                .font(.geist(12)).foregroundStyle(p.mutedFg).multilineTextAlignment(.center)
                .frame(maxWidth: 360).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.background)
    }

    private var serversCard: some View {
        let shown = serversAll ? browser.servers : Array(browser.servers.prefix(4))
        return card {
            ForEach(shown) { s in
                openRow(icon: "square-terminal", title: s.title.flatMap { $0.isEmpty ? nil : $0 } ?? s.process,
                        detail: ":\(s.port)", onOpen: { browser.open(s.url) })
            }
            if browser.servers.count > 4 {
                Button { serversAll.toggle() } label: {
                    Text(serversAll ? "Свернуть" : "Показать все").font(.geist(12)).foregroundStyle(p.mutedFg)
                        .frame(maxWidth: .infinity).frame(height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var linksCard: some View {
        card {
            ForEach(app.savedLinks) { l in
                openRow(icon: "globe", title: l.title, detail: l.short, onOpen: { if let u = URL(string: l.url) { browser.open(u) } },
                        onRemove: { app.removeLink(url: l.url) })
            }
            if adding {
                addForm
            } else {
                Button { adding = true } label: {
                    HStack(spacing: 10) {
                        Icon("plus", 14).frame(width: 18)
                        Text("Добавить ссылку").font(.geist(13))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(p.mutedFg).padding(.horizontal, 8).frame(height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $newTitle, prompt: Text("Название").foregroundStyle(p.mutedFg.opacity(0.7)))
                .textFieldStyle(.plain).font(.geist(13))
            TextField("", text: $newURL, prompt: Text("Введите URL").foregroundStyle(p.mutedFg.opacity(0.7)))
                .textFieldStyle(.plain).font(.geist(13))
                .onSubmit(saveNewLink)
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Button("Отмена") { adding = false; newTitle = ""; newURL = "" }
                    .buttonStyle(.plain).font(.geist(12)).foregroundStyle(p.mutedFg)
                Button("Сохранить", action: saveNewLink)
                    .buttonStyle(.plain).font(.geist(12, .medium)).foregroundStyle(p.glow)
                    .disabled(BrowserModel.address(newURL) == nil)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private func saveNewLink() {
        guard let u = BrowserModel.address(newURL) else { return }
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        app.saveLink(title: title.isEmpty ? (u.host ?? u.absoluteString) : title, url: u.absoluteString)
        adding = false
        newTitle = ""
        newURL = ""
    }

    /// Карточка пустой вкладки: скругление и рамка, как у списка серверов в макете
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(4)
            .background(p.card, in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
    }

    /// Строка карточки: иконка, название, подпись (порт или адрес), кнопка «открыть» ▶ и, если надо, крестик
    private func openRow(icon: String, title: String, detail: String, onOpen: @escaping () -> Void, onRemove: (() -> Void)? = nil) -> some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Icon(icon, 14).frame(width: 18)
                    Text(title).font(.geist(13, .medium)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(detail).font(.system(size: 12, design: .monospaced)).lineLimit(1).foregroundStyle(p.mutedFg)
                    Icon("play", 12).foregroundStyle(p.foreground).frame(width: 26, height: 26)
                        .background(p.background, in: RoundedRectangle(cornerRadius: R.md))
                        .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.border))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let onRemove {
                Button(action: onRemove) { Icon("x", 12).frame(width: 22, height: 26) }
                    .buttonStyle(.plain).foregroundStyle(p.mutedFg).padding(.leading, 6)
            }
        }
        .foregroundStyle(p.foreground)
        .padding(.horizontal, 8).frame(height: 36)
    }
}

/// WKWebView браузера: один на всё приложение, переживает закрытие панели
struct WebViewHost: NSViewRepresentable {
    let view: WKWebView

    func makeNSView(context: Context) -> NSView {
        let box = NSView()
        attach(to: box)
        return box
    }

    func updateNSView(_ box: NSView, context: Context) {
        if view.superview !== box { attach(to: box) }
    }

    private func attach(to box: NSView) {
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: box.leadingAnchor), view.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            view.topAnchor.constraint(equalTo: box.topAnchor), view.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
    }
}

/// Кнопка браузера: значок 14 в квадрате 26, подсветка под курсором
struct BrowserTool: View {
    let icon: String
    let help: String
    var active = false
    var enabled = true
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Icon(icon, 14)
                .foregroundStyle(active || (hover && enabled) ? p.foreground : p.mutedFg)
                .frame(width: 26, height: 26)
                .background(active ? p.secondary : (hover && enabled ? p.foreground.opacity(0.06) : .clear), in: RoundedRectangle(cornerRadius: R.md))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Вкладка: название и крестик. Крестик — у открытой вкладки и под курсором; средняя кнопка мыши тоже закрывает
struct BrowserTabChip: View {
    let title: String
    let on: Bool
    let select: () -> Void
    let close: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false
    @State private var hoverClose = false

    var body: some View {
        HStack(spacing: 2) {
            Button(action: select) {
                Text(title).font(.geist(12)).lineLimit(1)
                    .foregroundStyle(on ? p.foreground : p.mutedFg)
                    .frame(minWidth: 40, maxWidth: 150, alignment: .leading)
                    .padding(.leading, 10).frame(height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: close) {
                Icon("x", 10)
                    .foregroundStyle(hoverClose ? p.foreground : p.mutedFg)
                    .frame(width: 18, height: 18)
                    .background(hoverClose ? p.foreground.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(on || hover ? 1 : 0)
            .onHover { hoverClose = $0 }
            .help("Закрыть вкладку")
            .padding(.trailing, 4)
        }
        .background(on ? p.secondary : (hover ? p.foreground.opacity(0.04) : .clear), in: RoundedRectangle(cornerRadius: R.md))
        .onHover { hover = $0 }
        .onMiddleClick(close)
    }
}

private extension View {
    /// Средняя кнопка мыши — как в обычном браузере: закрыть вкладку
    func onMiddleClick(_ action: @escaping () -> Void) -> some View {
        overlay(MiddleClick(action: action).allowsHitTesting(true))
    }
}

/// Ловит только среднюю кнопку мыши; обычные клики проходят насквозь к кнопкам вкладки
private struct MiddleClick: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> View { View(action: action) }
    func updateNSView(_ v: View, context: Context) { v.action = action }

    final class View: NSView {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .otherMouseDown || NSApp.currentEvent?.type == .otherMouseUp ? super.hitTest(point) : nil
        }
        override func otherMouseUp(with event: NSEvent) {
            if event.buttonNumber == 2 { action() } else { super.otherMouseUp(with: event) }
        }
    }
}
