#!/bin/bash
set -euo pipefail
W=/Users/user/nvidia-trial/build/nvmtl-plugin; I=/Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver
ORIG=$W/backup/NVMTLDriver.orig; NEW=$W/out-xgpu/NVMTLDriver
case "${1:-apply}" in
  apply) src=$NEW;; undo) src=$ORIG;; *) echo "usage: $0 apply|undo"; exit 1;;
esac
[ -f "$src" ] || { echo "없음: $src"; exit 1; }
install -m 755 -o root -g wheel "$src" "$I.new" && mv -f "$I.new" "$I"
echo "설치: $(shasum -a 256 "$I" | cut -c1-16) ($1)"
