#!/bin/bash
set -u
T=/Users/user/nvidia-trial; D=/Users/user/tweak-backup-2026-11-13/res1920; INT=disk0s1; mode=${1:-apply}
O=/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-9e5/DisplayProductID-931
NEW=$T/build/wex-0.8.0-bootseamless7-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=9e17e2bea497e43355c30b47831ff1458ce5ee847dbcc4155171b35620159ac1
CUR_SHA=c053faf5e644e6d0cf6f95a10ac8964d45a7a60d3572fd7fa250cc9351325cc1
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "마운트 실패"
OC="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')/EFI/OC"; C="$OC/config.plist"; kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-res1920"
if [ "$mode" = undo ]; then
  [ -f "$BK/config.plist" ] && [ -f "$BK/WhateverXe" ] || stop "백업 없음"
  cp "$BK/WhateverXe" "$kx"; cp "$BK/config.plist" "$C"; cp "$D/DisplayProductID-931.before1920" "$O"; plutil -lint "$C"; sync; echo undone; exit 0
fi
[ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시 불일치"
[ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 6차가 아님"
plutil -lint "$D/DisplayProductID-931.1920" >/dev/null || stop "새 override 형식 오류"
mkdir -p "$BK" && cp "$kx" "$BK/WhateverXe" && cp "$C" "$BK/config.plist" || stop "백업 실패"
cp "$NEW" "$kx" || stop "kext 쓰기 실패"
/usr/libexec/PlistBuddy -c "Set :UEFI:Output:Resolution 1920x1080@32" -c "Set :UEFI:Output:UIScale 1" "$C" && plutil -lint "$C" || { cp "$BK/WhateverXe" "$kx"; cp "$BK/config.plist" "$C"; stop "config 실패 → 되돌림"; }
install -m 644 -o root -g wheel "$D/DisplayProductID-931.1920" "$O" || stop "override 설치 실패"
for k in UEFI.Output.Resolution UEFI.Output.UIScale Misc.Boot.ShowPicker; do echo "$k=$(plutil -extract $k raw -o - "$C")"; done
echo "kext $(shasum -a 256 "$kx" | cut -c1-16)"; plutil -p "$O" | grep -c bytes; sync; echo applied
