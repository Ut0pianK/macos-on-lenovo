#!/bin/bash
set -e
G=/var/db/.com.apple.iokit.graphics
/usr/local/bin/hidpi-mode 2240 1400 1x
sleep 4
s=$(plutil -extract 'IOService:/AppleACPIPlatformExpert/PC00@0/AppleACPIPCI/IGPU@2-9e5-931-c9dd920102076d30.startup-timing' raw -o - "$G" | base64 -d | xxd -s 32 -l 8 -p)
echo "startup scaled field: $s (0000000000000000 이어야 함)"
[ "$s" = 0000000000000000 ] || { echo "시작 모드가 바뀌지 않음 → 시험 중단, HiDPI 복귀"; /usr/local/bin/hidpi-mode 1536 960; exit 1; }
