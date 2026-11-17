#!/bin/bash
set -u
T="$HOME/nvidia-trial"; LOG="$T/logs/step3c-internal-efi-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "===== step3c-internal-efi $(date) (${1:-apply}) ====="
G=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82
ADD="nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth"
INT=""
for p in $(diskutil list physical | awk '$2=="EFI"{print $NF}'); do
  [ "$(diskutil info "${p%s*}" | awk -F': *' '/Device Location/{print $2}')" = Internal ] && INT=$p
done
[ -n "$INT" ] || { echo "!! 내장 EFI 파티션을 찾지 못함. 중단."; exit 1; }
if [ "${1:-}" != undo ] && [ ! -f "$T/USB_BOOT_VERIFIED" ]; then echo "!! USB 부팅 확인 표식이 없음 → 먼저 USB로 부팅해 확인. 중단."; exit 1; fi
sudo -v || exit 1
was=$(mount | grep -c "^/dev/$INT ")
[ "$was" = 0 ] && { sudo diskutil mount "$INT" || { echo "!! 마운트 실패. 중단."; exit 1; }; }
MP=$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')
cfg="$MP/EFI/OC/config.plist"; bak="$MP/EFI/OC/config.plist.before-nvidia"
fin() { sync; [ "$was" = 0 ] && sudo diskutil unmount "$INT"; echo "===== 끝. 로그: $LOG ====="; }
[ -f "$cfg" ] || { echo "!! $cfg 없음. 중단."; fin; exit 1; }
if [ "${1:-}" = undo ]; then
  if [ -f "$bak" ]; then cp "$bak" "$cfg" && plutil -lint "$cfg" && echo "복원됨. sha256: $(shasum -a 256 "$cfg" | cut -d' ' -f1) (원래 값은 910c3cfd… 로 시작)"; else echo "!! 백업 없음"; fi
  fin; exit 0
fi
orig=$(shasum -a 256 "$cfg" | cut -d' ' -f1)
echo "현재 config.plist sha256: $orig"
cur=$(plutil -extract $G.boot-args raw -o - "$cfg")
case " $cur " in *" nvaccel=1 "*) echo "이미 적용돼 있음. 변경 없음."; fin; exit 0;; esac
[ "$orig" = 910c3cfd6200c9533b3adb9e33f9c2382885f999181fbef8c939ead3207381d0 ] || { echo "!! config.plist 가 백업 때와 다름 → 확인 필요. 중단."; fin; exit 1; }
N=/tmp/int-config.new.$$
cp "$cfg" $N && plutil -replace $G.boot-args -string "$cur $ADD" $N && plutil -replace $G.csr-active-config -data QwoAAA== $N && plutil -lint $N || { echo "!! 편집 실패. EFI는 그대로."; rm -f $N; fin; exit 1; }
echo "-- diff (이전 → 이후)"; diff "$cfg" $N
n=$(diff "$cfg" $N | grep -c '^[<>]')
if [ "$n" = 4 ]; then
  cp "$cfg" "$bak" && cp $N "$cfg" && plutil -lint "$cfg" || echo "!! 쓰기 실패"
  echo "boot-args: $(plutil -extract $G.boot-args raw -o - "$cfg")"
  echo "csr-active-config: $(plutil -extract $G.csr-active-config raw -o - "$cfg")"
  echo "새 sha256: $(shasum -a 256 "$cfg" | cut -d' ' -f1)"
  echo "백업: $bak ($(shasum -a 256 "$bak" | cut -d' ' -f1))"
else echo "!! 예상(2줄 변경)과 다름: $n → 적용하지 않음"; fi
rm -f $N; fin
