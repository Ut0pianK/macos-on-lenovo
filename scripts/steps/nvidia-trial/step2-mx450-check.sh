#!/bin/bash
T="$HOME/nvidia-trial"; mkdir -p "$T/logs"
LOG="$T/logs/step2-mx450-check-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "===== step2-mx450-check $(date) ====="
echo "부팅 시각: $(sysctl -n kern.boottime)"
echo "boot-args: $(nvram boot-args 2>/dev/null | cut -f2-)"
echo "OpenCore: $(nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version 2>/dev/null | cut -f2)"

echo; echo "##### 1) NVIDIA PCI 장치"
N=$(ioreg -l -w0 | grep -c '"vendor-id" = <de100000>')
echo "10de 장치 수: $N"
ioreg -p IOService -w0 -l -r -c IOPCIDevice | perl -ne '
  if(/\+-o (\S+)\s+<class IOPCIDevice/){ print $buf if $nv; $buf="--- $1\n"; $nv=0 }
  $nv=1 if /"vendor-id" = <de100000>/;
  $buf.=$_ if /"(vendor-id|device-id|subsystem-vendor-id|subsystem-id|class-code|revision-id|pcidebug|acpi-path|assigned-addresses|reg|IOPCIExpressLinkStatus|IOPCIExpressLinkCapabilities|IOPCIResourced|IOPCIConfigured|IOName|model|IOPowerManagement|IOInterruptSpecifiers|IOPCIMSIMode)" =/;
  END{ print $buf if $nv }' | cut -c1-400
echo "-- 루트 포트와 전체 PCI 목록"
ioreg -p IOService -w0 -l -r -c IOPCIDevice | perl -ne 'if(/\+-o (\S+)\s+<class IOPCIDevice/){$n=$1} if(/"vendor-id" = <(..)(..)/){$v="$2$1"} if(/"device-id" = <(..)(..)/){$d="$2$1"} if(/"class-code" = <(..)(..)(..)/){$c="$3$2$1"} if(/"pcidebug" = "([^"]+)"/){print "$1  $v:$d class=$c  $n\n"}' | sort -u
echo "-- ACPI PEG0/PEGP"
ioreg -p IOACPIPlane -w0 -l -r -n PEG0 | grep -E '\+-o|"_STA"|"_ADR"|IOPowerManagement' | cut -c1-200
echo "-- NVIDIA 장치에 붙은 드라이버"
ioreg -w0 -r -n PEGP -d 4 2>/dev/null | cut -c1-160 | head -12

echo; echo "##### 2) 내장 그래픽 / Metal"
system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Chipset|Vendor|Device ID|Metal|Resolution|VRAM|Bus' 
kmutil showloaded 2>/dev/null | grep -iE 'TGL|WhateverXe|nullmoth|NVDA|GeForce' | awk '{print $6, $7}'

echo; echo "##### 3) 전력 (배터리일 때만 의미 있음. 30초 평균)"
pmset -g batt | head -2
w=0; n=0
for i in 1 2 3 4 5 6; do
  a=$(ioreg -r -c AppleSmartBattery -w0 | awk -F'= ' '/"InstantAmperage" =/{print $2}')
  v=$(ioreg -r -c AppleSmartBattery -w0 | awk -F'= ' '/"Voltage" =/{print $2; exit}')
  s=$(perl -e '$a=$ARGV[0]; $a-=18446744073709551616 if $a>9223372036854775807; printf "%.2f", abs($a)*$ARGV[1]/1e6' "$a" "$v")
  echo "  표본 $i: ${s} W"; w=$(perl -e 'printf "%.2f",$ARGV[0]+$ARGV[1]' "$w" "$s"); n=$((n+1)); sleep 5
done
echo "평균: $(perl -e 'printf "%.2f",$ARGV[0]/$ARGV[1]' "$w" "$n") W  (참고: MX450 꺼진 상태 기준값은 이 스크립트를 BIOS 변경 전에도 한 번 돌려 얻을 수 있음)"

echo; echo "##### 4) 새 패닉/진단 보고서 (이번 부팅 이후)"
B=$(sysctl -n kern.boottime | sed -n 's/^{ sec = \([0-9]*\),.*/\1/p')
for f in /Library/Logs/DiagnosticReports/*; do [ -f "$f" ] && [ "$(stat -f %m "$f")" -ge "$B" ] && echo "  $(basename "$f")"; done; echo "  (끝)"

echo; echo "##### 5) App Store 관련 서비스"
U=$(id -u)
for l in com.apple.fairplayd com.apple.adid com.apple.installd; do printf '  system %s: %s\n' $l "$(launchctl print system/$l 2>/dev/null | awk '/^\tstate =/{print $3}')"; done
for l in com.apple.appstoreagent com.apple.commerce com.apple.akd com.apple.amsaccountsd com.apple.storekitagent; do printf '  gui %s: %s\n' $l "$(launchctl print gui/$U/$l 2>/dev/null | awk '/^\tstate =/{print $3}')"; done
launchctl print-disabled gui/$U | grep -iE 'fairplay|fpsd|adid|akd|amsaccountsd|commerce|appstore|store' | grep -i disabled && echo "  !! 보호 대상이 비활성 목록에 있음" || echo "  OK: 보호 대상 비활성 없음"

echo; echo "##### 6) 네트워크 이름 해석"
for h in github.com download.nvidia.com apple.com; do printf '  %s: ' $h; dscacheutil -q host -a name $h 2>/dev/null | grep -m1 ip_address || echo "해석 실패"; done

echo; echo "===== 끝. 로그: $LOG ====="
