#!/bin/bash
set -u
T="$HOME/nvidia-trial"; PKG="$T/pkg/v2.9/pkgroot"
LOG="$T/logs/step5-rollback-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "===== step5-rollback $(date) (${1:-driver}) ====="
V2=4969d64073010048c1ea10909090909090909090909090
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
FB=/Library/Extensions/AppleIntelTGLGraphicsFramebuffer.kext/Contents/MacOS/AppleIntelTGLGraphicsFramebuffer
cnt() { perl -e 'local $/; open F,"<",$ARGV[0] or do{print "?";exit}; binmode F; $d=<F>; $p=pack("H*",$ARGV[1]); $n=0; $n++ while $d=~/\Q$p\E/g; print $n' "$1" "$2"; }

echo "-- 제거 전"
ls /Library/Extensions
ls -d /Library/NullMoth /Library/GPUBundles/NVMTLDriver.bundle /Library/GPUBundles/nvmtl /Library/LaunchDaemons/com.nullmoth.* 2>/dev/null

if ls -d /Library/Extensions/NVRM.kext /Library/Extensions/NVAccel.kext /Library/Extensions/NVRMFB.kext /Library/Extensions/NVRMAGDC.kext /Library/GPUBundles/NVMTLDriver.bundle >/dev/null 2>&1 || [ -d /Library/NullMoth/kexts ]; then
  [ "$(shasum -a 256 "$PKG/uninstall.sh" | cut -d' ' -f1)" = f0321838f53afe0efb33f0abf5510b2dcde8483ed8ea5c900ca7227ba0fdb19a ] || { echo "!! uninstall.sh 가 검토한 것과 다름. 중단."; exit 1; }
  (cd "$PKG" && shasum -a 256 --strict -c SHA256SUMS --quiet) || { echo "!! 패키지 내부 해시 불일치. 중단."; exit 1; }
  echo; echo "##### uninstall.sh"
  sudo /bin/bash "$PKG/uninstall.sh"; rc=$?
  echo "uninstall.sh 종료 코드: $rc"
else
  echo; echo "NullMoth 드라이버 파일이 없음 → uninstall.sh 건너뜀"; rc=0
  sudo -v
fi
sudo nvram -d 7C436110-AB2A-4BBB-A880-FE41995C9F82:nullmoth-remove 2>/dev/null

echo; echo "##### 확인"
RES=ok
left=$(ls /Library/Extensions | grep -E '^(NVRM|NVAccel|NVRMFB|NVRMAGDC|NVPrimarySelector|NMXAudio)\.kext$')
[ -z "$left" ] && echo "OK: /Library/Extensions 에 NullMoth kext 없음" || { echo "!! 남은 kext: $left"; RES=check; }
ls /Library/Extensions
if [ -f "$KC" ]; then
  INS=$(kmutil inspect -a x86_64 -A "$KC" 2>/dev/null)
  echo "$INS" | grep -q 'com.nullmoth' && { echo "!! AuxKC 에 아직 com.nullmoth 있음"; RES=check; } || echo "OK: AuxKC 에 com.nullmoth 없음"
  for id in com.apple.driver.AppleIntelTGLGraphicsFramebuffer com.apple.driver.AppleIntelTGLGraphics org.b00t0x.AppleIntelTGLCompat; do
    echo "$INS" | grep -q "$id" && echo "OK: AuxKC 에 $id" || { echo "!! AuxKC 에 $id 없음 — 재부팅하지 말 것"; RES=DO-NOT-REBOOT; }
  done
  echo "밝기 패치 v2 패턴: 디스크 파일=$(cnt "$FB" $V2) AuxKC=$(cnt "$KC" $V2)  (둘 다 1 이어야 함)"
  [ "$(cnt "$KC" $V2)" = 1 ] || { echo "!! AuxKC 에 밝기 패치가 없음 — 백업 README 의 C 절차로 복원 필요"; RES=check; }
  echo "AuxKC sha256: $(shasum -a 256 "$KC" | cut -d' ' -f1)  (설치 전 백업은 3bb930d8…)"
else
  echo "!! $KC 없음 — 재부팅하지 말 것"; RES=DO-NOT-REBOOT
fi
echo "-- 남은 NullMoth 흔적 (삭제하지 않고 목록만)"
ls -la /Library/NullMoth 2>/dev/null || echo "  /Library/NullMoth 없음"
ls /Library/LaunchDaemons | grep -i nullmoth || echo "  LaunchDaemon 없음"
ls /Library/GPUBundles
nvram -p | grep -i nullmoth || echo "  NVRAM 에 nullmoth 변수 없음"

if [ "${1:-}" = all ]; then
  echo; echo "##### 내장 EFI 복원"
  bash "$T/step3c-internal-efi.sh" undo
fi

echo; echo "##### App Store 관련 서비스"
U=$(id -u)
for l in com.apple.fairplayd com.apple.adid com.apple.installd; do printf '  system %s: %s\n' $l "$(launchctl print system/$l 2>/dev/null | awk '/^\tstate =/{print $3}')"; done
for l in com.apple.appstoreagent com.apple.commerce com.apple.akd com.apple.amsaccountsd; do printf '  gui %s: %s\n' $l "$(launchctl print gui/$U/$l 2>/dev/null | awk '/^\tstate =/{print $3}')"; done

echo; echo "ROLLBACK_RESULT=$RES (uninstall rc=$rc)"
[ "$RES" = ok ] && echo "재부팅하면 드라이버 없는 상태로 돌아갑니다. (재부팅은 직접)"
echo "===== 끝. 로그: $LOG ====="
