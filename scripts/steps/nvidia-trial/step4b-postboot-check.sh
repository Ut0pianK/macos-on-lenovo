#!/bin/bash
T="$HOME/nvidia-trial"; mkdir -p "$T/logs"
LOG="$T/logs/step4b-postboot-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "===== step4b-postboot-check $(date) ====="
echo "부팅 시각: $(sysctl -n kern.boottime | sed 's/.*} //')"
BA=$(nvram boot-args 2>/dev/null | cut -f2-); echo "boot-args: $BA"
case " $BA " in *" -nvoff "*) echo ">> USB EFI 로 부팅됨 (-nvoff): 드라이버는 꺼진 상태가 정상";; *" nvaccel=1 "*) echo ">> 내장 EFI 로 부팅됨 (nvaccel=1)";; *) echo ">> nv 인자 없음";; esac
echo "csr-active-config: $(nvram csr-active-config 2>/dev/null | cut -f2)"
csrutil status 2>&1 | head -1

echo; echo "##### 1) kext"
kmutil showloaded 2>/dev/null | grep -iE 'nullmoth|TGL|WhateverXe' | awk '{print "  " $6, $7}'
echo "nullmoth kext 수: $(kmutil showloaded --list-only 2>/dev/null | grep -c nullmoth) (정상이면 4)"

echo; echo "##### 2) MX450 과 붙은 드라이버"
ioreg -w0 -r -n PEGP -d 5 | grep -E '\+-o' | cut -c1-150
ioreg -w0 -r -n PEGP -d 1 -l | grep -E '"(vendor-id|device-id|IOPowerManagement|nvrm-[a-z-]+|model)" =' | cut -c1-200
echo "-- NVAccel 속성"
ioreg -w0 -r -c NVAccel -d 1 -l 2>/dev/null | grep -E '"(MetalPluginName|NVAccelHeadless|IOClass|PerformanceStatistics)" =' | cut -c1-240
echo "-- Intel 가속기 MetalPluginName"
ioreg -w0 -r -c IntelAccelerator -d 1 -l | grep -E '"MetalPluginName"' | cut -c1-120
echo "-- sysctl"
for k in debug.nvaccelfb debug.nmhybrid; do printf '  %s = %s\n' $k "$(sysctl -n $k 2>/dev/null || echo '(없음)')"; done

echo; echo "##### 3) system_profiler"
system_profiler SPDisplaysDataType 2>/dev/null | grep -vE '^$'

echo; echo "##### 4) Metal 장치 목록 (조회만)"
S="$T/tools/mtl-list.swift"
if [ -f "$S" ] && command -v swiftc >/dev/null; then
  BIN="$T/tools/mtl-list"
  [ -x "$BIN" ] && [ "$BIN" -nt "$S" ] || swiftc -O -o "$BIN" "$S" 2>&1 | tail -3
  [ -x "$BIN" ] && "$BIN" 2>&1 | head -20
else echo "  (mtl-list.swift 또는 swiftc 없음)"; fi

echo; echo "##### 5) 드라이버 커널 로그 (이번 부팅, 요약)"
/usr/bin/log show --last boot --style compact --predicate 'process == "kernel" AND (eventMessage CONTAINS "NVRM" OR eventMessage CONTAINS "NVAccel" OR eventMessage CONTAINS "NVRMFB" OR eventMessage CONTAINS "nullmoth")' 2>/dev/null > "$T/logs/nv-kernel-lastboot.txt"
echo "전체 $(wc -l < "$T/logs/nv-kernel-lastboot.txt") 줄 → $T/logs/nv-kernel-lastboot.txt"
grep -E 'headless check|auto-go|boot-arg|NOT starting|GSP|firmware|BAR1|FAIL|fail|error|guard|panic|IONDRVFramebuffer blocked|MetalPluginName' "$T/logs/nv-kernel-lastboot.txt" | cut -c1-260 | head -60
echo "-- Intel GPU 관련 오류 (이번 부팅)"
/usr/bin/log show --last boot --style compact --predicate 'process == "kernel" AND (eventMessage CONTAINS "GPURestart" OR eventMessage CONTAINS "DBUF" OR eventMessage CONTAINS "link training")' 2>/dev/null | tail -8 | cut -c1-220

