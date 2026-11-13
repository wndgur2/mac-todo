#!/usr/bin/env bash
# Todo.app 빌드 (Apple Silicon + Intel 유니버설)
#   ./build.sh            → build/Todo.app
#   ./build.sh install    → /Applications/Todo.app 에도 설치
#   ./build.sh dist       → dist/Todo.dmg (배포용 디스크 이미지)
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --triple arm64-apple-macosx14.0
swift build -c release --triple x86_64-apple-macosx14.0

ICNS=Resources/AppIcon.icns
if [ ! -f "$ICNS" ]; then
  TMP=$(mktemp -d)
  swift scripts/make_icon.swift "$TMP/icon.png"
  SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$ICNS"
  rm -rf "$TMP"
fi

APP=build/Todo.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
  .build/arm64-apple-macosx/release/Todo \
  .build/x86_64-apple-macosx/release/Todo \
  -output "$APP/Contents/MacOS/Todo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Todo"))"

case "${1:-}" in
  install)
    pkill -x Todo 2>/dev/null || true
    rm -rf /Applications/Todo.app
    cp -R "$APP" /Applications/Todo.app
    echo "Installed /Applications/Todo.app"
    ;;
  dist)
    mkdir -p dist
    STAGE=$(mktemp -d)
    cp -R "$APP" "$STAGE/Todo.app"
    ln -s /Applications "$STAGE/Applications"
    rm -f dist/Todo.dmg
    hdiutil create -volname "Todo" -srcfolder "$STAGE" -ov -format UDZO dist/Todo.dmg >/dev/null
    rm -rf "$STAGE"
    echo "Packaged dist/Todo.dmg ($(du -h dist/Todo.dmg | cut -f1))"
    ;;
esac
