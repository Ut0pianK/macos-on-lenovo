#!/bin/bash
set -u
T="$HOME/nvidia-trial"; OUT="$T/step0"; mkdir -p "$OUT" "$T/logs"
LOG="$T/logs/step0-efi-read-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "===== step0-efi-read $(date) ====="
sudo -v || { echo "관리자 암호가 필요합니다"; exit 1; }

for p in $(diskutil list physical | awk '$2=="EFI"{print $NF}'); do
  d=${p%s*}
  loc=$(diskutil info "$d" | awk -F': *' '/Device Location/{print $2}')
  tag=usb; [ "$loc" = Internal ] && tag=internal
  echo; echo "########## $p ($loc) → $tag"
  was=$(mount | grep -c "^/dev/$p ")
  [ "$was" = 0 ] && sudo diskutil mount readOnly "$p"
  mp=$(diskutil info "$p" | awk -F': *' '/Mount Point/{print $2}')
  if [ -z "$mp" ] || [ ! -d "$mp" ]; then echo "!! 마운트 실패"; continue; fi
  echo "마운트: $mp (원래 마운트돼 있었음=$was)"
  D="$OUT/$tag"; mkdir -p "$D"
  echo "-- 최상위"; ls -la "$mp" "$mp/EFI" 2>&1
  cfg="$mp/EFI/OC/config.plist"
  if [ -f "$cfg" ]; then
    echo "-- config.plist sha256: $(shasum -a 256 "$cfg" | cut -d' ' -f1)  크기 $(stat -f %z "$cfg")  수정 $(stat -f %Sm "$cfg")"
    plutil -lint "$cfg"
    cp "$cfg" "$D/config.redacted.plist"
    for k in MLB SystemSerialNumber SystemUUID ROM; do plutil -remove "PlatformInfo.Generic.$k" "$D/config.redacted.plist" 2>/dev/null; done
    echo "-- OC 폴더"; ls -la "$mp/EFI/OC"
    echo "-- ACPI (sha256)"; (cd "$mp/EFI/OC/ACPI" && shasum -a 256 * 2>/dev/null)
    echo "-- Kexts (버전)"
    for k in "$mp/EFI/OC/Kexts"/*.kext; do
      printf '  %s  %s\n' "$(basename "$k")" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$k/Contents/Info.plist" 2>/dev/null)"
    done
    echo "-- Drivers / Tools"; ls "$mp/EFI/OC/Drivers" "$mp/EFI/OC/Tools" 2>&1
    echo "-- OpenCore.efi / BOOTx64.efi sha256"; shasum -a 256 "$mp/EFI/OC/OpenCore.efi" "$mp/EFI/BOOT/BOOTx64.efi" 2>&1
  else
    echo "!! $cfg 없음"
  fi
  echo "-- dGPU/NVIDIA 관련 파일 검색"
  find "$mp" \( -iname '*dgpu*' -o -iname '*nvidia*' -o -iname '*nullmoth*' -o -iname '*NVDA*' -o -iname '*.aml.off' -o -iname '*.disabled' \) 2>/dev/null
  mkdir -p "$D/acpi-copy"
  find "$mp" -iname '*dgpu*.aml*' -exec cp {} "$D/acpi-copy/" \; 2>/dev/null
  echo "-- EFI 안의 모든 .aml / .sh"; find "$mp" \( -name '*.aml' -o -name '*.sh' -o -name '*.dsl' \) 2>/dev/null
  echo "-- OpenCore 로그 파일"; ls -la "$mp"/opencore-*.txt 2>/dev/null | tail -3
  last=$(ls "$mp"/opencore-*.txt 2>/dev/null | tail -1); [ -n "$last" ] && cp "$last" "$D/"
  echo "-- 여유 공간"; df -h "$mp" | tail -1
  [ "$was" = 0 ] && sudo diskutil unmount "$p"
done

echo; echo "########## 커널 메시지(이번 부팅)에서 PEG/NVIDIA/ACPI 오류"
sudo dmesg 2>/dev/null | grep -iE 'PEG|10de|nvidia|NVDA|GFX0|ACPI (Error|Warning|Exception)|DGPU|_OFF|_PS3' | head -60
echo; echo "########## system 도메인 disabled 서비스"
sudo launchctl print-disabled system
echo; echo "===== 끝. 로그: $LOG ====="
