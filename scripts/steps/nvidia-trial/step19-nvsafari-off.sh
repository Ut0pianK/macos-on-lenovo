#!/bin/bash
set -u
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
INT=disk0s1; mode=${1:-apply}
LOG=/Users/user/nvidia-trial/logs/step19-nvsafari-off-$(date +%Y%m%d-%H%M%S).log
exec >> "$LOG" 2>&1
echo "===== step19-nvsafari-off $(date) ($mode) ====="
stop() { echo "!! $* — 중단"; sync; [ "${was:-1}" = 0 ] && diskutil unmount "$INT"; exit 1; }
[ "$(id -u)" = 0 ] || { echo "!! root 필요"; exit 1; }
[ "$(diskutil info disk0 | awk -F': *' '/Device Location/{print $2}')" = Internal ] || { echo "!! disk0 이 내장이 아님"; exit 1; }
was=$(mount | grep -c "^/dev/$INT ")
[ "$was" = 0 ] && { diskutil mount "$INT" || { echo "!! 마운트 실패"; exit 1; }; }
MP=$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')
cfg="$MP/EFI/OC/config.plist"; BK="$MP/EFI/OC/config.plist.before-nvsafari-off"
[ -f "$cfg" ] || stop "config.plist 없음"
if [ "$mode" = undo ]; then
  plutil -lint "$BK" >/dev/null && cp "$BK" "$cfg" || stop "복원 실패"
  echo "복원됨: $(plutil -extract $K raw -o - "$cfg")"; sync; [ "$was" = 0 ] && diskutil unmount "$INT"; echo undone; exit 0
fi
cur=$(plutil -extract $K raw -o - "$cfg") || stop "boot-args 읽기 실패"
case " $cur " in *" -wex-nvsafari "*) ;; *) echo "-wex-nvsafari 이미 없음"; sync; [ "$was" = 0 ] && diskutil unmount "$INT"; echo applied; exit 0;; esac
case " $cur " in *" -wex-safarinv "*) stop "-wex-safarinv 가 아직 있음(step18 undo 먼저)";; esac
new=$(echo " $cur " | sed 's/ -wex-nvsafari / /' | sed 's/^ //; s/ $//')
cp "$cfg" "$BK" || stop "백업 실패"
N=/private/tmp/int-config.nvsafarioff.$$
cp "$cfg" "$N" && plutil -replace $K -string "$new" "$N" && plutil -lint "$N" >/dev/null || stop "config 편집 실패"
[ "$(diff "$cfg" "$N" | grep -c '^[<>]')" = 2 ] || stop "config 변경이 1줄이 아님"
cp "$N" "$cfg" && plutil -lint "$cfg" >/dev/null || { cp "$BK" "$cfg"; stop "config 쓰기 실패 → 되돌림"; }
echo "이후 boot-args: $(plutil -extract $K raw -o - "$cfg")"
sync; [ "$was" = 0 ] && diskutil unmount "$INT"; echo applied
