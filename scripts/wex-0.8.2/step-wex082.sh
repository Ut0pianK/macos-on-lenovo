#!/bin/bash
set -u
P=/Users/user/wex-0.8.2-port; MODE=${1:-}; INT=disk0s1
PKG=$P/dl/WhateverXe-Graphics-0.4.4.pkg; PKG_SHA=f4c2d680a7c52c33
NEWWEX=$P/out-port/WhateverXe.kext; NEWWEX_SHA=6a39830ab734ab64
LE=/Library/Extensions; GB=/Library/GPUBundles; KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
FB=$LE/AppleIntelTGLGraphicsFramebuffer.kext/Contents/MacOS/AppleIntelTGLGraphicsFramebuffer
VA=$GB/AppleIntelTGLGraphicsVADriver.bundle/Contents/MacOS
V2=4969d64073010048c1ea10909090909090909090909090
FB044=8b83600e0000410fafc6ba0180008048
FB044B=8b83600e0000410fafc6ba0180008048 FB044T=0fafd048c1ea2f
BK=$P/backup-before-wex082; LOG=/var/log/wex082.log
MARK=/var/db/wex082.armed; PL=/Library/LaunchDaemons/local.wex082-watchdog.plist; SELF=/usr/local/libexec/step-wex082.sh
NEED="com.apple.driver.AppleIntelTGLGraphics com.apple.driver.AppleIntelTGLGraphicsFramebuffer org.b00t0x.AppleIntelTGLCompat com.rugarciap.DisableTurboBoost com.nullmoth.NVAccel com.nullmoth.NVRM com.nullmoth.NVRMAGDC com.nullmoth.NVRMFB"
sha() { shasum -a 256 "$1" | cut -c1-16; }
cnt() { perl -e 'local $/; open F,"<",$ARGV[0] or do{print "?";exit}; binmode F; $d=<F>; $p=pack("H*",$ARGV[1]); $n=0; $n++ while $d=~/\Q$p\E/g; print $n' "$1" "$2"; }
log() { echo "$(date '+%F %T') [wex082] $*" | tee -a $LOG; }
stop() { log "!! $* — 중단"; sync; exit 1; }

if [ "$MODE" = check ]; then
  kmutil showloaded --list-only 2>/dev/null | awk '{print $6,$7}' | grep -E 'WhateverXe|AppleIntelTGL'
  ioreg -r -c IntelAccelerator -d1 -w0 | head -1
  system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Chipset|Metal'
  echo "FB V2=$(cnt "$FB" $V2) AuxKC V2=$(cnt "$KC" $V2)  dylib: $(ls "$VA")"
  sysctl debug.wexvp9 debug.wexpsr1 2>/dev/null; ioreg -l -d1 -w0 | grep -oE '"WhateverXe(NoScanSync|DmcScrub)" = [^,]*' | sort -u
  tail -5 $LOG; exit 0
