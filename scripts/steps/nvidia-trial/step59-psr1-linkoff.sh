#!/bin/bash
set -u
MODE=${1:-}; INT=disk0s1; ARG=-wex-psr1-linkoff
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
LOG=/var/log/psr1.log; MARK=/var/db/psr1-linkoff.armed
PL=/Library/LaunchDaemons/local.psr1-linkoff-watchdog.plist; SELF=/usr/local/libexec/step59-psr1-linkoff.sh
log() { echo "$(date '+%F %T') $*" | tee -a $LOG; }
stop() { log "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
efi() {
  mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "EFI 마운트 실패"
  MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"; OC="$MP/EFI/OC"; C="$OC/config.plist"; BK="$OC/backup-before-psr1-linkoff"
}
case "$MODE" in
apply)
  efi
  [ "$(shasum -a 256 "$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe" | cut -c1-8)" = 67483039 ] || stop "EFI 의 WhateverXe 가 psr1c(67483039)가 아님"
  cur=$(plutil -extract $K raw -o - "$C"); case " $cur " in *" -wex-psr1 "*) ;; *) stop "boot-args 에 -wex-psr1 이 없음";; esac
  mkdir -p "$BK" && cp -p "$C" "$BK/config.plist" || stop "백업 실패"
  case " $cur " in *" $ARG "*) ;; *) plutil -replace $K -string "$cur $ARG" "$C" && plutil -lint "$C" >/dev/null || { cp -p "$BK/config.plist" "$C"; stop "boot-args 실패 → 되돌림"; };; esac
  log "linkoff apply: boot-args = ... $(plutil -extract $K raw -o - "$C" | grep -o -- '-wex-psr[^ ]*' | tr '\n' ' ')"
  mkdir -p /usr/local/libexec && install -m 755 "$0" "$SELF"
  cat > $PL <<EOP
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>local.psr1-linkoff-watchdog</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>watchdog</string></array>
<key>RunAtLoad</key><true/></dict></plist>
EOP
  chmod 644 $PL; chown root:wheel $PL; rm -f $MARK ;;
undo)
  efi; [ -f "$BK/config.plist" ] || stop "백업 없음"
  cp -p "$BK/config.plist" "$C" && plutil -lint "$C" >/dev/null || stop "되돌리기 실패"
  log "linkoff undo: $(plutil -extract $K raw -o - "$C" | grep -o -- '-wex-psr[^ ]*' | tr '\n' ' ')"
  rm -f $MARK $PL; sync; [ -n "${NOBOOTOUT:-}" ] && exit 0
  launchctl bootout system/local.psr1-linkoff-watchdog 2>/dev/null ;;
watchdog)
  case " $(nvram boot-args) " in *" $ARG "*) ;; *) rm -f $MARK $PL; exit 0;; esac
  if [ -e $MARK ]; then log "linkoff watchdog: 이전 시험 부팅이 5분을 못 버팀 → 되돌리고 재부팅"; NOBOOTOUT=1 "$SELF" undo; sync; sleep 3; shutdown -r now; exit 0; fi
  touch $MARK; sync; log "linkoff watchdog: 시험 부팅 시작, 5분 감시"
  sleep 300; rm -f $MARK; sync; log "linkoff watchdog: 5분 통과"
  rm -f $PL; launchctl bootout system/local.psr1-linkoff-watchdog 2>/dev/null ;;
*) stop "사용법: $0 apply|undo|watchdog";;
esac
sync; exit 0
