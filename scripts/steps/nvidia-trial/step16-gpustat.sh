#!/bin/bash
set -u
T=/Users/user/nvidia-trial
NEW=$T/build/wex-0.8.0-gpustat-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=d467385b832e4fea9c471c798ecc2b901cd82ff06551ac6906bf1858e3231d97
CUR_SHA=77cbb972741d29855b99a3a8350145ac945dcf92b402ff0edd189badeb4bc535
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
INT=disk0s1; mode=${1:-apply}
LOG=$T/logs/step16-gpustat-$(date +%Y%m%d-%H%M%S).log
exec >> "$LOG" 2>&1
echo "===== step16-gpustat $(date) ($mode) ====="
stop() { echo "!! $* — 중단"; sync; [ "${was:-1}" = 0 ] && diskutil unmount "$INT"; exit 1; }
[ "$(id -u)" = 0 ] || { echo "!! root 필요"; exit 1; }
[ "$(diskutil info disk0 | awk -F': *' '/Device Location/{print $2}')" = Internal ] || { echo "!! disk0 이 내장이 아님"; exit 1; }
was=$(mount | grep -c "^/dev/$INT ")
[ "$was" = 0 ] && { diskutil mount "$INT" || { echo "!! 마운트 실패"; exit 1; }; }
MP=$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')
OC="$MP/EFI/OC"; cfg="$OC/config.plist"; kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-gpustat"
[ -f "$cfg" ] && [ -f "$kx" ] || stop "config.plist 또는 WhateverXe 가 예상 위치에 없음"
if [ "$mode" = undo ]; then
  [ "$(shasum -a 256 "$BK/WhateverXe" | cut -d' ' -f1)" = "$CUR_SHA" ] && plutil -lint "$BK/config.plist" >/dev/null || stop "백업이 온전하지 않음"
  cp "$BK/WhateverXe" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] && cp "$BK/config.plist" "$cfg" || stop "복원 실패"
  echo "복원됨(nvsafari2 빌드): $(plutil -extract $K raw -o - "$cfg")"; sync; [ "$was" = 0 ] && diskutil unmount "$INT"; echo undone; exit 0
fi
[ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시 불일치"
[ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 nvsafari2 빌드가 아님"
cur=$(plutil -extract $K raw -o - "$cfg") || stop "boot-args 읽기 실패"
case " $cur " in *" -wex-nvsafari "*) ;; *) stop "-wex-nvsafari 없음(예상과 다른 구성)";; esac
case " $cur " in *" -wex-gpustat "*) stop "이미 -wex-gpustat 있음";; esac
mkdir -p "$BK" && cp "$kx" "$BK/WhateverXe" && cp "$cfg" "$BK/config.plist" && [ "$(shasum -a 256 "$BK/WhateverXe" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "백업 실패"
N=/private/tmp/int-config.gpustat.$$
cp "$cfg" "$N" && plutil -replace $K -string "$cur -wex-gpustat" "$N" && plutil -lint "$N" >/dev/null || stop "config 편집 실패"
[ "$(diff "$cfg" "$N" | grep -c '^[<>]')" = 2 ] || stop "config 변경이 1줄이 아님"
cp "$NEW" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$NEW_SHA" ] || { cp "$BK/WhateverXe" "$kx"; stop "kext 쓰기 실패 → 되돌림"; }
cp "$N" "$cfg" && plutil -lint "$cfg" >/dev/null || { cp "$BK/WhateverXe" "$kx"; cp "$BK/config.plist" "$cfg"; stop "config 쓰기 실패 → 되돌림"; }
install -m 755 -o root -g wheel "$T/gpustat-reboot/gpustat-watchdog.sh" /usr/local/libexec/gpustat-watchdog.sh \
  && install -m 644 -o root -g wheel "$T/gpustat-reboot/local.gpustat-watchdog.plist" /Library/LaunchDaemons/local.gpustat-watchdog.plist \
  || { cp "$BK/WhateverXe" "$kx"; cp "$BK/config.plist" "$cfg"; stop "감시 데몬 설치 실패 → 되돌림"; }
echo "이후 boot-args: $(plutil -extract $K raw -o - "$cfg")"
sync; [ "$was" = 0 ] && diskutil unmount "$INT"; echo applied
