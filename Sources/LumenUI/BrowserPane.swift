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
        if tool == "show_in_chat" {
            let path = ((args["path"] as? String ?? "") as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { return .init(text: "Нет такого файла: \(path)", error: true) }
            guard let a = importAttachment(URL(fileURLWithPath: path)) else { return .init(text: "Файл не прочитался: \(path)", error: true) }
            guard chat.addShot(conv, a) else { return .init(text: "Сейчас нет идущего ответа, куда положить файл.", error: true) }
            return .init(text: "Показано в чате под ответом: \(a.name).")
        }
        let r = await browser.handle(tool: tool, args: args, who: who)
        if let png = r.image, let image = NSImage(data: png) {
            let name = "Снимок — \(browser.title.isEmpty ? (URL(string: browser.url)?.host ?? "страница") : browser.title).png"
            if let a = importImage(image, name: name) { chat.addShot(conv, a) }
        }
        return r
    }

    func toggleBrowser() {
        browserOpen.toggle()
    }
}

struct BrowserPane: View {
    @Bindable var app: AppModel
    @Bindable var browser: BrowserModel

    @Environment(\.palette) private var p
    @Environment(\.windowWidth) private var windowWidth
    @State private var address = ""
    @State private var serversOpen = false
    @FocusState private var editing: Bool

    private var blank: Bool { browser.url.isEmpty || browser.url == "about:blank" }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if browser.tabs.count > 1 { tabStrip }
            if let a = browser.activity {
                HStack(spacing: 8) {
                    LiveDot(color: p.glow, size: 6)
                    Text(a).tw(12, lh: 16).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(p.mutedFg)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(p.glow.opacity(0.08))
                .transition(.opacity)
            }
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
        }
        .frame(width: CGFloat(max(360, min(app.browserWidth, Double(windowWidth) * 0.6))))
        .background(p.background)
        .overlay(alignment: .leading) {
            ResizeHandle(side: .leading, width: $app.browserWidth, minWidth: 360) {}
                .offset(x: -4)
        }
        .overlay(alignment: .leading) { p.border.frame(width: 1) }
        .animation(.easeOut(duration: 0.15), value: browser.activity)
        .onChange(of: browser.url) { _, u in if !editing { address = u == "about:blank" ? "" : u } }
        .onChange(of: browser.viewport) { _, v in
            if let w = v.size?.width, app.browserWidth < Double(w) + 40 { app.browserWidth = Double(w) + 40 }
        }
        .onAppear { address = blank ? "" : browser.url }
        // запущенные localhost — раз в 5 секунд, пока панель открыта
        .task {
            while !Task.isCancelled {
                await browser.refreshServers()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            IconButton(icon: "arrow-left", help: "Назад") { browser.webView.goBack() }
                .disabled(!browser.canGoBack).opacity(browser.canGoBack ? 1 : 0.4)
            IconButton(icon: "rotate-ccw", help: browser.loading ? "Остановить" : "Обновить") {
                if browser.loading { browser.webView.stopLoading() } else { browser.webView.reload() }
            }
            HStack(spacing: 6) {
                Icon(browser.url.hasPrefix("https") ? "lock" : "globe", 12).foregroundStyle(p.mutedFg)
                TextField("", text: $address, prompt: Text("Адрес, файл или поиск").foregroundStyle(p.mutedFg.opacity(0.7)))
                    .textFieldStyle(.plain).font(.geist(13)).focused($editing)
                    .onSubmit {
                        if let u = BrowserModel.address(address) { browser.open(u) }
                        editing = false
                    }
                if browser.loading { LiveDot(color: p.glow, size: 6) }
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.md))
            .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(editing ? p.glow.opacity(0.35) : p.border))
            serversButton
            IconButton(icon: "plus", help: "Новая вкладка") { browser.newTab(configuration: nil) }
            IconButton(icon: "laptop", help: viewportHelp, active: browser.viewport != .desktop) {
                let next: BrowserModel.Viewport = browser.viewport == .desktop ? .mobile : (browser.viewport == .mobile ? .tablet : .desktop)
                browser.setViewport(next)
            }
            IconButton(icon: "external-link", help: "Открыть в Safari") {
                if let u = URL(string: browser.url), !blank { NSWorkspace.shared.open(u) }
            }
            .disabled(blank)
            IconButton(icon: "x", help: "Закрыть браузер") { app.browserOpen = false }
        }
        .padding(.horizontal, 8).frame(height: 48)
        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
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
                Icon("square-terminal", 14)
                if !browser.servers.isEmpty {
                    Text("\(browser.servers.count)").tw(12, .medium, lh: 16)
                }
            }
            .foregroundStyle(browser.servers.isEmpty ? p.mutedFg : p.glow)
            .padding(.horizontal, 6).frame(height: 28)
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

    private var tabStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(browser.tabs) { t in
                    let on = t.id == browser.activeID
                    HStack(spacing: 6) {
                        Text(t.title.isEmpty ? (URL(string: t.url)?.host ?? "Новая вкладка") : t.title)
                            .tw(12, lh: 16).lineLimit(1).frame(maxWidth: 160, alignment: .leading)
                        Button { browser.close(t.id) } label: { Icon("x", 10) }.buttonStyle(.plain).foregroundStyle(p.mutedFg)
                    }
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(on ? p.foreground.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: R.md))
                    .contentShape(Rectangle())
                    .onTapGesture { browser.select(t.id) }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .scrollIndicators(.never)
        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Icon("globe", 28).foregroundStyle(p.glow)
            Text("Браузер Lumen").font(.geist(16, .semibold))
            Text("Здесь работают Lumen, агенты и боты — ты видишь каждый шаг. Сюда же они выкладывают макеты, картинки и сайты, чтобы ты посмотрел.\n\nВойди в свои аккаунты прямо здесь — вход сохранится, и агенты смогут работать от твоего имени.")
                .font(.geist(13)).foregroundStyle(p.mutedFg).multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            if !browser.servers.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Запущено сейчас").tw(12, .medium, lh: 16).foregroundStyle(p.mutedFg).padding(.horizontal, 8)
                    ForEach(browser.servers) { s in serverRow(s) }
                }
                .padding(8)
                .frame(maxWidth: 340)
                .background(p.card, in: RoundedRectangle(cornerRadius: R.lg))
                .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                .padding(.top, 8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.background)
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
