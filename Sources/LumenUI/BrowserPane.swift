import AppKit
import LumenCore
import SwiftUI
import WebKit

/// Встроенный браузер сбоку окна: адресная строка, назад/вперёд, страница. Агенты работают здесь же —
/// сверху видно, кто и что делает. Входы в аккаунты остаются после перезапуска.
extension AppModel {
    /// Запустить сокет браузера для lumen-mcp (один раз за запуск)
    func startBrowser() {
        guard browserServer == nil else { return }
        let browser = self.browser
        let server = BrowserServer(path: paths.browserSocket.path) { tool, args, who in
            nonisolated(unsafe) let a = args
            return await browser.handle(tool: tool, args: a, who: who)
        }
        do {
            try server.start()
            browserServer = server
        } catch {
            log("Браузер: сокет не открылся — \(error.localizedDescription)")
        }
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
    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
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
                WebViewHost(view: browser.webView)
                if browser.url.isEmpty || browser.url == "about:blank" { empty }
            }
        }
        // макеты и сайты — шире обычной панели: до 60% окна
        .frame(width: CGFloat(max(360, min(app.browserWidth, Double(windowWidth) * 0.6))))
        .background(p.background)
        .overlay(alignment: .leading) {
            ResizeHandle(side: .leading, width: $app.browserWidth, minWidth: 360) {}
                .offset(x: -4)
        }
        .overlay(alignment: .leading) { p.border.frame(width: 1) }
        .animation(.easeOut(duration: 0.15), value: browser.activity)
        .onChange(of: browser.url) { _, u in if !editing { address = u == "about:blank" ? "" : u } }
        .onAppear { address = browser.url == "about:blank" ? "" : browser.url }
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
            IconButton(icon: "external-link", help: "Открыть в Safari") {
                if let u = URL(string: browser.url), !browser.url.isEmpty { NSWorkspace.shared.open(u) }
            }
            .disabled(browser.url.isEmpty)
            IconButton(icon: "x", help: "Закрыть браузер") { app.browserOpen = false }
        }
        .padding(.horizontal, 8).frame(height: 48)
        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Icon("globe", 28).foregroundStyle(p.glow)
            Text("Браузер Lumen").font(.geist(16, .semibold))
            Text("Здесь работают Lumen, агенты и боты — ты видишь каждый шаг. Сюда же они выкладывают макеты, картинки и сайты, чтобы ты посмотрел.\n\nВойди в свои аккаунты прямо здесь — вход сохранится, и агенты смогут работать от твоего имени.")
                .font(.geist(13)).foregroundStyle(p.mutedFg).multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.background)
        .allowsHitTesting(false)
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
