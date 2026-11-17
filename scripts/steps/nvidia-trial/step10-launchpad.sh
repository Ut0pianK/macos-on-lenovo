#!/bin/bash
set -u
T=/Users/user/nvidia-trial
NEW=$T/build/wex-0.8.0-launchpad-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=145218cad66b7ce66846cbe3c03cc5c761b33c4efcc75067025274a73dc23bf3
OLD_SHA=abe7c16210ae34c92e6836bc74737fa020dd6aac8b7f0b6fc1c3f63db4e60c81
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
INT=disk0s1
LOG=$T/logs/step10-launchpad-$(date +%Y%m%d-%H%M%S).log
exec >> "$LOG" 2>&1
mode=${1:-apply}
echo "===== step10-launchpad $(date) ($mode) ====="
stop() { echo "!! $* — 중단"; sync; [ "${was:-1}" = 0 ] && diskutil unmount "$INT"; exit 1; }
[ "$(id -u)" = 0 ] || { echo "!! root 필요"; exit 1; }
[ "$(diskutil info disk0 | awk -F': *' '/Device Location/{print $2}')" = Internal ] || { echo "!! disk0 이 내장이 아님"; exit 1; }
was=$(mount | grep -c "^/dev/$INT ")
[ "$was" = 0 ] && { diskutil mount "$INT" || { echo "!! 마운트 실패"; exit 1; }; }
MP=$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')
OC="$MP/EFI/OC"; cfg="$OC/config.plist"; kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"
BK="$OC/backup-before-launchpad"
[ -f "$cfg" ] && [ -f "$kx" ] || stop "config.plist 또는 WhateverXe 가 예상 위치에 없음"

if [ "$mode" = undo ]; then
  [ -f "$BK/config.plist" ] && [ -f "$BK/WhateverXe" ] || stop "백업($BK)이 없음"
  [ "$(shasum -a 256 "$BK/WhateverXe" | cut -d' ' -f1)" = "$OLD_SHA" ] || stop "백업 kext 해시가 다름"
  plutil -lint "$BK/config.plist" >/dev/null || stop "백업 config 가 손상됨"
  cp "$BK/WhateverXe" "$kx" && cp "$BK/config.plist" "$cfg" || stop "복원 복사 실패"
  echo "복원됨: kext $(shasum -a 256 "$kx" | cut -c1-12), boot-args: $(plutil -extract $K raw -o - "$cfg")"
  sync; [ "$was" = 0 ] && diskutil unmount "$INT"; echo undone; exit 0
fi

[ "$mode" = apply ] || stop "알 수 없는 모드"
[ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시가 빌드 때와 다름"
cur_sha=$(shasum -a 256 "$kx" | cut -d' ' -f1); echo "EFI 의 현재 WhateverXe: $cur_sha"
[ "$cur_sha" = "$OLD_SHA" ] || stop "EFI 의 WhateverXe 가 userpatch 빌드(abe7c162…)가 아님"
cur=$(plutil -extract $K raw -o - "$cfg") || stop "boot-args 읽기 실패"; echo "이전 boot-args: $cur"
case " $cur " in *" -wex-launchpad "*) stop "이미 -wex-launchpad 가 있음";; esac
case " $cur " in *" -wex-userpatch "*) ;; *) stop "-wex-userpatch 가 없음(예상과 다른 구성)";; esac
FB=/Users/user/EFI-backup-$(date +%Y-%m-%d-%H%M%S)
cp -R "$MP/EFI" "$FB" && chown -R user:staff "$FB" || stop "EFI 전체 백업 실패"
echo "EFI 전체 백업: $FB"
mkdir -p "$BK" && cp "$kx" "$BK/WhateverXe" && cp "$cfg" "$BK/config.plist" || stop "EFI 내 백업 실패"
[ "$(shasum -a 256 "$BK/WhateverXe" | cut -d' ' -f1)" = "$OLD_SHA" ] || stop "EFI 내 백업 검증 실패"
N=/private/tmp/int-config.launchpad.$$
cp "$cfg" "$N" && plutil -replace $K -string "$cur -wex-launchpad" "$N" && plutil -lint "$N" >/dev/null || stop "config 편집 실패 (EFI 는 그대로)"
[ "$(diff "$cfg" "$N" | grep -c '^[<>]')" = 2 ] || stop "config 변경이 1줄이 아님 (EFI 는 그대로)"
cp "$NEW" "$kx" || stop "kext 복사 실패 → bash $0 undo 필요"
[ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$NEW_SHA" ] || { cp "$BK/WhateverXe" "$kx"; stop "kext 쓰기 검증 실패 → 원래 것으로 되돌림"; }
cp "$N" "$cfg" && plutil -lint "$cfg" >/dev/null || { cp "$BK/WhateverXe" "$kx"; cp "$BK/config.plist" "$cfg"; stop "config 쓰기 실패 → 둘 다 되돌림"; }
echo "이후 boot-args: $(plutil -extract $K raw -o - "$cfg")"
install -m 755 -o root -g wheel "$T/launchpad-reboot/launchpad-watchdog.sh" /usr/local/libexec/launchpad-watchdog.sh \
  && install -m 644 -o root -g wheel "$T/launchpad-reboot/local.launchpad-watchdog.plist" /Library/LaunchDaemons/local.launchpad-watchdog.plist \
  || { cp "$BK/WhateverXe" "$kx"; cp "$BK/config.plist" "$cfg"; stop "감시 데몬 설치 실패 → EFI 되돌림"; }
sync; [ "$was" = 0 ] && diskutil unmount "$INT"
echo applied
