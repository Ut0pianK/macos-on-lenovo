#!/bin/bash
set -u; INT=disk0s1; K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || { echo "마운트 실패"; exit 1; }
MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"; C="$MP/EFI/OC/config.plist"; BK="$MP/EFI/OC/backup-before-rtd3-off"
mkdir -p "$BK" && cp -p "$C" "$BK/config.plist" || exit 1
cur=$(plutil -extract $K raw -o - "$C")
new=$(echo " $cur " | perl -pe 's/ nvrtd3(?:res)?=\S+(?= )//g; s/^ +//; s/ +$//')
plutil -replace $K -string "$new" "$C" && plutil -lint "$C" >/dev/null || { cp -p "$BK/config.plist" "$C"; echo "실패 → 되돌림"; exit 1; }
echo "boot-args: $new"; sync
