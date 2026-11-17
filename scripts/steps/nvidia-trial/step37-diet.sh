#!/bin/bash
set -u
T=/Users/user/nvidia-trial; INT=disk0s1; mode=${1:-apply}
ARC=/Users/user/EFI-archive-2026-11-13
NEW=$T/build/wex-0.8.0-bootseamless10-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=75a779ec83473eaeef42fbbcf1d9472e90e28491386b7107bea1a5ef7d5a1285
CUR_SHA=40e5baf0577abe00c81feed982c80e9a5fc9a23f07a96ab6578e3fca2f235a2a
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "마운트 실패"
MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"; OC="$MP/EFI/OC"; C="$OC/config.plist"; kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-diet"
if [ "$mode" = undo ]; then
  [ -f "$BK/config.plist" ] && [ -f "$BK/WhateverXe" ] || stop "백업 없음"
  cp "$BK/WhateverXe" "$kx"; cp "$BK/config.plist" "$C"; plutil -lint "$C"; sync; echo undone; exit 0
fi
[ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시 불일치"
[ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 9차가 아님"
mkdir -p "$ARC/OC" "$ARC/root" || stop "보관함 생성 실패"
cd "$OC" || stop "OC 폴더 없음"
moved=0
for f in backup-before-* config.plist.bak-* config.plist.before-* WhateverXe.before-settle; do
  [ -e "$f" ] || continue
  cp -Rp "$f" "$ARC/OC/" || stop "복사 실패: $f"
  diff -rq "$f" "$ARC/OC/$f" >/dev/null || stop "대조 불일치: $f"
  rm -rf "$f" && moved=$((moved+1))
done
for f in "$MP"/opencore-*.txt; do [ -e "$f" ] || continue; cp -p "$f" "$ARC/root/" && cmp -s "$f" "$ARC/root/$(basename "$f")" && rm -f "$f"; done
chown -R 501:20 "$ARC"
echo "옮긴 항목: $moved, 보관함: $(du -sh "$ARC" | cut -f1)"
mkdir -p "$BK" && cp "$kx" "$BK/WhateverXe" && cp "$C" "$BK/config.plist" || stop "백업 실패"
cp "$NEW" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$NEW_SHA" ] || { cp "$BK/WhateverXe" "$kx"; stop "kext 쓰기 실패 → 되돌림"; }
cur=$(plutil -extract $K raw -o - "$C") || stop "boot-args 읽기 실패"
new=$(echo " $cur " | sed 's/ -wex-bootprobe / /; s/ -wex-tgl-prog-off / /' | sed 's/^ *//; s/ *$//')" -wex-tgl-prog-off"
plutil -replace $K -string "$new" "$C" && plutil -lint "$C" || { cp "$BK/WhateverXe" "$kx"; cp "$BK/config.plist" "$C"; stop "config 실패 → 되돌림"; }
echo "boot-args: $(plutil -extract $K raw -o - "$C")"
ls "$OC"; df -h "$MP" | tail -1; sync; echo applied
