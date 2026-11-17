#!/bin/bash
set -u
T="$HOME/nvidia-trial"; LOG="$T/logs/step3b-usb-nvoff-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "===== step3b-usb-nvoff $(date) (${1:-apply}) ====="
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
EXT=""
for p in $(diskutil list physical | awk '$2=="EFI"{print $NF}'); do
  [ "$(diskutil info "${p%s*}" | awk -F': *' '/Device Location/{print $2}')" = External ] && EXT=$p
done
[ -n "$EXT" ] || { echo "!! USB EFI 파티션을 찾지 못함. 중단."; exit 1; }
sudo -v || exit 1
was=$(mount | grep -c "^/dev/$EXT ")
[ "$was" = 0 ] && { sudo diskutil mount "$EXT" || { echo "!! 마운트 실패. 중단."; exit 1; }; }
MP=$(diskutil info "$EXT" | awk -F': *' '/Mount Point/{print $2}')
cfg="$MP/EFI/OC/config.plist"; bak="$MP/EFI/OC/config.plist.before-nvoff"
[ -f "$cfg" ] || { echo "!! $cfg 없음. 중단."; sudo diskutil unmount "$EXT"; exit 1; }
if [ "${1:-}" = undo ]; then
  [ -f "$bak" ] && cp "$bak" "$cfg" && plutil -lint "$cfg" && echo "복원됨: boot-args = $(plutil -extract $K raw -o - "$cfg")" || echo "!! 백업 없음"
else
  cur=$(plutil -extract $K raw -o - "$cfg")
  echo "이전: $cur"
  case " $cur " in *" -nvoff "*) echo "이미 -nvoff 있음. 변경 없음.";;
  *)
    [ -f "$bak" ] || cp "$cfg" "$bak"
    cp "$cfg" /tmp/usb-config.new.$$ && plutil -replace $K -string "$cur -nvoff" /tmp/usb-config.new.$$ && plutil -lint /tmp/usb-config.new.$$ || { echo "!! 편집 실패. USB는 그대로."; rm -f /tmp/usb-config.new.$$; sudo diskutil unmount "$EXT"; exit 1; }
    echo "-- diff (이전 → 이후)"; diff "$cfg" /tmp/usb-config.new.$$
    n=$(diff "$cfg" /tmp/usb-config.new.$$ | grep -c '^[<>]')
    if [ "$n" = 2 ]; then cp /tmp/usb-config.new.$$ "$cfg" && plutil -lint "$cfg" && echo "이후: $(plutil -extract $K raw -o - "$cfg")"
    else echo "!! 예상(1줄)과 다른 변경 $n줄 → 적용하지 않음"; fi
    rm -f /tmp/usb-config.new.$$;;
  esac
fi
echo "config.plist sha256: $(shasum -a 256 "$cfg" | cut -d' ' -f1)"
sync; [ "$was" = 0 ] && sudo diskutil unmount "$EXT"
echo "===== 끝. 로그: $LOG ====="
