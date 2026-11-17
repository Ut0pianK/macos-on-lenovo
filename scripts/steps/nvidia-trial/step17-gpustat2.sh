#!/bin/bash
set -u
T=/Users/user/nvidia-trial
NEW=$T/build/wex-0.8.0-gpustat2-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=b6dfac67fce1a646b4ef25f66358477da9af8d4a377522e4a34a6a159e191cb9
CUR_SHA=d467385b832e4fea9c471c798ecc2b901cd82ff06551ac6906bf1858e3231d97
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
INT=disk0s1; mode=${1:-apply}
LOG=$T/logs/step17-gpustat2-$(date +%Y%m%d-%H%M%S).log
exec >> "$LOG" 2>&1
echo "===== step17-gpustat2 $(date) ($mode) ====="
stop() { echo "!! $* — 중단"; sync; [ "${was:-1}" = 0 ] && diskutil unmount "$INT"; exit 1; }
[ "$(id -u)" = 0 ] || { echo "!! root 필요"; exit 1; }
[ "$(diskutil info disk0 | awk -F': *' '/Device Location/{print $2}')" = Internal ] || { echo "!! disk0 이 내장이 아님"; exit 1; }
was=$(mount | grep -c "^/dev/$INT ")
[ "$was" = 0 ] && { diskutil mount "$INT" || { echo "!! 마운트 실패"; exit 1; }; }
MP=$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')
OC="$MP/EFI/OC"; cfg="$OC/config.plist"; kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-gpustat2"
[ -f "$cfg" ] && [ -f "$kx" ] || stop "config.plist 또는 WhateverXe 가 예상 위치에 없음"
if [ "$mode" = undo ]; then
  [ "$(shasum -a 256 "$BK/WhateverXe" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "백업이 온전하지 않음"
  cp "$BK/WhateverXe" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "복원 실패"
  echo "복원됨(gpustat 진단 빌드)"; sync; [ "$was" = 0 ] && diskutil unmount "$INT"; echo undone; exit 0
fi
[ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시 불일치"
[ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 gpustat 진단 빌드가 아님"
cur=$(plutil -extract $K raw -o - "$cfg") || stop "boot-args 읽기 실패"
case " $cur " in *" -wex-gpustat "*) ;; *) stop "-wex-gpustat 없음(예상과 다른 구성)";; esac
mkdir -p "$BK" && cp "$kx" "$BK/WhateverXe" && [ "$(shasum -a 256 "$BK/WhateverXe" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "백업 실패"
cp "$NEW" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$NEW_SHA" ] || { cp "$BK/WhateverXe" "$kx"; stop "kext 쓰기 실패 → 되돌림"; }
install -m 755 -o root -g wheel "$T/gpustat2-reboot/gpustat2-watchdog.sh" /usr/local/libexec/gpustat2-watchdog.sh \
  && install -m 644 -o root -g wheel "$T/gpustat2-reboot/local.gpustat2-watchdog.plist" /Library/LaunchDaemons/local.gpustat2-watchdog.plist \
  || { cp "$BK/WhateverXe" "$kx"; stop "감시 데몬 설치 실패 → 되돌림"; }
echo "boot-args(변경 없음): $cur"
sync; [ "$was" = 0 ] && diskutil unmount "$INT"; echo applied
