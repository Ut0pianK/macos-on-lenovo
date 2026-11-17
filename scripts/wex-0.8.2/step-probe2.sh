#!/bin/bash
set -u
P=/Users/user/wex-0.8.2-port; MODE=${1:-}; INT=disk0s1
NEW=$P/out-orphan2/WhateverXe.kext; NEW_SHA=6e7e639ffbbcf424; CUR_SHA=adbddec5c9cedff6
BK=$P/backup-before-probe2; LOG=/var/log/wex082.log
MARK=/var/db/probe2.armed; PL=/Library/LaunchDaemons/local.probe2-watchdog.plist; SELF=/usr/local/libexec/step-probe2.sh
SC3PL=/Library/LaunchDaemons/local.safaricow3-watchdog.plist
sha() { shasum -a 256 "$1" | cut -c1-16; }
log() { echo "$(date '+%F %T') [probe2] $*" | tee -a $LOG; }
stop() { log "!! $* — 중단"; sync; exit 1; }
if [ "$MODE" = check ]; then
  bash $P/step-orphanfix.sh check; echo "--- 계측 기록"; bash $P/step-hangprobe2.sh check 2>&1 | tail -n +1
  exit 0
fi
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "EFI 마운트 실패"
MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"
[ "$MP" = /Volumes/EFI ] || stop "EFI 가 /Volumes/EFI 가 아닌 $MP 에 마운트됨(다른 세션 사용 중으로 봄)"
KX="$MP/EFI/OC/Kexts"; K="$KX/WhateverXe.kext/Contents/MacOS/WhateverXe"
[ -f "$K" ] || stop "EFI 에 WhateverXe 없음"
putkext() { rm -rf "$KX/WhateverXe.kext" && ditto "$1" "$KX/WhateverXe.kext" && [ "$(sha "$K")" = "$2" ]; }
case "$MODE" in
apply)
  [ "$(sha "$NEW/Contents/MacOS/WhateverXe")" = "$NEW_SHA" ] || stop "새 빌드 해시 불일치"
  [ "$(sha "$K")" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 orphanfix 빌드(adbddec5)가 아님: $(sha "$K")"
  rm -rf "$BK"; mkdir -p "$BK" && ditto "$KX/WhateverXe.kext" "$BK/WhateverXe.kext" || stop "백업 실패"
  [ "$(sha "$BK/WhateverXe.kext/Contents/MacOS/WhateverXe")" = "$CUR_SHA" ] || stop "백업 검증 실패"
  putkext "$NEW" "$NEW_SHA" || { putkext "$BK/WhateverXe.kext" "$CUR_SHA"; stop "kext 교체 실패 → 되돌림"; }
  mkdir -p /usr/local/libexec && install -m 755 "$0" "$SELF"
  cat > $PL <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>local.probe2-watchdog</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>watchdog</string></array>
<key>RunAtLoad</key><true/></dict></plist>
EOF
  chmod 644 $PL; chown root:wheel $PL; rm -f $MARK; sync
  log "적용: EFI WEX $NEW_SHA (백업 $BK). 재부팅 뒤 bash $P/step-probe2.sh check" ;;
undo)
  [ -d "$BK/WhateverXe.kext" ] || stop "백업 없음"
  putkext "$BK/WhateverXe.kext" "$CUR_SHA" || stop "kext 복원 실패"
  log "undo: EFI WEX $(sha "$K")(orphanfix)"; rm -f $MARK $PL; sync
  [ -n "${NOBOOTOUT:-}" ] || launchctl bootout system/local.probe2-watchdog 2>/dev/null ;;
watchdog)
  [ "$(sha "$K")" = "$NEW_SHA" ] || { rm -f $MARK $PL; exit 0; }
  if [ -e $MARK ]; then log "watchdog: 이전 시험 부팅이 5분을 못 버팀 → undo 후 재부팅"; rm -f $PL; NOBOOTOUT=1 "$SELF" undo; sync; sleep 3; shutdown -r now; exit 0; fi
  touch $MARK; sync; log "watchdog: 시험 부팅 시작"
  ok=0; for i in $(seq 1 48); do ioreg -r -c IntelAccelerator -d1 -w0 | grep -q IntelAccelerator && { ok=1; break; }; sleep 5; done
  if [ $ok = 0 ]; then log "watchdog: Intel 가속 없음 → undo 후 재부팅"; rm -f $PL; NOBOOTOUT=1 "$SELF" undo; sync; sleep 3; shutdown -r now; exit 0; fi
  sleep 240; rm -f $MARK; sync
  log "watchdog: 5분 통과 — $(ioreg -l -d1 -w0 | grep -oE '"WhateverXeOrphanFixReady" = [A-Za-z]*'), safarilist $(sysctl -n debug.wexsafarilist 2>/dev/null)/$(sysctl -n debug.wexsafarilist_last 2>/dev/null)"
  rm -f $PL; launchctl bootout system/local.probe2-watchdog 2>/dev/null ;;
*) stop "사용법: $0 apply|undo|watchdog|check";;
esac
sync; exit 0
