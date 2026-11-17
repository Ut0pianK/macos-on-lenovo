#!/bin/bash
set -u
MODE=${1:-}; T=/Users/user/nvidia-trial; INT=disk0s1
NEW=$T/build/wex-0.8.0-psys-RELEASE/WhateverXe.kext/Contents/MacOS/WhateverXe
NEW_SHA=166538848326df5ebe2199f893f63903f2495cdb97b7bd9a9cc4b22cbc0297b1
CUR_SHA=2fa88051ddcbe4d2a15eeeea315ad6ba95491321828d369dff00160fff995196
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
LOG=/var/log/psr1.log; MARK=/var/db/psys.armed
PL=/Library/LaunchDaemons/local.psys-watchdog.plist; SELF=/usr/local/libexec/step63-psys.sh
log() { echo "$(date '+%F %T') $*" | tee -a $LOG; }
stop() { log "!! $* — 중단"; sync; exit 1; }
stat() { ioreg -l -d1 -w0 | sed -n 's/.*"WhateverXePsrStat" = <\([0-9a-f]*\)>.*/\1/p'; }
[ "$(id -u)" = 0 ] || stop "root 필요"
efi() {
  mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "EFI 마운트 실패"
  MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"; OC="$MP/EFI/OC"; C="$OC/config.plist"
  kx="$OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe"; BK="$OC/backup-before-psys"
}
case "$MODE" in
apply)
  efi
  [ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "새 kext 해시 불일치"
  [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 epp(2fa88051)가 아님"
  TS=$(date +%Y-%m-%d-%H%M%S); cp -Rp "$MP/EFI" "/Users/user/EFI-backup-$TS" && chown -R user:staff "/Users/user/EFI-backup-$TS" || stop "EFI 전체 백업 실패"
  mkdir -p "$BK" && cp -p "$kx" "$BK/WhateverXe" && cp -p "$C" "$BK/config.plist" || stop "백업 실패"
  cp "$NEW" "$kx" && [ "$(shasum -a 256 "$kx" | cut -d' ' -f1)" = "$NEW_SHA" ] || { cp -p "$BK/WhateverXe" "$kx"; stop "kext 쓰기 실패 → 되돌림"; }
  cur=$(plutil -extract $K raw -o - "$C")
  case " $cur " in *" -wex-noturbo "*) ;; *) plutil -replace $K -string "$cur -wex-noturbo" "$C" && plutil -lint "$C" >/dev/null || { cp -p "$BK/config.plist" "$C"; cp -p "$BK/WhateverXe" "$kx"; stop "boot-args 실패 → 되돌림"; };; esac
  log "apply: kext 16653884, boot-args = $(plutil -extract $K raw -o - "$C") (백업 ~/EFI-backup-$TS)"
  mkdir -p /usr/local/libexec && install -m 755 "$0" "$SELF"
  cat > $PL <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>local.psys-watchdog</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>watchdog</string></array>
<key>RunAtLoad</key><true/></dict></plist>
EOF
  chmod 644 $PL; chown root:wheel $PL; rm -f $MARK ;;
undo)
  efi; [ -f "$BK/WhateverXe" ] && [ -f "$BK/config.plist" ] || stop "백업 없음"
  cp -p "$BK/WhateverXe" "$kx" && cp -p "$BK/config.plist" "$C" && plutil -lint "$C" >/dev/null || stop "되돌리기 실패"
  log "undo: kext $(shasum -a 256 "$kx" | cut -c1-8)"
  rm -f $MARK $PL; sync; [ -n "${NOBOOTOUT:-}" ] && exit 0
  launchctl bootout system/local.psys-watchdog 2>/dev/null ;;
watchdog)
  case " $(nvram boot-args) " in *" -wex-pmcstat "*) ;; *) rm -f $MARK $PL; exit 0;; esac
  if [ -e $MARK ]; then log "watchdog: 이전 시험 부팅이 5분을 못 버팀 → 되돌리고 재부팅"; NOBOOTOUT=1 "$SELF" undo; sync; sleep 3; shutdown -r now; exit 0; fi
  touch $MARK; sync; log "watchdog: 시험 부팅 시작, 5분 감시"
  sleep 300; rm -f $MARK; sync
  log "watchdog: 5분 통과 — psr1stat $(ioreg -l -d1 -w0 | sed -n 's/.*"WhateverXePsr1Stat" = <\([0-9a-f]*\)>.*/\1/p' | cut -c1-128)"
  rm -f $PL; launchctl bootout system/local.psys-watchdog 2>/dev/null ;;
*) stop "사용법: $0 apply|undo|watchdog";;
esac
sync; exit 0
