#!/bin/bash
set -u
T=/Users/user/nvidia-trial; INT=disk0s1; mode=${1:-apply}
NEW=$T/build/wex-0.8.0-bootseamless12-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=65e094c752a64c53e124062b5b76bfb4f966689b1a30ee53af391d460162d62e
CUR_SHA=afde1511bfa16c0c40dc0abd5e0a54674a68f424bbcf6cb6eaf8e51f7848761f
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "마운트 실패"
OC="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')/EFI/OC"; kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-match"
if [ "$mode" = undo ]; then [ "$(shasum -a 256 "$BK/WhateverXe" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "백업 없음"; cp "$BK/WhateverXe" "$kx"; sync; echo undone; exit 0; fi
[ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시 불일치"
[ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 11차가 아님"
mkdir -p "$BK" && cp "$kx" "$BK/WhateverXe" || stop "백업 실패"
cp "$NEW" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$NEW_SHA" ] || { cp "$BK/WhateverXe" "$kx"; stop "쓰기 실패 → 되돌림"; }
sync; echo applied
