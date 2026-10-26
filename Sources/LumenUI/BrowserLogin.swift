import AppKit
import Foundation
import LumenCore
import WebKit

/// Мост от страницы: человек ввёл логин и пароль и нажал «Войти» — Lumen предложит сохранить.
/// Скрипт работает в отдельном мире JavaScript, поэтому сама страница не может подделать такое сообщение.
@MainActor
final class LoginMessageProxy: NSObject, WKScriptMessageHandler {
    weak var model: BrowserModel?

    init(_ model: BrowserModel) { self.model = model }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any], let password = d["password"] as? String, !password.isEmpty else { return }
        let username = (d["username"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = message.frameInfo.request.url ?? message.webView?.url, BrowserVault.safeToFill(url), let host = url.host else { return }
        model?.loginCaptured(host: host, username: username, password: password)
    }
}

extension BrowserModel {
    // MARK: сохранение входа, который человек ввёл сам

    func loginCaptured(host: String, username: String, password: String) {
        guard !username.isEmpty, let offer = vault.offer(host: host, username: username, password: password) else { return }
        pendingLogin = offer
    }

    func savePendingLogin() {
        guard let c = pendingLogin else { return }
        _ = try? vault.add(host: c.host, username: c.username, password: c.password)
        pendingLogin = nil
    }

    func dismissPendingLogin(never: Bool) {
        if never, let c = pendingLogin { vault.never(host: c.host) }
        pendingLogin = nil
    }

    // MARK: подстановка

    /// «Подставить» в окошке входов: поля заполняются на открытой странице, «Войти» человек нажимает сам
    func fillForHuman(_ login: SavedLogin) async -> Bool {
        let t = active
        guard t.file == nil, let url = t.web?.url, BrowserVault.safeToFill(url) else { say("Подставляю только на защищённых страницах"); return false }
        let r = await fill(login, in: t, submit: false)
        guard r.filled else { say("На странице нет формы входа"); return false }
        vault.used(login.id)
        filledLogin = login
        loginOffer = nil
        say("Вход подставлен")
        return true
    }

    /// Что на странице: форма с паролем, только логин (первый шаг) или ничего
    private func loginKind(_ tab: Tab) async -> String {
        guard let w = tab.web else { return "none" }
        let r = try? await w.callAsyncJavaScript(Self.loginJS, arguments: ["args": ["mode": "detect"]], in: nil, contentWorld: .defaultClient)
        return r as? String ?? "none"
    }

    struct FillResult { var kind = "none"; var filled = false; var submitted = false }

