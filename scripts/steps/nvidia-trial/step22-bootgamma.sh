#!/bin/bash
set -u
T=/Users/user/nvidia-trial
NEW=$T/build/wex-0.8.0-bootgamma-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=48024bbc9e2de699cd6e8f7822e3755c8b1fbb706e7a9c76b3707cdf81ed0db1
CUR_SHA=21c22b28f0fae0feb339cf9b9237b8d8da0ee0bce9df72e2fc21155cbec4b3be
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
INT=disk0s1; mode=${1:-apply}
LOG=$T/logs/step22-bootgamma-$(date +%Y%m%d-%H%M%S).log
exec > >(tee -a "$LOG") 2>&1
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || { echo "!! root 필요"; exit 1; }
[ "$(diskutil info disk0 | awk -F': *' '/Device Location/{print $2}')" = Internal ] || stop "disk0 이 내장이 아님"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" || stop "마운트 실패"
MP=$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')
OC="$MP/EFI/OC"; cfg="$OC/config.plist"; kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-bootgamma"
[ -f "$cfg" ] && [ -f "$kx" ] || stop "config.plist 또는 WhateverXe 가 예상 위치에 없음"
if [ "$mode" = undo ]; then
  [ "$(shasum -a 256 "$BK/WhateverXe" | cut -d' ' -f1)" = "$CUR_SHA" ] && [ -f "$BK/config.plist" ] || stop "백업이 온전하지 않음"
  cp "$BK/WhateverXe" "$kx" && cp "$BK/config.plist" "$cfg" && plutil -lint "$cfg" || stop "복원 실패"
  echo "boot-args: $(plutil -extract $K raw -o - "$cfg")"; sync; echo undone; exit 0
fi
[ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시 불일치"
[ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 probe2 빌드가 아님"
cur=$(plutil -extract $K raw -o - "$cfg") || stop "boot-args 읽기 실패"
mkdir -p "$BK" && cp "$kx" "$BK/WhateverXe" && cp "$cfg" "$BK/config.plist" || stop "백업 실패"
cp "$NEW" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$NEW_SHA" ] || { cp "$BK/WhateverXe" "$kx"; stop "kext 쓰기 실패 → 되돌림"; }
new=$(echo " $cur " | sed 's/ -wex-nvmtl-lv / /; s/ -wex-bootgamma / /' | sed 's/^ *//; s/ *$//')" -wex-bootgamma"
plutil -replace $K -string "$new" "$cfg" && plutil -lint "$cfg" || { cp "$BK/WhateverXe" "$kx"; cp "$BK/config.plist" "$cfg"; stop "boot-args 쓰기 실패 → 되돌림"; }
echo "boot-args: $(plutil -extract $K raw -o - "$cfg")"; sync; echo applied
