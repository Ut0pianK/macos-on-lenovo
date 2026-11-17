#!/bin/bash
set -u
MODE=${1:-}; INT=disk0s1; K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
ARGS='-nodisplaysleepDC6 -noDC9 dc6config=0'
LOG=/var/log/dc6-trial.log; SELF=/usr/local/libexec/step53-dc6.sh; TRIG=/Users/user/.dc6-undo
PG=/Library/LaunchDaemons/local.dc6-guard.plist; PT=/Library/LaunchDaemons/local.dc6-trigger.plist
log() { echo "$(date '+%F %T') $*" | tee -a $LOG; }
stop() { log "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
efi() {
  mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "EFI 마운트 실패"
  MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"; C="$MP/EFI/OC/config.plist"; BK="$MP/EFI/OC/backup-before-dc6-2"
}
undo_reboot() { log "$1 → 되돌리고 재부팅"; NOBOOTOUT=1 "$SELF" undo; sync; sleep 3; shutdown -r now; }
case "$MODE" in
apply)
  efi; TS=$(date +%Y-%m-%d-%H%M%S)
  cp -Rp "$MP/EFI" "/Users/user/EFI-backup-$TS" && chown -R user:staff "/Users/user/EFI-backup-$TS" || stop "EFI 백업 실패"
  mkdir -p "$BK" && cp -p "$C" "$BK/config.plist" || stop "config 백업 실패"
  cur=$(plutil -extract $K raw -o - "$C")
  new=$(echo " $cur " | perl -pe 's/ (?:-nodisplaysleepDC6|-noDC9|dc6config=\S+)(?= )//g; s/^ +//; s/ +$//')
  plutil -replace $K -string "$new" "$C" && plutil -lint "$C" >/dev/null || { cp -p "$BK/config.plist" "$C"; stop "쓰기 실패 → 되돌림"; }
  log "apply: kext $(shasum -a 256 "$MP/EFI/OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe" | cut -c1-12), boot-args = $new (백업 ~/EFI-backup-$TS)"
  mkdir -p /usr/local/libexec && install -m 755 "$0" "$SELF"; rm -f "$TRIG"
  for m in guard trigger; do
    P=/Library/LaunchDaemons/local.dc6-$m.plist
    extra=""; [ $m = guard ] && extra="<key>KeepAlive</key><true/>"
    [ $m = trigger ] && extra="<key>WatchPaths</key><array><string>$TRIG</string></array>"
    cat > $P <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>local.dc6-$m</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>$m</string></array>
<key>RunAtLoad</key><true/>$extra</dict></plist>
EOF
    chmod 644 $P; chown root:wheel $P
  done
  log "apply: 감시 데몬 설치(다음 부팅부터). 원격 복구: touch ~/.dc6-undo" ;;
undo)
  efi; cur=$(plutil -extract $K raw -o - "$C")
  case " $cur " in *" -nodisplaysleepDC6 "*) log "undo: 이미 들어 있음";;
    *) plutil -replace $K -string "$cur $ARGS" "$C" && plutil -lint "$C" >/dev/null || stop "되돌리기 실패"
       log "undo: boot-args = $(plutil -extract $K raw -o - "$C")";; esac
  rm -f $PG $PT "$TRIG"; sync; [ -n "${NOBOOTOUT:-}" ] && exit 0
  launchctl bootout system/local.dc6-trigger 2>/dev/null; launchctl bootout system/local.dc6-guard 2>/dev/null ;;
guard)
  case " $(nvram boot-args) " in *" -nodisplaysleepDC6 "*) exit 0;; esac
  /usr/bin/log stream --style compact --predicate 'process == "kernel" AND (eventMessage CONTAINS "link training failed" OR eventMessage CONTAINS "DBUF 2 power up timeout")' 2>/dev/null |
  while read -r line; do case "$line" in Filtering*|Timestamp*) continue;; *kernel*"link training failed"*|*kernel*"power up timeout"*) undo_reboot "guard: 검은 화면 신호 감지: ${line:0:160}"; exit 0;; esac; done ;;
trigger)
  [ -e "$TRIG" ] && undo_reboot "trigger: ~/.dc6-undo 감지" ;;
*) stop "사용법: $0 apply|undo|guard|trigger";;
esac
sync; exit 0