fi
[ "$(id -u)" = 0 ] || stop "root 필요"
efi() { mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "EFI 마운트 실패"; MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"; KX="$MP/EFI/OC/Kexts"; }
KARG=(--allow-missing-kdk); [ -f /System/Library/Kernels/kernel ] && KARG+=(--kernel /System/Library/Kernels/kernel)
rebuild() {
  local N="$KC.wex082-new"; rm -f "$N"
  kmutil create -n aux --volume-root / "${KARG[@]}" -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions -A "$N" -z > "$P/kmutil-wex082.log" 2>&1 \
    || { tail -15 "$P/kmutil-wex082.log"; return 1; }
  [ -s "$N" ] || return 1
  local INS; INS=$(kmutil inspect -a x86_64 -A "$N" 2>/dev/null) || return 1
  for id in $NEED; do echo "$INS" | grep -q "$id" || { log "!! 새 AuxKC 에 $id 없음"; return 1; }; done
  [ "$(cnt "$N" $V2)" = 1 ] || { log "!! 새 AuxKC 에 밝기 패치 V2 가 1곳이 아님"; return 1; }
  chmod 0644 "$N"; mv -f "$N" "$KC" && log "새 AuxKC: $(sha "$KC")"
}
restore_all() {
  efi
  [ -d "$BK/WhateverXe.kext" ] && { rm -rf "$KX/WhateverXe.kext.wex082-old"; mv "$KX/WhateverXe.kext" "$KX/WhateverXe.kext.wex082-old" 2>/dev/null; ditto "$BK/WhateverXe.kext" "$KX/WhateverXe.kext" && rm -rf "$KX/WhateverXe.kext.wex082-old"; }
  [ -f "$BK/intel-kexts.tar" ] && { for k in AppleIntelTGLCompat AppleIntelTGLGraphics AppleIntelTGLGraphicsFramebuffer; do rm -rf "$LE/$k.kext"; done; tar -xpf "$BK/intel-kexts.tar" -C /; }
  [ -f "$BK/bundles.tar" ] && { for b in GLDriver MTLDriver VADriver; do rm -rf "$GB/AppleIntelTGLGraphics$b.bundle"; done; tar -xpf "$BK/bundles.tar" -C /; }
  [ -f "$BK/AuxiliaryKernelExtensions.kc" ] && cp -p "$BK/AuxiliaryKernelExtensions.kc" "$KC"
  [ -f "$BK/CoreMedia.plist" ] && cp -p "$BK/CoreMedia.plist" /Library/Preferences/FeatureFlags/Domain/CoreMedia.plist
  sync
}

case "$MODE" in
apply)
  [ "$(sha "$PKG")" = "$PKG_SHA" ] || stop "Graphics pkg 해시 불일치"
  [ "$(sha "$NEWWEX/Contents/MacOS/WhateverXe")" = "$NEWWEX_SHA" ] || stop "새 WhateverXe 해시 불일치"
  [ "$(cnt "$FB" $V2)" = 1 ] && [ "$(cnt "$KC" $V2)" = 1 ] || stop "지금 FB/AuxKC 의 V2 상태가 예상과 다름"
  [ -f "$VA/vp9stack.dylib" ] && [ -f "$VA/cmfcld.dylib" ] || stop "VA 번들에 우리 dylib 이 없음"
  efi; [ -d "$KX/WhateverXe.kext" ] || stop "EFI 에 WhateverXe.kext 없음"
  [ -e "$BK" ] && stop "백업 폴더가 이미 있음($BK) — 이전 시도 확인 필요"
  mkdir -p "$BK" || stop "백업 폴더 실패"
  ditto "$KX/WhateverXe.kext" "$BK/WhateverXe.kext" && cp -Rp "$MP/EFI" "$BK/EFI-full" || stop "EFI 백업 실패"
  ( cd / && tar -cpf "$BK/intel-kexts.tar" Library/Extensions/AppleIntelTGLCompat.kext Library/Extensions/AppleIntelTGLGraphics.kext Library/Extensions/AppleIntelTGLGraphicsFramebuffer.kext ) || stop "kext 백업 실패"
  ( cd / && tar -cpf "$BK/bundles.tar" Library/GPUBundles/AppleIntelTGLGraphicsGLDriver.bundle Library/GPUBundles/AppleIntelTGLGraphicsMTLDriver.bundle Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle ) || stop "번들 백업 실패"
  cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc" && cp -p "$VA/vp9stack.dylib" "$VA/cmfcld.dylib" "$BK/" || stop "AuxKC/dylib 백업 실패"
  [ -f /Library/Preferences/FeatureFlags/Domain/CoreMedia.plist ] && cp -p /Library/Preferences/FeatureFlags/Domain/CoreMedia.plist "$BK/CoreMedia.plist"
  log "백업 완료: $BK (WEX $(sha "$KX/WhateverXe.kext/Contents/MacOS/WhateverXe"), AuxKC $(sha "$KC"))"
  installer -pkg "$PKG" -target / > "$P/installer-wex082.log" 2>&1 || { tail -5 "$P/installer-wex082.log"; restore_all; stop "pkg 설치 실패 → 전부 복원"; }
  log "Graphics 0.4.4 설치됨: Compat $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' $LE/AppleIntelTGLCompat.kext/Contents/Info.plist)"
  for f in vp9stack.dylib cmfcld.dylib; do [ -f "$VA/$f" ] && [ "$(sha "$VA/$f")" = "$(sha "$BK/$f")" ] || { cp -p "$BK/$f" "$VA/$f"; chown root:wheel "$VA/$f"; chmod 755 "$VA/$f"; log "dylib 복원: $f"; }; done
  perl -e '
    my ($f,$h,$t,$v)=@ARGV; open F,"+<:raw",$f or die "open"; local $/; my $d=<F>;
    my $o=0x4a5a0; my $want=pack("H*",$h).pack("H*",$t); length($want)==23 or die "len";
    my $n=()=$d=~/\Q$want\E/g; $n==1 or die "pattern count $n";
    substr($d,$o,23) eq $want or die "offset mismatch";
    seek F,$o,0; print F pack("H*",$v); close F; print "ok\n";' "$FB" "$FB044B" "$FB044T" "$V2" || { restore_all; stop "V2 재적용 실패 → 전부 복원"; }
  [ "$(cnt "$FB" $V2)" = 1 ] || { restore_all; stop "V2 확인 실패 → 전부 복원"; }
  log "밝기 패치 V2 재적용(FB $(sha "$FB"))"
  rebuild || { restore_all; stop "AuxKC 재생성 실패 → 전부 복원 (재부팅해도 안전)"; }
  rm -rf "$KX/WhateverXe.kext" && ditto "$NEWWEX" "$KX/WhateverXe.kext" || { restore_all; stop "EFI kext 교체 실패 → 전부 복원"; }
  [ "$(sha "$KX/WhateverXe.kext/Contents/MacOS/WhateverXe")" = "$NEWWEX_SHA" ] || { restore_all; stop "EFI kext 해시 불일치 → 전부 복원"; }
  sync
  mkdir -p /usr/local/libexec && install -m 755 "$0" "$SELF"
  cat > $PL <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>local.wex082-watchdog</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>watchdog</string></array>
