#!/bin/bash
D=/Users/user/deep-idle-analysis; P=/Users/user/tweak-backup-2026-11-13/power; O=$D/psr-ab.txt
rm -f $D/psr-ab.done; echo "# $(date '+%F %T') 시작 $(pmset -g batt | head -1)" > $O
/usr/bin/caffeinate -d -t 1000 &
for p in 0 1 0 1 0 1; do
  sysctl -w debug.wexpsr1=$p >/dev/null; sleep 40
  c=$(perl $P/cpustat.pl 110 | awk '/PC8/{c=$2} /패키지/{w=$2} END{printf "PC8 %s pkg %sW", c,w}')
  echo "psr=$p: $c | 배터리 $(perl $P/w.pl | sed 's/.*inst=\([0-9.]*W\).*/\1/') | $(python3 -I /Users/user/psr-analysis/psrstat.py | grep -o '켜져 있던 시간 [0-9]*s')" >> $O
done
sysctl -w debug.wexpsr1=1 >/dev/null
echo "# $(date '+%F %T') 끝" >> $O; chown user:staff $O; touch $D/psr-ab.done; chown user:staff $D/psr-ab.done
launchctl remove local.deepidle-psrab
