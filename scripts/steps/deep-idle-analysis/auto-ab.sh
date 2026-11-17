#!/bin/bash
D=/Users/user/deep-idle-analysis; n=0
echo "$(date '+%F %T') 대기 시작" >> $D/auto-ab.log
while :; do
  sleep 30
  if pmset -g batt | head -1 | grep -q "Battery Power"; then n=$((n+1)); else n=0; fi
  idle=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {printf "%d", $NF/1000000000; exit}')
  if [ $n -ge 6 ] && [ "${idle:-0}" -ge 120 ]; then
    echo "$(date '+%F %T') 측정 시작(배터리 ${n}회 연속, 손 뗀 지 ${idle}s)" >> $D/auto-ab.log
    /bin/bash $D/l1ss-ab.sh
    echo "$(date '+%F %T') 측정 끝" >> $D/auto-ab.log
    rm -f /Library/LaunchDaemons/local.deepidle-autoab.plist
    launchctl bootout system/local.deepidle-autoab 2>/dev/null
    exit 0
  fi
done
