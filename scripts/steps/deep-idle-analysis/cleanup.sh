#!/bin/bash
set -u
U=/Users/user; TS=$(date +%Y-%m-%d-%H%M%S); AR=$U/EFI-보관; O=$U/deep-idle-analysis/cleanup.txt
echo "# $(date '+%F %T')" > $O
mount | grep -q "^/dev/disk0s1 " || diskutil mount disk0s1 >/dev/null || { echo "EFI 마운트 실패" >> $O; exit 1; }
MP="$(diskutil info disk0s1 | awk -F': *' '/Mount Point/{print $2}')"
B=$U/EFI-backup-$TS
cp -Rp "$MP/EFI" "$B" && echo "전체 백업: $B ($(du -sh "$B" | cut -f1))" >> $O || { echo "백업 실패 — 중단" >> $O; exit 1; }
[ "$(shasum -a 256 "$MP/EFI/OC/config.plist" | cut -c1-16)" = "$(shasum -a 256 "$B/OC/config.plist" | cut -c1-16)" ] && [ "$(shasum -a 256 "$MP/EFI/OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe" | cut -c1-16)" = "$(shasum -a 256 "$B/OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe" | cut -c1-16)" ] || { echo "백업 검증 실패 — 중단" >> $O; exit 1; }
echo "백업 검증: config·WhateverXe 해시 일치 (WhateverXe $(shasum -a 256 "$B/OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe" | cut -c1-8))" >> $O
echo "EFI 사용량(전): $(df -h "$MP" | tail -1 | awk '{print $3" / "$2}')" >> $O
mkdir -p "$AR/EFI안-backup-before-$TS"
n=0
for d in "$MP"/EFI/OC/backup-before-*; do
  [ -d "$d" ] || continue
  [ "$(basename "$d")" = backup-before-depop ] && continue
  cp -Rp "$d" "$AR/EFI안-backup-before-$TS/" && rm -rf "$d" && n=$((n+1))
done
echo "EFI 안 backup-before-* ${n}개를 $AR/EFI안-backup-before-$TS 로 옮김 (남김: backup-before-depop)" >> $O
echo "EFI 사용량(후): $(df -h "$MP" | tail -1 | awk '{print $3" / "$2}')" >> $O
mkdir -p "$AR/libexec-$TS"; m=0
for f in /usr/local/libexec/step*.sh /usr/local/libexec/*-watchdog.sh /usr/local/libexec/*.bak-* /usr/local/libexec/*.bak; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in step68-depop.sh) continue;; esac
  mv "$f" "$AR/libexec-$TS/" && m=$((m+1))
done
echo "/usr/local/libexec 옛 파일 ${m}개를 $AR/libexec-$TS 로 옮김. 남은 것: $(ls /usr/local/libexec | tr '\n' ' ')" >> $O
chown -R user:staff "$B" "$AR" $O
sync
