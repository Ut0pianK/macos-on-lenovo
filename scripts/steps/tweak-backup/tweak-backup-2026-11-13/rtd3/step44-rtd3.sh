#!/bin/bash
set -u
MODE=${1:-}
INT=disk0s1
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
ARGS='nvrtd3=1 nvrtd3res=\_SB.PC00.PEG0.PCRP'
LOG=/var/log/rtd3-trial.log
MARK=/var/db/rtd3-trial.armed
PL=/Library/LaunchDaemons/local.rtd3-watchdog.plist
SELF=/usr/local/libexec/step44-rtd3.sh
log() { echo "$(date '+%F %T') $*" | tee -a $LOG; }
stop() { log "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"

efi() {
  mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "EFI 마운트 실패"
  MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"; OC="$MP/EFI/OC"; C="$OC/config.plist"
  [ -f "$C" ] || stop "config.plist 없음"
}
strip_args() { echo " $1 " | sed -e 's/ nvrtd3=[^ ]*//g' -e 's/ nvrtd3res=[^ ]*//g' -e 's/^ *//' -e 's/ *$//'; }

case "$MODE" in
apply)
  efi
  TS=$(date +%Y-%m-%d-%H%M%S)
  cp -Rp "$MP/EFI" "/Users/user/EFI-backup-$TS" || stop "EFI 전체 백업 실패"
  chown -R user:staff "/Users/user/EFI-backup-$TS"
  mkdir -p "$OC/backup-before-rtd3" && cp -p "$C" "$OC/backup-before-rtd3/config.plist" || stop "config 백업 실패"
  cur=$(plutil -extract $K raw -o - "$C") || stop "boot-args 읽기 실패"
  new="$(strip_args "$cur") $ARGS"
  plutil -replace $K -string "$new" "$C" || { cp -p "$OC/backup-before-rtd3/config.plist" "$C"; stop "쓰기 실패 → 되돌림"; }
  plutil -lint "$C" >/dev/null || { cp -p "$OC/backup-before-rtd3/config.plist" "$C"; stop "형식 오류 → 되돌림"; }
  log "apply: boot-args = $(plutil -extract $K raw -o - "$C")"
  mkdir -p /usr/local/libexec && install -m 755 "$0" "$SELF"
  cat > $PL <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.rtd3-watchdog</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>watchdog</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
EOF
  chmod 644 $PL; chown root:wheel $PL; rm -f $MARK
  log "apply: 감시 데몬 설치(다음 부팅부터 동작). 백업 ~/EFI-backup-$TS, EFI OC/backup-before-rtd3"
  ;;
undo)
  efi
  cur=$(plutil -extract $K raw -o - "$C") || stop "boot-args 읽기 실패"
  plutil -replace $K -string "$(strip_args "$cur")" "$C" && plutil -lint "$C" >/dev/null || stop "되돌리기 실패"
  log "undo: boot-args = $(plutil -extract $K raw -o - "$C")"
  rm -f $MARK $PL
  launchctl bootout system/local.rtd3-watchdog 2>/dev/null
  ;;
watchdog)
  case " $(nvram boot-args 2>/dev/null) " in *" nvrtd3=1 "*) ;; *) log "watchdog: 이번 부팅에 nvrtd3 없음 — 할 일 없음"; rm -f $MARK; exit 0;; esac
  if [ -e $MARK ]; then
    log "watchdog: 이전 시험 부팅이 5분을 못 버팀 → 되돌리고 재부팅"
    "$0" undo; sync; sleep 5; shutdown -r now; exit 0
  fi
  touch $MARK; sync; log "watchdog: 시험 부팅 시작, 5분 감시"
  sleep 300
  rm -f $MARK; sync
  log "watchdog: 5분 통과 — 감시 데몬 제거"
  rm -f $PL
  launchctl bootout system/local.rtd3-watchdog 2>/dev/null
  ;;
*) stop "사용법: $0 apply|undo|watchdog";;
esac
sync; exit 0
