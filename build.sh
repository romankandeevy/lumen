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
# иконка (tools/make-icon.swift → Icon Composer → actool): собирается один раз, пока не поменялся скрипт
mkdir -p build
if [ ! -f build/icon-out/Assets.car ] || [ tools/make-icon.swift -nt build/icon-out/Assets.car ]; then
    echo "==> иконка"
    rm -rf build/icon-out && mkdir -p build/icon-out
    swift tools/make-icon.swift >/dev/null
    xcrun actool build/AppIcon.icon --compile build/icon-out --platform macosx \
        --minimum-deployment-target 14.0 --app-icon AppIcon \
        --output-partial-info-plist build/icon-out/partial.plist >/dev/null
fi
echo "==> swift build"
swift build -c release --product Lumen
swift build -c release --product lumen-mcp
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Lumen" "$APP/Contents/MacOS/Lumen"
# помощник памяти: claude запускает его как MCP-сервер
cp "$BIN/lumen-mcp" "$APP/Contents/MacOS/lumen-mcp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Fonts Resources/Icons "$APP/Contents/Resources/"
cp build/icon-out/AppIcon.icns build/icon-out/Assets.car "$APP/Contents/Resources/"
# редактор макетов (OpenPencil, MIT): собирается отдельно tools/design/build.sh, без него макетов просто нет
if [ -f build/design/index.html ]; then
    ditto build/design "$APP/Contents/Resources/Design"
else
    echo "==> нет build/design — макеты не войдут в сборку (tools/design/build.sh)"
fi
# 3D-редактор (three.js editor, MIT): tools/model3d/build.sh
if [ -f build/model3d/editor/index.html ]; then
    ditto build/model3d "$APP/Contents/Resources/Model3D"
else
    echo "==> нет build/model3d — 3D не войдёт в сборку (tools/model3d/build.sh)"
fi
# видео (HyperFrames, Apache-2.0): сам движок берётся через npx при первом ролике, в сборку — только справочник для агента
ditto tools/video/guide "$APP/Contents/Resources/VideoGuide"
cp tools/video/LICENSE-HyperFrames.txt "$APP/Contents/Resources/VideoGuide/"
# ресурсы пакетов (GRDB кладёт свой бандл с PrivacyInfo)
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
# автообновление: Sparkle.framework рядом с программой (rpath @executable_path/../Frameworks)
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# Постоянная подпись, как у остальных приложений набора (Связка ключей не спрашивает пароль после каждой сборки);
# если её нет — временная.
SIGN_ID="-"
security find-identity -v -p codesigning 2>/dev/null | grep -q "Local Dev Signing" && SIGN_ID="Local Dev Signing"
codesign --force --sign "$SIGN_ID" "$APP/Contents/MacOS/lumen-mcp"
# Sparkle подписываем изнутри наружу: службы, помощник установки, сам фреймворк
SP="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for x in "$SP"/XPCServices/*.xpc "$SP/Autoupdate" "$SP/Updater.app"; do
    [ -e "$x" ] && codesign --force --sign "$SIGN_ID" "$x"
done
codesign --force --sign "$SIGN_ID" "$APP/Contents/Frameworks/Sparkle.framework"
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
