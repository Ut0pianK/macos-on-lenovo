#!/bin/bash
set -e; B=/Users/user/tweak-backup-2026-11-13/helium
[ -d "$B/Helium.app/Contents" ] || { echo "백업 없음"; exit 1; }
pgrep -f "/Applications/Helium.app/" >/dev/null && { echo "Helium 을 먼저 종료"; exit 1; }
mv /Applications/Helium.app "$B/Helium.resigned.$(date +%H%M%S).app" && ditto "$B/Helium.app" /Applications/Helium.app && echo restored
