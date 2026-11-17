#!/bin/bash
set -u
T=/Users/user/nvidia-trial
NEW=$T/build/wex-0.8.0-bootseamless5-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=0d7a88d64d55042a50b00298239b17029009be14ce3f99ab4aee532c367c5be0
CUR_SHA=87933b8b89fa76eee1b1a03210cf101432bbf0621d0b4b1bb9c3ea926f5a20e7
INT=disk0s1; mode=${1:-apply}
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "마운트 실패"
OC="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')/EFI/OC"; kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-bootseamless5"
if [ "$mode" = undo ]; then
  [ "$(shasum -a 256 "$BK/WhateverXe" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "백업이 온전하지 않음"
  cp "$BK/WhateverXe" "$kx"; [ -f "$BK/config.plist" ] && cp "$BK/config.plist" "$OC/config.plist"; echo undone; sync; exit 0
fi
[ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시 불일치"
[ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 bootseamless 4차가 아님"
mkdir -p "$BK" && cp "$kx" "$BK/WhateverXe" && cp "$OC/config.plist" "$BK/config.plist" || stop "백업 실패"
/usr/libexec/PlistBuddy -c "Set :Misc:Boot:TakeoffDelay 10000" "$OC/config.plist" && plutil -lint "$OC/config.plist" || { cp "$BK/config.plist" "$OC/config.plist"; stop "config 쓰기 실패 → 되돌림"; }
cp "$NEW" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$NEW_SHA" ] || { cp "$BK/WhateverXe" "$kx"; stop "쓰기 실패 → 되돌림"; }
C="$OC/config.plist"; for k in Misc.Boot.ShowPicker Misc.Boot.Timeout Misc.Boot.PollAppleHotKeys Misc.Boot.PickerMode Misc.Boot.TakeoffDelay UEFI.Input.KeySupport UEFI.Input.KeySupportMode UEFI.Input.KeyForgetThreshold UEFI.Output.Resolution UEFI.Output.UIScale; do echo "$k=$(plutil -extract $k raw -o - "$C" 2>/dev/null)"; done; plutil -extract UEFI.Drivers json -o - "$C" | tr "," "\n" | grep -o "\"Path\":\"[^\"]*\"" ; sync; echo applied
