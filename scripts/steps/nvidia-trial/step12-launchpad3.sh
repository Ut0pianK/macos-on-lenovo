#!/bin/bash
set -u
T=/Users/user/nvidia-trial
NEW=$T/build/wex-0.8.0-launchpad3-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=fe3019f64bb2adb8b151d5a62f37aa9631b30263b13eab06066611feb945498b
CUR_SHA=241fa6d5f20fa792952ef7717b17e6fdaf2280a1684752b72cd8a2b86959589b
OLD_SHA=abe7c16210ae34c92e6836bc74737fa020dd6aac8b7f0b6fc1c3f63db4e60c81
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
INT=disk0s1
LOG=$T/logs/step12-launchpad3-$(date +%Y%m%d-%H%M%S).log
exec >> "$LOG" 2>&1
echo "===== step12-launchpad3 $(date) ====="
stop() { echo "!! $* — 중단"; sync; [ "${was:-1}" = 0 ] && diskutil unmount "$INT"; exit 1; }
[ "$(id -u)" = 0 ] || { echo "!! root 필요"; exit 1; }
[ "$(diskutil info disk0 | awk -F': *' '/Device Location/{print $2}')" = Internal ] || { echo "!! disk0 이 내장이 아님"; exit 1; }
was=$(mount | grep -c "^/dev/$INT ")
[ "$was" = 0 ] && { diskutil mount "$INT" || { echo "!! 마운트 실패"; exit 1; }; }
MP=$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')
OC="$MP/EFI/OC"; cfg="$OC/config.plist"; kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-launchpad"
[ -f "$cfg" ] && [ -f "$kx" ] || stop "config.plist 또는 WhateverXe 가 예상 위치에 없음"
[ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시가 빌드 때와 다름"
[ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 2단계 빌드(241fa6d5…)가 아님"
[ -f "$BK/WhateverXe" ] && [ "$(shasum -a 256 "$BK/WhateverXe" | cut -d' ' -f1)" = "$OLD_SHA" ] && plutil -lint "$BK/config.plist" >/dev/null || stop "1단계 백업이 온전하지 않음"
case " $(plutil -extract $K raw -o - "$cfg") " in *" -wex-launchpad "*) ;; *) stop "boot-args 에 -wex-launchpad 가 없음";; esac
cp "$kx" "$OC/backup-before-launchpad/WhateverXe.stage2" || stop "1단계 kext 백업 실패"
cp "$NEW" "$kx" || stop "kext 복사 실패"
[ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$NEW_SHA" ] || { cp "$OC/backup-before-launchpad/WhateverXe.stage2" "$kx"; stop "kext 쓰기 검증 실패 → 1단계 것으로 되돌림"; }
install -m 755 -o root -g wheel "$T/launchpad-reboot/launchpad-watchdog.sh" /usr/local/libexec/launchpad-watchdog.sh \
  && install -m 644 -o root -g wheel "$T/launchpad-reboot/local.launchpad-watchdog.plist" /Library/LaunchDaemons/local.launchpad-watchdog.plist \
  || { cp "$OC/backup-before-launchpad/WhateverXe.stage2" "$kx"; stop "감시 데몬 설치 실패 → kext 되돌림"; }
echo "EFI kext: $(shasum -a 256 "$kx" | cut -c1-16)…"
sync; [ "$was" = 0 ] && diskutil unmount "$INT"
echo applied
