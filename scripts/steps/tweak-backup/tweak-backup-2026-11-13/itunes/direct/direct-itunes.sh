#!/bin/bash
set -e
D=/Users/user/tweak-backup-2026-11-13/itunes/direct; A=/Applications/iTunes.app
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
R=$(pgrep -fl "iTunes.app/Contents/MacOS/iTunes" | grep -v direct-itunes || true); [ -n "$R" ] && { echo "iTunes를 먼저 종료: $R"; exit 1; }
case "$1" in
apply)
  [ -f "$A/Contents/MacOS/iTunes.app/Contents/MacOS/iTunes" ] || { echo "지금 구조가 실행기+안쪽 iTunes 가 아님"; exit 1; }
  [ -e "$D/iTunes-wrapper.app" ] && { echo "백업이 이미 있음"; exit 1; }
  mv "$A" "$D/iTunes-wrapper.app"
  cp -Rp "$D/iTunes-wrapper.app/Contents/MacOS/iTunes.app" "$A"
  install -m 755 "$D/iTunes-wrapper.app/Contents/MacOS/libseeshim.dylib" "$A/Contents/Frameworks/libseeshim.dylib"
  P=/usr/libexec/PlistBuddy; I="$A/Contents/Info.plist"
  $P -c "Set :CFBundleShortVersionString 12.99.0" -c "Set :CFBundleVersion 12.99.0" "$I"
  $P -c "Delete :LSEnvironment" "$I" 2>/dev/null || true
  $P -c "Add :LSEnvironment dict" -c "Add :LSEnvironment:DYLD_INSERT_LIBRARIES string $A/Contents/Frameworks/libseeshim.dylib" "$I"
  codesign --force --sign - --preserve-metadata=identifier,entitlements "$A" 2>&1 | grep -v replacing || true
  codesign -v "$A" && echo "서명 OK"
  $LSR -u "$D/iTunes-wrapper.app" 2>/dev/null || true; $LSR -f "$A";;
undo)
  [ -e "$D/iTunes-wrapper.app" ] || { echo "백업 없음"; exit 1; }
  $LSR -u "$A" 2>/dev/null || true; rm -rf "$A"; mv "$D/iTunes-wrapper.app" "$A"; $LSR -f "$A";;
*) echo "apply|undo"; exit 1;;
esac
chown -R root:admin "$A" 2>/dev/null || true
echo "결과: $1 완료"
