#!/bin/bash
set -u
T="$HOME/nvidia-trial"; D="$T/step0/usb"; mkdir -p "$D" "$T/logs"
LOG="$T/logs/step0-usb-efi-diag-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "===== step0-usb-efi-diag $(date) ====="
P=""
for p in $(diskutil list physical | awk '$2=="EFI"{print $NF}'); do
  loc=$(diskutil info "${p%s*}" | awk -F': *' '/Device Location/{print $2}')
  [ "$loc" = External ] && P=$p
done
[ -n "$P" ] || { echo "!! 외장 디스크의 EFI 파티션을 찾지 못함 (USB가 꽂혀 있나요?)"; exit 1; }
echo "대상: /dev/$P"; diskutil list "${P%s*}"
sudo -v || { echo "관리자 암호가 필요합니다"; exit 1; }

echo; echo "##### 1) 부트 섹터 (첫 512바이트)"
sudo dd if="/dev/r$P" bs=512 count=1 2>/dev/null | xxd | head -32

echo; echo "##### 2) fsck_msdos -n (검사만)"
sudo fsck_msdos -n "/dev/r$P"; echo "fsck 종료 코드: $?"

echo; echo "##### 3) 마운트 시도 (읽기 전용)"
MP=""
if mount | grep -q "^/dev/$P "; then MP=$(diskutil info "$P" | awk -F': *' '/Mount Point/{print $2}'); echo "이미 마운트됨: $MP"; OURS=0
else
  OURS=1
  sudo diskutil mount readOnly "$P"; echo "diskutil 종료 코드: $?"
  MP=$(diskutil info "$P" | awk -F': *' '/Mount Point/{print $2}')
  if [ -z "$MP" ]; then
    echo "-- diskutil 실패 → mount -r -t msdos 시도"
    ALT="/tmp/usb-efi-ro.$$"; mkdir -p "$ALT"
    if sudo mount -r -t msdos "/dev/$P" "$ALT"; then MP="$ALT"; else echo "mount 종료 코드: $?"; rmdir "$ALT"; fi
  fi
fi

echo; echo "##### 4) 최근 2분 시스템 로그의 msdos/fskit/disk 오류"
/usr/bin/log show --last 2m --style compact --predicate 'eventMessage CONTAINS[c] "msdos" OR eventMessage CONTAINS[c] "fskit" OR eventMessage CONTAINS[c] "'"$P"'"' 2>/dev/null | grep -iE 'error|fail|corrupt|dirty|invalid|unsupported|denied' | cut -c1-260 | tail -25

if [ -n "$MP" ] && [ -d "$MP" ]; then
  echo; echo "##### 5) 내용 (마운트: $MP)"
  ls -la "$MP" "$MP/EFI" "$MP/EFI/OC" 2>&1
  cfg="$MP/EFI/OC/config.plist"
  if [ -f "$cfg" ]; then
    echo "-- config.plist sha256: $(shasum -a 256 "$cfg" | cut -d' ' -f1)  수정 $(stat -f %Sm "$cfg")"
    plutil -lint "$cfg"
    cp "$cfg" "$D/config.redacted.plist"
    for k in MLB SystemSerialNumber SystemUUID ROM; do plutil -remove "PlatformInfo.Generic.$k" "$D/config.redacted.plist" 2>/dev/null; done
    echo "-- ACPI (sha256)"; (cd "$MP/EFI/OC/ACPI" && shasum -a 256 * 2>/dev/null)
    echo "-- Kexts (버전)"
    for k in "$MP/EFI/OC/Kexts"/*.kext; do printf '  %s  %s\n' "$(basename "$k")" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$k/Contents/Info.plist" 2>/dev/null)"; done
    echo "-- Drivers / Tools"; ls "$MP/EFI/OC/Drivers" "$MP/EFI/OC/Tools" 2>&1
    echo "-- OpenCore.efi / BOOTx64.efi sha256"; shasum -a 256 "$MP/EFI/OC/OpenCore.efi" "$MP/EFI/BOOT/BOOTx64.efi" 2>&1
  else echo "!! $cfg 없음"; fi
  echo "-- dGPU/NVIDIA 관련 파일"; find "$MP" \( -iname '*dgpu*' -o -iname '*nvidia*' -o -iname '*nullmoth*' -o -iname '*.sh' \) 2>/dev/null
  mkdir -p "$D/acpi-copy"; find "$MP" -iname '*dgpu*.aml*' -exec cp {} "$D/acpi-copy/" \; 2>/dev/null
  echo "-- 여유 공간"; df -h "$MP" | tail -1
  if [ "$OURS" = 1 ]; then
    case "$MP" in /tmp/usb-efi-ro.*) sudo umount "$MP" && rmdir "$MP";; *) sudo diskutil unmount "$P";; esac
  fi
else
  echo; echo "!! 어떤 방법으로도 마운트되지 않음 — 위 1)~4) 결과로 원인 판단"
fi
echo; echo "===== 끝. 로그: $LOG ====="
