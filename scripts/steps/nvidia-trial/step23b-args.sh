#!/bin/bash
set -e
K=NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args
mount | grep -q "^/dev/disk0s1 " || diskutil mount disk0s1 >/dev/null
cfg=/Volumes/EFI/EFI/OC/config.plist
cur=$(plutil -extract $K raw -o - "$cfg")
new=$(echo " $cur " | sed 's/ -wex-bootgamma / /; s/ -wex-bootclear / /' | sed 's/^ *//; s/ *$//')" -wex-bootclear"
plutil -replace $K -string "$new" "$cfg" && plutil -lint "$cfg"
shasum -a 256 /Volumes/EFI/EFI/OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe | cut -c1-16
echo "boot-args: $(plutil -extract $K raw -o - "$cfg")"
