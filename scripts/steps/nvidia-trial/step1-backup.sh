#!/bin/bash
set -u
T="$HOME/nvidia-trial"; TS=$(date +%Y%m%d-%H%M%S); B="$T/backup-$TS"
mkdir -p "$B/state" "$T/logs"
LOG="$T/logs/step1-backup-$TS.log"
exec > >(tee -a "$LOG") 2>&1
echo "===== step1-backup $(date) → $B ====="
sudo -v || { echo "관리자 암호가 필요합니다"; exit 1; }
ME=$(id -un); OK=1
fail() { echo "!! $*"; OK=0; }

for p in $(diskutil list physical | awk '$2=="EFI"{print $NF}'); do
  loc=$(diskutil info "${p%s*}" | awk -F': *' '/Device Location/{print $2}')
  tag=usb; [ "$loc" = Internal ] && tag=internal
  echo; echo "##### EFI $p ($loc) → EFI-$tag"
  OURS=0; ALT=""
  MP=$(diskutil info "$p" | awk -F': *' '/Mount Point/{print $2}')
  if [ -z "$MP" ]; then
    OURS=1
    sudo diskutil mount readOnly "$p" >/dev/null 2>&1
    MP=$(diskutil info "$p" | awk -F': *' '/Mount Point/{print $2}')
    if [ -z "$MP" ]; then
      ALT="/tmp/efi-ro-$tag.$$"; mkdir -p "$ALT"
      if sudo mount -r -t msdos "/dev/$p" "$ALT"; then MP="$ALT"; echo "(dirty 표시 때문에 mount -r 로 마운트)"; else rmdir "$ALT"; ALT=""; fi
    fi
  fi
  if [ -z "$MP" ] || [ ! -f "$MP/EFI/OC/config.plist" ]; then fail "$p 마운트 실패 또는 OpenCore 없음"; continue; fi
  echo "마운트: $MP"
  sudo ditto "$MP" "$B/EFI-$tag" || fail "ditto 실패 ($tag)"
  sudo chown -R "$ME":staff "$B/EFI-$tag"
  if diff -rq -x '._*' "$MP/EFI" "$B/EFI-$tag/EFI" >/dev/null 2>&1; then echo "검증 OK: EFI 폴더 내용 일치 (파일 $(find "$B/EFI-$tag/EFI" -type f | wc -l | tr -d ' ')개)"
  else fail "검증 실패: $tag 사본이 원본과 다름"; diff -rq -x '._*' "$MP/EFI" "$B/EFI-$tag/EFI" | head; fi
  echo "config.plist sha256: $(shasum -a 256 "$B/EFI-$tag/EFI/OC/config.plist" | cut -d' ' -f1)"
  echo "$p $loc" > "$B/EFI-$tag.source.txt"
  if [ "$OURS" = 1 ]; then
    if [ -n "$ALT" ]; then sudo umount "$ALT" && rmdir "$ALT"; else sudo diskutil unmount "$p" >/dev/null; fi
  fi
done
[ -d "$B/EFI-internal" ] || fail "내장 EFI 백업 없음"
[ -d "$B/EFI-usb" ] || fail "USB EFI 백업 없음 (USB가 꽂혀 있나요?)"

echo; echo "##### /Library/Extensions"
sudo tar -cpf "$B/Library-Extensions.tar" -C /Library Extensions || fail "tar 실패"
sudo chown "$ME":staff "$B/Library-Extensions.tar"
n1=$(find /Library/Extensions -type f | wc -l | tr -d ' '); n2=$(tar -tf "$B/Library-Extensions.tar" | grep -vc '/$')
echo "파일 수: 원본 $n1 / tar $n2"; [ "$n1" = "$n2" ] || fail "Extensions 파일 수 불일치"
ls -la /Library/Extensions > "$B/state/Library-Extensions-ls.txt"
(cd /Library && find Extensions -type f -exec shasum -a 256 {} \;) > "$B/state/Library-Extensions-sha256.txt"
for k in /Library/Extensions/*.kext; do
  printf '%s\t%s\t%s\n' "$(basename "$k")" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$k/Contents/Info.plist" 2>/dev/null)" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$k/Contents/Info.plist" 2>/dev/null)"
done > "$B/state/Library-Extensions-versions.txt"

echo; echo "##### AuxKC"
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
sudo cp -p "$KC" "$B/AuxiliaryKernelExtensions.kc" && sudo chown "$ME":staff "$B/AuxiliaryKernelExtensions.kc"
a=$(shasum -a 256 "$KC" | cut -d' ' -f1); b=$(shasum -a 256 "$B/AuxiliaryKernelExtensions.kc" | cut -d' ' -f1)
echo "sha256 원본 $a"; echo "sha256 사본 $b"; [ "$a" = "$b" ] || fail "AuxKC 해시 불일치"

echo; echo "##### 상태 덤프"
S="$B/state"; U=$(id -u)
nvram -p > "$S/nvram-p.txt" 2>&1
sudo nvram -xp > "$S/nvram-xp.plist" 2>&1; sudo chown "$ME":staff "$S/nvram-xp.plist"
nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version > "$S/opencore-version.txt" 2>&1
kmutil showloaded > "$S/kmutil-showloaded.txt" 2>&1
kmutil inspect -B /Library/KernelCollections/AuxiliaryKernelExtensions.kc > "$S/auxkc-inspect.txt" 2>&1
sw_vers > "$S/sw_vers.txt"; csrutil status > "$S/csrutil.txt" 2>&1; csrutil authenticated-root status >> "$S/csrutil.txt" 2>&1
system_profiler SPDisplaysDataType > "$S/SPDisplaysDataType.txt" 2>&1
ioreg -l -w0 > "$S/ioreg-l.txt" 2>&1
ioreg -p IOACPIPlane -l -w0 > "$S/ioreg-acpi.txt" 2>&1
pmset -g > "$S/pmset-g.txt" 2>&1; pmset -g batt > "$S/pmset-batt.txt" 2>&1
sudo launchctl print-disabled system > "$S/disabled-system.txt" 2>&1
launchctl print-disabled gui/$U > "$S/disabled-gui.txt" 2>&1
launchctl print-disabled user/$U > "$S/disabled-user.txt" 2>&1
ps axo pid,user,comm | grep -iE 'fairplay|fpsd|adid|akd|amsaccountsd|amsengagementd|commerce|appstore|storekit|storeaccountd|storedownloadd|installd' | grep -v grep > "$S/appstore-procs.txt"
diskutil list > "$S/diskutil-list.txt" 2>&1
ls -la /Library/Logs/DiagnosticReports > "$S/DiagnosticReports-ls.txt" 2>&1
cp /etc/hosts "$S/hosts.txt"
for f in "$S"/*; do [ -s "$f" ] || echo "  (비어 있음) $(basename "$f")"; done
echo "상태 파일 $(ls "$S" | wc -l | tr -d ' ')개"

(cd "$B" && find . -type f ! -name SHA256SUMS.txt -exec shasum -a 256 {} \; > SHA256SUMS.txt)
echo "SHA256SUMS.txt: $(wc -l < "$B/SHA256SUMS.txt" | tr -d ' ')개 파일"
du -sh "$B"

echo
if [ "$OK" = 1 ]; then echo "BACKUP_VERIFIED=yes"; echo "$B" > "$T/LATEST_BACKUP"; else echo "BACKUP_VERIFIED=no — 위의 !! 줄을 확인"; fi
echo "===== 끝. 로그: $LOG ====="
[ "$OK" = 1 ]