    private func fill(_ login: SavedLogin, in tab: Tab, submit: Bool) async -> FillResult {
        // страница могла смениться (вход через Google, Microsoft, редирект): перед каждой подстановкой — тот же сайт
        guard let w = tab.web, let u = w.url, BrowserVault.safeToFill(u), let h = u.host, BrowserVault.siteMatches(saved: login.host, page: h),
              let pw = vault.password(for: login) else { return FillResult() }
        let args: [String: Any] = ["mode": "fill", "username": login.username, "password": pw, "submit": submit, "host": login.host]
        guard let s = try? await w.callAsyncJavaScript(Self.loginJS, arguments: ["args": args], in: nil, contentWorld: .defaultClient) as? String,
              let d = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] else { return FillResult() }
        return FillResult(kind: d["kind"] as? String ?? "none", filled: d["filled"] as? Bool ?? false, submitted: d["submitted"] as? Bool ?? false)
    }

    /// Не больше двух входов на сайт за пять минут: неверный пароль не должен блокировать аккаунт
    private func canSubmit(_ host: String) -> Bool {
        let recent = (loginAttempts[host] ?? []).filter { Date().timeIntervalSince($0) < 300 }
        loginAttempts[host] = recent
        return recent.count < 2
    }

    /// Страница входа и сохранённый вход: поля заполняются сами; если работает агент — ещё и нажимается «Войти»
    /// (двухшаговые входы — по шагам). Человеку подставляется без нажатия
    func autoLoginIfNeeded(tab: Tab? = nil, who: String?) async {
        let t = tab ?? workTab
        guard options.autoLogin, t.file == nil, let url = t.web?.url, BrowserVault.safeToFill(url), let host = url.host,
              let login = vault.matches(host: host).first, !loginBusy.contains(t.id) else { return }
        loginBusy.insert(t.id)
        defer { loginBusy.remove(t.id) }
        // «Войти» нажимается, только если в этой вкладке работает агент (человеку подставляется без нажатия)
        let byAgent = t.id == agentTabID && (acting > 0 || agentActive)
        // человеку на странице входа — подсказка «Войти как …» у адреса; подставляется по его нажатию, а не сама
        guard byAgent else {
            if t.id == activeID, await loginKind(t) != "none" { loginOffer = login }
            return
        }
        for _ in 0..<8 {
            if t.web?.isLoading == true { try? await Task.sleep(for: .milliseconds(250)) }
            let kind = await loginKind(t)
            if kind == "none" { return }
            let submit = byAgent && login.autoSubmit
            if submit, kind == "password", !canSubmit(login.host) {
                events.append("Вход на \(host) уже пробовали дважды за пять минут — больше не подставляю. Возможно, пароль устарел: скажи человеку.")
                return
            }
            let r = await fill(login, in: t, submit: submit)
            guard r.filled else { return }
            vault.used(login.id)
            if t.id == activeID { filledLogin = login }
            if !submit { return }
            if r.submitted, r.kind == "password" { loginAttempts[login.host, default: []].append(Date()) }
            try? await Task.sleep(for: .milliseconds(900))
            while t.web?.isLoading == true { try? await Task.sleep(for: .milliseconds(150)) }
            // после «Далее» на странице появляется поле пароля — тогда второй круг; иначе вход закончен
            if r.kind != "username" { return }
        }
    }

    /// browser_login: подставить сохранённый вход на этой странице. Пароль модели не показывается
    func loginForAgent(username: String, submit: Bool, who: String) async -> BrowserTools.Reply {
        let t = workTab
        guard t.file == nil, let url = t.web?.url, let host = url.host else { return .init(text: "Сначала открой страницу входа (browser_navigate).", error: true) }
        guard BrowserVault.safeToFill(url) else { return .init(text: "Вход подставляю только на защищённых страницах (https) — эта не такая.", error: true) }
        var found = vault.matches(host: host)
        if !username.isEmpty { found = found.filter { $0.username.lowercased() == username.lowercased() || $0.label.lowercased() == username.lowercased() } }
        guard let login = found.first else {
            let all = vault.matches(host: host)
            return .init(text: all.isEmpty
                ? "Для \(host) нет сохранённого входа. Попроси человека войти самому в панели браузера или сохранить вход (кнопка с ключом) — пароль мне не показывается и сам я его не ввожу."
                : "Нет входа «\(username)» для \(host). Есть: \(all.map(\.title).joined(separator: ", ")).", error: true)
        }
        var did = FillResult()
        for step in 0..<3 {
            if t.web?.isLoading == true { try? await Task.sleep(for: .milliseconds(250)) }
            let kind = await loginKind(t)
            if submit, kind == "password", !canSubmit(login.host) {
                return .init(text: "На \(host) уже было два входа за пять минут — не повторяю, чтобы не заблокировали аккаунт. Скажи человеку: возможно, нужен код из письма или пароль устарел.", error: true)
            }
            let r = await fill(login, in: t, submit: submit)
            guard r.filled else {
                return step == 0 ? .init(text: "На странице нет формы входа (поля логина или пароля). Открой страницу входа сайта.", error: true) : .init(text: loginSummary(login, did))
            }
            did = r
            vault.used(login.id)
            if t.id == activeID { filledLogin = login }
            if !submit { break }
            if r.submitted, r.kind == "password" { loginAttempts[login.host, default: []].append(Date()) }
            try? await Task.sleep(for: .milliseconds(900))
            while t.web?.isLoading == true { try? await Task.sleep(for: .milliseconds(150)) }
            if r.kind != "username" { break }
        }
        return .init(text: loginSummary(login, did))
    }

    private func loginSummary(_ login: SavedLogin, _ r: FillResult) -> String {
        var s = "Подставлен вход «\(login.title)» для \(login.host): логин и пароль введены в поля (пароль не показывается)."
        s += r.submitted ? " Нажата кнопка входа." : " Кнопка входа не нажата."
        s += " Если сайт просит код (SMS, письмо, приложение) — попроси его у человека, сам не угадывай."
        return s
    }

    // MARK: скрипты

    /// Форма входа: найти поля и (mode fill) заполнить; JSON {kind, filled, submitted}
    static let loginJS = prelude + #"""
    const textual = el => ['text', 'email', 'tel', 'search', ''].includes((el.getAttribute('type') || 'text').toLowerCase());
    const hint = el => [el.name, el.id, el.autocomplete, el.placeholder, el.getAttribute('aria-label'), el.getAttribute('data-testid')].join(' ').toLowerCase();
    const inputs = [...document.querySelectorAll('input')].filter(el => vis(el) && !el.disabled && !el.readOnly);
    const pw = inputs.find(el => el.type === 'password');
    let user = null;
    if (pw) {
      const scope = pw.form || pw.closest('form, [role=dialog], main') || document;
      const cands = [...scope.querySelectorAll('input')].filter(el => el !== pw && vis(el) && !el.disabled && textual(el));
      const before = cands.filter(el => el.compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING);
      user = before[before.length - 1] || cands.find(el => /user|login|email|mail|phone|логин|почт/.test(hint(el))) || null;
    } else {
      user = inputs.find(el => textual(el) && /user|login|email|mail|phone|ident|account|логин|почт|телефон/.test(hint(el))) || null;
      if (!user) { const t = inputs.filter(textual); if (t.length === 1 && /sign.?in|log.?in|login|вход|войти|auth|account/i.test(location.href + ' ' + document.title)) user = t[0]; }
    }
    const kind = pw ? 'password' : (user ? 'username' : 'none');
    if (args.mode === 'detect') return kind;
    if (kind === 'none') return JSON.stringify({kind, filled: false, submitted: false});
    // ещё раз в самой странице: защищённая и того же сайта, иначе ничего не вводим
    const here = location.hostname.toLowerCase().replace(/^www\./, ''), want = String(args.host || '').toLowerCase();
    const secure = location.protocol === 'https:' || ['localhost', '127.0.0.1'].includes(location.hostname) || location.hostname.endsWith('.localhost');
    if (!want || !secure || !(here === want || here.endsWith('.' + want))) return JSON.stringify({kind: 'none', filled: false, submitted: false});
    let filled = false;
    if (user && args.username) { if (user.value !== args.username) setValue(user, args.username); filled = true; }
    if (pw && args.password) { setValue(pw, args.password); filled = true; }
    let submitted = false;
    if (args.submit && filled) {
      const field = pw || user, form = field.form;
      const labels = /войти|вход|log.?in|sign.?in|продолжить|далее|continue|next|submit|отправить/i;
      const scope = form || field.closest('main, [role=dialog], body') || document.body;
      const buttons = [...scope.querySelectorAll('button, input[type=submit], input[type=button], [role=button]')].filter(b => vis(b) && !b.disabled);
      const btn = buttons.find(b => b.type === 'submit') || buttons.find(b => labels.test(b.innerText || b.value || b.getAttribute('aria-label') || ''));
      if (btn) { btn.click(); submitted = true; }
      else if (form) { form.requestSubmit ? form.requestSubmit() : form.submit(); submitted = true; }
      else { key(field, 'Enter'); submitted = true; }
    }
    return JSON.stringify({kind, filled, submitted});
    """#

    /// Человек ввёл пароль и нажал «Войти»: сообщить Lumen (мир скрипта отдельный, страница подделать не может)
    static let loginCaptureJS = #"""
    (() => {
      if (window.__lumenLoginHook) return; window.__lumenLoginHook = true;
      let last = '';
      const send = () => {
        const pw = [...document.querySelectorAll('input[type=password]')].find(e => e.value);
        if (!pw) return;
        const scope = pw.form || document;
        const cands = [...scope.querySelectorAll('input')].filter(e => e !== pw && ['text', 'email', 'tel', ''].includes((e.getAttribute('type') || 'text').toLowerCase()) && e.value);
        const before = cands.filter(e => e.compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING);
        const user = (before[before.length - 1] || cands[0] || {value: ''}).value;
        const key = user + '\u0000' + pw.value;
        if (key === last) return; last = key;
        window.webkit.messageHandlers.lumenLogin.postMessage({username: user, password: pw.value});
      };
      const looksLikeLogin = b => b && (b.type === 'submit' || /войти|вход|log.?in|sign.?in|продолжить|continue|next|далее|зарегистр|sign.?up/i.test(b.innerText || b.value || b.getAttribute('aria-label') || ''));
      // только настоящие действия человека: скрипт страницы не может выдать свои данные за вход
      document.addEventListener('submit', e => { if (e.isTrusted) send(); }, true);
      document.addEventListener('click', e => { if (!e.isTrusted) return; const b = e.target.closest && e.target.closest('button, input[type=submit], [role=button]'); if (looksLikeLogin(b)) send(); }, true);
      document.addEventListener('keydown', e => { if (e.isTrusted && e.key === 'Enter' && e.target && e.target.type === 'password') send(); }, true);
    })();
    """#
}
