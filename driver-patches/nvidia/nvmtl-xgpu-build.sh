#!/bin/bash
set -euo pipefail
S=$(cd "$1" && pwd); O=$2; mkdir -p "$O"; O=$(cd "$O" && pwd); H=$(cd "$(dirname "$0")" && pwd)/Vulkan-Headers/include
cd "$S"
xcrun clang -arch x86_64 -mmacosx-version-min=15.0 -bundle -fobjc-arc -O1 -DNVMTL_RELEASE=1 \
  -Wno-protocol -Wno-incomplete-implementation -Werror=unguarded-availability-new \
  -I"$H" -o "$O/NVMTLDriver" NVMTLDevice.m nvmtl_dlss.c dlss/elfhost.c dlss/lnxlibc.c \
  -framework Foundation -framework Metal -framework IOSurface -framework IOKit -framework CoreFoundation -framework MetalFX -liconv 2>"$O/build.err" \
  || { grep ' error:' "$O/build.err" | head -20; exit 1; }
codesign -f -s - "$O/NVMTLDriver" 2>/dev/null
echo "built $O/NVMTLDriver $(stat -f %z "$O/NVMTLDriver") B, warnings $(grep -c ': warning:' "$O/build.err" || true), minos $(vtool -show-build "$O/NVMTLDriver" | awk '/minos/{print $2; exit}')"
