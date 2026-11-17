#!/bin/bash
set -e
A=/Applications/iTunes.app; D=/Users/user/tweak-backup-2026-11-13/itunes
case "$1" in
apply) cp "$A/Contents/Frameworks/libseeshim.dylib" "$D/clean/libseeshim.v2.installed" 2>/dev/null || true; install -m 755 "$D/clean/libseeshim.v3.dylib" "$A/Contents/Frameworks/libseeshim.dylib";;
undo) install -m 755 "$D/clean/libseeshim.v2.installed" "$A/Contents/Frameworks/libseeshim.dylib";;
*) echo "apply|undo"; exit 1;;
esac
codesign --force --sign - --preserve-metadata=identifier,entitlements "$A" 2>&1 | grep -v replacing || true
codesign -v "$A" && echo "서명 OK"; echo "결과: $1 완료"
