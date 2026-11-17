#!/bin/bash
set -u
T="$HOME/nvidia-trial"; TS=$(date +%Y%m%d-%H%M%S)
LOG="$T/logs/step1b-sync-usb-efi-$TS.log"
exec > >(tee -a "$LOG") 2>&1
echo "===== step1b-sync-usb-efi $(date) ====="
B=$(cat "$T/LATEST_BACKUP" 2>/dev/null)
if [ -z "$B" ] || [ ! -f "$B/EFI-usb/EFI/OC/config.plist" ] || [ ! -f "$B/EFI-internal/EFI/OC/config.plist" ]; then
  echo "!! 검증된 백업이 없음 → 먼저 step1-backup.sh 를 실행하세요. 중단."; exit 1
fi
echo "백업 확인: $B"
INT=""; EXT=""
for p in $(diskutil list physical | awk '$2=="EFI"{print $NF}'); do
  loc=$(diskutil info "${p%s*}" | awk -F': *' '/Device Location/{print $2}')
  if [ "$loc" = Internal ]; then INT=$p; elif [ "$loc" = External ]; then EXT=$p; fi
done
[ -n "$INT" ] && [ -n "$EXT" ] || { echo "!! 내장($INT) 또는 USB($EXT) EFI 파티션을 찾지 못함. 중단."; exit 1; }
echo "내장: $INT / USB: $EXT"
sudo -v || { echo "관리자 암호가 필요합니다"; exit 1; }
mp() { diskutil info "$1" | awk -F': *' '/Mount Point/{print $2}'; }

IOURS=0; SRC=$(mp "$INT")
if [ -z "$SRC" ]; then IOURS=1; sudo diskutil mount readOnly "$INT" >/dev/null; SRC=$(mp "$INT"); fi
[ -f "$SRC/EFI/OC/config.plist" ] || { echo "!! 내장 EFI 마운트 실패. 중단."; exit 1; }
cleanup_int() { [ "$IOURS" = 1 ] && sudo diskutil unmount "$INT" >/dev/null; }
if ! diff -rq -x '._*' "$SRC/EFI" "$B/EFI-internal/EFI" >/dev/null; then
  echo "!! 내장 EFI가 백업 이후 바뀌었음 → 백업을 다시 만드세요. 중단."; cleanup_int; exit 1
fi
need=$(du -sk "$SRC/EFI" | cut -f1)

echo; echo "##### 1) USB EFI 파일시스템 정리 (fsck_msdos -y)"
[ -n "$(mp "$EXT")" ] && sudo diskutil unmount "$EXT"
sudo fsck_msdos -y "/dev/r$EXT"; rc=$?
echo "fsck 종료 코드: $rc"
[ "$rc" = 0 ] || { echo "!! fsck 실패. USB는 그대로 둠. 중단."; cleanup_int; exit 1; }
sudo diskutil mount "$EXT" || { echo "!! USB EFI 쓰기 마운트 실패. 중단."; cleanup_int; exit 1; }
DST=$(mp "$EXT")
[ -d "$DST/EFI" ] || { echo "!! $DST/EFI 없음. 중단."; sudo diskutil unmount "$EXT"; cleanup_int; exit 1; }
free=$(df -k "$DST" | tail -1 | awk '{print $4}')
echo "필요 ${need}KB / 여유 ${free}KB"
if [ "$free" -lt $((need + 8192)) ]; then echo "!! 공간 부족. 아무것도 바꾸지 않음. 중단."; sudo diskutil unmount "$EXT"; cleanup_int; exit 1; fi

echo; echo "##### 2) 옛 EFI 폴더 이름 변경 (삭제 안 함)"
OLD="$DST/EFI.old-$TS"
sudo mv "$DST/EFI" "$OLD" || { echo "!! 이름 변경 실패. 중단."; sudo diskutil unmount "$EXT"; cleanup_int; exit 1; }
echo "  $DST/EFI → $OLD"

echo; echo "##### 3) 내장 EFI 복사"
if sudo ditto --norsrc --noextattr "$SRC/EFI" "$DST/EFI" && diff -rq -x '._*' "$SRC/EFI" "$DST/EFI" && plutil -lint "$DST/EFI/OC/config.plist"; then
  echo "검증 OK: USB EFI = 내장 EFI"
  echo "config.plist sha256 내장: $(shasum -a 256 "$SRC/EFI/OC/config.plist" | cut -d' ' -f1)"
  echo "config.plist sha256 USB : $(shasum -a 256 "$DST/EFI/OC/config.plist" | cut -d' ' -f1)"
  RES=yes
else
  echo "!! 복사 또는 검증 실패 → 되돌림"
  [ -d "$DST/EFI" ] && sudo mv "$DST/EFI" "$DST/EFI.failed-$TS"
  sudo mv "$OLD" "$DST/EFI" && echo "  옛 EFI 폴더를 원래 이름으로 되돌림"
  RES=no
fi
echo; echo "-- USB EFI 최상위"; ls -la "$DST" | grep -v 'opencore-'; echo "(opencore-*.txt 로그 $(ls "$DST"/opencore-*.txt 2>/dev/null | wc -l | tr -d ' ')개는 그대로)"
df -h "$DST" | tail -1
sync
sudo diskutil unmount "$EXT"; cleanup_int
echo; echo "USB_EFI_SYNCED=$RES"
echo "===== 끝. 로그: $LOG ====="
[ "$RES" = yes ]
