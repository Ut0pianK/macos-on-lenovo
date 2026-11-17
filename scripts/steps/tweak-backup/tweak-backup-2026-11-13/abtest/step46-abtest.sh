#!/bin/bash
set -u
MODE=${1:-}; INT=disk0s1; D=/Users/user/tweak-backup-2026-11-13/abtest
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
LOG=/var/log/abtest.log; MARK=/var/db/abtest.armed
PL=/Library/LaunchDaemons/local.abtest-watchdog.plist; SELF=/usr/local/libexec/step46-abtest.sh
log() { echo "$(date '+%F %T') $*" | tee -a $LOG; }
stop() { log "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
efi() {
  mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "EFI 마운트 실패"
  MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"; OC="$MP/EFI/OC"; C="$OC/config.plist"
  KX="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-abtest"
}
case "$MODE" in
test)
  efi; [ -f "$D/WhateverXe-orig.kext/Contents/MacOS/WhateverXe" ] || stop "원본 kext 없음"
  TS=$(date +%Y-%m-%d-%H%M%S); cp -Rp "$MP/EFI" "/Users/user/EFI-backup-$TS" && chown -R user:staff "/Users/user/EFI-backup-$TS" || stop "EFI 백업 실패"
  mkdir -p "$BK" && cp -p "$C" "$BK/config.plist" && cp -p "$KX" "$BK/WhateverXe" || stop "백업 실패"
  cp "$D/WhateverXe-orig.kext/Contents/MacOS/WhateverXe" "$KX" || { cp -p "$BK/WhateverXe" "$KX"; stop "kext 교체 실패 → 되돌림"; }
  cur=$(plutil -extract $K raw -o - "$C")
  new=$(echo " $cur " | perl -pe 's/ -wex-(?:userpatch|launchpad|vpfix|gpustat|bootseamless|bootquiet|hangfinish)(?= )//g; s/^ +//; s/ +$//')
  plutil -replace $K -string "$new" "$C" && plutil -lint "$C" >/dev/null || { cp -p "$BK/config.plist" "$C"; cp -p "$BK/WhateverXe" "$KX"; stop "config 실패 → 되돌림"; }
  log "test: kext $(shasum -a 256 "$KX" | cut -c1-12), boot-args = $new (백업 ~/EFI-backup-$TS)"
  mkdir -p /usr/local/libexec && install -m 755 "$0" "$SELF"
  cat > $PL <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>local.abtest-watchdog</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>watchdog</string></array>
<key>RunAtLoad</key><true/></dict></plist>
EOF
  chmod 644 $PL; chown root:wheel $PL; rm -f $MARK ;;
restore)
  efi; [ -f "$BK/config.plist" ] && [ -f "$BK/WhateverXe" ] || stop "백업 없음"
  cp -p "$BK/config.plist" "$C" && cp -p "$BK/WhateverXe" "$KX" && plutil -lint "$C" >/dev/null || stop "되돌리기 실패"
  log "restore: kext $(shasum -a 256 "$KX" | cut -c1-12), boot-args = $(plutil -extract $K raw -o - "$C")"
  rm -f $MARK $PL; launchctl bootout system/local.abtest-watchdog 2>/dev/null ;;
watchdog)
  [ -e $MARK ] && { log "watchdog: 이전 시험 부팅이 5분을 못 버팀 → 되돌리고 재부팅"; "$0" restore; sync; sleep 5; shutdown -r now; exit 0; }
  touch $MARK; sync; log "watchdog: 시험 부팅 시작, 5분 감시"; sleep 300; rm -f $MARK; sync; log "watchdog: 5분 통과"
  rm -f $PL; launchctl bootout system/local.abtest-watchdog 2>/dev/null ;;
*) stop "사용법: $0 test|restore|watchdog";;
esac
sync; exit 0
