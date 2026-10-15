#!/bin/bash
# Сборка Lumen.app (SwiftUI, Swift Package). Нужен Xcode или Command Line Tools.
#
#   ./build.sh          собрать build/Lumen.app
#   ./build.sh run      собрать и открыть из build/
#   ./build.sh install  собрать, положить в /Applications (Программы) и открыть
#   ./build.sh test     тесты (живые, на настоящем claude: LUMEN_LIVE=1 ./build.sh test)
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = test ]; then
    swift test
    exit
fi

APP="build/Lumen.app"
echo "==> swift build"
swift build -c release --product Lumen
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Lumen" "$APP/Contents/MacOS/Lumen"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Fonts "$APP/Contents/Resources/"
# ресурсы пакетов (GRDB кладёт свой бандл с PrivacyInfo)
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
# Постоянная подпись, как у остальных приложений набора (Связка ключей не спрашивает пароль после каждой сборки);
# если её нет — временная.
SIGN_ID="-"
security find-identity -v -p codesigning 2>/dev/null | grep -q "Local Dev Signing" && SIGN_ID="Local Dev Signing"
codesign --force --sign "$SIGN_ID" "$APP"
echo "==> готово: $APP"

quit_lumen() {
    pgrep -xq Lumen || return 0
    osascript -e 'quit app id "com.roman.lumen"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6; do pgrep -xq Lumen || return 0; sleep 0.5; done
    pkill -x Lumen || true
}

case "${1:-}" in
    install)
        quit_lumen
        rm -rf "/Applications/Lumen.app"
        cp -R "$APP" /Applications/
        echo "==> установлено: /Applications/Lumen.app"
        open /Applications/Lumen.app
        ;;
    run)
        quit_lumen
        open "$APP"
        ;;
esac
