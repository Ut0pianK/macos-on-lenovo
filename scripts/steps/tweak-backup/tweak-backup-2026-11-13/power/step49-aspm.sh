#!/bin/bash
set -u
MODE=${1:-}; INT=disk0s1; K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
LOG=/var/log/aspm-trial.log; MARK=/var/db/aspm-trial.armed
PL=/Library/LaunchDaemons/local.aspm-watchdog.plist; SELF=/usr/local/libexec/step49-aspm.sh
PATHS=("PciRoot(0x0)/Pci(0x1C,0x0)" "PciRoot(0x0)/Pci(0x1C,0x0)/Pci(0x0,0x0)" "PciRoot(0x0)/Pci(0x1D,0x0)" "PciRoot(0x0)/Pci(0x1D,0x0)/Pci(0x0,0x0)")
log() { echo "$(date '+%F %T') $*" | tee -a $LOG; }
stop() { log "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
efi() {
  mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "EFI 마운트 실패"
  MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"; C="$MP/EFI/OC/config.plist"; BK="$MP/EFI/OC/backup-before-aspm"
}
case "$MODE" in
apply)
  efi; TS=$(date +%Y-%m-%d-%H%M%S)
  cp -Rp "$MP/EFI" "/Users/user/EFI-backup-$TS" && chown -R user:staff "/Users/user/EFI-backup-$TS" || stop "EFI 백업 실패"
  mkdir -p "$BK" && cp -p "$C" "$BK/config.plist" || stop "config 백업 실패"
  for p in "${PATHS[@]}"; do
    /usr/libexec/PlistBuddy -c "Add :DeviceProperties:Add:$p dict" "$C" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Delete :DeviceProperties:Add:$p:pci-aspm-default" "$C" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Add :DeviceProperties:Add:$p:pci-aspm-default data" "$C" || { cp -p "$BK/config.plist" "$C"; stop "속성 추가 실패"; }
  done
  for p in "${PATHS[@]}"; do
    kp="DeviceProperties.Add.$(echo "$p" | sed 's/\./\\./g').pci-aspm-default"
    plutil -replace "$kp" -data AgAAAA== "$C" || { cp -p "$BK/config.plist" "$C"; stop "값 쓰기 실패"; }
  done
  cur=$(plutil -extract $K raw -o - "$C")
  case " $cur " in *" nvrmaspm=1 "*) ;; *) plutil -replace $K -string "$cur nvrmaspm=1" "$C";; esac
  plutil -lint "$C" >/dev/null || { cp -p "$BK/config.plist" "$C"; stop "형식 오류 → 되돌림"; }
  for p in "${PATHS[@]}"; do log "apply: $p = $(/usr/libexec/PlistBuddy -c "Print :DeviceProperties:Add:$p:pci-aspm-default" "$C" | xxd -p)"; done
  log "apply: boot-args = $(plutil -extract $K raw -o - "$C") (백업 ~/EFI-backup-$TS)"
  mkdir -p /usr/local/libexec && install -m 755 "$0" "$SELF"
  cat > $PL <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>local.aspm-watchdog</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>watchdog</string></array>
<key>RunAtLoad</key><true/></dict></plist>
EOF
  chmod 644 $PL; chown root:wheel $PL; rm -f $MARK ;;
undo)
  efi; [ -f "$BK/config.plist" ] || stop "백업 없음"
  cp -p "$BK/config.plist" "$C" && plutil -lint "$C" >/dev/null || stop "되돌리기 실패"
  log "undo: config 복구"; rm -f $MARK $PL; sync; [ -n "${NOBOOTOUT:-}" ] && exit 0
  launchctl bootout system/local.aspm-watchdog 2>/dev/null ;;
watchdog)
  case " $(nvram boot-args) " in *" nvrmaspm=1 "*) ;; *) rm -f $MARK $PL; exit 0;; esac
  if [ -e $MARK ]; then log "watchdog: 이전 시험 부팅이 5분을 못 버팀 → 되돌리고 재부팅"; NOBOOTOUT=1 "$SELF" undo; sync; sleep 3; shutdown -r now; exit 0; fi
  touch $MARK; sync; log "watchdog: 시험 부팅 시작, 5분 감시"; sleep 300; rm -f $MARK; sync; log "watchdog: 5분 통과"
  rm -f $PL; launchctl bootout system/local.aspm-watchdog 2>/dev/null ;;
*) stop "사용법: $0 apply|undo|watchdog";;
esac
sync; exit 0
