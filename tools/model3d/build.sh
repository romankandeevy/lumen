#!/bin/bash
# 3D-редактор в браузере Lumen — редактор three.js (MIT, github.com/mrdoob/three.js, папка editor/).
# Берёт релиз r186, накладывает lumen-3d.patch (мост window.lumen3D для агента, русский язык интерфейса)
# и кладёт в build/model3d (editor/, build/, examples/jsm/). ./build.sh копирует в Lumen.app/Contents/Resources/Model3D.
#
#   tools/model3d/build.sh        нужен только git; ~20 МБ, сборки нет — редактор работает из исходников
set -euo pipefail
cd "$(dirname "$0")/../.."
TAG=r186
SRC=build/model3d-src
OUT=build/model3d
if [ ! -d "$SRC/.git" ]; then
    git clone --depth 1 --branch "$TAG" --filter=blob:none --sparse https://github.com/mrdoob/three.js.git "$SRC"
    git -C "$SRC" sparse-checkout set --no-cone /editor/ /build/ /examples/jsm/ /LICENSE
fi
git -C "$SRC" checkout -f "$TAG"
git -C "$SRC" clean -fdq
git -C "$SRC" apply "$PWD/tools/model3d/lumen-3d.patch"
rm -rf "$OUT"
mkdir -p "$OUT/examples"
cp -R "$SRC/editor" "$SRC/build" "$OUT/"
cp -R "$SRC/examples/jsm" "$OUT/examples/jsm"
# офлайн-кэш PWA не нужен: страницу отдаёт сам Lumen
rm -f "$OUT/editor/sw.js"
cp tools/model3d/LICENSE-three.js.txt "$OUT/LICENSE-three.js.txt"
echo "==> 3D-редактор: $OUT ($(du -sh "$OUT" | cut -f1))"
