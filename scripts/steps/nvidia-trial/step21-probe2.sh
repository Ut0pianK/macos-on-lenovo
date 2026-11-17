#!/bin/bash
set -u
T=/Users/user/nvidia-trial
NEW=$T/build/wex-0.8.0-probe2-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=21c22b28f0fae0feb339cf9b9237b8d8da0ee0bce9df72e2fc21155cbec4b3be
CUR_SHA=98fa694749e313ed82af5d76957aaeb3407649af911d72569cadc9377f850515
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
INT=disk0s1; mode=${1:-apply}
LOG=$T/logs/step21-probe2-$(date +%Y%m%d-%H%M%S).log
exec > >(tee -a "$LOG") 2>&1
echo "===== step21-probe2 $(date) ($mode) ====="
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || { echo "!! root 필요"; exit 1; }
[ "$(diskutil info disk0 | awk -F': *' '/Device Location/{print $2}')" = Internal ] || { echo "!! disk0 이 내장이 아님"; exit 1; }
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" || { echo "!! 마운트 실패"; exit 1; }
MP=$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')
OC="$MP/EFI/OC"; cfg="$OC/config.plist"; kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-probe2"
[ -f "$cfg" ] && [ -f "$kx" ] || stop "config.plist 또는 WhateverXe 가 예상 위치에 없음"
if [ "$mode" = undo ]; then
  [ "$(shasum -a 256 "$BK/WhateverXe" | cut -d' ' -f1)" = "$CUR_SHA" ] && [ -f "$BK/config.plist" ] || stop "백업이 온전하지 않음"
  cp "$BK/WhateverXe" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "kext 복원 실패"
  cur=$(plutil -extract $K raw -o - "$cfg") || stop "boot-args 읽기 실패"
  new=$(echo " $cur " | sed 's/ -wex-nvmtl-lv / /' | sed 's/^ *//; s/ *$//')
  plutil -replace $K -string "$new" "$cfg" && plutil -lint "$cfg" || stop "boot-args 복원 실패"
  echo "복원됨: $new"; sync; echo undone; exit 0
fi
[ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시 불일치"
[ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 bootprobe 빌드가 아님"
cur=$(plutil -extract $K raw -o - "$cfg") || stop "boot-args 읽기 실패"
mkdir -p "$BK" && cp "$kx" "$BK/WhateverXe" && cp "$cfg" "$BK/config.plist" && [ "$(shasum -a 256 "$BK/WhateverXe" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "백업 실패"
cp "$NEW" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$NEW_SHA" ] || { cp "$BK/WhateverXe" "$kx"; stop "kext 쓰기 실패 → 되돌림"; }
case " $cur " in *" -wex-nvmtl-lv "*) new="$cur";; *) new="$cur -wex-nvmtl-lv";; esac
plutil -replace $K -string "$new" "$cfg" && plutil -lint "$cfg" || { cp "$BK/WhateverXe" "$kx"; cp "$BK/config.plist" "$cfg"; stop "boot-args 쓰기 실패 → 되돌림"; }
echo "boot-args: $(plutil -extract $K raw -o - "$cfg")"
diff <(plutil -convert xml1 -o - "$BK/config.plist") <(plutil -convert xml1 -o - "$cfg") | head -6
sync; echo applied
