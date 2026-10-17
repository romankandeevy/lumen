import Foundation

/// Скрипты встроенного браузера. Выполняются в отдельном мире JavaScript (страница их не видит и не ломает),
/// DOM — общий. Метки eN ставятся атрибутом data-lumen-ref и живут, пока жив элемент.
/// Все получают `args`; ошибка — строка с «ERR:».
extension BrowserModel {
    static let prelude = #"""
    const INTER = new Set(['link','button','textbox','searchbox','checkbox','radio','combobox','listbox','option','tab','menuitem','menuitemcheckbox','switch','slider','spinbutton']);
    const SKIP = new Set(['SCRIPT','STYLE','NOSCRIPT','TEMPLATE','HEAD','META','LINK','svg','SVG','PATH']);
    window.__lumenRefN = window.__lumenRefN || 0;
    const clean = s => (s || '').replace(/\s+/g, ' ').trim();
    function vis(el) {
      if (el.checkVisibility) return el.checkVisibility({checkOpacity: true, checkVisibilityCSS: true});
      const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0;
    }
    function roleOf(el) {
      const r = el.getAttribute('role'); if (r) return r.split(' ')[0];
      const t = el.tagName;
      if (t === 'A') return el.hasAttribute('href') ? 'link' : null;
      if (t === 'BUTTON' || t === 'SUMMARY') return 'button';
      if (t === 'INPUT') {
        const ty = (el.getAttribute('type') || 'text').toLowerCase();
        if (ty === 'hidden') return null;
        if (['button','submit','reset','image'].includes(ty)) return 'button';
        if (ty === 'checkbox') return 'checkbox'; if (ty === 'radio') return 'radio';
        if (ty === 'range') return 'slider'; if (ty === 'search') return 'searchbox';
        return 'textbox';
      }
      if (t === 'TEXTAREA') return 'textbox';
      if (t === 'SELECT') return 'combobox';
      if (/^H[1-6]$/.test(t)) return 'heading';
      if (t === 'IMG') return el.getAttribute('alt') ? 'img' : null;
      if (el.isContentEditable && !(el.parentElement && el.parentElement.isContentEditable)) return 'textbox';
      if (el.hasAttribute('onclick') || (el.tabIndex >= 0 && t !== 'BODY' && t !== 'HTML' && getComputedStyle(el).cursor === 'pointer')) return 'button';
      return null;
    }
    function nameOf(el, role) {
      let s = el.getAttribute('aria-label') || '';
      if (!s && el.getAttribute('aria-labelledby')) s = el.getAttribute('aria-labelledby').split(' ').map(id => { const e = document.getElementById(id); return e ? e.innerText : ''; }).join(' ');
      if (!s && el.labels && el.labels.length) s = el.labels[0].innerText;
      if (!s && (role === 'textbox' || role === 'searchbox' || role === 'combobox')) s = el.getAttribute('placeholder') || el.getAttribute('name') || '';
      if (!s) s = el.getAttribute('alt') || el.getAttribute('title') || '';
      if (!s && role !== 'textbox') s = el.innerText || el.value || '';
      return clean(s).slice(0, 80);
    }
    function ref(el) {
      let r = el.getAttribute('data-lumen-ref');
      if (!r) { r = 'e' + (++window.__lumenRefN); el.setAttribute('data-lumen-ref', r); }
      return r;
    }
    function byRef(r) { return r ? document.querySelector('[data-lumen-ref="' + r + '"]') : null; }
    function describe(el) {
      const role = roleOf(el) || el.tagName.toLowerCase();
      return '[' + ref(el) + '] ' + role + ' "' + nameOf(el, role) + '"';
    }
    function key(el, k) {
      const codes = {Enter: 13, Escape: 27, Tab: 9, Backspace: 8, ArrowDown: 40, ArrowUp: 38, ArrowLeft: 37, ArrowRight: 39, PageDown: 34, PageUp: 33, ' ': 32, Space: 32, Delete: 46, Home: 36, End: 35};
      const name = k === 'Space' ? ' ' : k;
      const o = {key: name, code: k === ' ' ? 'Space' : k, keyCode: codes[k] || 0, which: codes[k] || 0, bubbles: true, cancelable: true, composed: true};
      const down = el.dispatchEvent(new KeyboardEvent('keydown', o));
      if (name.length === 1 || k === 'Enter') el.dispatchEvent(new KeyboardEvent('keypress', o));
      el.dispatchEvent(new KeyboardEvent('keyup', o));
      return down;
    }
    function setValue(el, v) {
      const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : (el.tagName === 'SELECT' ? HTMLSelectElement.prototype : HTMLInputElement.prototype);
      Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, v);
      el.dispatchEvent(new InputEvent('input', {bubbles: true, composed: true, inputType: 'insertText', data: v}));
      el.dispatchEvent(new Event('change', {bubbles: true}));
    }
    function submit(el) {
      if (key(el, 'Enter') && el.form) { el.form.requestSubmit ? el.form.requestSubmit() : el.form.submit(); }
    }
    function scroller() {
      const d = document.scrollingElement || document.documentElement;
      if (d.scrollHeight > d.clientHeight + 4) return d;
      let el = document.elementFromPoint(innerWidth / 2, innerHeight / 2);
      while (el && el !== document.body) {
        const s = getComputedStyle(el);
        if (/(auto|scroll)/.test(s.overflowY) && el.scrollHeight > el.clientHeight + 4) return el;
        el = el.parentElement;
      }
      return d;
    }
    """#

    static let snapshotJS = prelude + #"""
    const out = []; let size = 0; let cut = false;
    const push = line => { if (size > args.max) { cut = true; return; } out.push(line); size += line.length + 1; };
    function walk(el, depth) {
      if (cut || SKIP.has(el.tagName) || !vis(el)) return;
      const role = roleOf(el);
      const pad = '  '.repeat(Math.min(depth, 6));
      const shown = role && (INTER.has(role) || ((role === 'heading' || role === 'img') && !args.interactive));
      if (shown) {
        let line = pad + (INTER.has(role) ? '[' + ref(el) + '] ' : '') + role + ' "' + nameOf(el, role) + '"';
        if (role === 'textbox' || role === 'searchbox') { const v = el.isContentEditable ? el.innerText : el.value; if (v) line += ' = "' + clean(v).slice(0, 80) + '"'; }
        if (role === 'checkbox' || role === 'radio' || role === 'switch') line += (el.checked || el.getAttribute('aria-checked') === 'true') ? ' ✓' : ' ☐';
        if (el.tagName === 'SELECT' && el.selectedIndex >= 0) line += ' = "' + clean(el.options[el.selectedIndex].text) + '"';
        if (el.disabled || el.getAttribute('aria-disabled') === 'true') line += ' (неактивно)';
        push(line);
        // у ссылки, кнопки, заголовка всё внутри уже в названии
        if (role !== 'listbox' && role !== 'combobox' || el.tagName === 'SELECT') return;
      }
      if (!args.interactive && !role) {
        let own = ''; for (const n of el.childNodes) if (n.nodeType === 3) own += n.textContent;
        own = clean(own);
        if (own.length > 1) push(pad + 'text "' + own.slice(0, 200) + '"');
      }
      for (const c of el.children) walk(c, depth + (shown ? 1 : 0));
      if (el.shadowRoot) for (const c of el.shadowRoot.children) walk(c, depth);
    }
    if (document.body) walk(document.body, 0);
    if (cut) out.push('… страница длиннее — browser_scroll, browser_find или browser_text');
    return out.join('\n');
    """#

    static let findJS = prelude + #"""
    const q = clean(args.query).toLowerCase();
    if (!q) return 'ERR:Пустой запрос.';
    const hits = [];
    for (const el of document.querySelectorAll('a,button,input,textarea,select,summary,label,[role],[contenteditable],[onclick],[tabindex],h1,h2,h3,h4,h5,h6')) {
      if (hits.length >= 25) break;
      if (!vis(el)) continue;
      const role = roleOf(el) || el.tagName.toLowerCase();
      const hay = (nameOf(el, role) + ' ' + (el.getAttribute('placeholder') || '') + ' ' + (el.value || '')).toLowerCase();
      if (hay.includes(q)) hits.push(describe(el));
    }
    if (!hits.length) {
      // просто текст: самый глубокий элемент, где он есть
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      let n;
      while ((n = walker.nextNode()) && hits.length < 10) {
        if (n.textContent.toLowerCase().includes(q) && n.parentElement && vis(n.parentElement)) hits.push(describe(n.parentElement) + ' — текст');
      }
    }
    return hits.length ? hits.join('\n') : 'Ничего не нашлось по «' + args.query + '».';
    """#

    static let clickJS = prelude + #"""
    let el = byRef(args.ref);
    if (!el && args.x !== undefined) el = document.elementFromPoint(args.x, args.y);
    if (!el) return 'ERR:Нет элемента ' + (args.ref || '') + ' — метки меняются после перехода, прочитай страницу заново (browser_read_page).';
    el.scrollIntoView({block: 'center', inline: 'center'});
    const r = el.getBoundingClientRect(); const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    const top = document.elementFromPoint(cx, cy);
    const t = top && el.contains(top) ? top : el;
    const o = {bubbles: true, cancelable: true, composed: true, clientX: cx, clientY: cy, button: 0, buttons: 1, view: window, pointerType: 'mouse', isPrimary: true};
    t.dispatchEvent(new PointerEvent('pointerover', o)); t.dispatchEvent(new MouseEvent('mouseover', o));
    t.dispatchEvent(new PointerEvent('pointerdown', o)); t.dispatchEvent(new MouseEvent('mousedown', o));
    if (el.focus) el.focus({preventScroll: true});
    t.dispatchEvent(new PointerEvent('pointerup', o)); t.dispatchEvent(new MouseEvent('mouseup', o));
    t.click();
    return describe(el);
    """#

    static let typeJS = prelude + #"""
    const el = args.ref ? byRef(args.ref) : document.activeElement;
    if (!el || el === document.body) return 'ERR:Нет поля ' + (args.ref || 'с фокусом') + ' — найди его меткой (browser_read_page).';
    el.scrollIntoView({block: 'center'});
    el.focus();
    if (el.isContentEditable) {
      document.execCommand('selectAll', false);
      document.execCommand('insertText', false, args.text);
    } else if ('value' in el && el.tagName !== 'SELECT') {
      setValue(el, args.text);
    } else return 'ERR:' + describe(el) + ' — не поле ввода.';
    if (args.submit) submit(el);
    return 'Введено в ' + describe(el) + (args.submit ? ', нажат Enter.' : '.');
    """#

    static let selectJS = prelude + #"""
    const el = byRef(args.ref);
    if (!el) return 'ERR:Нет элемента ' + args.ref + ' — прочитай страницу заново.';
    const v = clean(args.value);
    if (el.tagName === 'SELECT') {
      const lv = v.toLowerCase();
      const opt = [...el.options].find(o => o.value === v || clean(o.text).toLowerCase() === lv) || [...el.options].find(o => clean(o.text).toLowerCase().includes(lv));
      if (!opt) return 'ERR:Нет варианта «' + v + '». Есть: ' + [...el.options].map(o => clean(o.text)).join(', ');
      setValue(el, opt.value);
      return 'Выбрано «' + clean(opt.text) + '» в ' + describe(el) + '.';
    }
    const role = roleOf(el);
    if (role === 'checkbox' || role === 'radio' || role === 'switch') {
      const want = ['true', '1', 'да', 'yes', 'on', 'вкл'].includes(v.toLowerCase());
      const now = el.checked !== undefined && el.tagName === 'INPUT' ? el.checked : el.getAttribute('aria-checked') === 'true';
      if (now !== want) el.click();
      return (want ? 'Отмечено ' : 'Снято ') + describe(el) + '.';
    }
    el.click();
    return 'Нажато ' + describe(el) + '.';
    """#

    static let keyJS = prelude + #"""
    const el = document.activeElement || document.body;
    const k = args.key;
    const go = key(el, k);
    if (go) {
      if (k === 'Enter' && el.form) { el.form.requestSubmit ? el.form.requestSubmit() : el.form.submit(); }
      else if (k === 'Enter' && el !== document.body && el.click && roleOf(el) !== 'textbox') el.click();
      else if (k === 'Tab') {
        const all = [...document.querySelectorAll('a[href],button,input,textarea,select,[tabindex]:not([tabindex="-1"]),[contenteditable]')].filter(vis);
        const i = all.indexOf(el); const next = all[(i + 1) % all.length]; if (next) next.focus();
      } else if (k === 'Backspace' && 'value' in el && el.tagName !== 'SELECT') setValue(el, el.value.slice(0, -1));
      else if (['PageDown', 'PageUp', 'ArrowDown', 'ArrowUp', ' ', 'Space'].includes(k) && (el === document.body || !('value' in el))) {
        const s = scroller(); const step = k.startsWith('Page') || k === ' ' || k === 'Space' ? innerHeight * 0.85 : 60;
        s.scrollBy(0, (k === 'PageUp' || k === 'ArrowUp') ? -step : step);
      }
    }
    return 'Нажата клавиша ' + k + (el && el !== document.body ? ' в ' + describe(el) : '') + '.';
    """#

    static let scrollJS = prelude + #"""
    if (args.ref) {
      const el = byRef(args.ref);
      if (!el) return 'ERR:Нет элемента ' + args.ref + '.';
      el.scrollIntoView({block: 'center'});
      return 'Прокручено до ' + describe(el) + '.';
    }
    const s = scroller();
    s.scrollBy(0, (args.direction === 'up' ? -1 : 1) * (args.amount || 1) * innerHeight * 0.85);
    const max = Math.max(1, s.scrollHeight - s.clientHeight);
    return 'Прокручено: ' + Math.round(100 * s.scrollTop / max) + '% страницы.';
    """#
}
