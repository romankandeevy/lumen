#!/bin/bash
# Редактор макетов «как Фигма» внутри браузера Lumen — OpenPencil (MIT, github.com/open-pencil/open-pencil).
# Собирает его веб-версию с мостом для Lumen (lumen-bridge.patch: window.lumenDesign — те же команды, что у его MCP)
# и кладёт в build/design. ./build.sh копирует её в Lumen.app/Contents/Resources/Design.
#
#   tools/design/build.sh        нужен bun (npm install -g bun); сборка ~3 минуты, 38 МБ
set -euo pipefail
cd "$(dirname "$0")/../.."
COMMIT=b45526406e5d20cf0c9c03608f68ceea4306f590   # OpenPencil 0.16.0+, проверено с Lumen 26.10
SRC=build/design-src
OUT=build/design
if [ ! -d "$SRC/.git" ]; then
    git clone https://github.com/open-pencil/open-pencil.git "$SRC"
fi
git -C "$SRC" fetch --depth 1 origin "$COMMIT" 2>/dev/null || true
git -C "$SRC" checkout -f "$COMMIT"
git -C "$SRC" clean -fdq -e node_modules
git -C "$SRC" apply "$PWD/tools/design/lumen-bridge.patch"
(cd "$SRC" && bun install && VITE_OPENPENCIL_CLOUD=off bun run build:packages && VITE_OPENPENCIL_CLOUD=off bunx vite build)
rm -rf "$OUT"
cp -R "$SRC/dist" "$OUT"
# офлайн-кэш PWA не нужен: страницу отдаёт сам Lumen
rm -f "$OUT/sw.js" "$OUT"/workbox-*.js
cp tools/design/LICENSE-OpenPencil.txt "$OUT/LICENSE-OpenPencil.txt"
echo "==> редактор макетов: $OUT ($(du -sh "$OUT" | cut -f1))"
