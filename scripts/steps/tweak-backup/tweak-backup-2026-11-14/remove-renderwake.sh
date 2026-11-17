#!/bin/bash
set -u; MODE=${1:-}; K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
[ "$(id -u)" = 0 ] || { echo "root 필요"; exit 1; }
mount | grep -q "^/dev/disk0s1 " || diskutil mount disk0s1 >/dev/null || exit 1
MP="$(diskutil info disk0s1 | awk -F': *' '/Mount Point/{print $2}')"; C="$MP/EFI/OC/config.plist"; BK="$MP/EFI/OC/backup-before-renderwake-off"
case "$MODE" in
apply) mkdir -p "$BK" && cp -p "$C" "$BK/config.plist" || exit 1
  cur=$(plutil -extract $K raw -o - "$C"); new=$(echo " $cur " | perl -pe 's/ -wex-tgl-hold-render-wake(?= )//g; s/^ +//; s/ +$//')
  plutil -replace $K -string "$new" "$C" && plutil -lint "$C" >/dev/null || { cp -p "$BK/config.plist" "$C"; echo "실패 → 되돌림"; exit 1; }
  echo "boot-args: $new" ;;
undo) cp -p "$BK/config.plist" "$C" && echo "되돌림: $(plutil -extract $K raw -o - "$C")" ;;
*) echo "사용법: $0 apply|undo"; exit 1 ;;
esac; sync
