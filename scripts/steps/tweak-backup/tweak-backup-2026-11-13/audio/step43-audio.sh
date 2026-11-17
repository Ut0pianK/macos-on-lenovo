#!/bin/bash
set -u
MODE=${1:-}
D=/Users/user/tweak-backup-2026-11-13/audio
INT=disk0s1
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "EFI 마운트 실패"
MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"; OC="$MP/EFI/OC"; C="$OC/config.plist"
[ -f "$C" ] || stop "config.plist 없음"
BK="$OC/backup-before-alcverbs"

case "$MODE" in
apply)
  TS=$(date +%Y-%m-%d-%H%M%S)
  cp -Rp "$MP/EFI" "/Users/user/EFI-backup-$TS" || stop "EFI 전체 백업 실패"
  chown -R user:staff "/Users/user/EFI-backup-$TS"
  mkdir -p "$BK" && cp -p "$C" "$BK/config.plist" || stop "config 백업 실패"
  cur=$(plutil -extract $K raw -o - "$C") || stop "boot-args 읽기 실패"
  case " $cur " in *" alcverbs=1 "*) echo "alcverbs=1 이미 있음";;
    *) plutil -replace $K -string "$cur alcverbs=1" "$C" || { cp -p "$BK/config.plist" "$C"; stop "쓰기 실패 → 되돌림"; };;
  esac
  plutil -lint "$C" || { cp -p "$BK/config.plist" "$C"; stop "형식 오류 → 되돌림"; }
  echo "boot-args: $(plutil -extract $K raw -o - "$C")"
  installer -pkg "$D/SimpleHDA-HAL-1.0.1.pkg" -target / || stop "HAL 설치 실패 (EFI 변경은 유지됨)"
  codesign -v /Library/Audio/Plug-Ins/SimpleHDA/AppleHDAHALPlugIn.bundle && echo "HAL 서명 정상"
  mkdir -p /usr/local/bin && install -m 755 "$D/alc-verb" /usr/local/bin/alc-verb && echo "alc-verb 설치"
  echo "백업: ~/EFI-backup-$TS, $BK"
  ;;
undo)
  [ -f "$BK/config.plist" ] || stop "백업 없음"
  cp -p "$BK/config.plist" "$C" && plutil -lint "$C" && echo "config 되돌림"
  rm -rf /Library/Audio/Plug-Ins/SimpleHDA/AppleHDAHALPlugIn.bundle; rmdir /Library/Audio/Plug-Ins/SimpleHDA 2>/dev/null
  pkgutil --forget cn.laobamac.SimpleHDA.HAL >/dev/null 2>&1; echo "HAL 제거"
  ;;
*) stop "사용법: $0 apply|undo";;
esac
sync; echo done
