#!/bin/bash
set -u
P=/Users/user/wex-0.8.2-port; MODE=${1:-}; INT=disk0s1; ARG=-wex-safarilist
NEW=$P/out-safaricow/WhateverXe.kext; NEW_SHA=e81f7dcc4f0f0bc9; CUR_SHA=c8fe8f581b05bd12
SAFE=$P/backup-before-nvsync/WhateverXe.kext; SAFE_SHA=1b30e7af46f209ad
BK=$P/backup-before-safaricow; LOG=/var/log/wex082.log
MARK=/var/db/safaricow.armed; PL=/Library/LaunchDaemons/local.safaricow-watchdog.plist; SELF=/usr/local/libexec/step-safaricow.sh
FW=/System/Volumes/Preboot/Cryptexes/App/System/Library/StagedFrameworks/Safari/Safari.framework/Versions/A/Safari
sha() { shasum -a 256 "$1" | cut -c1-16; }
log() { echo "$(date '+%F %T') [safaricow] $*" | tee -a $LOG; }
stop() { log "!! $* — 중단"; sync; exit 1; }
if [ "$MODE" = check ]; then
  kmutil showloaded 2>/dev/null | grep -o "org.b00t0x.WhateverXe ([0-9.]*) [0-9A-F-]*"
  sysctl -n kern.bootargs | grep -q -- "$ARG" && echo "boot-arg $ARG: 있음" || echo "boot-arg $ARG: 없음"
  echo "debug.wexsafarilist(이번 부팅 패치한 Safari 실행 수) = $(sysctl -n debug.wexsafarilist 2>/dev/null || echo 없음)"
  echo "debug.wexsafarilist_last(1 패치, 2 이미, <0 오류) = $(sysctl -n debug.wexsafarilist_last 2>/dev/null || echo 없음)"
  sudo -n dmesg 2>/dev/null | grep -a "safarilist" | tail -5
  if dd if="$FW" of=/dev/null bs=1m 2>/dev/null; then echo "Safari.framework 파일 읽기: 정상"; else echo "Safari.framework 파일 읽기: I/O 오류(UBC 손상)"; fi
  /usr/bin/log show --last 1h --style compact --predicate 'process == "kernel" AND eventMessage CONTAINS "hash mismatch"' 2>/dev/null | grep -c "hash mismatch" | sed 's/^/최근 1시간 APFS hash mismatch: /'
  exit 0
fi
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "EFI 마운트 실패"
MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"
[ "$MP" = /Volumes/EFI ] || stop "EFI 가 /Volumes/EFI 가 아닌 $MP 에 마운트됨"
KX="$MP/EFI/OC/Kexts"; K="$KX/WhateverXe.kext/Contents/MacOS/WhateverXe"; CFG="$MP/EFI/OC/config.plist"
[ -f "$K" ] && [ -f "$CFG" ] || stop "EFI 에 WhateverXe/config.plist 없음"
bootargs() { plutil -extract NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args raw "$1"; }
delarg() { /usr/bin/python3 -I - "$CFG" <<'PY'
import sys,re
p=sys.argv[1]; s=open(p,encoding='utf-8').read(); arg='-wex-safarilist'
m=re.findall(r'(<key>boot-args</key>\s*<string>)([^<]*)(</string>)',s)
if len(m)!=1: sys.exit('boot-args 항목이 1개가 아님: %d'%len(m))
old=m[0][1]; new=' '.join(w for w in old.split(' ') if w and w!=arg)
open(p+'.new','w',encoding='utf-8').write(s.replace(m[0][0]+old+m[0][2],m[0][0]+new+m[0][2],1))
PY
  [ -s "$CFG.new" ] && plutil -lint "$CFG.new" >/dev/null || { rm -f "$CFG.new"; return 1; }
  mv "$CFG.new" "$CFG"; ! bootargs "$CFG" | grep -q -- "$ARG"; }
