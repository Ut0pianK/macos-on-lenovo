#!/bin/bash
set -u
INT=disk0s1
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "마운트 실패"
OC="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')/EFI/OC"; C="$OC/config.plist"; kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"
V4=$OC/backup-before-bootseamless5/WhateverXe
[ "$(shasum -a 256 "$V4" | cut -d' ' -f1)" = 87933b8b89fa76eee1b1a03210cf101432bbf0621d0b4b1bb9c3ea926f5a20e7 ] || stop "4차 kext 백업 없음"
cp -p "$C" "$OC/config.plist.before-settle" && cp -p "$kx" "$OC/WhateverXe.before-settle" || stop "백업 실패"
cp "$V4" "$kx" || stop "kext 복귀 실패"
/usr/libexec/PlistBuddy -c "Set :UEFI:Output:Resolution Max" -c "Set :UEFI:Output:UIScale 2" -c "Set :Misc:Debug:Target 0" \
  -c "Set :Misc:Boot:ShowPicker true" -c "Set :Misc:Boot:Timeout 1" -c "Set :Misc:Boot:TakeoffDelay 0" "$C" || { cp "$OC/config.plist.before-settle" "$C"; stop "config 쓰기 실패 → 되돌림"; }
plutil -lint "$C" || { cp "$OC/config.plist.before-settle" "$C"; stop "형식 오류 → 되돌림"; }
for k in UEFI.Output.Resolution UEFI.Output.UIScale Misc.Debug.Target Misc.Boot.ShowPicker Misc.Boot.Timeout Misc.Boot.PollAppleHotKeys Misc.Boot.TakeoffDelay; do echo "$k=$(plutil -extract $k raw -o - "$C")"; done
echo "kext: $(shasum -a 256 "$kx" | cut -c1-16)"; echo "boot-args: $(plutil -extract NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args raw -o - "$C" | grep -o -- '-wex-boot[a-z]*' | tr '\n' ' ')"
sync; echo settled
