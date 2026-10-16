#!/bin/bash
# Выпуск версии Lumen на GitHub (docs/versions.md).
#
#   tools/release.sh 1.0          стабильная: релиз Latest, в ленте без канала
#   tools/release.sh 1.0.1 beta   бета: Pre-release, в ленте канал beta
#
# Что делает: ставит номер в Info.plist, собирает build/Lumen.app, пакует zip,
# подписывает его ключом EdDSA из Связки ключей (generate_keys --account lumen),
# дописывает версию в appcast.xml, коммитит, ставит тег, отправляет и создаёт релиз через gh.
# Заметки к релизу — docs/releases/<версия>.md (если файла нет, скрипт остановится).
#
# Нотаризации здесь нет: для неё нужен платный Developer ID. Без него при первом запуске
# скачанного Lumen macOS спросит «Открыть всё равно» (Системные настройки → Защита).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?номер версии, например 1.0 или 1.0.1}"
CHANNEL="${2:-stable}"
NOTES="docs/releases/$VERSION.md"
TAG="v$VERSION"
case "$VERSION" in *.*.*) ;; *) TAG="v$VERSION.0" ;; esac

[ -f "$NOTES" ] || { echo "нет заметок $NOTES"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "сначала закоммить правки"; exit 1; }
git rev-parse "$TAG" >/dev/null 2>&1 && { echo "тег $TAG уже есть"; exit 1; }

# номер сборки растёт с каждым релизом: Sparkle сравнивает именно его
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Resources/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $BUILD" Resources/Info.plist

./build.sh
ZIP="build/Lumen-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/Lumen.app "$ZIP"

SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
SIG=$("$SPARKLE_BIN/sign_update" --account lumen "$ZIP")   # sparkle:edSignature="…" length="…"
URL="https://github.com/romankandeevy/lumen/releases/download/$TAG/Lumen-$VERSION.zip"
CHANNEL_TAG=""
[ "$CHANNEL" = beta ] && CHANNEL_TAG="<sparkle:channel>beta</sparkle:channel>"

python3 - "$VERSION" "$BUILD" "$URL" "$SIG" "$CHANNEL_TAG" "$TAG" <<'EOF'
import io, sys, email.utils
version, build, url, sig, channel, tag = sys.argv[1:]
item = f"""        <item>
            <title>Lumen {version}</title>
            <pubDate>{email.utils.formatdate(localtime=True)}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink>https://github.com/romankandeevy/lumen/releases/tag/{tag}</sparkle:releaseNotesLink>
            {channel}
            <enclosure url="{url}" {sig} type="application/octet-stream"/>
        </item>
"""
p = "appcast.xml"
s = io.open(p, encoding="utf-8").read()
s = s.replace("        <language>ru</language>\n", "        <language>ru</language>\n" + item, 1)
io.open(p, "w", encoding="utf-8").write(s)
EOF

git add Resources/Info.plist appcast.xml
git commit -m "$VERSION — выпуск"
git tag "$TAG"
git push origin HEAD "$TAG"

PRE=""
[ "$CHANNEL" = beta ] && PRE="--prerelease"
gh release create "$TAG" "$ZIP" --title "Lumen $VERSION" --notes-file "$NOTES" $PRE
echo "==> выпущено: $TAG ($CHANNEL)"
