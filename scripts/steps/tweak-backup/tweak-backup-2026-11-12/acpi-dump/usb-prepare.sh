#!/bin/bash
O=/Users/user/tweak-backup-2026-11-12/acpi-dump; exec >> "$O/usb-prepare.log" 2>&1
echo "===== $(date) ${1:-prepare} ====="
SRC=/Users/user/EFI-backup-2026-11-11-0016/EFI
[ "$(diskutil info disk6 | awk -F': *' '/Device Location/{print $2}')" = External ] || { echo "disk6 이 외장이 아님"; exit 1; }
diskutil mount disk6s1 || exit 1
MP=$(diskutil info disk6s1 | awk -F': *' '/Mount Point/{print $2}'); KEEP="$MP/EFI.rel-keep-20261112"
fin() { sync; diskutil unmount disk6s1; }
if [ "${1:-prepare}" = restore ]; then
  [ -d "$KEEP" ] || { echo "보존본 없음"; fin; exit 1; }
  mv "$MP/EFI" "$MP/EFI.debug-used-$(date +%H%M%S)" && mv "$KEEP" "$MP/EFI" && echo restored; fin; exit 0
fi
[ -d "$KEEP" ] && { echo "이미 준비돼 있음"; fin; exit 0; }
[ "$(shasum -a 256 "$SRC/OC/OpenCore.efi" | cut -c1-12)" = 298be0bf72b6 ] || { echo "원본 디버그 OpenCore 해시 불일치"; fin; exit 1; }
mv "$MP/EFI" "$KEEP" || { echo "이름 바꾸기 실패"; fin; exit 1; }
cp -R "$SRC" "$MP/EFI" || { echo "복사 실패 → 되돌림"; mv "$KEEP" "$MP/EFI"; fin; exit 1; }
C="$MP/EFI/OC/config.plist"
plutil -replace Misc.Debug.SysReport -bool true "$C" && plutil -replace Misc.Boot.Timeout -integer 0 "$C" && plutil -replace Misc.Boot.ShowPicker -bool true "$C" && plutil -lint "$C" || { echo "설정 편집 실패 → 되돌림"; mv "$MP/EFI" "$MP/EFI.failed" ; mv "$KEEP" "$MP/EFI"; fin; exit 1; }
for k in Misc.Debug.SysReport Misc.Debug.Target Misc.Boot.Timeout Misc.Boot.ShowPicker; do echo "$k = $(plutil -extract $k raw -o - "$C")"; done
ls "$MP"; shasum -a 256 "$MP/EFI/OC/OpenCore.efi" "$MP/EFI/BOOT/BOOTx64.efi" | cut -c1-20; df -h "$MP" | tail -1
fin; echo prepared
