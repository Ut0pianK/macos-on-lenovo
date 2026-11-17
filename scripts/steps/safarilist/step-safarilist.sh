#!/bin/bash
set -u
P=/Users/user/wex-0.8.2-port; MODE=${1:-}; INT=disk0s1
NEW=$P/out-safarilist/WhateverXe.kext; NEW_SHA=1b30e7af46f209ad; CUR_SHA=79631edaf3fbabce
SAFE=$P/backup-before-hangprobe2/WhateverXe.kext; SAFE_SHA=5d1b8d7f79ee9cc6
BK=$P/backup-before-safarilist; LOG=/var/log/wex082.log; ARG=-wex-safarilist
MARK=/var/db/safarilist.armed; PL=/Library/LaunchDaemons/local.safarilist-watchdog.plist; SELF=/usr/local/libexec/step-safarilist.sh
FW=/System/Volumes/Preboot/Cryptexes/App/System/Library/StagedFrameworks/Safari/Safari.framework/Versions/A/Safari
sha() { shasum -a 256 "$1" | cut -c1-16; }
log() { echo "$(date '+%F %T') [safarilist] $*" | tee -a $LOG; }
stop() { log "!! $* — 중단"; sync; exit 1; }
if [ "$MODE" = check ]; then
  sysctl -n kern.bootargs | grep -q -- "$ARG" && echo "boot-arg: 있음" || echo "boot-arg: 없음"
  kmutil showloaded 2>/dev/null | grep -o "org.b00t0x.WhateverXe ([0-9.]*)"
  echo "Safari.framework 파일(디스크)은 그대로여야 함: $(sha "$FW")"
  P1=$(pgrep -x Safari | head -1); [ -n "$P1" ] || { echo "Safari 미실행 — 실행 뒤 다시 check"; exit 0; }
  sudo -n /usr/bin/python3 -I - "$P1" <<'PY'
import sys,subprocess,re,ctypes,ctypes.util
pid=int(sys.argv[1])
out=subprocess.run(['vmmap','-wide',str(pid)],capture_output=True,text=True).stdout
base=None
for l in out.splitlines():
    if l.startswith('__TEXT') and l.rstrip().endswith('Safari.framework/Versions/A/Safari'):
        base=int(re.search(r'([0-9a-f]+)-[0-9a-f]+',l).group(1),16); break
if base is None: print('Safari.framework __TEXT 를 못 찾음'); sys.exit()
lib=ctypes.CDLL(ctypes.util.find_library('c'))
task=ctypes.c_uint();
if lib.task_for_pid(lib.mach_task_self(),pid,ctypes.byref(task))!=0: print('task_for_pid 실패(SIP 디버깅 제한) — 화면으로 확인'); sys.exit()
def rd(a,n):
    buf=ctypes.create_string_buffer(n); got=ctypes.c_ulong(0)
    lib.mach_vm_read_overwrite.argtypes=[ctypes.c_uint,ctypes.c_ulonglong,ctypes.c_ulonglong,ctypes.c_void_p,ctypes.POINTER(ctypes.c_ulong)]
    r=lib.mach_vm_read_overwrite(task,a,n,buf,ctypes.byref(got)); return buf.raw if r==0 else None
for name,off in (('CompletionListWindow',0x7b68b0),('AutoFillCompletionWindow',0x13fd21)):
    b=rd(base+off,11); print(name, b.hex() if b else '읽기 실패', '→ 패치됨' if b and b[5]==0 else '→ 원본')
PY
  exit 0
fi
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "EFI 마운트 실패"
MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"; KX="$MP/EFI/OC/Kexts"; K="$KX/WhateverXe.kext/Contents/MacOS/WhateverXe"; CFG="$MP/EFI/OC/config.plist"
[ -f "$K" ] && [ -f "$CFG" ] || stop "EFI 에 WhateverXe/config.plist 없음"
bootargs() { plutil -extract NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args raw "$1"; }
setargs() { /usr/bin/python3 -I - "$CFG" "$1" <<'PY'
import sys,re
p,mode=sys.argv[1],sys.argv[2]; s=open(p,encoding='utf-8').read(); arg='-wex-safarilist'
m=re.findall(r'(<key>boot-args</key>\s*<string>)([^<]*)(</string>)',s)
if len(m)!=1: sys.exit('boot-args 항목이 1개가 아님: %d'%len(m))
old=m[0][1]; words=[w for w in old.split(' ') if w and w!=arg]
new=' '.join(words+[arg]) if mode=='add' else ' '.join(words)
s2=s.replace(m[0][0]+old+m[0][2],m[0][0]+new+m[0][2],1)
open(p+'.new','w',encoding='utf-8').write(s2)
PY
  [ -s "$CFG.new" ] && plutil -lint "$CFG.new" >/dev/null || { rm -f "$CFG.new"; return 1; }
  mv "$CFG.new" "$CFG"; }
