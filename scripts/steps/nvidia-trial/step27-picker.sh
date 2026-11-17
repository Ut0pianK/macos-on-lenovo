#!/bin/bash
set -u
INT=disk0s1; mode=${1:-apply}
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "마운트 실패"
OC="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')/EFI/OC"; C="$OC/config.plist"; BK="$OC/config.plist.before-picker"
if [ "$mode" = undo ]; then [ -f "$BK" ] || stop "백업 없음"; cp "$BK" "$C"; plutil -lint "$C"; echo undone; sync; exit 0; fi
[ -f "$BK" ] || cp -p "$C" "$BK" || stop "백업 실패"
/usr/libexec/PlistBuddy -c "Set :Misc:Boot:ShowPicker false" -c "Set :Misc:Boot:PollAppleHotKeys true" "$C" || { cp "$BK" "$C"; stop "쓰기 실패 → 되돌림"; }
plutil -lint "$C" || { cp "$BK" "$C"; stop "형식 오류 → 되돌림"; }
diff <(plutil -convert xml1 -o - "$BK") <(plutil -convert xml1 -o - "$C")
sync; echo applied