echo; echo "##### 6) 새 패닉/진단 보고서 (이번 부팅 이후)"
B=$(sysctl -n kern.boottime | sed -n 's/^{ sec = \([0-9]*\),.*/\1/p')
for f in /Library/Logs/DiagnosticReports/* "$HOME"/Library/Logs/DiagnosticReports/*; do [ -f "$f" ] && [ "$(stat -f %m "$f")" -ge "$B" ] && echo "  $(basename "$f")"; done; echo "  (끝)"
echo "-- 최근 패닉 파일"; ls -t /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | head -3
echo "-- NullMoth 보호 장치"; nvram -p | grep -i nullmoth || echo "  NVRAM 에 nullmoth 변수 없음"
tail -5 /Library/NullMoth/bootguard.log 2>/dev/null

echo; echo "##### 7) 밝기 패치 v2"
V2=4969d64073010048c1ea10909090909090909090909090
cnt() { perl -e 'local $/; open F,"<",$ARGV[0] or do{print "?";exit}; binmode F; $d=<F>; $p=pack("H*",$ARGV[1]); $n=0; $n++ while $d=~/\Q$p\E/g; print $n' "$1" "$2"; }
echo "디스크 파일=$(cnt /Library/Extensions/AppleIntelTGLGraphicsFramebuffer.kext/Contents/MacOS/AppleIntelTGLGraphicsFramebuffer $V2) AuxKC=$(cnt /Library/KernelCollections/AuxiliaryKernelExtensions.kc $V2)  (둘 다 1 이어야 함)"

echo; echo "##### 8) 전력 (배터리로 2분 이상 쓴 뒤에만 의미 있음. 30초 평균)"
pmset -g batt | head -2
if pmset -g batt | grep -q "Battery Power"; then
  w=0; n=0
  for i in 1 2 3 4 5 6; do
    a=$(ioreg -r -c AppleSmartBattery -w0 | awk -F'= ' '/"InstantAmperage" =/{print $2}')
    v=$(ioreg -r -c AppleSmartBattery -w0 | awk -F'= ' '/"Voltage" =/{print $2; exit}')
    s=$(perl -e '$a=$ARGV[0]; $a-=18446744073709551616 if $a>9223372036854775807; printf "%.2f", abs($a)*$ARGV[1]/1e6' "$a" "$v")
    echo "  표본 $i: ${s} W"; [ "$s" != 0.00 ] && { w=$(perl -e 'printf "%.2f",$ARGV[0]+$ARGV[1]' "$w" "$s"); n=$((n+1)); }; sleep 5
  done
  [ "$n" -gt 0 ] && echo "평균: $(perl -e 'printf "%.2f",$ARGV[0]/$ARGV[1]' "$w" "$n") W ($n 표본)" || echo "측정 실패: 전류 값이 0 (충전기를 뽑은 직후). 2분 뒤 다시 실행"
else echo "  충전 중 → 측정 건너뜀"; fi

echo; echo "##### 9) App Store 관련 서비스 / 네트워크"
U=$(id -u)
for l in com.apple.fairplayd com.apple.adid com.apple.installd; do printf '  system %s: %s\n' $l "$(launchctl print system/$l 2>/dev/null | awk '/^\tstate =/{print $3}')"; done
for l in com.apple.appstoreagent com.apple.commerce com.apple.akd com.apple.amsaccountsd com.apple.storekitagent; do printf '  gui %s: %s\n' $l "$(launchctl print gui/$U/$l 2>/dev/null | awk '/^\tstate =/{print $3}')"; done
launchctl print-disabled gui/$U | grep -iE 'fairplay|fpsd|adid|akd|amsaccountsd|commerce|appstore|store' | grep -i disabled && echo "  !! 보호 대상이 비활성 목록에 있음" || echo "  OK: 보호 대상 비활성 없음"
printf '  apple.com: '; dscacheutil -q host -a name apple.com 2>/dev/null | grep -m1 ip_address || echo "해석 실패"

echo; echo "===== 끝. 로그: $LOG ====="
