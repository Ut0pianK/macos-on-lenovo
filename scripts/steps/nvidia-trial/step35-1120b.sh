#!/bin/bash
set -u
T=/Users/user/nvidia-trial; D=/Users/user/tweak-backup-2026-11-13/res1920; INT=disk0s1; mode=${1:-apply}
O=/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-9e5/DisplayProductID-931
NEW=$T/build/wex-0.8.0-bootseamless8-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=0aed8539fc5b0ce880028f42ba6b5f4f8caaf54646b9b02137460128762dc671
CUR_SHA=9e17e2bea497e43355c30b47831ff1458ce5ee847dbcc4155171b35620159ac1
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "마운트 실패"
OC="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')/EFI/OC"; C="$OC/config.plist"; kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-1120b"
if [ "$mode" = undo ]; then
  [ -f "$BK/config.plist" ] && [ -f "$BK/WhateverXe" ] && [ -f "$BK/override" ] || stop "백업 없음"
  cp "$BK/WhateverXe" "$kx"; cp "$BK/config.plist" "$C"; cp "$BK/override" "$O"; plutil -lint "$C"; sync; echo undone; exit 0
fi
[ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시 불일치"
[ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 7차가 아님"
plutil -lint "$D/DisplayProductID-931.1120b" >/dev/null || stop "override 형식 오류"
mkdir -p "$BK" && cp "$kx" "$BK/WhateverXe" && cp "$C" "$BK/config.plist" && cp "$O" "$BK/override" || stop "백업 실패"
cp "$NEW" "$kx" || stop "kext 쓰기 실패"
cur=$(plutil -extract $K raw -o - "$C") || stop "boot-args 읽기 실패"
case " $cur " in *" -wex-bootfade "*) new="$cur";; *) new="$cur -wex-bootfade";; esac
plutil -replace $K -string "$new" "$C" && plutil -lint "$C" || { cp "$BK/WhateverXe" "$kx"; cp "$BK/config.plist" "$C"; stop "config 실패 → 되돌림"; }
install -m 644 -o root -g wheel "$D/DisplayProductID-931.1120b" "$O" || stop "override 설치 실패"
echo "boot-args: $(plutil -extract $K raw -o - "$C" | grep -o -- '-wex-boot[a-z]*' | tr '\n' ' ')"
echo "kext $(shasum -a 256 "$kx" | cut -c1-16)"; sync; echo applied
