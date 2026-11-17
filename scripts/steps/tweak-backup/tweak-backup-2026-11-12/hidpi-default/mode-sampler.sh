#!/bin/sh
LOG="$HOME/Library/Logs/hidpi-default-sampler.log"
P="$HOME/Library/LaunchAgents/local.hidpi-default-sampler.plist"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') 부팅 $(sysctl -n kern.boottime | sed 's/.*} //')" >> "$LOG"
i=0; last=""
while [ $i -lt 80 ]; do
  cur=$(/usr/local/bin/hidpi-mode 2>/dev/null | grep -- '<- current' | sed 's/ *<- current//')
  [ "$cur" != "$last" ] && echo "$(date '+%H:%M:%S') [$cur]" >> "$LOG"
  last="$cur"; i=$((i+1)); /bin/sleep 0.5
done
echo "끝" >> "$LOG"
/bin/mv "$P" "$HOME/tweak-backup-2026-11-12/hidpi-default/sampler.plist.done"
