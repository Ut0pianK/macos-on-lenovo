#!/bin/bash
set -u
T=/Users/user/nvidia-trial; INT=disk0s1; mode=${1:-apply}
NEW=$T/build/wex-0.8.0-bootseamless6-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=c053faf5e644e6d0cf6f95a10ac8964d45a7a60d3572fd7fa250cc9351325cc1
CUR_SHA=87933b8b89fa76eee1b1a03210cf101432bbf0621d0b4b1bb9c3ea926f5a20e7
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "마운트 실패"
OC="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')/EFI/OC"; C="$OC/config.plist"; kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-bootseamless6"
if [ "$mode" = undo ]; then
  [ "$(shasum -a 256 "$BK/WhateverXe" | cut -d' ' -f1)" = "$CUR_SHA" ] && [ -f "$BK/config.plist" ] || stop "백업이 온전하지 않음"
  cp "$BK/WhateverXe" "$kx" && cp "$BK/config.plist" "$C" && plutil -lint "$C"; sync; echo undone; exit 0
fi
[ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시 불일치"
[ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 4차가 아님"
mkdir -p "$BK" && cp "$kx" "$BK/WhateverXe" && cp "$C" "$BK/config.plist" || stop "백업 실패"
cp "$NEW" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$NEW_SHA" ] || { cp "$BK/WhateverXe" "$kx"; stop "kext 쓰기 실패 → 되돌림"; }
/usr/libexec/PlistBuddy -c "Set :Misc:Boot:ShowPicker false" "$C" && plutil -lint "$C" || { cp "$BK/WhateverXe" "$kx"; cp "$BK/config.plist" "$C"; stop "config 쓰기 실패 → 되돌림"; }
for k in Misc.Boot.ShowPicker Misc.Boot.Timeout UEFI.Output.Resolution UEFI.Output.UIScale; do echo "$k=$(plutil -extract $k raw -o - "$C")"; done
sync; echo applied
