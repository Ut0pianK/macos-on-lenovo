#!/bin/bash
set -u
T="$HOME/nvidia-trial"; PKG="$T/pkg/v2.9/pkgroot"; TAR="$T/download/v2.9/nullmoth-nvidia-2.9.tar.gz"
LOG="$T/logs/step4-install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "===== step4-install $(date) ====="
V2=4969d64073010048c1ea10909090909090909090909090
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
FB=/Library/Extensions/AppleIntelTGLGraphicsFramebuffer.kext/Contents/MacOS/AppleIntelTGLGraphicsFramebuffer
cnt() { perl -e 'local $/; open F,"<",$ARGV[0] or do{print "?";exit}; binmode F; $d=<F>; $p=pack("H*",$ARGV[1]); $n=0; $n++ while $d=~/\Q$p\E/g; print $n' "$1" "$2"; }
stop() { echo "!! $* — 중단 (아무것도 설치하지 않음)"; exit 1; }

echo "##### 0) 사전 확인"
B=$(cat "$T/LATEST_BACKUP" 2>/dev/null)
[ -n "$B" ] && [ -f "$B/SHA256SUMS.txt" ] && [ -f "$B/AuxiliaryKernelExtensions.kc" ] && [ -f "$B/Library-Extensions.tar" ] && [ -d "$B/EFI-internal/EFI/OC" ] || stop "검증된 백업이 없음"
echo "백업: $B"
[ -f "$T/USB_BOOT_VERIFIED" ] || stop "USB 부팅 확인 표식 없음"
[ -x "$T/step5-rollback.sh" ] || stop "복구 스크립트 없음"
[ "$(shasum -a 256 "$TAR" | cut -d' ' -f1)" = b624bf07c78cea03043e096383d5c8b01e4fb2c804a6ba377a4e66a2566422ef ] || stop "패키지 해시 불일치"
[ "$(shasum -a 256 "$PKG/install.sh" | cut -d' ' -f1)" = 31cf6e1b70184267999f509ed7a17c1ed72a3f77f4b149f8b509a08d03486d5b ] || stop "install.sh 가 검토한 것과 다름"
(cd "$PKG" && shasum -a 256 --strict -c SHA256SUMS --quiet) || stop "패키지 내부 해시 불일치"
echo "패키지·install.sh 해시 OK"
[ -e /Library/NullMoth ] && stop "/Library/NullMoth 가 이미 있음 (이전 설치 흔적) — 먼저 확인 필요"
ioreg -r -c IOPCIDevice -d 1 | grep -q '"vendor-id" = <de100000>' || stop "MX450 이 PCI 버스에 안 보임 (BIOS 확인)"
curl -fsI --max-time 15 -o /dev/null https://download.nvidia.com/XFree86/Linux-x86_64/620.70.06/NVIDIA-Linux-x86_64-620.70.06.run || stop "NVIDIA 다운로드 서버에 연결 안 됨"
echo "NVIDIA 서버 연결 OK"
kcsha=$(shasum -a 256 "$KC" | cut -d' ' -f1)
echo "현재 AuxKC: $kcsha"
if [ "$kcsha" != "$(shasum -a 256 "$B/AuxiliaryKernelExtensions.kc" | cut -d' ' -f1)" ]; then
  P="$T/pre-install-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$P" && cp -p "$KC" "$P/" && echo "AuxKC 가 백업 때와 달라 추가 사본을 만듦: $P"
fi
echo "밝기 패치 v2 패턴(설치 전): 디스크 파일=$(cnt "$FB" $V2) AuxKC=$(cnt "$KC" $V2)"
ls /Library/Extensions > "$T/logs/pre-install-extensions.txt"
echo "boot-args(이번 부팅): $(nvram boot-args | cut -f2-)"
pmset -g batt | head -1

echo; echo "##### 1) install.sh  (펌웨어 다운로드 때문에 몇 분 걸릴 수 있음)"
sudo /bin/bash "$PKG/install.sh"; rc=$?
echo "install.sh 종료 코드: $rc"