<key>RunAtLoad</key><true/></dict></plist>
EOF
  chmod 644 $PL; chown root:wheel $PL; rm -f $MARK; sync
  log "적용 완료: EFI WEX $NEWWEX_SHA, Graphics 0.4.4, V2, AuxKC. 재부팅 뒤 bash $P/step-wex082.sh check" ;;
undo)
  [ -d "$BK" ] || stop "백업 없음"
  restore_all
  log "undo: EFI WEX $(sha "$KX/WhateverXe.kext/Contents/MacOS/WhateverXe"), FB V2=$(cnt "$FB" $V2), AuxKC $(sha "$KC")"
  rm -f $MARK; sync; [ -n "${NOBOOTOUT:-}" ] && exit 0
  rm -f $PL; launchctl bootout system/local.wex082-watchdog 2>/dev/null ;;
watchdog)
  efi; [ "$(sha "$KX/WhateverXe.kext/Contents/MacOS/WhateverXe")" = "$NEWWEX_SHA" ] || { rm -f $MARK $PL; exit 0; }
  if [ -e $MARK ]; then log "watchdog: 이전 시험 부팅이 5분을 못 버팀 → 되돌리고 재부팅"; rm -f $PL; NOBOOTOUT=1 "$SELF" undo; sync; sleep 3; shutdown -r now; exit 0; fi
  touch $MARK; sync; log "watchdog: 시험 부팅 시작 (가속 4분, 생존 5분 감시)"
  ok=0; for i in $(seq 1 48); do ioreg -r -c IntelAccelerator -d1 -w0 | grep -q IntelAccelerator && { ok=1; break; }; sleep 5; done
  if [ $ok = 0 ]; then log "watchdog: 4분 동안 Intel 가속 없음 → 되돌리고 재부팅"; rm -f $MARK $PL; NOBOOTOUT=1 "$SELF" undo; sync; sleep 3; shutdown -r now; exit 0; fi
  log "watchdog: 가속 확인 ($((i*5))초)"
  sleep 240; rm -f $MARK; sync
  log "watchdog: 5분 통과 — $(kmutil showloaded --list-only 2>/dev/null | awk '{print $6,$7}' | grep -E 'WhateverXe|TGLCompat' | tr '\n' ' ')"
  rm -f $PL; launchctl bootout system/local.wex082-watchdog 2>/dev/null ;;
*) stop "사용법: $0 apply|undo|watchdog|check";;
esac
sync; exit 0
