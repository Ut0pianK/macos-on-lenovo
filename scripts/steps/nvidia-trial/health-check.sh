#!/bin/bash
T="$HOME/nvidia-trial"; mkdir -p "$T/logs"; LOG="$T/logs/health-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1
h() { echo; echo "=== $* ==="; }
k() { /usr/bin/log show --last boot --style compact --predicate "$1" 2>/dev/null; }
h "기본"; date; echo "부팅: $(sysctl -n kern.boottime | sed 's/.*} //')"; sw_vers | tr '\n' ' '; echo; uptime
h "오늘 생긴 진단 보고서 (종류별)"
ls /Library/Logs/DiagnosticReports ~/Library/Logs/DiagnosticReports 2>/dev/null | grep "$(date +%Y-%m-%d)" | sed -E 's/[-_]20[0-9]{2}-.*\././' | sort | uniq -c | sort -rn | head -25
h "이번 부팅: GPU 멈춤 판정 / APFS 해시 불일치 / pagein 오류"
echo "GPURestart: $(k 'process == "kernel" AND eventMessage CONTAINS "GPURestart"' | grep -c GPURestart)"
echo "hash mismatch: $(k 'process == "kernel" AND eventMessage CONTAINS "hash mismatch"' | grep -c mismatch)"
echo "pagein error: $(k 'process == "kernel" AND eventMessage CONTAINS "pagein error"' | grep -c pagein)"
h "저장 장치"; df -h / /System/Volumes/Data | cut -c1-90
diskutil info disk0 | grep -E 'Media Name|SMART|Solid State|Disk Size' | sed 's/^ *//'
system_profiler SPNVMeDataType 2>/dev/null | grep -E 'Model|TRIM|S.M.A.R.T|Link (Width|Speed)' | sed 's/^ *//'
h "메모리"; memory_pressure 2>/dev/null | tail -1; sysctl vm.swapusage | cut -c1-80; vm_stat | grep -E 'Pages (free|active|wired|occupied by compressor)|Swapouts' | tr -s ' '
h "CPU·열·전원"; pmset -g therm 2>/dev/null | grep -vE '^Note|^$'; sysctl -n machdep.xcpm.mode 2>/dev/null | sed 's/^/xcpm.mode=/'
ioreg -rn X86PlatformPlugin -d1 2>/dev/null | grep -cE 'X86PlatformPlugin' | sed 's/^/X86PlatformPlugin 수=/'
top -l 2 -n 6 -o cpu -stats command,cpu 2>/dev/null | tail -7
h "배터리"; pmset -g batt | tail -1 | cut -c1-90
ioreg -rn AppleSmartBattery -d1 2>/dev/null | grep -E '"(CycleCount|DesignCapacity|AppleRawMaxCapacity|NominalChargeCapacity|Temperature)" =' | sed 's/^[ |]*//' | tr '\n' ' '; echo
h "잠자기"; pmset -g | grep -E 'hibernatemode|standby |powernap|tcpkeepalive|proximitywake|womp' | tr -s ' '
pmset -g log 2>/dev/null | grep -E 'Wake from|Sleep  |DarkWake|Failure' | tail -6 | cut -c1-150
h "장치 인식"
echo "Wi-Fi: $(networksetup -getairportpower en0 2>&1 | cut -c1-60)"; ipconfig getifaddr en0 >/dev/null 2>&1 && echo "  en0 IP 있음" || echo "  en0 IP 없음"
echo "Bluetooth: $(system_profiler SPBluetoothDataType 2>/dev/null | grep -E 'State|Chipset|Firmware' | tr -s ' ' | tr '\n' ';' | cut -c1-140)"
echo "오디오: $(system_profiler SPAudioDataType 2>/dev/null | grep -E '^ {8}[A-Za-z].*:$' | tr -s ' ' | tr '\n' ' ' | cut -c1-160)"
echo "카메라: $(system_profiler SPCameraDataType 2>/dev/null | grep -E '^ {4}[A-Za-z].*:$' | tr -s ' ' | tr '\n' ' ')"
echo "터치패드/키보드: $(ioreg -l -w0 | grep -oE 'VoodooI2CHID[A-Za-z]*|VoodooI2CPrecisionTouchpad[A-Za-z]*|ApplePS2Keyboard' | sort -u | tr '\n' ' ')"
echo "밝기 제어: $(ioreg -l -w0 | grep -c 'AppleBacklightDisplay\|AppleIntelPanel')  조도센서: $(ioreg -l -w0 | grep -c '"ACPI0008"\|SMCLightSensor')"
echo "화면: $(system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Chipset Model|VRAM|Metal|Resolution|Vendor' | tr -s ' ' | tr '\n' ';' | cut -c1-260)"
h "USB 포트 (연결된 장치)"; system_profiler SPUSBDataType 2>/dev/null | grep -E '^ {4,10}[A-Za-z0-9].*:$|Speed:' | tr -s ' ' | head -16
h "kext"; echo "/Library/Extensions: $(ls /Library/Extensions | tr '\n' ' ')"
echo "로드된 비-Apple kext 수: $(kmutil showloaded --list-only 2>/dev/null | grep -vc 'com.apple')"
echo "이번 부팅 kext 로드 실패 로그: $(k 'eventMessage CONTAINS[c] "kext" AND (eventMessage CONTAINS[c] "failed to load" OR eventMessage CONTAINS[c] "Can.t load")' | grep -ci kext)"
h "NVRAM·시간·보안 상태 (값은 읽기만)"; nvram -p >/dev/null 2>&1 && echo "nvram 읽기 OK ($(nvram -p | wc -l | tr -d ' ')개)"
csrutil status 2>/dev/null; sntp -t 3 time.apple.com 2>/dev/null | tail -1 | cut -c1-60
h "App Store 관련 서비스"
for s in com.apple.fairplayd com.apple.adid com.apple.amsaccountsd com.apple.commerce com.apple.appstoreagent com.apple.akd; do
  printf "%s: " $s; (launchctl print system/$s 2>/dev/null || launchctl print gui/$(id -u)/$s 2>/dev/null) | grep -m1 'state =' | tr -d '\t' || echo "(없음)"; done
echo "비활성화된 항목: $(for d in system gui/$(id -u) user/$(id -u); do launchctl print-disabled $d 2>/dev/null; done | grep -ciE 'fairplay|fpsd|adid|akd|amsaccounts|commerce|appstore')"
h "이번 부팅 로그를 많이 쏟는 프로세스 (오류·결함 수준, 최근 10분)"
/usr/bin/log show --last 10m --style compact --predicate 'messageType == error OR messageType == fault' 2>/dev/null | awk 'NR>1{print $4}' | sed -E 's/\[[0-9]+:?[0-9a-f]*\]//;s/:$//' | sort | uniq -c | sort -rn | head -12
h "작업 폴더 용량"; du -sh "$T"/backup-* "$T"/upstream "$T"/build "$T"/logs 2>/dev/null
echo; echo "===== 끝. 로그: $LOG ====="
