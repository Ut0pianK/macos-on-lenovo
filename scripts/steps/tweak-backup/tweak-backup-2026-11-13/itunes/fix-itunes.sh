#!/bin/bash
set -e
D=/Users/user/tweak-backup-2026-11-13/itunes; A=/Applications/iTunes.app; W="$A/Contents/MacOS/iTunes"
case "$1" in
apply)
  cmp -s "$W" "$D/wrapper.orig" || grep -q libseeshim "$W" || { echo "래퍼가 예상과 다름"; exit 1; }
  install -m 755 "$D/libseeshim.dylib" "$A/Contents/MacOS/libseeshim.dylib"
  grep -q libseeshim "$W" || /usr/bin/sed -i '' 's|^\(    export DYLD_LIBRARY_PATH=.*\)$|\1\
    export DYLD_INSERT_LIBRARIES="${iTunes_PATH}/libseeshim.dylib"|' "$W"
  grep -q 'DYLD_INSERT_LIBRARIES' "$W" || { cp "$D/wrapper.orig" "$W"; echo "래퍼 수정 실패 → 되돌림"; exit 1; } ;;
undo)
  cp "$D/wrapper.orig" "$W"; chmod 755 "$W"; rm -f "$A/Contents/MacOS/libseeshim.dylib" ;;
*) echo "apply|undo"; exit 1;;
esac
codesign --force --sign - "$A" 2>&1 | grep -v replacing || true
cat "$W"; echo "결과: $1 완료"
