#!/bin/bash
set -u
MODE=${1:-}; T=/Users/user/nvidia-trial; INT=disk0s1
NEW=$T/build/wex-0.8.0-vp9-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=ff17b44ece7ddefa54ff1e5960e848d00310e9b835340a844f5cc9db9180a64f
CUR_SHA=36886a5e55f12bb14c2a24f4b4e04d1c5b9b2ccc7fb4b0e13d5d632b769b15db
DYSRC=/Users/user/vp9-port/build/link/vp9stack.dylib
DYDST=/Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle/Contents/MacOS/vp9stack.dylib
VA=/Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle/Contents/MacOS/AppleIntelTGLGraphicsVADriver
VA_SHA=a972cdb7ddd56bcf
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
LOG=/var/log/psr1.log; MARK=/var/db/vp9.armed
PL=/Library/LaunchDaemons/local.vp9-watchdog.plist; SELF=/usr/local/libexec/step72-vp9.sh
log() { echo "$(date '+%F %T') [vp9] $*" | tee -a $LOG; }
stop() { log "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
efi() {
  mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "EFI 마운트 실패"
  MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"; OC="$MP/EFI/OC"; C="$OC/config.plist"
  kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-vp9"
}
case "$MODE" in
apply)
  efi
  [ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시 불일치"
  [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 psridle(36886a5e)가 아님: $(shasum -a 256 "$kx" | cut -c1-8)"
  [ "$(shasum -a 256 "$VA" | cut -c1-16)" = "$VA_SHA" ] || stop "VA 드라이버가 패치 대상 판(a972cdb7…)이 아님"
  [ -s "$DYSRC" ] || stop "vp9stack.dylib 없음"
  case " $(plutil -extract $K raw -o - "$C") " in *" -wex-vpfix "*) ;; *) stop "boot-args 에 -wex-vpfix 가 없음(스텁 자리가 살아 있는 코드가 됨)";; esac
  TS=$(date +%Y-%m-%d-%H%M%S); cp -Rp "$MP/EFI" "/Users/user/EFI-backup-$TS" && chown -R user:staff "/Users/user/EFI-backup-$TS" || stop "EFI 전체 백업 실패"
  mkdir -p "$BK" && cp -p "$kx" "$BK/WhateverXe" && cp -p "$C" "$BK/config.plist" || stop "백업 실패"
  cp "$DYSRC" "$DYDST" && chown root:wheel "$DYDST" && chmod 755 "$DYDST" && codesign -f -s - "$DYDST" 2>/dev/null || stop "dylib 설치 실패"
  cp "$NEW" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$NEW_SHA" ] || { cp -p "$BK/WhateverXe" "$kx"; rm -f "$DYDST"; stop "kext 쓰기 실패 → 되돌림"; }
  cur=$(plutil -extract $K raw -o - "$C")
  case " $cur " in *" -wex-vp9 "*) ;; *) plutil -replace $K -string "$cur -wex-vp9" "$C" && plutil -lint "$C" >/dev/null || { cp -p "$BK/config.plist" "$C"; cp -p "$BK/WhateverXe" "$kx"; rm -f "$DYDST"; stop "boot-args 실패 → 되돌림"; };; esac
  log "apply: kext ff17b44e, dylib $(shasum -a 256 "$DYDST" | cut -c1-8), boot-args 끝에 -wex-vp9 (백업 ~/EFI-backup-$TS)"
  mkdir -p /usr/local/libexec && install -m 755 "$0" "$SELF"
  cat > $PL <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>local.vp9-watchdog</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>watchdog</string></array>
<key>RunAtLoad</key><true/></dict></plist>
EOF
  chmod 644 $PL; chown root:wheel $PL; rm -f $MARK ;;
undo)
  efi; [ -f "$BK/WhateverXe" ] && [ -f "$BK/config.plist" ] || stop "백업 없음"
  cp -p "$BK/WhateverXe" "$kx" && cp -p "$BK/config.plist" "$C" && plutil -lint "$C" >/dev/null || stop "되돌리기 실패"
  rm -f "$DYDST"
  log "undo: kext $(shasum -a 256 "$kx" | cut -c1-8), dylib 제거"
  rm -f $MARK $PL; sync; [ -n "${NOBOOTOUT:-}" ] && exit 0
  launchctl bootout system/local.vp9-watchdog 2>/dev/null ;;
watchdog)
  case " $(nvram boot-args) " in *" -wex-vp9 "*) ;; *) rm -f $MARK $PL; exit 0;; esac
  if [ -e $MARK ]; then log "watchdog: 이전 시험 부팅이 5분을 못 버팀 → psridle 로 되돌리고 재부팅"; NOBOOTOUT=1 "$SELF" undo; sync; sleep 3; shutdown -r now; exit 0; fi
  touch $MARK; sync; log "watchdog: 시험 부팅 시작, 5분 감시"
  sleep 300; rm -f $MARK; sync
  log "watchdog: 5분 통과 — wexvp9=$(sysctl -n debug.wexvp9 2>/dev/null) idle=$(sysctl -n debug.wexpsr1_idle 2>/dev/null)"
  rm -f $PL; launchctl bootout system/local.vp9-watchdog 2>/dev/null ;;
*) stop "사용법: $0 apply|undo|watchdog";;
esac
sync; exit 0
