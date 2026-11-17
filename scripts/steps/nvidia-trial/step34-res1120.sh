#!/bin/bash
set -u
D=/Users/user/tweak-backup-2026-11-13/res1920; INT=disk0s1; mode=${1:-apply}
O=/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-9e5/DisplayProductID-931
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "마운트 실패"
OC="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')/EFI/OC"; C="$OC/config.plist"; BK="$OC/config.plist.before-res1120"
if [ "$mode" = undo ]; then [ -f "$BK" ] || stop "백업 없음"; cp "$BK" "$C"; cp "$D/DisplayProductID-931.1920" "$O"; plutil -lint "$C"; sync; echo undone; exit 0; fi
plutil -lint "$D/DisplayProductID-931.1120" >/dev/null || stop "override 형식 오류"
cp -p "$C" "$BK" || stop "백업 실패"
/usr/libexec/PlistBuddy -c "Set :UEFI:Output:Resolution Max" -c "Set :UEFI:Output:UIScale 2" "$C" && plutil -lint "$C" || { cp "$BK" "$C"; stop "config 실패 → 되돌림"; }
install -m 644 -o root -g wheel "$D/DisplayProductID-931.1120" "$O" || stop "override 설치 실패"
for k in UEFI.Output.Resolution UEFI.Output.UIScale Misc.Boot.ShowPicker; do echo "$k=$(plutil -extract $k raw -o - "$C")"; done
sync; echo applied