putkext() { rm -rf "$KX/WhateverXe.kext" && ditto "$1" "$KX/WhateverXe.kext" && [ "$(sha "$K")" = "$2" ]; }
case "$MODE" in
apply)
  [ "$(sha "$NEW/Contents/MacOS/WhateverXe")" = "$NEW_SHA" ] || stop "새 빌드 해시 불일치"
  [ "$(sha "$SAFE/Contents/MacOS/WhateverXe")" = "$SAFE_SHA" ] || stop "안전 복귀용 1판 백업 해시 불일치"
  [ "$(sha "$K")" = "$CUR_SHA" ] || stop "EFI 의 WhateverXe 가 계측 2판(79631eda)이 아님: $(sha "$K")"
  rm -rf "$BK"; mkdir -p "$BK" && ditto "$KX/WhateverXe.kext" "$BK/WhateverXe.kext" && cp -p "$CFG" "$BK/config.plist" || stop "백업 실패"
  OLD="$(bootargs "$CFG")"
  putkext "$NEW" "$NEW_SHA" || { putkext "$BK/WhateverXe.kext" "$CUR_SHA"; stop "kext 교체 실패 → 되돌림"; }
  setargs add && [ "$(bootargs "$CFG")" = "$OLD $ARG" ] || { cp -p "$BK/config.plist" "$CFG"; putkext "$BK/WhateverXe.kext" "$CUR_SHA"; stop "boot-args 수정 실패 → 되돌림"; }
  mkdir -p /usr/local/libexec && install -m 755 "$0" "$SELF"
  cat > $PL <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>local.safarilist-watchdog</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>watchdog</string></array>
<key>RunAtLoad</key><true/></dict></plist>
EOF
  chmod 644 $PL; chown root:wheel $PL; rm -f $MARK; sync
  log "적용: EFI WEX $NEW_SHA + boot-arg $ARG (백업 $BK). 재부팅 뒤 bash $P/step-safarilist.sh check" ;;
undo)
  [ -d "$BK/WhateverXe.kext" ] && [ -f "$BK/config.plist" ] || stop "백업 없음"
  putkext "$BK/WhateverXe.kext" "$CUR_SHA" || stop "kext 복원 실패"
  cp -p "$BK/config.plist" "$CFG" && plutil -lint "$CFG" >/dev/null || stop "config 복원 실패"
  log "undo: EFI WEX $(sha "$K"), boot-args 원래대로"; rm -f $MARK $PL; sync
  launchctl bootout system/local.safarilist-watchdog 2>/dev/null ;;
safe)
  putkext "$SAFE" "$SAFE_SHA" || stop "1판 복원 실패"
  setargs del || stop "boot-args 복원 실패"
  log "safe: EFI WEX $(sha "$K")(계측 1판), $ARG 제거"; rm -f $MARK; sync ;;
watchdog)
  [ "$(sha "$K")" = "$NEW_SHA" ] || { rm -f $MARK $PL; exit 0; }
  if [ -e $MARK ]; then log "watchdog: 이전 시험 부팅이 5분을 못 버팀 → 1판으로 되돌리고 재부팅"; rm -f $PL; "$SELF" safe; sync; sleep 3; shutdown -r now; exit 0; fi
  touch $MARK; sync; log "watchdog: 시험 부팅 시작"
  ok=0; for i in $(seq 1 48); do ioreg -r -c IntelAccelerator -d1 -w0 | grep -q IntelAccelerator && { ok=1; break; }; sleep 5; done
  if [ $ok = 0 ]; then log "watchdog: Intel 가속 없음 → 1판으로 되돌리고 재부팅"; rm -f $PL; "$SELF" safe; sync; sleep 3; shutdown -r now; exit 0; fi
  sleep 240; rm -f $MARK; sync
  log "watchdog: 5분 통과 — $(sysctl -n kern.bootargs | grep -o -- "$ARG") $(ioreg -l -d1 -w0 | grep -oE '"WhateverXeHangProbeRouted" = [A-Za-z]*')"
  rm -f $PL; launchctl bootout system/local.safarilist-watchdog 2>/dev/null ;;
*) stop "사용법: $0 apply|undo|watchdog|check";;
esac
sync; exit 0
