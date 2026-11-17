#!/bin/bash
D=/Users/user/deep-idle-analysis; P=/Users/user/tweak-backup-2026-11-13/power; O=$D/l1ss-ab.txt
seg() { sleep 40; c=$(perl $P/cpustat.pl 110 | awk '/PC8/{c=$2} /PC10/{e=$2} /패키지/{w=$2} END{printf "PC8 %s PC10 %s pkg %sW", c,e,w}'); idle=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {printf "%d", $NF/1000000000; exit}'); echo "$1: $c | 배터리 $(perl $P/w.pl | sed 's/.*inst=\([0-9.]*W\).*/\1/') | 손 뗀 지 ${idle}s$([ "${idle:-0}" -lt 150 ] && echo ' (사용 중: 이 구간 제외)') | $(pmset -g batt | head -1 | grep -o "'.*'")" >> $O; }
rm -f $D/l1ss-ab.done; echo "# $(date '+%F %T') 시작 $(pmset -g batt | head -1)" > $O
/usr/bin/caffeinate -d -t 930 & CP=$!
for v in 0 3 0 3 0 3; do sysctl -w debug.wexl1ss=$v >/dev/null; seg "화면켬 l1ss=$v"; done
kill $CP 2>/dev/null; sudo -u user pmset displaysleepnow; sleep 30
for v in 0 3 0 3; do sysctl -w debug.wexl1ss=$v >/dev/null; seg "화면끔 l1ss=$v"; done
/usr/bin/python3 -I $D/pmcstat.py 2>/dev/null | sed -n '8,17p' >> $O
caffeinate -u -t 3
echo "# $(date '+%F %T') 끝 (wexl1ss=$(sysctl -n debug.wexl1ss))" >> $O; chown user:staff $O; touch $D/l1ss-ab.done; chown user:staff $D/l1ss-ab.done
launchctl remove local.deepidle-l1ssab
