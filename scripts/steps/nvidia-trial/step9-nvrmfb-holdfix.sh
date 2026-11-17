#!/bin/bash
set -u
T=/Users/user/nvidia-trial
NEW=$T/build/nvrmfb-2.9-holdfix/NVRMFB.kext/Contents/MacOS/NVRMFB
CUR=/Library/Extensions/NVRMFB.kext/Contents/MacOS/NVRMFB
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
BK=$T/backup-nvrmfb-orig
ORIG_MD5=d13f81cb8884002545729fb65ac2edbc
NEW_SHA=0799c08203a77e47ca2fe1b44c06b64a350a750f2f2796390df320188278de03
V2=4969d64073010048c1ea10909090909090909090909090
FB=/Library/Extensions/AppleIntelTGLGraphicsFramebuffer.kext/Contents/MacOS/AppleIntelTGLGraphicsFramebuffer
NEED="com.apple.driver.AppleIntelTGLGraphics com.apple.driver.AppleIntelTGLGraphicsFramebuffer org.b00t0x.AppleIntelTGLCompat com.rugarciap.DisableTurboBoost com.nullmoth.NVAccel com.nullmoth.NVRM com.nullmoth.NVRMAGDC com.nullmoth.NVRMFB"
cnt() { perl -e 'local $/; open F,"<",$ARGV[0] or do{print "?";exit}; binmode F; $d=<F>; $p=pack("H*",$ARGV[1]); $n=0; $n++ while $d=~/\Q$p\E/g; print $n' "$1" "$2"; }
stop() { echo "!! $* — 중단"; exit 1; }
mode=${1:-apply}

if [ "$mode" = check ]; then
  echo "설치된 NVRMFB sha256: $(shasum -a 256 "$CUR" | cut -d' ' -f1)"
  echo "로드된 NVRMFB: $(kextstat 2>/dev/null | grep com.nullmoth.NVRMFB | awk '{print $6,$7,$8}')"
  echo "-- 이번 부팅의 auto-go / 헤드리스 판정 로그"
  /usr/bin/log show --last boot --style compact --predicate 'process == "kernel" AND (eventMessage CONTAINS "auto-go" OR eventMessage CONTAINS "boot hold" OR eventMessage CONTAINS "headless check" OR eventMessage CONTAINS "getDisplays")' 2>/dev/null \
    | grep -E '^20' | sed -E 's/ Df kernel\[0:[0-9a-f]+\]//' | awk '!s[substr($0,25)]++' | cut -c1-230 | head -20
  echo "-- 로그인 단계"
  /usr/bin/log show --last boot --style compact --predicate 'process == "loginwindow" AND category == "KeyMilestone" AND eventMessage CONTAINS "login state"' 2>/dev/null \
    | grep -E 'WindowServerConnectionMade|ContinueAfterDesktopReady|LoginComplete' | cut -c1-140
  sysctl -n kern.boottime
  system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset|Metal"
  exit 0
fi

[ "$(id -u)" = 0 ] || stop "sudo 로 실행할 것"
KARG=(--allow-missing-kdk); [ -f /System/Library/Kernels/kernel ] && KARG+=(--kernel /System/Library/Kernels/kernel)
rebuild_and_publish() {
  local N="$KC.holdfix-new"
  kmutil create -n aux --volume-root / "${KARG[@]}" -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions -A "$N" -z > "$T/logs/step9-kmutil.log" 2>&1 \
    || { tail -15 "$T/logs/step9-kmutil.log"; return 1; }
  [ -s "$N" ] || return 1
  local INS; INS=$(kmutil inspect -a x86_64 -A "$N" 2>/dev/null) || return 1
  for id in $NEED; do echo "$INS" | grep -q "$id" || { echo "!! 새 AuxKC 에 $id 없음"; return 1; }; done
  [ "$(cnt "$N" $V2)" = 1 ] || { echo "!! 새 AuxKC 에 밝기 패치가 없음"; return 1; }
  mv -f "$N" "$KC" && echo "새 AuxKC sha256: $(shasum -a 256 "$KC" | cut -d' ' -f1)"
}

if [ "$mode" = undo ]; then
  [ -f "$BK/NVRMFB" ] && [ "$(md5 -q "$BK/NVRMFB")" = "$ORIG_MD5" ] || stop "원본 백업($BK/NVRMFB)이 없거나 다름"
  cp "$BK/NVRMFB" "$CUR" && chown root:wheel "$CUR" && chmod 755 "$CUR" || stop "원본 복사 실패"
  if [ -f "$BK/AuxiliaryKernelExtensions.kc" ]; then
    cp -p "$BK/AuxiliaryKernelExtensions.kc" "$KC" && echo "적용 전 AuxKC 복원: $(shasum -a 256 "$KC" | cut -d' ' -f1)"
  else rebuild_and_publish || stop "AuxKC 재생성 실패 — 재부팅하지 말 것"; fi
  echo "되돌림 완료. 재부팅하면 원본 드라이버로 돌아간다."; exit 0
fi

[ "$mode" = apply ] || stop "알 수 없는 모드: $mode"
[ "$(shasum -a 256 "$NEW" | cut -d' ' -f1)" = "$NEW_SHA" ] || stop "수정본 해시가 빌드 때와 다름"
cur_md5=$(md5 -q "$CUR")
if [ "$(shasum -a 256 "$CUR" | cut -d' ' -f1)" = "$NEW_SHA" ]; then echo "이미 수정본이 설치돼 있음 (AuxKC 만 다시 확인)"; else
  [ "$cur_md5" = "$ORIG_MD5" ] || stop "설치된 NVRMFB 가 2.9 원본이 아님 ($cur_md5)"
  [ "$(cnt "$FB" $V2)" = 1 ] && [ "$(cnt "$KC" $V2)" = 1 ] || stop "밝기 패치 상태가 예상과 다름"
  mkdir -p "$BK" && cp -p "$CUR" "$BK/NVRMFB" && cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc" || stop "백업 실패"
  [ "$(md5 -q "$BK/NVRMFB")" = "$ORIG_MD5" ] || stop "백업 검증 실패"
  echo "백업: $BK (원본 NVRMFB, 적용 전 AuxKC $(shasum -a 256 "$BK/AuxiliaryKernelExtensions.kc" | cut -c1-16)…)"
  cp "$NEW" "$CUR" && chown root:wheel "$CUR" && chmod 755 "$CUR" || stop "수정본 복사 실패 (sudo bash $0 undo 로 되돌릴 것)"
fi
if rebuild_and_publish; then
  echo "적용 완료. 재부팅 후:  bash $0 check"
else
  echo "!! AuxKC 재생성/검증 실패 → 원본으로 되돌림"
  cp "$BK/NVRMFB" "$CUR" && chown root:wheel "$CUR" && chmod 755 "$CUR"
  echo "AuxKC 는 바꾸지 않았음. 현재 상태 그대로 재부팅해도 원본 드라이버."; exit 1
fi
