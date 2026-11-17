#!/bin/bash
set -u
MODE=${1:-}; INT=disk0s1; K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "EFI 마운트 실패"
MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"; C="$MP/EFI/OC/config.plist"; BK="$MP/EFI/OC/backup-before-i2c"
cur=$(plutil -extract $K raw -o - "$C") || stop "boot-args 읽기 실패"
case "$MODE" in
apply)
  TS=$(date +%Y-%m-%d-%H%M%S); cp -Rp "$MP/EFI" "/Users/user/EFI-backup-$TS" && chown -R user:staff "/Users/user/EFI-backup-$TS" || stop "EFI 백업 실패"
  mkdir -p "$BK" && cp -p "$C" "$BK/config.plist" || stop "config 백업 실패"
  new=$(echo " $cur " | sed -e 's/ -vi2c-force-polling / /g' -e 's/^ *//' -e 's/ *$//')
  plutil -replace $K -string "$new" "$C" && plutil -lint "$C" >/dev/null || { cp -p "$BK/config.plist" "$C"; stop "쓰기 실패 → 되돌림"; }
  echo "백업 ~/EFI-backup-$TS"; ;;
undo)
  case " $cur " in *" -vi2c-force-polling "*) echo "이미 있음";; *) plutil -replace $K -string "$cur -vi2c-force-polling" "$C" && plutil -lint "$C" >/dev/null || stop "되돌리기 실패";; esac ;;
*) stop "사용법: $0 apply|undo";;
esac
echo "boot-args: $(plutil -extract $K raw -o - "$C")"; sync
