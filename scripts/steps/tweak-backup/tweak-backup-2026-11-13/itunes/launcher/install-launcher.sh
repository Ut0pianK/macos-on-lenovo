#!/bin/bash
set -e
D=/Users/user/tweak-backup-2026-11-13/itunes/launcher; A=/Applications/iTunes.app
pgrep -f "$A/Contents/MacOS/iTunes.app/Contents/MacOS/iTunes" >/dev/null && { echo "iTunes를 먼저 종료"; exit 1; }
case "$1" in
apply) install -m 755 "$D/iTunes-launcher" "$A/Contents/MacOS/iTunes"; cp "$D/Info.plist" "$A/Contents/Info.plist";;
undo) install -m 755 "$D/wrapper-script.current" "$A/Contents/MacOS/iTunes"; cp "$D/Info.plist.orig" "$A/Contents/Info.plist";;
*) echo "apply|undo"; exit 1;;
esac
codesign --force --sign - "$A" 2>&1 | grep -v replacing || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$A"
codesign -v "$A/Contents/MacOS/iTunes.app" && echo "안쪽 iTunes 서명 OK"; echo "결과: $1 완료"
