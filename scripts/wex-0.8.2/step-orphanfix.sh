#!/bin/bash
set -u
P=/Users/user/wex-0.8.2-port; MODE=${1:-}; INT=disk0s1
NEW=$P/out-orphan/WhateverXe.kext; NEW_SHA=adbddec5c9cedff6; CUR_SHA=f4ae9483bfab4370
BK=$P/backup-before-orphanfix; LOG=/var/log/wex082.log
MARK=/var/db/orphanfix.armed; PL=/Library/LaunchDaemons/local.orphanfix-watchdog.plist; SELF=/usr/local/libexec/step-orphanfix.sh
SC3PL=/Library/LaunchDaemons/local.safaricow3-watchdog.plist
sha() { shasum -a 256 "$1" | cut -c1-16; }
log() { echo "$(date '+%F %T') [orphanfix] $*" | tee -a $LOG; }
stop() { log "!! $* — 중단"; sync; exit 1; }
if [ "$MODE" = check ]; then
  kmutil showloaded 2>/dev/null | grep -o "org.b00t0x.WhateverXe ([0-9.]*) [0-9A-F-]*"
  ioreg -l -d1 -w0 | grep -oE '"(WhateverXeOrphanFixReady|WhateverXeOrphanFixed|WhateverXeOrphanNvram|WhateverXeHangProbeRouted)" = [A-Za-z0-9]*'
  echo "debug.wexorphanfix(이번 부팅 완료 처리한 stamp 수) = $(sysctl -n debug.wexorphanfix 2>/dev/null || echo 없음)"
  nvram -x wex-orphan 2>/dev/null | /usr/bin/python3 -I -c '
import sys,plistlib,struct
raw=sys.stdin.buffer.read()
if not raw.strip(): print("NVRAM wex-orphan: 없음(이번까지 처리·건너뜀 기록 없음)"); sys.exit()
d=plistlib.loads(raw).get("wex-orphan",b"")
if len(d)<16: print("wex-orphan 형식 이상",len(d)); sys.exit()
mg,ver,cnt,nv=struct.unpack_from("<4I",d,0); print("wex-orphan: magic=%08x ver=%d 건수=%d"%(mg,ver,cnt))
names={1:"완료 처리",3:"건너뜀(다른 stamp 의존 대기)",4:"건너뜀(미완료 수 범위 밖)",5:"건너뜀(부팅당 한도)",6:"건너뜀(대기열에 작업 남음)",7:"대기열 항목 취소 후 완료",8:"건너뜀(대기열 항목 검증 실패)"}
pf=lambda x:"빔" if x==0xffffffff else "큐밖" if x==0xfffffffe else "%x"%x
import time
for i in range(cnt):
  v=struct.unpack_from("<%dI"%nv,d,16+i*nv*4)
  idx=v[1]&0xff; cs=(v[1]>>8)&0xff; act=v[1]>>16
  print(" %s idx=%d 엔진=%d %s hw=%d 현재=%d 제출=%d 처리뒤hw=%d 대기마스크=%08x%08x 큐 head=%d tail=%d"%(
    time.strftime("%m-%d %H:%M:%S",time.localtime(v[0])),idx,cs,names.get(act,str(act)),v[2],v[3],v[4],v[5],v[7],v[6],v[8],v[9]))
  if nv>=22:
    print("    큐 미회수=%d 첫항목 플래그=%x stamp=%d | 엔진 큐마스크=%08x 커서=%d 포트셋=%d 정지=%d sched정지=%d | 포트 %s | accel1190=%08x 취소=%d"%(
      v[10],v[11],v[12],v[13],v[14],v[15]&0xff,(v[15]>>8)&0xff,(v[15]>>16)&0xff," ".join(pf(x) for x in v[16:20]),v[20],v[21]))
'
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
  [ "$(sha "$K")" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 safaricow3 빌드(f4ae9483)가 아님: $(sha "$K")"
  rm -rf "$BK"; mkdir -p "$BK" && ditto "$KX/WhateverXe.kext" "$BK/WhateverXe.kext" || stop "백업 실패"
  [ "$(sha "$BK/WhateverXe.kext/Contents/MacOS/WhateverXe")" = "$CUR_SHA" ] || stop "백업 검증 실패"
  [ -f "$SC3PL" ] && { cp -p "$SC3PL" "$BK/" || stop "safaricow3 감시 plist 백업 실패"; }
  putkext "$NEW" "$NEW_SHA" || { putkext "$BK/WhateverXe.kext" "$CUR_SHA"; stop "kext 교체 실패 → 되돌림"; }
  mkdir -p /usr/local/libexec && install -m 755 "$0" "$SELF"
  cat > $PL <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>local.orphanfix-watchdog</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>watchdog</string></array>
<key>RunAtLoad</key><true/></dict></plist>
EOF
  chmod 644 $PL; chown root:wheel $PL; rm -f $MARK; sync
  log "적용: EFI WEX $NEW_SHA (백업 $BK$([ -f "$BK/$(basename $SC3PL)" ] && echo ', safaricow3 감시 plist 포함')). 재부팅 뒤 bash $P/step-orphanfix.sh check" ;;
undo)
  [ -d "$BK/WhateverXe.kext" ] || stop "백업 없음"
  putkext "$BK/WhateverXe.kext" "$CUR_SHA" || stop "kext 복원 실패"
  if [ -f "$BK/$(basename $SC3PL)" ] && [ -f /usr/local/libexec/step-safaricow3.sh ]; then
    cp -p "$BK/$(basename $SC3PL)" "$SC3PL" && chown root:wheel "$SC3PL" && chmod 644 "$SC3PL"; rm -f /var/db/safaricow3.armed
  fi
  log "undo: EFI WEX $(sha "$K")(safaricow3)$([ -f "$SC3PL" ] && echo ', safaricow3 감시 되살림')"; rm -f $MARK $PL; sync
  [ -n "${NOBOOTOUT:-}" ] || launchctl bootout system/local.orphanfix-watchdog 2>/dev/null ;;
watchdog)
  [ "$(sha "$K")" = "$NEW_SHA" ] || { rm -f $MARK $PL; exit 0; }
  if [ -e $MARK ]; then log "watchdog: 이전 시험 부팅이 5분을 못 버팀 → undo 후 재부팅"; rm -f $PL; NOBOOTOUT=1 "$SELF" undo; sync; sleep 3; shutdown -r now; exit 0; fi
  touch $MARK; sync; log "watchdog: 시험 부팅 시작"
  ok=0; for i in $(seq 1 48); do ioreg -r -c IntelAccelerator -d1 -w0 | grep -q IntelAccelerator && { ok=1; break; }; sleep 5; done
  if [ $ok = 0 ]; then log "watchdog: Intel 가속 없음 → undo 후 재부팅"; rm -f $PL; NOBOOTOUT=1 "$SELF" undo; sync; sleep 3; shutdown -r now; exit 0; fi
  sleep 240; rm -f $MARK; sync
  log "watchdog: 5분 통과 — $(ioreg -l -d1 -w0 | grep -oE '"WhateverXeOrphanFixReady" = [A-Za-z]*'), safarilist $(sysctl -n debug.wexsafarilist 2>/dev/null)/$(sysctl -n debug.wexsafarilist_last 2>/dev/null)"
  rm -f $PL; launchctl bootout system/local.orphanfix-watchdog 2>/dev/null ;;
*) stop "사용법: $0 apply|undo|watchdog|check";;
esac
sync; exit 0
