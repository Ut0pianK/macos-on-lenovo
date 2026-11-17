#!/bin/bash
set -u
T="$HOME/nvidia-trial"; LOG="$T/logs/step6a-renderwake-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "===== step6a-renderwake $(date) (${1:-apply}) ====="
ARG="-wex-tgl-hold-render-wake"
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
INT=""
for p in $(diskutil list physical | awk '$2=="EFI"{print $NF}'); do
  [ "$(diskutil info "${p%s*}" | awk -F': *' '/Device Location/{print $2}')" = Internal ] && INT=$p
done
[ -n "$INT" ] || { echo "!! 내장 EFI 파티션을 찾지 못함. 중단."; exit 1; }
echo "내장 EFI: $INT"
sudo -v || exit 1
was=$(mount | grep -c "^/dev/$INT ")
[ "$was" = 0 ] && { sudo diskutil mount "$INT" || { echo "!! 마운트 실패. 중단."; exit 1; }; }
MP=$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')
cfg="$MP/EFI/OC/config.plist"; bak="$MP/EFI/OC/config.plist.before-renderwake"
fin() { sync; [ "$was" = 0 ] && sudo diskutil unmount "$INT"; echo "===== 끝. 로그: $LOG ====="; }
[ -f "$cfg" ] || { echo "!! $cfg 없음. 중단."; fin; exit 1; }
if [ "${1:-}" = undo ]; then
  if [ -f "$bak" ]; then cp "$bak" "$cfg" && plutil -lint "$cfg" && echo "복원됨: $(plutil -extract $K raw -o - "$cfg")"; else echo "!! 백업 없음"; fi
  fin; exit 0
fi
echo "현재 sha256: $(shasum -a 256 "$cfg" | cut -d' ' -f1)"
cur=$(plutil -extract $K raw -o - "$cfg"); echo "이전: $cur"
case " $cur " in *" $ARG "*) echo "이미 들어 있음. 변경 없음."; fin; exit 0;; esac
run=$(nvram boot-args 2>/dev/null | cut -f2-)
[ "$cur" = "$run" ] || { echo "!! 파일의 boot-args 가 현재 부팅 값과 다름 → 확인 필요. 중단."; echo "   현재 부팅: $run"; fin; exit 1; }
N=/tmp/int-config.renderwake.$$
cp "$cfg" $N && plutil -replace $K -string "$cur $ARG" $N && plutil -lint $N || { echo "!! 편집 실패. EFI는 그대로."; rm -f $N; fin; exit 1; }
echo "-- diff (이전 → 이후)"; diff "$cfg" $N
if [ "$(diff "$cfg" $N | grep -c '^[<>]')" = 2 ]; then
  cp "$cfg" "$bak" && cp $N "$cfg" && plutil -lint "$cfg" || echo "!! 쓰기 실패"
  echo "이후: $(plutil -extract $K raw -o - "$cfg")"
  echo "새 sha256: $(shasum -a 256 "$cfg" | cut -d' ' -f1)"
else echo "!! 예상(1줄 변경)과 다름 → 적용하지 않음"; fi
rm -f $N; fin
