#!/bin/bash
set -u
T=/Users/user/nvidia-trial
NEW=$T/build/wex-0.8.0-bootseamless4-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=87933b8b89fa76eee1b1a03210cf101432bbf0621d0b4b1bb9c3ea926f5a20e7
CUR_SHA=e99f1d4e45448a93c2f9cac0865280e492d3a13d2c59cc6c86338d4cc1fe4e3c
INT=disk0s1; mode=${1:-apply}
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "마운트 실패"
OC="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')/EFI/OC"; kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-bootseamless4"
if [ "$mode" = undo ]; then
  [ "$(shasum -a 256 "$BK/WhateverXe" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "백업이 온전하지 않음"
  cp "$BK/WhateverXe" "$kx"; echo undone; sync; exit 0
fi
[ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시 불일치"
[ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 bootseamless 3차가 아님"
mkdir -p "$BK" && cp "$kx" "$BK/WhateverXe" || stop "백업 실패"
cp "$NEW" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$NEW_SHA" ] || { cp "$BK/WhateverXe" "$kx"; stop "쓰기 실패 → 되돌림"; }
C="$OC/config.plist"; for k in Misc.Boot.ShowPicker Misc.Boot.Timeout Misc.Boot.PollAppleHotKeys Misc.Boot.PickerMode Misc.Boot.TakeoffDelay UEFI.Input.KeySupport UEFI.Input.KeySupportMode UEFI.Input.KeyForgetThreshold UEFI.Output.Resolution UEFI.Output.UIScale; do echo "$k=$(plutil -extract $k raw -o - "$C" 2>/dev/null)"; done; plutil -extract UEFI.Drivers json -o - "$C" | tr "," "\n" | grep -o "\"Path\":\"[^\"]*\"" ; sync; echo applied
