#!/bin/bash
set -u
T=/Users/user/nvidia-trial; MODE=${1:-}
NEW_RM=$T/build/nvrm-vramstat/NVRM.kext/Contents/MacOS/NVRM;        NEW_RM_SHA=d946d888705ae286
NEW_AC=$T/build/nvaccel-vramstat/NVAccel.kext/Contents/MacOS/NVAccel; NEW_AC_SHA=9e5bbf98da6c4fb2
CUR_RM=/Library/Extensions/NVRM.kext/Contents/MacOS/NVRM;          CUR_RM_SHA=2cfd82148bccaaa9
CUR_AC=/Library/Extensions/NVAccel.kext/Contents/MacOS/NVAccel;    CUR_AC_SHA=41f60bf7b60c3f16
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc; BK=$T/backup-before-vramstat
V2=4969d64073010048c1ea10909090909090909090909090
NEED="com.apple.driver.AppleIntelTGLGraphics com.apple.driver.AppleIntelTGLGraphicsFramebuffer org.b00t0x.AppleIntelTGLCompat com.rugarciap.DisableTurboBoost com.nullmoth.NVAccel com.nullmoth.NVRM com.nullmoth.NVRMAGDC com.nullmoth.NVRMFB"
LOG=/var/log/vramstat.log; MARK=/var/db/vramstat.armed
PL=/Library/LaunchDaemons/local.vramstat-watchdog.plist; SELF=/usr/local/libexec/step56-vramstat.sh
sha() { shasum -a 256 "$1" | cut -c1-16; }
cnt() { perl -e 'local $/; open F,"<",$ARGV[0] or do{print "?";exit}; binmode F; $d=<F>; $p=pack("H*",$ARGV[1]); $n=0; $n++ while $d=~/\Q$p\E/g; print $n' "$1" "$2"; }
log() { echo "$(date '+%F %T') $*" | tee -a $LOG; }
stop() { log "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
KARG=(--allow-missing-kdk); [ -f /System/Library/Kernels/kernel ] && KARG+=(--kernel /System/Library/Kernels/kernel)
rebuild() {
  local N="$KC.vramstat-new"; rm -f "$N"
  kmutil create -n aux --volume-root / "${KARG[@]}" -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions -A "$N" -z > "$T/logs/step56-kmutil.log" 2>&1 \
    || { tail -15 "$T/logs/step56-kmutil.log"; return 1; }
  [ -s "$N" ] || return 1
  local INS; INS=$(kmutil inspect -a x86_64 -A "$N" 2>/dev/null) || return 1
  for id in $NEED; do echo "$INS" | grep -q "$id" || { echo "!! 새 AuxKC 에 $id 없음"; return 1; }; done
  [ "$(cnt "$N" $V2)" = 1 ] || { echo "!! 새 AuxKC 에 밝기 패치가 없음"; return 1; }
  mv -f "$N" "$KC" && log "새 AuxKC: $(sha "$KC")"
}
restore() { cp -p "$BK/NVRM" "$CUR_RM"; cp -p "$BK/NVAccel" "$CUR_AC"; cp -p "$BK/AuxiliaryKernelExtensions.kc" "$KC"; }
case "$MODE" in
apply)
  [ "$(sha "$NEW_RM")" = "$NEW_RM_SHA" ] && [ "$(sha "$NEW_AC")" = "$NEW_AC_SHA" ] || stop "수정본 해시가 빌드 때와 다름"
  [ "$(sha "$CUR_RM")" = "$CUR_RM_SHA" ] || stop "설치된 NVRM 이 rtd3fix(2cfd8214)가 아님 ($(sha "$CUR_RM"))"
  [ "$(sha "$CUR_AC")" = "$CUR_AC_SHA" ] || stop "설치된 NVAccel 이 2.9 원본(41f60bf7)이 아님 ($(sha "$CUR_AC"))"
  [ "$(cnt "$KC" $V2)" = 1 ] || stop "현재 AuxKC 의 밝기 패치 상태가 예상과 다름"
  mkdir -p "$BK" && cp -p "$CUR_RM" "$BK/NVRM" && cp -p "$CUR_AC" "$BK/NVAccel" && cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc" || stop "백업 실패"
  [ "$(sha "$BK/NVRM")" = "$CUR_RM_SHA" ] && [ "$(sha "$BK/NVAccel")" = "$CUR_AC_SHA" ] || stop "백업 검증 실패"
  log "백업: $BK (AuxKC $(sha "$BK/AuxiliaryKernelExtensions.kc"))"
  cp "$NEW_RM" "$CUR_RM" && chown root:wheel "$CUR_RM" && chmod 755 "$CUR_RM" \
    && cp "$NEW_AC" "$CUR_AC" && chown root:wheel "$CUR_AC" && chmod 755 "$CUR_AC" || { restore; stop "복사 실패 → 되돌림"; }
  rebuild || { restore; stop "AuxKC 재생성 실패 → 원래 NVRM·NVAccel·AuxKC 로 되돌림 (재부팅해도 안전)"; }
  mkdir -p /usr/local/libexec && install -m 755 "$0" "$SELF"
  cat > $PL <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>local.vramstat-watchdog</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>watchdog</string></array>
<key>RunAtLoad</key><true/></dict></plist>
EOF
  chmod 644 $PL; chown root:wheel $PL; rm -f $MARK
  log "적용 완료: NVRM $(sha "$CUR_RM"), NVAccel $(sha "$CUR_AC"). 재부팅 후 ioreg -r -c NVAccel 의 vramUsedBytes 확인" ;;
undo)
  [ -f "$BK/NVRM" ] && [ -f "$BK/NVAccel" ] && [ -f "$BK/AuxiliaryKernelExtensions.kc" ] || stop "백업 없음"
  [ "$(sha "$BK/NVRM")" = "$CUR_RM_SHA" ] && [ "$(sha "$BK/NVAccel")" = "$CUR_AC_SHA" ] || stop "백업 해시 불일치"
  restore && chown root:wheel "$CUR_RM" "$CUR_AC" && chmod 755 "$CUR_RM" "$CUR_AC" || stop "복원 실패"
  log "undo: NVRM $(sha "$CUR_RM"), NVAccel $(sha "$CUR_AC"), AuxKC $(sha "$KC")"
  rm -f $MARK $PL; sync; [ -n "${NOBOOTOUT:-}" ] && exit 0
  launchctl bootout system/local.vramstat-watchdog 2>/dev/null ;;
watchdog)
  [ "$(sha "$CUR_RM")" = "$NEW_RM_SHA" ] || { rm -f $MARK $PL; exit 0; }
  if [ -e $MARK ]; then log "watchdog: 이전 시험 부팅이 5분을 못 버팀 → 되돌리고 재부팅"; NOBOOTOUT=1 "$SELF" undo; sync; sleep 3; shutdown -r now; exit 0; fi
  touch $MARK; sync; log "watchdog: 시험 부팅 시작, 5분 감시"
  sleep 300; rm -f $MARK; sync
  log "watchdog: 5분 통과 — $(ioreg -r -c NVAccel -d1 -w0 | grep -o '"vramUsedBytes"=[0-9]*\|"vramFreeBytes"=[0-9]*\|"Device Utilization %"=[0-9]*' | tr '\n' ' ')"
  rm -f $PL; launchctl bootout system/local.vramstat-watchdog 2>/dev/null ;;
*) stop "사용법: $0 apply|undo|watchdog";;
esac
sync; exit 0
