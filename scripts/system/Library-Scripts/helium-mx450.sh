#!/bin/bash
A=/Applications/Helium.app
FLAG="--disable-angle-features=disableMetalOnNvidia"
RESIGN="$HOME/tweak-backup-2026-11-13/helium/resign-gpu-helpers.sh"
LOG="$HOME/Library/Logs/helium-mx450.log"
say() { echo "$(date '+%F %T') $*" >> "$LOG"; }
PID=$(pgrep -f "$A/Contents/MacOS/Helium" | head -1)
if [ -n "$PID" ]; then
  if ps -o args= -p "$PID" | grep -q -- "$FLAG"; then open -a "$A"; exit 0; fi
  echo RUNNING_WITHOUT_FLAG; exit 0
fi
H=$(ls -d "$A/Contents/Frameworks/Helium Framework.framework/Versions/"[0-9]* 2>/dev/null | head -1)"/Helpers/Helium Helper (Aperitif).app"
if ! codesign -d --entitlements - "$H" 2>/dev/null | grep -q disable-library-validation; then
  if /bin/bash "$RESIGN" >> "$LOG" 2>&1; then say "재서명 적용(업데이트 뒤로 보임)"; echo RESIGNED
  else say "재서명 실패"; echo RESIGN_FAILED; fi
fi
open --env NVMTL_ENABLE=1 -a "$A" --args "$FLAG"
