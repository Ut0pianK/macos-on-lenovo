#!/bin/bash
set -u
INT=disk0s1; mode=${1:-apply}
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "마운트 실패"
OC="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')/EFI/OC"; C="$OC/config.plist"; BK="$OC/config.plist.before-ocres"
PB=/usr/libexec/PlistBuddy
case "$mode" in
undo) [ -f "$BK" ] || stop "백업 없음"; cp "$BK" "$C";;
logoff) $PB -c "Set :Misc:Debug:Target 0" "$C";;
apply) [ -f "$BK" ] || cp -p "$C" "$BK" || stop "백업 실패"
  $PB -c "Set :UEFI:Output:Resolution 1536x960@32" -c "Set :UEFI:Output:UIScale 1" -c "Set :Misc:Debug:Target 65" -c "Set :Misc:Debug:DisplayLevel 2147483714" "$C" || { cp "$BK" "$C"; stop "쓰기 실패 → 되돌림"; };;
*) stop "apply|undo|logoff";;
esac
plutil -lint "$C" || { cp "$BK" "$C"; stop "형식 오류 → 되돌림"; }
for k in UEFI.Output.Resolution UEFI.Output.UIScale Misc.Debug.Target Misc.Debug.DisplayLevel; do echo "$k=$(plutil -extract $k raw -o - "$C")"; done
sync; echo "$mode done"
