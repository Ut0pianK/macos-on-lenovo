#!/bin/bash
set -u
LOG=/Users/user/tweak-backup-2026-11-12/remove-music/remove-music-$(date +%H%M%S).log
exec >> "$LOG" 2>&1
echo "===== remove-music $(date) ====="
[ "$(id -u)" = 0 ] || { echo "!! root 필요"; exit 1; }
DEV=/dev/disk1s4; MNT=/Volumes/sysrw-music; DEST=/Users/user/removed-system-apps/Music.app
[ "$(diskutil info disk1s4 | awk -F': *' '/Volume Name/{print $2}')" = Hacintosh ] || { echo "!! disk1s4 가 시스템 볼륨이 아님"; exit 1; }
[ "$(csrutil authenticated-root status | grep -c disabled)" = 1 ] || { echo "!! authenticated-root 가 켜져 있음"; exit 1; }
[ -e "$DEST" ] && { echo "!! $DEST 가 이미 있음"; exit 1; }
mkdir -p "$MNT" && mount -o nobrowse -t apfs "$DEV" "$MNT" || { echo "!! 마운트 실패"; exit 1; }
fin() { sync; umount "$MNT" && rmdir "$MNT"; }
SRC="$MNT/System/Applications/Music.app"
[ -d "$SRC" ] || { echo "!! $SRC 없음"; fin; exit 1; }
[ ! -e "$MNT/System/Applications/Maps.app" ] && [ -d "$MNT/System/Library/CoreServices" ] || { echo "!! 마운트된 볼륨 상태가 예상과 다름"; fin; exit 1; }
n1=$(find "$SRC" | wc -l | tr -d ' ')
cp -Rp "$SRC" "$DEST" || { echo "!! 복사 실패"; fin; exit 1; }
n2=$(find "$DEST" | wc -l | tr -d ' ')
[ "$n1" = "$n2" ] || { echo "!! 복사본 파일 수 불일치 ($n1 vs $n2) — 시스템 쪽은 그대로 둠"; fin; exit 1; }
echo "복사 완료 ($n2 항목). 시스템 볼륨에서 제거"
rm -R "$SRC" || { echo "!! 제거 실패"; fin; exit 1; }
[ -e "$SRC" ] && { echo "!! 제거 후에도 남아 있음"; fin; exit 1; }
bless --folder "$MNT/System/Library/CoreServices" --bootefi --create-snapshot; rc=$?
echo "bless 종료 코드 $rc"
diskutil apfs listSnapshots disk1s4 | grep -E "Name|XID|root to"
fin
[ $rc = 0 ] && echo applied || echo "!! bless 실패 — 재부팅해도 이전 스냅샷(음악 앱 있음)으로 부팅됨"