echo; echo "##### 2) 설치 후 확인"
RES=ok; [ "$rc" = 0 ] || RES=install-failed
echo "-- /Library/Extensions"; ls /Library/Extensions
echo "-- /Library/NullMoth"; ls -la /Library/NullMoth 2>/dev/null
echo "-- 펌웨어"; find /Library/NullMoth/nvfw -type f -exec ls -la {} \; 2>/dev/null
echo "-- /Library/GPUBundles"; ls /Library/GPUBundles
echo "-- LaunchDaemons"; ls /Library/LaunchDaemons | grep -i nullmoth
echo "-- NVRAM nullmoth 변수"; nvram -p | grep -i nullmoth || echo "  없음"
if [ -f "$KC" ]; then
  INS=$(kmutil inspect -a x86_64 -A "$KC" 2>/dev/null)
  for id in com.nullmoth.NVRM com.nullmoth.NVAccel com.nullmoth.NVRMFB com.nullmoth.NVRMAGDC; do
    echo "$INS" | grep -q "$id" && echo "OK: AuxKC 에 $id" || { echo "!! AuxKC 에 $id 없음"; [ "$RES" = ok ] && RES=check; }
  done
  for id in com.apple.driver.AppleIntelTGLGraphicsFramebuffer com.apple.driver.AppleIntelTGLGraphics org.b00t0x.AppleIntelTGLCompat com.rugarciap.DisableTurboBoost; do
    echo "$INS" | grep -q "$id" && echo "OK: AuxKC 에 $id" || { echo "!! AuxKC 에 $id 없음 — 재부팅하지 말 것"; RES=DO-NOT-REBOOT; }
  done
  echo "밝기 패치 v2 패턴(설치 후): 디스크 파일=$(cnt "$FB" $V2) AuxKC=$(cnt "$KC" $V2)  (둘 다 1 이어야 함)"
  [ "$(cnt "$KC" $V2)" = 1 ] && [ "$(cnt "$FB" $V2)" = 1 ] || { echo "!! 밝기 패치가 사라짐 — 재부팅하지 말 것"; RES=DO-NOT-REBOOT; }
  echo "새 AuxKC sha256: $(shasum -a 256 "$KC" | cut -d' ' -f1)"
else
  echo "!! $KC 없음 — 재부팅하지 말 것"; RES=DO-NOT-REBOOT
fi
echo "-- Intel kext 파일이 그대로인지 (백업 때 해시와 비교)"
( cd /Library && grep -E 'AppleIntelTGL|DisableTurboBoost' "$B/state/Library-Extensions-sha256.txt" | shasum -a 256 -c --quiet - ) && echo "OK: Intel·터보 kext 파일 변경 없음" || { echo "!! Intel kext 파일이 바뀜"; RES=DO-NOT-REBOOT; }

echo; echo "##### 3) App Store 관련 서비스"
U=$(id -u)
for l in com.apple.fairplayd com.apple.adid com.apple.installd; do printf '  system %s: %s\n' $l "$(launchctl print system/$l 2>/dev/null | awk '/^\tstate =/{print $3}')"; done
for l in com.apple.appstoreagent com.apple.commerce com.apple.akd com.apple.amsaccountsd; do printf '  gui %s: %s\n' $l "$(launchctl print gui/$U/$l 2>/dev/null | awk '/^\tstate =/{print $3}')"; done

echo; echo "INSTALL_RESULT=$RES (install.sh rc=$rc)"
case "$RES" in
  ok) echo "다음: Claude 에게 결과를 알리고, 안내에 따라 '내장 디스크'로 재부팅 (재부팅은 직접).";;
  *)  echo "재부팅하지 말고 이 로그를 Claude 에게 알려 주세요. 되돌리기: bash ~/nvidia-trial/step5-rollback.sh";;
esac
echo "===== 끝. 로그: $LOG ====="
