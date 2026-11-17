#!/bin/bash
set -u
T=/Users/user/nvidia-trial; MODE=${1:-}
NEW=$T/build/nvrm-rtd3fix/NVRM.kext/Contents/MacOS/NVRM; NEW_SHA=2cfd82148bccaaa9
CUR=/Library/Extensions/NVRM.kext/Contents/MacOS/NVRM; ORIG_SHA=c1d62ff7447374c1
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc; BK=$T/backup-nvrm-orig
SSDT=/Users/user/tweak-backup-2026-11-13/nvpwr/SSDT-NVPWR.aml
RTD3=/Users/user/tweak-backup-2026-11-13/rtd3/step44-rtd3.sh
V2=4969d64073010048c1ea10909090909090909090909090
NEED="com.apple.driver.AppleIntelTGLGraphics com.apple.driver.AppleIntelTGLGraphicsFramebuffer org.b00t0x.AppleIntelTGLCompat com.rugarciap.DisableTurboBoost com.nullmoth.NVAccel com.nullmoth.NVRM com.nullmoth.NVRMAGDC com.nullmoth.NVRMFB"
sha() { shasum -a 256 "$1" | cut -c1-16; }
cnt() { perl -e 'local $/; open F,"<",$ARGV[0] or do{print "?";exit}; binmode F; $d=<F>; $p=pack("H*",$ARGV[1]); $n=0; $n++ while $d=~/\Q$p\E/g; print $n' "$1" "$2"; }
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
KARG=(--allow-missing-kdk); [ -f /System/Library/Kernels/kernel ] && KARG+=(--kernel /System/Library/Kernels/kernel)
rebuild() {
  local N="$KC.rtd3-new"; rm -f "$N"
  kmutil create -n aux --volume-root / "${KARG[@]}" -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions -A "$N" -z > "$T/logs/step51-kmutil.log" 2>&1 \
    || { tail -15 "$T/logs/step51-kmutil.log"; return 1; }
  [ -s "$N" ] || return 1
  local INS; INS=$(kmutil inspect -a x86_64 -A "$N" 2>/dev/null) || return 1
  for id in $NEED; do echo "$INS" | grep -q "$id" || { echo "!! 새 AuxKC 에 $id 없음"; return 1; }; done
  [ "$(cnt "$N" $V2)" = 1 ] || { echo "!! 새 AuxKC 에 밝기 패치가 없음"; return 1; }
  mv -f "$N" "$KC" && echo "새 AuxKC: $(sha "$KC")"
}
efi() {
  mount | grep -q "^/dev/disk0s1 " || diskutil mount disk0s1 >/dev/null || stop "EFI 마운트 실패"
  MP="$(diskutil info disk0s1 | awk -F': *' '/Mount Point/{print $2}')"; OC="$MP/EFI/OC"; C="$OC/config.plist"
}
case "$MODE" in
apply)
  [ "$(sha "$NEW")" = "$NEW_SHA" ] || stop "수정본 해시가 빌드 때와 다름"
  [ "$(sha "$CUR")" = "$ORIG_SHA" ] || stop "설치된 NVRM 이 2.9 원본이 아님 ($(sha "$CUR"))"
  [ "$(cnt "$KC" $V2)" = 1 ] || stop "현재 AuxKC 의 밝기 패치 상태가 예상과 다름"
  mkdir -p "$BK" && cp -p "$CUR" "$BK/NVRM" && cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc" || stop "백업 실패"
  [ "$(sha "$BK/NVRM")" = "$ORIG_SHA" ] || stop "백업 검증 실패"
  echo "백업: $BK (NVRM $(sha "$BK/NVRM"), AuxKC $(sha "$BK/AuxiliaryKernelExtensions.kc"))"
  cp "$NEW" "$CUR" && chown root:wheel "$CUR" && chmod 755 "$CUR" || { cp -p "$BK/NVRM" "$CUR"; stop "복사 실패 → 원본으로 되돌림"; }
  rebuild || { cp -p "$BK/NVRM" "$CUR"; cp -p "$BK/AuxiliaryKernelExtensions.kc" "$KC"; stop "AuxKC 재생성 실패 → 원본 NVRM·AuxKC 로 되돌림 (재부팅해도 안전)"; }
  efi; mkdir -p "$OC/backup-before-nvpwr" && cp -p "$C" "$OC/backup-before-nvpwr/config.plist" || stop "config 백업 실패"
  cp "$SSDT" "$OC/ACPI/SSDT-NVPWR.aml" || stop "SSDT 복사 실패"
  if ! /usr/libexec/PlistBuddy -c "Print :ACPI:Add" "$C" | grep -q SSDT-NVPWR.aml; then
    n=$(plutil -extract ACPI.Add raw -o - "$C")
    plutil -insert "ACPI.Add.$n" -dictionary "$C" && plutil -insert "ACPI.Add.$n.Path" -string SSDT-NVPWR.aml "$C" \
      && plutil -insert "ACPI.Add.$n.Enabled" -bool true "$C" && plutil -insert "ACPI.Add.$n.Comment" -string "MX450 RTD3 helpers XPOF/XPON (2026-11-14)" "$C" \
      && plutil -lint "$C" >/dev/null || { cp -p "$OC/backup-before-nvpwr/config.plist" "$C"; stop "SSDT 등록 실패 → config 되돌림"; }
  fi
  echo "SSDT-NVPWR 등록: $(/usr/libexec/PlistBuddy -c 'Print :ACPI:Add' "$C" | grep -c Path)개 중 하나"
  bash "$RTD3" apply || stop "nvrtd3 인자 추가 실패 (드라이버는 설치됨; nvrtd3 없이는 원본과 같게 동작)"
  echo "적용 완료. 재부팅 후 커널 로그의 'NVRM: RTD3 try' 줄 확인" ;;
undo)
  [ -f "$BK/NVRM" ] && [ "$(sha "$BK/NVRM")" = "$ORIG_SHA" ] || stop "원본 백업 없음"
  cp "$BK/NVRM" "$CUR" && chown root:wheel "$CUR" && chmod 755 "$CUR" || stop "원본 복사 실패"
  if [ -f "$BK/AuxiliaryKernelExtensions.kc" ]; then cp -p "$BK/AuxiliaryKernelExtensions.kc" "$KC" && echo "AuxKC 복원: $(sha "$KC")"; else rebuild || stop "AuxKC 재생성 실패 — 재부팅하지 말 것"; fi
  efi; [ -f "$OC/backup-before-nvpwr/config.plist" ] && cp -p "$OC/backup-before-nvpwr/config.plist" "$C"; rm -f "$OC/ACPI/SSDT-NVPWR.aml"
  bash "$RTD3" undo
  echo "되돌림 완료" ;;
*) stop "사용법: $0 apply|undo";;
esac
sync
