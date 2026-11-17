#!/bin/bash
set -e
D=/Users/user/tweak-backup-2026-11-13/itunes; IN=/Applications/iTunes.app/Contents/MacOS/iTunes.app; B="$IN/Contents/MacOS/iTunes"
pgrep -x iTunes >/dev/null && { echo "iTunes를 먼저 종료"; exit 1; }
case "$1" in
apply) [ "$(shasum -a 256 "$B" | cut -c1-16)" = "$(shasum -a 256 "$D/iTunes.bin.orig" | cut -c1-16)" ] || cmp -s "$B" "$D/iTunes.bin.patched" || { echo "실행 파일이 예상과 다름"; exit 1; }
  cp "$D/iTunes.bin.patched" "$B" ;;
undo) cp "$D/iTunes.bin.orig" "$B" ;;
*) echo "apply|undo"; exit 1;;
esac
codesign --force --sign - --preserve-metadata=identifier,entitlements "$IN" 2>&1 | grep -v "replacing" || true
codesign --force --sign - /Applications/iTunes.app 2>&1 | grep -v "replacing" || true
codesign -v "$IN" && echo "서명 확인 OK"; echo "결과: $1 완료"
