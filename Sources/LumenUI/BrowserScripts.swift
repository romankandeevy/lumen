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
    function key(el, k, mods) {
      const codes = {Enter: 13, Escape: 27, Tab: 9, Backspace: 8, ArrowDown: 40, ArrowUp: 38, ArrowLeft: 37, ArrowRight: 39, PageDown: 34, PageUp: 33, ' ': 32, Space: 32, Delete: 46, Home: 36, End: 35};
      const name = k === 'Space' ? ' ' : k;
      const code = k.length === 1 && /[a-z]/i.test(k) ? 'Key' + k.toUpperCase() : (k === ' ' ? 'Space' : k);
      const o = Object.assign({key: name, code, keyCode: codes[k] || (k.length === 1 ? k.toUpperCase().charCodeAt(0) : 0), which: codes[k] || 0, bubbles: true, cancelable: true, composed: true}, mods || {});
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
    // filter: visible — то, что сейчас на экране; interactive — только то, что нажимается и заполняется (весь документ);
    // all — всё, и вне экрана тоже. root — метка поддерева, depth — глубина
    const out = []; let size = 0; let cut = false;
    const push = line => { if (size > args.max) { cut = true; return; } out.push(line); size += line.length + 1; };
    const onlyVisible = args.filter === 'visible', inter = args.filter === 'interactive';
    const inView = el => { const r = el.getBoundingClientRect(); return r.bottom > 0 && r.right > 0 && r.top < innerHeight && r.left < innerWidth; };
    function walk(el, depth) {
      if (cut || depth > args.depth || SKIP.has(el.tagName) || !vis(el)) return;
      const role = roleOf(el);
      const pad = '  '.repeat(Math.min(depth, 8));
      const here = !onlyVisible || inView(el);
      const shown = here && role && (INTER.has(role) || ((role === 'heading' || role === 'img') && !inter));
      if (shown) {
        let line = pad + (INTER.has(role) ? '[' + ref(el) + '] ' : '') + role + ' "' + nameOf(el, role) + '"';
        if (role === 'textbox' || role === 'searchbox') { const v = el.isContentEditable ? el.innerText : el.value; if (v) line += ' = "' + clean(v).slice(0, 80) + '"'; }
        if (role === 'checkbox' || role === 'radio' || role === 'switch') line += (el.checked || el.getAttribute('aria-checked') === 'true') ? ' ✓' : ' ☐';
        if (el.tagName === 'SELECT' && el.selectedIndex >= 0) line += ' = "' + clean(el.options[el.selectedIndex].text) + '"';
        if (el.tagName === 'INPUT' && el.type === 'file') line += ' (файл — browser_upload)';
        if (el.disabled || el.getAttribute('aria-disabled') === 'true') line += ' (неактивно)';
        push(line);
        // у ссылки, кнопки, заголовка всё внутри уже в названии
        if (role !== 'listbox' && role !== 'combobox' || el.tagName === 'SELECT') return;
      }
      if (here && !inter && !role) {
        let own = ''; for (const n of el.childNodes) if (n.nodeType === 3) own += n.textContent;
        own = clean(own);
        if (own.length > 1) push(pad + 'text "' + own.slice(0, 200) + '"');
      }
      for (const c of el.children) walk(c, depth + (shown ? 1 : 0));
      if (el.shadowRoot) for (const c of el.shadowRoot.children) walk(c, depth);
    }
    const start = args.root ? byRef(args.root) : document.body;
    if (args.root && !start) return 'ERR:Нет элемента ' + args.root + ' — прочитай страницу заново.';
    if (start) walk(start, 0);
    if (onlyVisible) {
      const d = document.scrollingElement || document.documentElement;
      const below = d.scrollHeight - d.scrollTop - innerHeight;
      if (below > 40) out.push('… ниже ещё ' + Math.round(below / innerHeight * 10) / 10 + ' экрана — browser_scroll или filter: "all"');
    }
    if (cut) out.push('… страница длиннее — browser_scroll, browser_find или browser_text');
    return out.join('\n');
    """#

    static let findJS = prelude + #"""
    const q = clean(args.query).toLowerCase();
    if (!q) return 'ERR:Пустой запрос.';
    const words = q.split(' ').filter(w => w.length > 1);
    const hits = [];
    for (const el of document.querySelectorAll('a,button,input,textarea,select,summary,label,[role],[contenteditable],[onclick],[tabindex],h1,h2,h3,h4,h5,h6,img[alt]')) {
      if (hits.length >= 20) break;
      if (!vis(el)) continue;
      const role = roleOf(el) || el.tagName.toLowerCase();
      const hay = (nameOf(el, role) + ' ' + (el.getAttribute('placeholder') || '') + ' ' + (el.value || '') + ' ' + role).toLowerCase();
      if (hay.includes(q) || (words.length > 1 && words.every(w => hay.includes(w)))) hits.push(describe(el));
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

    /// Где элемент: прокрутить к нему и вернуть центр (точки страницы) — для настоящих событий мыши
    static let locateJS = prelude + #"""
    const el = byRef(args.ref);
    if (!el) return 'ERR:нет';
    el.scrollIntoView({block: 'center', inline: 'center'});
    const r = el.getBoundingClientRect();
    return JSON.stringify({x: r.left + r.width / 2, y: r.top + r.height / 2, name: describe(el)});
    """#

    /// Нажатие из скрипта (когда панель свёрнута): кнопка, сколько раз, модификаторы
    static let clickJS = prelude + #"""
    const el = document.elementFromPoint(args.x, args.y);
    if (!el) return 'ERR:В точке ' + Math.round(args.x) + ', ' + Math.round(args.y) + ' ничего нет.';
    const m = args.modifiers || '';
    const btn = args.button === 'right' ? 2 : (args.button === 'middle' ? 1 : 0);
    const o = {bubbles: true, cancelable: true, composed: true, clientX: args.x, clientY: args.y, button: btn, buttons: 1 << btn, view: window,
               pointerType: 'mouse', isPrimary: true, shiftKey: m.includes('shift'), ctrlKey: m.includes('ctrl'), altKey: m.includes('alt') || m.includes('opt'), metaKey: m.includes('cmd') || m.includes('meta')};
    el.dispatchEvent(new PointerEvent('pointerover', o)); el.dispatchEvent(new MouseEvent('mouseover', o));
    el.dispatchEvent(new PointerEvent('pointermove', o)); el.dispatchEvent(new MouseEvent('mousemove', o));
    if (args.clicks < 1 || args.button === 'none') return describe(el);
    for (let i = 1; i <= Math.min(3, args.clicks); i++) {
      const oi = Object.assign({}, o, {detail: i});
      el.dispatchEvent(new PointerEvent('pointerdown', oi)); el.dispatchEvent(new MouseEvent('mousedown', oi));
      if (i === 1 && el.focus) el.focus({preventScroll: true});
      el.dispatchEvent(new PointerEvent('pointerup', oi)); el.dispatchEvent(new MouseEvent('mouseup', oi));
      if (btn === 2) el.dispatchEvent(new MouseEvent('contextmenu', oi));
      else if (btn === 0) { if (i === 1) el.click(); else el.dispatchEvent(new MouseEvent('click', oi)); }
      if (i === 2 && btn === 0) el.dispatchEvent(new MouseEvent('dblclick', oi));
    }
    return describe(el);
    """#

    /// Перетаскивание из скрипта: указатель и HTML5 drag&drop
    static let dragJS = prelude + #"""
    const a = document.elementFromPoint(args.ax, args.ay), b = document.elementFromPoint(args.bx, args.by);
    if (!a || !b) return 'ERR:В точке начала или конца ничего нет.';
    const p = (x, y, extra) => Object.assign({bubbles: true, cancelable: true, composed: true, clientX: x, clientY: y, button: 0, buttons: 1, pointerType: 'mouse', isPrimary: true}, extra || {});
    a.dispatchEvent(new PointerEvent('pointerdown', p(args.ax, args.ay))); a.dispatchEvent(new MouseEvent('mousedown', p(args.ax, args.ay)));
    for (let i = 1; i <= 10; i++) {
      const x = args.ax + (args.bx - args.ax) * i / 10, y = args.ay + (args.by - args.ay) * i / 10;
      const t = document.elementFromPoint(x, y) || b;
      t.dispatchEvent(new PointerEvent('pointermove', p(x, y))); t.dispatchEvent(new MouseEvent('mousemove', p(x, y)));
    }
    b.dispatchEvent(new PointerEvent('pointerup', p(args.bx, args.by))); b.dispatchEvent(new MouseEvent('mouseup', p(args.bx, args.by)));
    if (a.draggable) {
      const dt = new DataTransfer();
      a.dispatchEvent(new DragEvent('dragstart', p(args.ax, args.ay, {dataTransfer: dt})));
      b.dispatchEvent(new DragEvent('dragenter', p(args.bx, args.by, {dataTransfer: dt})));
      b.dispatchEvent(new DragEvent('dragover', p(args.bx, args.by, {dataTransfer: dt})));
      b.dispatchEvent(new DragEvent('drop', p(args.bx, args.by, {dataTransfer: dt})));
      a.dispatchEvent(new DragEvent('dragend', p(args.bx, args.by, {dataTransfer: dt})));
    }
    return 'ok';
    """#

    static let typeJS = prelude + #"""
    const el = args.ref ? byRef(args.ref) : document.activeElement;
    if (!el || el === document.body) return 'ERR:Нет поля ' + (args.ref || 'с фокусом') + ' — найди его меткой (browser_read_page).';
    el.scrollIntoView({block: 'center'});
    el.focus();
    if (el.isContentEditable) {
      if (args.clear) document.execCommand('selectAll', false);
      document.execCommand('insertText', false, args.text);
    } else if ('value' in el && el.tagName !== 'SELECT') {
      if (args.clear) setValue(el, args.text);
      else {
        const s = el.selectionStart ?? el.value.length, e = el.selectionEnd ?? el.value.length;
        setValue(el, el.value.slice(0, s) + args.text + el.value.slice(e));
        try { el.setSelectionRange(s + args.text.length, s + args.text.length); } catch (x) {}
      }
    } else return 'ERR:' + describe(el) + ' — не поле ввода.';
    if (args.submit) submit(el);
    return 'Введено в ' + describe(el) + (args.submit ? ', нажат Enter.' : '.');
    """#

    static let selectJS = prelude + #"""
    const el = byRef(args.ref);
    if (!el) return 'ERR:Нет элемента ' + args.ref + ' — прочитай страницу заново.';
    const v = clean(String(args.value));
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
    if ('value' in el && el.tagName === 'INPUT') { setValue(el, v); return 'Значение ' + v + ' в ' + describe(el) + '.'; }
    el.click();
    return 'Нажато ' + describe(el) + '.';
    """#

    /// Клавиши: «Enter», сочетание «cmd+a», последовательность «Backspace Backspace», repeat — сколько раз
    static let keyJS = prelude + #"""
    const seq = clean(args.keys).split(' ').filter(Boolean);
    if (!seq.length) return 'ERR:Какую клавишу нажать?';
    const done = [];
    for (let r = 0; r < args.repeat; r++) for (const chord of seq) {
      const parts = chord.split('+'); const k = parts.pop(); const mods = parts.map(x => x.toLowerCase());
      const el = document.activeElement || document.body;
      const cmd = mods.includes('cmd') || mods.includes('meta') || mods.includes('ctrl');
      const o = {shiftKey: mods.includes('shift'), ctrlKey: mods.includes('ctrl'), altKey: mods.includes('alt') || mods.includes('option'), metaKey: mods.includes('cmd') || mods.includes('meta')};
      const go = key(el, k, o);
      done.push(chord);
      if (!go) continue;
      const editable = 'value' in el && el.tagName !== 'SELECT' && el.type !== 'checkbox';
      if (cmd && k.toLowerCase() === 'a') { if (editable) el.select(); else if (el.isContentEditable) document.execCommand('selectAll'); else getSelection().selectAllChildren(document.body); }
      else if (k === 'Enter' && el.form && !cmd) { el.form.requestSubmit ? el.form.requestSubmit() : el.form.submit(); }
      else if (k === 'Enter' && el !== document.body && el.click && roleOf(el) !== 'textbox') el.click();
      else if (k === 'Tab') {
        const all = [...document.querySelectorAll('a[href],button,input,textarea,select,[tabindex]:not([tabindex="-1"]),[contenteditable]')].filter(vis);
        const i = all.indexOf(el); const next = all[(i + (o.shiftKey ? all.length - 1 : 1)) % all.length]; if (next) next.focus();
      } else if ((k === 'Backspace' || k === 'Delete') && editable) {
        const s = el.selectionStart ?? el.value.length, e = el.selectionEnd ?? el.value.length;
        if (s !== e) setValue(el, el.value.slice(0, s) + el.value.slice(e));
        else if (k === 'Backspace' && s > 0) { setValue(el, el.value.slice(0, s - 1) + el.value.slice(s)); try { el.setSelectionRange(s - 1, s - 1); } catch (x) {} }
      } else if (k === 'Backspace' && el.isContentEditable) document.execCommand('delete');
      else if (k === 'Escape' && el.blur && el !== document.body) {}
      else if (['PageDown', 'PageUp', 'ArrowDown', 'ArrowUp', ' ', 'Space', 'Home', 'End'].includes(k) && (el === document.body || !editable)) {
        const sc = scroller(); const step = k.startsWith('Page') || k === ' ' || k === 'Space' ? innerHeight * 0.85 : 60;
        if (k === 'Home') sc.scrollTo(0, 0); else if (k === 'End') sc.scrollTo(0, sc.scrollHeight);
        else sc.scrollBy(0, (k === 'PageUp' || k === 'ArrowUp') ? -step : step);
      } else if (k.length === 1 && !cmd && editable) {
        const s = el.selectionStart ?? el.value.length, e = el.selectionEnd ?? el.value.length;
        setValue(el, el.value.slice(0, s) + k + el.value.slice(e)); try { el.setSelectionRange(s + 1, s + 1); } catch (x) {}
      }
    }
    const el = document.activeElement;
    return 'Нажато: ' + (args.repeat > 1 ? args.repeat + ' × ' : '') + seq.join(' ') + (el && el !== document.body ? ' в ' + describe(el) : '') + '.';
    """#

    /// Прокрутка: до элемента, в точке (тот блок, что под ней) или всю страницу; вниз, вверх, влево, вправо
    static let scrollJS = prelude + #"""
    if (args.ref) {
      const el = byRef(args.ref);
      if (!el) return 'ERR:Нет элемента ' + args.ref + '.';
      el.scrollIntoView({block: 'center'});
      return 'Прокручено до ' + describe(el) + '.';
    }
    let s = scroller();
    if (args.x !== undefined) {
      let el = document.elementFromPoint(args.x, args.y);
      const horiz = args.direction === 'left' || args.direction === 'right';
      while (el && el !== document.body) {
        const st = getComputedStyle(el);
        if (horiz ? (/(auto|scroll)/.test(st.overflowX) && el.scrollWidth > el.clientWidth + 4) : (/(auto|scroll)/.test(st.overflowY) && el.scrollHeight > el.clientHeight + 4)) { s = el; break; }
        el = el.parentElement;
      }
    }
    const k = args.amount || 1;
    if (args.direction === 'left' || args.direction === 'right') s.scrollBy((args.direction === 'left' ? -1 : 1) * k * (s.clientWidth || innerWidth) * 0.85, 0);
    else s.scrollBy(0, (args.direction === 'up' ? -1 : 1) * k * Math.min(s.clientHeight || innerHeight, innerHeight) * 0.85);
    const max = Math.max(1, s.scrollHeight - s.clientHeight);
    return 'Прокручено: ' + Math.round(100 * s.scrollTop / max) + '% по вертикали.';
    """#

    /// Текст страницы: сначала основное содержимое (main, article), потом остальное
    static let textJS = #"""
    const main = document.querySelector('main, [role=main], article');
    const all = document.body ? document.body.innerText : '';
    let t = main ? main.innerText : all;
    if (main && all.length > t.length) t += '\n\n— остальное на странице —\n' + all.replace(main.innerText, '').trim();
    return ((document.title ? document.title + '\n\n' : '') + t).slice(0, 40000);
    """#

    /// Файлы в поле <input type=file> (или в зону перетаскивания)
    static let uploadJS = prelude + #"""
    let el = byRef(args.ref);
    if (!el) return 'ERR:Нет элемента ' + args.ref + ' — найди поле файла (browser_find «загрузить» или read_page).';
    const dt = new DataTransfer();
    for (const f of args.files) {
      const bin = atob(f.b64); const u = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
      dt.items.add(new File([u], f.name, {type: f.type}));
    }
    const input = el.tagName === 'INPUT' && el.type === 'file' ? el : el.querySelector('input[type=file]');
    if (input) {
      input.files = dt.files;
      input.dispatchEvent(new Event('input', {bubbles: true})); input.dispatchEvent(new Event('change', {bubbles: true}));
      return 'Загружено в ' + describe(input) + ': ' + args.files.map(f => f.name).join(', ') + '.';
    }
    const o = {bubbles: true, cancelable: true, composed: true, dataTransfer: dt};
    el.dispatchEvent(new DragEvent('dragenter', o)); el.dispatchEvent(new DragEvent('dragover', o)); el.dispatchEvent(new DragEvent('drop', o));
    return 'Брошено на ' + describe(el) + ': ' + args.files.map(f => f.name).join(', ') + '.';
    """#

    /// Журнал консоли и сети: ставится до кода страницы (в её мире), копит до 500 записей
    static let captureJS = #"""
    (() => { if (window.__lumenLog) return;
      const L = window.__lumenLog = {console: [], net: [], cr: 0, nr: 0, seen: new Set()};
      const push = (arr, item) => { arr.push(item); if (arr.length > 500) arr.shift(); };
      const str = x => { try { return typeof x === 'string' ? x : (x instanceof Error ? (x.stack || x.message) : JSON.stringify(x)); } catch (e) { return String(x); } };
      for (const lvl of ['log', 'info', 'warn', 'error', 'debug']) {
        const orig = console[lvl];
        console[lvl] = function (...a) { try { push(L.console, {level: lvl, text: a.map(str).join(' ').slice(0, 2000)}); } catch (e) {} return orig.apply(this, a); };
      }
      addEventListener('error', e => push(L.console, {level: 'error', text: (e.message || 'Ошибка') + (e.filename ? ' (' + e.filename + ':' + e.lineno + ')' : '')}));
      addEventListener('unhandledrejection', e => push(L.console, {level: 'error', text: 'Unhandled rejection: ' + str(e.reason)}));
      const of = window.fetch;
      if (of) window.fetch = async function (input, init) {
        const t0 = performance.now(); const method = (init && init.method) || (input && input.method) || 'GET';
        const url = String((input && input.url) || input); L.seen.add(url);
        try { const r = await of.apply(this, arguments); push(L.net, {method, url, status: r.status, type: r.headers.get('content-type') || '', ms: Math.round(performance.now() - t0)}); return r; }
        catch (e) { push(L.net, {method, url, status: 0, type: 'ошибка: ' + e.message, ms: Math.round(performance.now() - t0)}); throw e; }
      };
      const xo = XMLHttpRequest.prototype.open, xs = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (m, u) { this.__l = {method: m, url: String(u)}; return xo.apply(this, arguments); };
      XMLHttpRequest.prototype.send = function () {
        const t0 = performance.now(); if (this.__l) L.seen.add(new URL(this.__l.url, location.href).href);
        this.addEventListener('loadend', () => { if (this.__l) push(L.net, {method: this.__l.method, url: this.__l.url, status: this.status, type: this.getResponseHeader('content-type') || '', ms: Math.round(performance.now() - t0)}); });
        return xs.apply(this, arguments);
      };
    })();
    """#

    static let consoleJS = #"""
    const L = window.__lumenLog;
    if (!L) return 'Журнал консоли на этой странице не ведётся (страница открылась до Lumen или это не веб-страница).';
    const re = args.pattern ? new RegExp(args.pattern, 'i') : null;
    const items = L.console.slice(L.cr).filter(e => (!args.errors || e.level === 'error') && (!re || re.test(e.text)));
    L.cr = L.console.length;
    return items.length ? items.map(e => '[' + e.level + '] ' + e.text).join('\n') : 'Новых сообщений в консоли нет.';
    """#

    static let networkJS = #"""
    const L = window.__lumenLog;
    const re = args.pattern ? new RegExp(args.pattern, 'i') : null;
    const out = [];
    if (L) {
      for (const e of L.net.slice(L.nr)) out.push(e.method + ' ' + e.status + ' ' + e.url + ' — ' + e.type + ', ' + e.ms + ' мс');
      L.nr = L.net.length;
    }
    // картинки, стили, скрипты — из Performance (без кода ответа)
    const seen = L ? L.seen : new Set();
    for (const r of performance.getEntriesByType('resource')) {
      if (seen.has(r.name) || r.initiatorType === 'fetch' || r.initiatorType === 'xmlhttprequest') continue;
      seen.add(r.name);
      out.push('GET ' + (r.responseStatus || '') + ' ' + r.name + ' — ' + r.initiatorType + ', ' + Math.round(r.duration) + ' мс');
    }
    const lines = re ? out.filter(l => re.test(l)) : out;
    return lines.length ? lines.slice(-200).join('\n') : 'Новых запросов нет.';
    """#
}
