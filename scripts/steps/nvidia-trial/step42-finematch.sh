#!/bin/bash
set -u
T=/Users/user/nvidia-trial; INT=disk0s1; mode=${1:-apply}
NEW=$T/build/wex-0.8.0-bootseamless15-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=5802564959319e7b7b56303f534e7038b35e4205db52ca917b59a47aac8a116f
CUR_SHA=8b4a7bce42ae2cc4551e119b641dd151d2a3280456f46af21782809583399667
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "마운트 실패"
OC="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')/EFI/OC"; kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-finematch"
if [ "$mode" = undo ]; then [ "$(shasum -a 256 "$BK/WhateverXe" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "백업 없음"; cp "$BK/WhateverXe" "$kx"; sync; echo undone; exit 0; fi
[ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시 불일치"
[ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 14차가 아님"
mkdir -p "$BK" && cp "$kx" "$BK/WhateverXe" || stop "백업 실패"
cp "$NEW" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$NEW_SHA" ] || { cp "$BK/WhateverXe" "$kx"; stop "쓰기 실패 → 되돌림"; }
sync; echo applied
