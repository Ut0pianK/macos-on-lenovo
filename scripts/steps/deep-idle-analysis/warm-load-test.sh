#!/bin/bash
D=/Users/user/deep-idle-analysis; O=$D/warm-load-test.txt
kt() { top -l 2 -s 4 -n 3 -o cpu -stats pid,command,cpu 2>/dev/null | awk '/^PID/{c++} c==2' | grep kernel_task | awk '{print $3}'; }
echo "# $(date '+%F %T') 부팅 후 $(uptime | sed 's/.*up //; s/,.*//')" > $O
echo "적재 전: kernel_task $(kt)% $(/usr/bin/python3 -I /Users/user/psr-analysis/psrstat.py | grep -o 'DMC\[0\] 0x80000=[0-9a-fx]*')" >> $O
sysctl -w debug.wexdmc=1 >> $O 2>&1
for t in 5 15 30 45; do sleep 8; echo "적재 후 ~${t}초: kernel_task $(kt)%" >> $O; done
chown user:staff $O
