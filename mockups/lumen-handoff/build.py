#!/usr/bin/env python3
"""Собирает index.html из index.src.html.
[[имя|размер]] — иконка (Lucide, ISC: из Resources/Icons, недостающие — ниже), подобранная по таблице
docs/design-system/HANDOFF.md / redesign.md раздел 7. {{ec:64}} / {{ecs:22}} — знак-затмение из lumen-theme.css."""
import re, pathlib
here = pathlib.Path(__file__).parent
icons_dir = here.parent.parent / "Resources" / "Icons"
EXTRA = {
 "house": '<path d="M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8"/><path d="M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
 "thumbs-up": '<path d="M7 10v12"/><path d="M15 5.88 14 10h5.83a2 2 0 0 1 1.92 2.56l-2.33 8A2 2 0 0 1 17.5 22H4a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h2.76a2 2 0 0 0 1.79-1.11L12 2a3.13 3.13 0 0 1 3 3.88Z"/>',
 "thumbs-down": '<path d="M17 14V2"/><path d="M9 18.12 10 14H4.17a2 2 0 0 1-1.92-2.56l2.33-8A2 2 0 0 1 6.5 2H20a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2.76a2 2 0 0 0-1.79 1.11L12 22a3.13 3.13 0 0 1-3-3.88Z"/>',
 "rotate-cw": '<path d="M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/>',
 "camera": '<path d="M13.997 4a2 2 0 0 1 1.76 1.05l.486.9A2 2 0 0 0 18.003 7H20a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h1.997a2 2 0 0 0 1.759-1.048l.489-.904A2 2 0 0 1 10.004 4z"/><circle cx="12" cy="13" r="3"/>',
 "mic": '<path d="M12 19v3"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><rect x="9" y="2" width="6" height="13" rx="3"/>',
 "audio-lines": '<path d="M2 10v3"/><path d="M6 6v11"/><path d="M10 3v18"/><path d="M14 8v7"/><path d="M18 5v13"/><path d="M22 10v3"/>',
 "blocks": '<rect width="7" height="7" x="14" y="3" rx="1"/><path d="M10 21V8a1 1 0 0 0-1-1H4a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-5a1 1 0 0 0-1-1H3"/>',
 "plug": '<path d="M12 22v-5"/><path d="M15 8V2"/><path d="M17 8a1 1 0 0 1 1 1v4a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4V9a1 1 0 0 1 1-1z"/><path d="M9 8V2"/>',
 "file-search": '<path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M4.268 21a2 2 0 0 0 1.727 1H18a2 2 0 0 0 2-2V7l-5-5H6a2 2 0 0 0-2 2v3"/><path d="m9 18-1.5-1.5"/><circle cx="5" cy="14" r="3"/>',
 "share": '<path d="M12 2v13"/><path d="m16 6-4-4-4 4"/><path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/>',
 "list-filter": '<path d="M3 6h18"/><path d="M7 12h10"/><path d="M10 18h4"/>',
 "git-compare": '<circle cx="18" cy="18" r="3"/><circle cx="6" cy="6" r="3"/><path d="M13 6h3a2 2 0 0 1 2 2v7"/><path d="M11 18H8a2 2 0 0 1-2-2V9"/>',
 "cloud": '<path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z"/>',
 "briefcase-business": '<path d="M12 12h.01"/><path d="M16 6V4a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2"/><path d="M22 13a18.15 18.15 0 0 1-20 0"/><rect width="20" height="14" x="2" y="6" rx="2"/>',
 "picture-in-picture-2": '<path d="M21 9V6a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v10c0 1.1.9 2 2 2h4"/><rect width="10" height="7" x="12" y="13" rx="2"/>',
 "archive": '<rect width="20" height="5" x="2" y="3" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8"/><path d="M10 12h4"/>',
 "monitor-smartphone": '<path d="M18 8V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h8"/><path d="M10 19v-3.96 3.15"/><path d="M7 19h5"/><rect width="6" height="10" x="16" y="12" rx="2"/>',
 "book-open-check": '<path d="M12 21V7"/><path d="m16 12 2 2 4-4"/><path d="M22 6V4a1 1 0 0 0-1-1h-5a4 4 0 0 0-4 4 4 4 0 0 0-4-4H3a1 1 0 0 0-1 1v13a1 1 0 0 0 1 1h6a3 3 0 0 1 3 3 3 3 0 0 1 3-3h6a1 1 0 0 0 1-1v-1.3"/>',
}
EC_FULL = ('<span class="ec" style="--s:{s}px" aria-hidden="true"><span class="ec-glow"></span><span class="ec-streamers"></span>'
           '<span class="ec-fibers"></span><span class="ec-inner"></span><span class="ec-orbit"><span class="ec-sun"></span>'
           '<span class="ec-bloom"></span></span><span class="ec-moon"></span><span class="ec-dia"><span class="ec-tw"></span></span></span>')
EC_SMALL = ('<span class="ec sm" style="--s:{s}px" aria-hidden="true"><span class="ec-inner"></span><span class="ec-orbit">'
            '<span class="ec-sun"></span><span class="ec-bloom"></span></span><span class="ec-moon"></span></span>')
src = (here / "index.src.html").read_text(encoding="utf-8")
src = re.sub(r"\{\{ec:(\d+)\}\}", lambda m: EC_FULL.format(s=m.group(1)), src)
src = re.sub(r"\{\{ecs:(\d+)\}\}", lambda m: EC_SMALL.format(s=m.group(1)), src)
used = sorted(set(m.group(1) for m in re.finditer(r"\[\[([a-z0-9-]+)(?:\|\d+)?\]\]", src)))
sprite = ['<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>']
missing = []
for n in used:
    f = icons_dir / f"{n}.svg"
    if n in EXTRA:
        inner = EXTRA[n]
    elif f.exists():
        inner = re.search(r"<svg[^>]*>(.*)</svg>", f.read_text(encoding="utf-8"), re.S).group(1)
    else:
        missing.append(n); continue
    sprite.append(f'<symbol id="i-{n}" viewBox="0 0 24 24">{inner}</symbol>')
sprite.append("</defs></svg>")
def rep(m):
    n, s = m.group(1), m.group(2) or "20"
    return f'<svg class="ic i{s}" width="{s}" height="{s}"><use href="#i-{n}"/></svg>'
out = re.sub(r"\[\[([a-z0-9-]+)(?:\|(\d+))?\]\]", rep, src).replace("<!--SPRITE-->", "\n".join(sprite))
(here / "index.html").write_text(out, encoding="utf-8")
print("ok, icons:", len(used), "missing:", missing)
