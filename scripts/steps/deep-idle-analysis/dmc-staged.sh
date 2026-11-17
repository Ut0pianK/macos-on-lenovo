#!/bin/bash
D=/Users/user/deep-idle-analysis; O=$D/dmc-staged.txt
kt() { top -l 2 -s 5 -n 3 -o cpu -stats pid,command,cpu 2>/dev/null | awk '/^PID/{c++} c==2' | grep -E "kernel_task" | awk '{print $3}'; }
m() { echo "$(date +%T) $1: kernel_task $(kt)% | $(perl $D/psys.pl 8) | $(/usr/bin/python3 -I $D/dcstat.py | tail -1)" >> $O; }
rm -f $D/dmc-staged.done; echo "# $(date '+%F %T') 시작 (부팅 후 $(uptime | sed 's/.*up //; s/,.*//'))" > $O
m "0 기준"; m "0 기준"
sysctl -w debug.wexdmc=1 >> $O 2>&1
m "1 DMC 적재 직후"; m "1 DMC +20초"; m "1 DMC +40초"
if [ "${1:-}" = dc ]; then
  sudo -u user pmset displaysleepnow; sleep 12; m "2 화면 끔"
  sysctl -w debug.wexdc=2 >> $O 2>&1; m "2 DC6 허용"; m "2 DC6 허용 +15초"
  sysctl -w debug.wexdc=0 >> $O 2>&1; m "2 해제 뒤"
  sudo -u user caffeinate -u -t 3; sleep 6; m "2 화면 켬 뒤"; m "2 화면 켬 +15초"
fi
echo "# $(date '+%F %T') 끝" >> $O; chown user:staff $O; touch $D/dmc-staged.done; chown user:staff $D/dmc-staged.done
launchctl remove local.deepidle-staged
