#!/bin/bash
set -u
MODE=${1:-}; T=/Users/user/nvidia-trial; INT=disk0s1
NEW=$T/build/wex-0.8.0-micin-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=e25a78dc643ca7183eac44c03232d777b8b8d46ef62507b06262642624ce8b91
CUR_SHA=f45b7e4921c280133e91a42d713976be8b7cd9225b91b48721fc7c348406272c
LOG=/var/log/psr1.log
log() { echo "$(date '+%F %T') [micin] $*" | tee -a $LOG; }
stop() { log "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
efi() {
  mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "EFI 마운트 실패"
  MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"; OC="$MP/EFI/OC"
  kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-micin"
}
case "$MODE" in
apply)
  efi
  [ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시 불일치"
  [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 psrtune(f45b7e49)가 아님: $(shasum -a 256 "$kx" | cut -c1-8)"
  TS=$(date +%Y-%m-%d-%H%M%S); cp -Rp "$MP/EFI" "/Users/user/EFI-backup-$TS" && chown -R user:staff "/Users/user/EFI-backup-$TS" || stop "EFI 전체 백업 실패"
  mkdir -p "$BK" && cp -p "$kx" "$BK/WhateverXe" || stop "백업 실패"
  cp "$NEW" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$NEW_SHA" ] || { cp -p "$BK/WhateverXe" "$kx"; stop "kext 쓰기 실패 → 되돌림"; }
  log "apply: kext e25a78dc (백업 ~/EFI-backup-$TS, EFI 안 backup-before-micin)" ;;
undo)
  efi; [ -f "$BK/WhateverXe" ] || stop "백업 없음"
  cp -p "$BK/WhateverXe" "$kx" || stop "되돌리기 실패"
  log "undo: kext $(shasum -a 256 "$kx" | cut -c1-8)" ;;
*) stop "사용법: $0 apply|undo";;
esac
sync; exit 0