putkext() { rm -rf "$KX/WhateverXe.kext" && ditto "$1" "$KX/WhateverXe.kext" && [ "$(sha "$K")" = "$2" ]; }
case "$MODE" in
apply)
  [ "$(sha "$NEW/Contents/MacOS/WhateverXe")" = "$NEW_SHA" ] || stop "새 빌드 해시 불일치"
  [ "$(sha "$SAFE/Contents/MacOS/WhateverXe")" = "$SAFE_SHA" ] || stop "안전 복귀용 safarilist 빌드 백업 해시 불일치"
  [ "$(sha "$K")" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 nvsync 빌드(c8fe8f58)가 아님: $(sha "$K")"
  bootargs "$CFG" | grep -q -- "$ARG" || stop "boot-args 에 $ARG 없음"
  rm -rf "$BK"; mkdir -p "$BK" && ditto "$KX/WhateverXe.kext" "$BK/WhateverXe.kext" && cp -p "$CFG" "$BK/config.plist" || stop "백업 실패"
  [ "$(sha "$BK/WhateverXe.kext/Contents/MacOS/WhateverXe")" = "$CUR_SHA" ] || stop "백업 검증 실패"
  putkext "$NEW" "$NEW_SHA" || { putkext "$BK/WhateverXe.kext" "$CUR_SHA"; stop "kext 교체 실패 → 되돌림"; }
  mkdir -p /usr/local/libexec && install -m 755 "$0" "$SELF"
  cat > $PL <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>local.safaricow-watchdog</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>watchdog</string></array>
<key>RunAtLoad</key><true/></dict></plist>
EOF
  chmod 644 $PL; chown root:wheel $PL; rm -f $MARK; sync
  log "적용: EFI WEX $NEW_SHA (백업 $BK). 재부팅 뒤 bash $P/step-safaricow.sh check" ;;
undo)
  [ -d "$BK/WhateverXe.kext" ] || stop "백업 없음"
  putkext "$BK/WhateverXe.kext" "$CUR_SHA" || stop "kext 복원 실패"
  delarg || stop "boot-args 수정 실패"
  log "undo: EFI WEX $(sha "$K")(nvsync), $ARG 제거"; rm -f $MARK $PL; sync
  [ -n "${NOBOOTOUT:-}" ] || launchctl bootout system/local.safaricow-watchdog 2>/dev/null ;;
safe)
  putkext "$SAFE" "$SAFE_SHA" || stop "safarilist 빌드 복원 실패"
  delarg || stop "boot-args 수정 실패"
  log "safe: EFI WEX $(sha "$K")(부팅 검증된 빌드), $ARG 제거"; rm -f $MARK; sync ;;
watchdog)
  [ "$(sha "$K")" = "$NEW_SHA" ] || { rm -f $MARK $PL; exit 0; }
  if [ -e $MARK ]; then log "watchdog: 이전 시험 부팅이 5분을 못 버팀 → safe 후 재부팅"; rm -f $PL; "$SELF" safe; sync; sleep 3; shutdown -r now; exit 0; fi
  touch $MARK; sync; log "watchdog: 시험 부팅 시작"
  ok=0; for i in $(seq 1 48); do ioreg -r -c IntelAccelerator -d1 -w0 | grep -q IntelAccelerator && { ok=1; break; }; sleep 5; done
  if [ $ok = 0 ]; then log "watchdog: Intel 가속 없음 → safe 후 재부팅"; rm -f $PL; "$SELF" safe; sync; sleep 3; shutdown -r now; exit 0; fi
  sleep 240; rm -f $MARK; sync
  log "watchdog: 5분 통과 — safarilist $(sysctl -n debug.wexsafarilist 2>/dev/null)/$(sysctl -n debug.wexsafarilist_last 2>/dev/null)"
  rm -f $PL; launchctl bootout system/local.safaricow-watchdog 2>/dev/null ;;
*) stop "사용법: $0 apply|undo|safe|watchdog|check";;
esac
sync; exit 0
