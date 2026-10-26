import AppKit
import Foundation
import Testing
import WebKit
@testable import LumenCore
@testable import LumenProviders
@testable import LumenUI

// Видео в браузере сбоку (1.7.2): HyperFrames — агент пишет сцены, проверяет, смотрит кадры и рендерит MP4,
// человек монтирует в Студии и шлёт выделенное в чат. Нужны Node и FFmpeg — без них тест не идёт.

@MainActor @Test(.enabled(if: BrowserModel.videoAvailable), .timeLimit(.minutes(5))) func agentMakesAnAnimatedVideoAndRendersIt() async throws {
    let videos = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-videos-\(UUID().uuidString.prefix(6))")
    let browser = BrowserModel()
    browser.videosDir = videos
    defer {
        browser.stopAllStudios()
        try? FileManager.default.removeItem(at: videos)
    }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 860), styleMask: [.borderless], backing: .buffered, defer: false)
    browser.webView.frame = window.contentView!.bounds
    window.contentView!.addSubview(browser.webView)
    window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
    window.orderFrontRegardless()
    defer { window.orderOut(nil) }
    func call(_ tool: String, _ args: [String: Any] = [:]) async -> BrowserTools.Reply {
        await browser.handle(tool: tool, args: args, who: "@designer")
    }

    // без открытого ролика — понятный ответ
    let early = await call("video_files")
    #expect(early.error && early.text.contains("video_open"))

    let opened = await call("video_open", ["name": "Промо"])
    #expect(!opened.error, "\(opened.text.prefix(600))")
    #expect(opened.text.contains("video_write") && opened.text.contains("HyperFrames"), "справочник в первый раз")
    let tab = try #require(browser.videoTab)
    #expect(browser.videoDocs[tab.id] == "Промо")
    #expect(browser.wantsFull > 0)
    #expect(FileManager.default.fileExists(atPath: videos.appendingPathComponent("Промо/index.html").path))

    // Студия загрузилась, реклама их приложения спрятана
    var studio = ""
    for _ in 0..<40 {
        try await Task.sleep(for: .milliseconds(500))
        studio = try await tab.webView.callAsyncJavaScript("return document.body ? document.body.innerText : ''", contentWorld: .page) as? String ?? ""
        if studio.contains("Timeline") { break }
    }
    #expect(studio.contains("Timeline"), "\(studio.prefix(300))")
    try await Task.sleep(for: .milliseconds(400))
    let promo = try await tab.webView.callAsyncJavaScript("const b = document.querySelector('[data-testid=header-open-in-desktop]'); return b ? getComputedStyle(b).display : 'none'", contentWorld: .page) as? String
    #expect(promo == "none")

    // сцена: заголовок выезжает, плашка проявляется — 3 секунды
    let html = """
    <!doctype html>
    <html><head><meta charset="utf-8">
    <script src="https://cdn.jsdelivr.net/npm/gsap@3.12.5/dist/gsap.min.js"></script>
    <style>
      html, body { margin: 0; width: 1920px; height: 1080px; background: #0E0E10; overflow: hidden; }
      #title { position: absolute; left: 160px; top: 420px; font: 700 140px/1 -apple-system, sans-serif; color: #F5F1E8; }
      #bar { position: absolute; left: 160px; top: 600px; width: 520px; height: 14px; border-radius: 7px; background: #E8B04B; }
    </style></head>
    <body>
    <div id="root" data-composition-id="main" data-start="0" data-duration="3" data-width="1920" data-height="1080">
      <h1 id="title" class="clip" data-start="0" data-duration="3" data-track-index="0">Кофе за 3 минуты</h1>
      <div id="bar" class="clip" data-start="0.4" data-duration="2.6" data-track-index="1"></div>
    </div>
    <script>
      window.__timelines = window.__timelines || {};
      const tl = gsap.timeline({ paused: true });
      tl.from('#title', { y: 80, opacity: 0, duration: 0.9, ease: 'power3.out' }, 0)
        .from('#bar', { scaleX: 0, transformOrigin: 'left center', duration: 0.8, ease: 'expo.out' }, 0.4);
      window.__timelines['main'] = tl;
    </script>
    </body></html>
    """
    let wrote = await call("video_write", ["path": "index.html", "content": html])
    #expect(!wrote.error, "\(wrote.text)")
    // за пределы папки ролика не пишет
    let escape = await call("video_write", ["path": "../чужое.html", "content": "x"])
    #expect(escape.error)
    let absolute = await call("video_write", ["path": "/tmp/x.html", "content": "x"])
    #expect(absolute.error)

    let read = await call("video_read", ["path": "index.html"])
    #expect(read.text.contains("Кофе за 3 минуты"))
    let files = await call("video_files")
    #expect(files.text.contains("index.html"), "\(files.text)")

    let check = await call("video_cli", ["command": "check"])
    #expect(!check.text.isEmpty, "\(check.text.prefix(800))")
    // опасные команды не запускаются
    let bad = await call("video_cli", ["command": "init"])
    #expect(bad.error)

    let shot = await call("video_shot", ["at": [0.2, 1.5]])
    #expect(!shot.error, "\(shot.text.prefix(800))")
    #expect(shot.image != nil)

    let render = await call("video_render", ["quality": "draft"])
    #expect(!render.error, "\(render.text)")
    var done = await call("video_render_wait", ["seconds": 80])
    if done.text.contains("ещё идёт") { done = await call("video_render_wait", ["seconds": 80]) }
    #expect(!done.error, "\(done.text.prefix(1500))")
    #expect(done.text.contains(".mp4"), "\(done.text)")
    let mp4 = try FileManager.default.contentsOfDirectory(at: videos.appendingPathComponent("Промо/renders"), includingPropertiesForKeys: nil).first { $0.pathExtension == "mp4" }
    #expect(mp4 != nil)

    // вкладка видео переживает перезапуск
    let saved = browser.savedState()
    #expect(saved.tabs.contains { $0.kind == "video" && $0.title == "Промо" })
    #expect(browser.videoProjects() == ["Промо"])

    // закрыли вкладку — процесс Студии остановлен
    let pid = try #require(browser.videoPIDs["Промо"])
    #expect(kill(pid, 0) == 0)
    browser.close(tab.id)
    var gone = false
    for _ in 0..<20 where !gone {
        try await Task.sleep(for: .milliseconds(250))
        gone = kill(pid, 0) != 0
    }
    #expect(gone)
    #expect(browser.videoPorts["Промо"] == nil)
}

@Test func videoToolsAreDescribedForTheAgent() {
    for name in ["video_open", "video_guide", "video_files", "video_read", "video_write", "video_cli", "video_shot", "video_render", "video_render_wait"] {
        #expect(BrowserTools.names.contains(name), "\(name)")
    }
    #expect(BrowserTools.rules.contains("video_open"))
}

@MainActor @Test func videoGuideIsFoundAndTopicsResolve() async {
    #expect(BrowserModel.videoGuideRoot() != nil)
    let browser = BrowserModel()
    let main = await browser.handle(tool: "video_guide", args: [:], who: "Lumen")
    #expect(!main.error && main.text.contains("HyperFrames"), "\(main.text.prefix(200))")
    let missing = await browser.handle(tool: "video_guide", args: ["topic": "../../etc/passwd"], who: "Lumen")
    #expect(missing.error)
}
