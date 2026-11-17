#!/bin/bash
D=/Users/user/deep-idle-analysis; O=$D/l1ss-fast.txt
rm -f $D/l1ss-fast.done; echo "# $(date '+%F %T') $(pmset -g batt | head -1) $(pmset -g batt | grep -o '[0-9]*%; [a-z ]*')" > $O
/usr/bin/caffeinate -d -t 330 &
for v in 0 3 0 3 0 3 0 3 0 3 0 3; do
  sysctl -w debug.wexl1ss=$v >/dev/null; sleep 6
  echo "l1ss=$v: $(perl $D/psys.pl 16) | 충전 $(perl /Users/user/tweak-backup-2026-11-13/power/w.pl | sed 's/.*inst=\([-0-9.]*W\).*/\1/')" >> $O
done
sysctl -w debug.wexl1ss=3 >/dev/null
echo "# $(date '+%F %T') 끝" >> $O; chown user:staff $O; touch $D/l1ss-fast.done; chown user:staff $D/l1ss-fast.done
launchctl remove local.deepidle-l1ssfast
